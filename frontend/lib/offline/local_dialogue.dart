// 单机版对话引擎：默认不联网，用「原文检索 + 概念卡 + 苏格拉底追问」组合出回答；
// 用户在「AI 大模型 API 配置」里填了自己的 Key 后，优先走在线模型（见 respond）。
//
// 红线：回答里出现的引文必须是 chunks.json 里真实存在的原文，逐字摘录并
// 标明出处；不生成任何虚构引文。因此本地模式只做「定位—摘录—追问」，
// 不做自由发挥式的长论述。在线模型的输出同样要过本机立场层才展示。
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../offline/local_db.dart';
import '../offline/local_guard.dart';
import '../offline/offline_content.dart';
import '../services/llm_client.dart';
import '../services/llm_config_store.dart';
import 'local_mastery.dart';

class LocalDialogue {
  LocalDialogue._();

  static const int _maxExcerpt = 180;

  // ------------------------------------------------------------ 检索
  //
  // 精度三原则（都是实测踩出来的）：
  //  ① **只拿实词检索**：以前用 2/3/4-gram 取前 48 个，长问句里一半是「的是在」
  //     这类 2-gram，把真正关键的词稀释掉了；
  //  ② **长段不因字多占优**：按段长做对数归一，避免「最长的那段」永远排第一；
  //  ③ **摘录要落在命中的那句上**：整段截前 180 字经常把关键句截在框外，
  //     改成句子级打分后只摘最有证据力的那 1—2 句（逐字，不改写）。

  /// 问句里的疑问/语气成分：整体删掉，不当检索词
  // 长整块必须排在短整块前面：「如何」若先匹配，「如何理解矛盾的普遍性」就
  // 只剩「理解矛盾的普遍性」，切出「理解矛盾」「理解」这种废词去检索，真正的
  // 主词「矛盾」反被稀释（实测：问矛盾的普遍性与特殊性时首条依据跑到 1844 手稿）。
  static const String _questionNoise = '如何理解|怎样理解|怎么理解|如何认识|如何把握|'
      '怎么看待|如何看待|如何对待|怎样对待|'
      '为什么|什么是|什么叫|怎么样|怎么|怎样|如何|'
      '是不是|能不能|可不可以|有没有|请解释|请说明|解释一下|讲讲|说一下|'
      '我想问|问一下|请问|谈谈|举例|举个例子|要不要|'
      // 「请就这段原文展开」：整句都是指令，没有内容词。以前「段原文展开」
      // 会被当成问句主语，覆盖率判定永远失败，明明做答到了也报「没有直接回答」。
      '这段原文|这段|原文|展开|说说|讲一讲|'
      '由什么|由谁|由哪些|由哪个|什么|哪些|哪种|哪个|谁|'
      '必须|应该|应当|需要|能否|可否|是否|到底|究竟|'
      // 这些是「提问动词」，不是内容词：以前「毛泽东如何看待调查研究」整块
      // 被当成检索词，全库零命中，白丢一次检索
      '看待|认为|强调|指出|主张|提出|论述|讲过|说了|'
      '理解|把握|阐述|讲解|解读|分析|说明|讨论|总结';

  /// 虚词（按字切分用）：这些字出现的位置就是词的边界
  static const String _stopChars =
      '的了是在和与就都而也还很更这不么什样如为请你说讲问我你他她它们'
      '把被从向于之其以所因但可若则即又再从到给让嘛呀啊吧呢吗哦哟着过地得';
  // 以上刻意**不含** 要/有/能/个/对/们：它们是虚词，但也是实词的构件
  // （主要矛盾、所有制、能动性、个人、对抗、人民），当分隔符会把这些词切坏。
  // 出现在词首/词尾时由 _trimStops 剥掉，不影响断句。

  /// 泛词：命中率极高、区分度低 → 加权时打折
  /// （「本质」「关系」这类词几乎每段都有，拿它当主证会把不相干的段落顶上来）
  static const Set<String> _weak = {
    '关系', '问题', '意思', '含义', '区别', '联系', '内容', '作用', '意义',
    '方法', '观点', '看法', '说法', '东西', '事情', '情况', '过程', '方面', '时候',
    '本质', '基本', '主要', '特点', '特征', '性质', '地位', '目的', '任务', '对象',
    '条件', '原因', '结果', '规律', '原则', '阶段', '一切', '全部', '一般', '具体',
    '形式', '方式', '状态', '表现', '回答', '问题所在',
  };

  static final RegExp _stopRe = RegExp('[$_stopChars]');

  /// 可以剥掉的词首/词尾虚词 = 分隔符 + 几个只能出现在句首的虚字。
  /// 「要反对本本主义」要剥成「反对本本主义」，但「主要矛盾」不能被切开。
  static const String _edgeExtra = '要有能个们该每各让给做都就还';
  // 以上不含「对」：它既是介词也是实词构件（对象/对抗/对立/对策），
  // 当词首虚词剥掉会把「对象」变成「象」，检索直接跑偏。
  static final Set<int> _trimSet = {
    for (final u in '$_stopChars$_edgeExtra'.codeUnits) u,
  };

  /// 虚词字符集（按 codeUnit 判，比 substring 快一个数量级）
  static final Set<int> _stopSet = {
    for (final u in _stopChars.codeUnits) u,
  };

  /// 句子切分缓存：同一段劝文会被五个模式先后取用，不重复切。
  static final Map<String, List<String>> _sentCache = {};

  /// 编者注 / 版本说明 / 页内注：不是原著正文。
  /// 早期评测里「＊这是为中共中央起草的指示，经毛泽东同志修改过。」
  /// 被当成原文摘录印在回答最前面，等于把编者的话冒充作者原话。
  static final RegExp _noteRe = RegExp(
      r'^\s*[＊*※]|^\s*注\s*[）)：:]|^\s*\[\d{1,3}\]|原题为|转引自|'
      r'见本书第|参见第|编者注|'
      r'这是为.{0,12}(起草|作)的?(指示|报告|提纲)|而写的(提纲|指示)|'
      r'经[\u4e00-\u9fff]{2,4}同志修改');

  // 热循环（全库 2 万多段）里用到的正则一律预编译：
  // 每段现场 new RegExp 是这一轮最大的隐性开销。
  static final RegExp _commaRe = RegExp(r'[,;]');
  static final RegExp _wsRe = RegExp(r'\s');
  static final RegExp _questionEndRe = RegExp(r'[？?]\s*$');
  static final RegExp _strongAssertRe =
      RegExp(r'必须|只能|决定|归根到底|一切|绝不|唯一');
  static final RegExp _nestedQuoteRe =
      RegExp(r'(他说|写道|指出|所说|认为)[：:]?\s*[“「]');
  static final RegExp _turningRe = RegExp(r'但是|然而|相反|所以|因此|因为|竟然|恰恰');
  static final RegExp _methodRe = RegExp(r'方法|一般|同样|适用于|正如|对于一切');
  static final RegExp _defineRe = RegExp(r'所谓|就是|是指|意味着|本质');
  // 反方攻击点的判据：有没有「一律化 / 排他 / 单向因果」，以及原文自带的限定语
  static final RegExp _allQuantRe =
      RegExp(r'凡是|全都|无一|所有[^。]{0,8}都|任何[^。]{0,8}都|一切[^。]{0,6}(都|均|必)');
  static final RegExp _onlyRe = RegExp(r'只能|唯一|只有|仅仅');
  static final RegExp _causeRe = RegExp(r'因为|所以|因此|由于|决定|导致');
  static final RegExp _limitRe =
      RegExp(r'归根到底|最终意义上|一般地|从根本上|在一定条件下|就其主要方面');

  /// 查询词提取：去问句成分 → 按虚词切块 → 留 2 字以上实词块。
  /// 例：「为什么说实践是检验真理的唯一标准」→ [实践, 检验真理, 标准]
  static bool _hasCjk(String t) {
    for (final u in t.codeUnits) {
      if (u >= 0x4e00 && u <= 0x9fff) return true;
    }
    return false;
  }

  static List<String> _keywords(String query) {
    var text = query.replaceAll(RegExp(_questionNoise), ' ');
    // 书名不当内容词：分片正文里几乎不会出现「《矛盾论》」这三个字，
    // 但书名本身又能定位到那一部书 → 走「著作偏好」加权（见 _preferredWorks）
    text = text.replaceAll(RegExp(r'《[^》]*》'), ' ');
    text = text.replaceAll(RegExp(r'[^\u4e00-\u9fffA-Za-z0-9]+'), ' ');
    _ensureNames();
    final out = <String>[];
    final seen = <String>{};

    void push(String w) {
      final t = _trimStops(_stripNames(w.trim()));
      if (t.length < 2 || t.length > 12) return;
      if (seen.add(t)) out.add(t);
    }

    for (final seg0 in text.split(' ')) {
      final seg = seg0.trim();
      if (seg.isEmpty) continue;
      final whole = _trimStops(_stripNames(seg));
      // 整段优先：「主要矛盾」「人民民主专政」以前被单字虚词表切碎，
      // 只剩「矛盾」一个泛词去检索，命中的全是泛段。
      if (whole.length >= 2 && whole.length <= 4) {
        push(whole);
      } else if (whole.length > 4 &&
          whole.length <= 12 &&
          !whole.codeUnits.any(_stopSet.contains)) {
        // 长整块容易零命中（「要反对本本主义」库里写作「反对」「本本主义」），
        // 整块与子块都给，让 IDF 去决定谁说话
        push(whole);
        for (final piece in seg.split(_stopRe)) {
          push(piece);
        }
      } else {
        for (final piece in seg.split(_stopRe)) {
          push(piece);
        }
        // 相邻片段跨一个「的/之/是」再拼回整词：「商品的价值」「历史的创造者」。
        // 整词命中一次，比「商品」「价值」各命中一次更能证明这段是在讲这件事
        // （实测：不拼整词时，「商品的价值由什么决定」把一句讲贵金属的
        //  短段顶到第一位，而「商品的价值量决定于社会必要劳动时间」排第二）。
        final pieces = <String>[];
        final gaps = <String>[];
        var last = 0;
        for (final m in _stopRe.allMatches(seg)) {
          pieces.add(seg.substring(last, m.start));
          gaps.add(m.group(0)!);
          last = m.end;
        }
        pieces.add(seg.substring(last));
        for (var i = 0; i + 1 < pieces.length; i++) {
          final a = _trimStops(_stripNames(pieces[i]));
          final b = _trimStops(_stripNames(pieces[i + 1]));
          if (a.isEmpty || b.isEmpty) continue;
          final g = gaps[i];
          if (g != '的' && g != '之' && g != '是') continue;
          final joined = '$a$g$b';
          if (joined.length >= 4 && joined.length <= 12) push(joined);
        }
      }
      if (out.length >= 8) break;
    }
    // 标准术语必须整词进检索：「实事求是」被「是」切成「实事求」，
    // 「人民民主专政」被切碎，「思想路线」剩「思想」——术语表（概念词典）里
    // 有的词只要在问句里出现，就整词保留，并去掉它被切出来的碎片。
    // 补整词之前先把「用户自己的词」留一份：判「库里有答案」要用它们，
    // 不能用补进来的术语整词——那会把没收录的长概念（社会主义初级阶段）
    // 判成「答出来了」，只因为库里有「社会主义」。
    final userTerms = [...out];
    // 最多补 4 个整词：补进来的词只用来提高精度，不能把检索词表撑成一大串。
    // **长的优先**插到最前面：问「实践唯物主义」时，先插短词「唯物主义」会让
    // 主语落在泛词上，关键词提示、摘录排序全跟着偏。
    final extras = <String>[
      for (final g in [..._wholeTerms, ..._glossaryTerms()])
        if (text.contains(g) && !out.contains(g)) g,
    ]..sort((a, b) => b.length.compareTo(a.length));
    for (final g in extras.take(4).toList().reversed) {
      out.insert(0, g);
    }
    // 问句的主语 = 用户词表里头一个**像样的实词**（碎片词跳过；只有全是碎片
    // 时才退回补进来的术语整词）。以前取 out.first，用户把「请就这段原文展开」
    // 连同选区一起发过来时，主语就成了「段原文展开」，覆盖率判定永远失败。
    _lastSubject = '';
    for (final t in userTerms) {
      if (!_isCleanTerm(t)) continue;
      _lastSubject = t;
      break;
    }
    if (_lastSubject.isEmpty) {
      _lastSubject =
          userTerms.isNotEmpty ? userTerms.first : (out.isEmpty ? '' : out.first);
    }
    if (out.isEmpty) {
      // 全是虚词/单字（「它呢」「这个」）：退回 2-gram 兜底，别让检索空转
      for (final seg in text.split(' ')) {
        for (var i = 0; i + 2 <= seg.length; i++) {
          final w = seg.substring(i, i + 2);
          if (seen.add(w)) out.add(w);
          if (out.length >= 6) return out;
        }
      }
    }
    return out.length > 8 ? out.sublist(0, 8) : out;
  }

  /// 概念词典没收、但属于固定搭配的复音词。
  /// 这类词里夹着虚字（实事求是、否定之否定、矛盾的主要方面），
  /// 按虚字切完就只剩碎片，检索再也拼不回去——所以整词另存一份。
  static const List<String> _wholeTerms = [
    '实事求是', '从实际出发', '理论联系实际', '具体问题具体分析',
    '否定之否定', '矛盾的主要方面', '主要矛盾方面', '量变到质变',
    '对立统一', '一分为二', '两点论', '重点论',
    '人民内部矛盾', '敌我矛盾', '民主集中制', '统一战线',
    '群众路线', '独立自主', '自力更生', '调查研究',
    '经济基础', '上层建筑', '意识形态', '阶级斗争',
    '人民民主专政', '按劳分配', '各尽所能', '共产主义',
    '社会主义', '唯物主义', '唯心主义', '形而上学',
    '生产关系', '生产力', '剩余价值', '帝国主义',
  ];

  /// 概念词典里的标准术语（含同义写法）：长度 3—8，只留中文。
  /// 用来防止长术语被单字虚词表切碎，切完就再也检不回来。
  static List<String>? _glossary;
  static List<String> _glossaryTerms() {
    final cached = _glossary;
    if (cached != null) return cached;
    final out = <String>[];
    final seen = <String>{};
    for (final c in OfflineContent.conceptList) {
      final names = <String>[
        '${c['name'] ?? ''}',
        ...((c['equivalent_terms'] as List?) ?? const []).map((e) => '$e'),
      ];
      for (final n in names) {
        final t = n.trim();
        if (t.length < 3 || t.length > 8) continue;
        if (!_hasCjk(t)) continue;
        if (seen.add(t)) out.add(t);
      }
    }
    _glossary = out;
    return out;
  }

  /// 去掉首尾虚词（不切中间的：「主要矛盾」里的「要」是实词成分）。
  static String _trimStops(String w) {
    var a = 0;
    var b = w.length;
    while (a < b && _trimSet.contains(w.codeUnitAt(a))) {
      a++;
    }
    while (b > a && _trimSet.contains(w.codeUnitAt(b - 1))) {
      b--;
    }
    return w.substring(a, b);
  }

  // ---------------------------------------------------- 人名 / 作者 / 书名
  /// 问句里点名的人名和著作名不是「内容词」，而是**限定条件**：
  /// 「毛泽东如何看待调查研究」真正要检索的是「调查研究」，
  /// 而「毛泽东」应该用来把结果往他本人的著作上拉。
  static const Set<String> _nameSuffixes = {
    '主义', '思想', '理论', '学说', '路线', '同志', '选集', '文集', '全集', '著作',
  };
  static Set<String>? _names;
  static Map<String, String>? _authorOfWork;

  static void _ensureNames() {
    if (_names != null) return;
    final names = <String>{};
    final owners = <String, String>{};
    for (final w in OfflineContent.works) {
      final work = '${w['work'] ?? ''}';
      final au = '${w['author'] ?? ''}';
      if (work.isNotEmpty) owners[work] = au;
      for (final a in au.split(RegExp(r'[、，,和与]'))) {
        final t = a.trim();
        if (t.length >= 2 && t.length <= 8) names.add(t);
      }
    }
    _authorOfWork = owners;
    _names = names;
  }

  /// 人名只在词首/词尾剥离（「马克思主义」不能剥离成「主义」）。
  static String _stripNames(String w) {
    if (_names == null || _names!.isEmpty) return w;
    var out = w;
    for (final n in _names!) {
      if (out.length <= n.length) continue;
      if (out.startsWith(n)) {
        final rest = out.substring(n.length);
        // 「马克思主义」「列宁思想」是**独立概念**，剥掉人名只剩「主义」就废了
        if (rest.length >= 2 && !_nameSuffixes.contains(rest)) out = rest;
      } else if (out.endsWith(n)) {
        final rest = out.substring(0, out.length - n.length);
        if (rest.length >= 2) out = rest;
      }
    }
    return out;
  }

  /// 问句里点名了哪些作者（用于把结果向其本人著作倾斜）
  static List<String> _preferredAuthors(String query) {
    _ensureNames();
    final hit = <String>[];
    for (final n in _names!) {
      if (query.contains(n)) hit.add(n);
    }
    hit.sort((a, b) => b.length.compareTo(a.length));
    return hit;
  }

  /// 问句里点名了哪些书（《矛盾论》→ 全书名的「矛盾论」）
  static Set<String> _preferredWorks(String query) {
    _ensureNames();
    final out = <String>{};
    for (final m in RegExp(r'《([^》]{2,20})》').allMatches(query)) {
      final t = (m.group(1) ?? '').trim();
      if (t.isEmpty) continue;
      for (final w in _authorOfWork!.keys) {
        if (w == t || w.contains(t) || t.contains(w)) out.add(w);
      }
    }
    return out;
  }

  /// 词权：越长越具体；泛词打折
  static double _termWeight(String t) {
    final base = math.pow(t.length, 1.5).toDouble();
    return _weak.contains(t) ? base * 0.35 : base;
  }

  /// 只切句、不改字：中文句末标点 + 换行
  static List<String> _sentences(String text) {
    final cached = _sentCache[text];
    if (cached != null) return cached;
    const enders = '。！？；!?;\n';
    final out = <String>[];
    final buf = StringBuffer();
    for (final r in text.runes) {
      final ch = String.fromCharCode(r);
      buf.write(ch);
      if (enders.contains(ch)) {
        final s = buf.toString().trim();
        if (s.replaceAll(_wsRe, '').length >= 8) out.add(s);
        buf.clear();
      }
    }
    final tail = buf.toString().trim();
    if (tail.replaceAll(_wsRe, '').length >= 8) out.add(tail);
    final res = out.isEmpty ? <String>[text.trim()] : out;
    if (_sentCache.length > 800) _sentCache.clear();
    _sentCache[text] = res;
    return res;
  }

  /// 引文去重签名：去掉空白与标点后取前 16 字。
  /// （同一句话在分片里可能以「条目版」「正文版」各登一份，
  /// 标点/空格不同 —— 按原样比前 24 字会漏掉，回答里就印两遍。）
  /// 出处串不能整段照印：解析章节标题时曾把「第X章…」整句正文当成章节名，
  /// 于是出处变成「第一章第一节更加科学而严密地…」几百字，读者以为引文串行。
  static String _shortLoc(String loc) {
    final t = loc.trim();
    if (t.length <= 18) return t;
    return '${t.substring(0, 18)}…';
  }

  static String _quoteSig(String s) {
    final t = s.replaceAll(RegExp(r'[^\u4e00-\u9fffA-Za-z0-9]'), '');
    return t.length >= 16 ? t.substring(0, 16) : t;
  }

  static const int _maxQuote = 220;

  /// 目录/出版说明类来源（如《…选集（四卷本·目录序言）》）不是原著正文，
  /// 与后端 `retrievable_chunks()` 同口径：不进检索候选，只在书目/阅读原文里出现。
  static bool _isIndexSource(String source) => source.contains('目录');

  /// 目录/索引类片段不是正文：被当成「原文摘录」会让人以为原著就这么写。
  /// 判据用两条硬信号：来源名含「目录」，或片段是「短碎片 + 半角逗号」的目录行。
  /// 为什么必须带「无句号 + 平均句段短」两条件：《苏联社会主义经济问题》
  /// 《论列宁主义的几个问题》的正文 OCR 出来就是半角逗号，光看逗号个数会把
  /// 整本书当成目录（实测误判 396 片，其中 248 片来自《苏联社会主义经济问题》）。
  static bool _isIndexLike(String source, String text) {
    if (_isIndexSource(source)) return true;
    final n = _commaRe.allMatches(text).length;
    if (n < 3) return false;
    if (text.contains('。')) return false;
    return text.length / (n + 1) < 14;
  }

  /// 从命中的原文里取一句「定义句」（含 就是/是指/所谓/意味着/本质）。
  /// 术语库没收录这个概念时，这是唯一不用自己编造的释义来源。
  static String _definitionSentence(
      List<Map<String, dynamic>> chunks, List<String> terms) {
    final head = _subjectHead(terms);
    if (head.isEmpty) return '';
    for (final c in chunks.take(3)) {
      final def = _definingSentence('${c['text'] ?? ''}', head);
      if (def.isNotEmpty) return def;
    }
    // 问句主语不是「X 的 Y」时上文可能定不出来，退回整块找「X是……」的句子
    for (final c in chunks.take(3)) {
      for (final raw in _sentences('${c['text'] ?? ''}')) {
        final st = raw.trimLeft();
        if (!_defineRe.hasMatch(st) || st.length < 12) continue;
        for (final t in terms) {
          if (st.startsWith(t)) return st;
        }
      }
    }
    return '';
  }

  /// 原文层判定：只有 layer==1 的分片才是作者原话。
  static bool _isOriginal(Map<String, dynamic> chunk) {
    final l = chunk['layer'];
    if (l == null) return true;
    if (l is num) return l == 1;
    return '$l'.trim() == '1';
  }

  /// 最常见的两字核心名词：概念词典只收「阶级斗争」不收「阶级」，
  /// 只收「商品价值」类的复合词，光靠术语表会把「阶级」「劳动」判成碎片。
  static const Set<String> _coreNouns = {
    '阶级', '劳动', '资本', '商品', '价值', '货币', '工资', '利润', '市场',
    '国家', '政权', '政党', '群众', '人民', '民族', '战争', '和平', '革命',
    '历史', '社会', '意识', '认识', '真理', '自由', '平等', '剥削', '压迫',
    '民主', '专政', '经济', '政治', '文化', '思想', '理论', '实践', '矛盾',
    '物质', '运动', '时间', '空间', '原因', '结果', '规律', '科学', '技术',
  };

  /// 术语白名单：概念词典的标准名/同义词 + 固定搭配表。
  static Set<String>? _knownTermsCache;
  static Set<String> _knownTerms() {
    final cached = _knownTermsCache;
    if (cached != null) return cached;
    final out = <String>{..._wholeTerms};
    for (final c in OfflineContent.conceptList) {
      final n = '${c['name'] ?? ''}'.trim();
      if (n.isNotEmpty) out.add(n);
      for (final e in ((c['equivalent_terms'] as List?) ?? const [])) {
        final t = '$e'.trim();
        if (t.isNotEmpty) out.add(t);
      }
    }
    return _knownTermsCache = out;
  }

  /// 虚词/副词：词里出现它们，说明这是按虚词切开后剩下的碎片
  /// （「旧唯物主义只」「段话」），不是能摆给读者看的关键词。
  static const Set<String> _funcChars = {
    '只', '也', '都', '就', '才', '又', '还', '而', '则', '其', '之', '者', '所',
    '被', '把', '让', '使', '得', '地', '了', '着', '过', '很', '最', '更', '不',
    '没', '要', '会', '能', '可', '应', '该', '在', '于', '与', '和', '及', '或',
    '对', '向', '从', '为', '以', '并', '且', '若', '如', '虽', '但', '却', '即',
    '乃', '将', '已', '未', '再', '吗', '呢', '吧', '啊', '的', '是', '有', '这',
    '那', '哪', '谁', '怎', '么', '些', '个', '给', '同', '跟', '比', '越', '太',
  };

  /// 能不能当「关键词」摆出来：整词、够短、不含虚字；
  /// 两字词还要在术语白名单里（「实践」「矛盾」进得去，「段话」进不去）。
  static bool _isCleanTerm(String t) {
    if (t.length < 2 || t.length > 8) return false;
    if (t.codeUnits.any(_stopSet.contains)) return false;
    // 只看首尾：中间的虚字很正常（社会主义、生产力、主观能动性），
    // 按「含虚字就丢」会把「社会主义初级阶段」这种真概念判成碎片，
    // 主语一丢，覆盖率判定就落到补进来的短词上，答非所问也报「答出来了」。
    if (_funcChars.contains(t[0]) || _funcChars.contains(t[t.length - 1])) {
      return false;
    }
    if (t.length >= 3) return true;
    return _knownTerms().contains(t) || _coreNouns.contains(t);
  }

  /// 命中段落与用户选区之间有没有**逐字重合**的长串（去标点空白后 12 字）。
  /// 用来回答「库里到底有没有他要问的那句话」，免得把真命中报成假警报。
  static bool _sharesSpan(List<String> texts, String selection) {
    const span = 12;
    final sel = selection.replaceAll(RegExp(r'[^\u4e00-\u9fffA-Za-z0-9]+'), '');
    if (sel.length < span) return false;
    for (final t in texts) {
      final hay = t.replaceAll(RegExp(r'[^\u4e00-\u9fffA-Za-z0-9]+'), '');
      if (hay.length < span) continue;
      for (var i = 0; i + span <= sel.length; i += 4) {
        if (hay.contains(sel.substring(i, i + span))) return true;
      }
    }
    return false;
  }

  /// 摘录开头的脚注标记。「［……］[20]实际上，而且对实践的唯物主义者……」这种
  /// 句子逐字是逐字了，但编号对读者是噪声——只删开头的方括号块，不动正文。
  static final RegExp _leadAnnotation = RegExp(
      r'^\s*(?:[\[［〔【(（][^\]］〕】)）]{0,40}[\]］〕】)）]\s*)+');

  /// 引号必须成对：`_quoteOf` 可能从「个人利益必须服从社会利益。」这种半个
  /// 引号处起头，原样塞进「」里读者会以为原文排版出错。成对则原样返回。
  static String _balanceQuote(String quote) {
    const pairs = {'“': '”', '「': '」', '『': '』', '（': '）', '(': ')'};
    var out = quote.trim();
    for (final e in pairs.entries) {
      var open = e.key.allMatches(out).length;
      final close = e.value.allMatches(out).length;
      while (open > close && out.startsWith(e.key)) {
        out = out.substring(1).trimLeft();
        open--;
      }
    }
    final trimmed = out.trimRight();
    if (trimmed.endsWith('，') || trimmed.endsWith('、')) {
      out = '${trimmed.substring(0, trimmed.length - 1)}……';
    }
    return out.trim();
  }

  /// 句子级逐字摘录：返回 (摘录, 该句得分)。一句都不命中时退回首句。
  /// 摘一句最有证据力的原文（逐字，不改写）。
  ///
  /// [preferDefine] 时优先给「定义句」：问「什么是X」，最该出现的是
  /// 「X就是……」那一句，而不是段落里随便一句提到 X 的话。
  static (String, double) _quoteOf(
      Map<String, dynamic> chunk, List<String> terms,
      {bool preferDefine = false}) {
    final text = '${chunk['text'] ?? ''}';
    if (text.trim().isEmpty) return ('', 0);
    final sents = _sentences(text);
    // 问「什么是 X」时先把这一段自己的界定句找出来（「生产力是生产中最活动、
    // 最革命的力量」），摘句时就钉住它——以前只按 `_defineRe`（就是/是指）
    // 加分，纯「是」的界定句不加分，结果摘到前面那句碎片「生产力的增长的现象。」
    final head = preferDefine ? _subjectHead(terms) : '';
    final defSentence = head.isEmpty ? '' : _definingSentence(text, head);
    final defMark = defSentence.length < 8
        ? defSentence
        : defSentence.substring(0, math.min(14, defSentence.length));
    var best = -1;
    var bestScore = -1.0;
    var fallback = -1;
    var fallbackScore = -1.0;
    for (var i = 0; i < sents.length; i++) {
      final s = sents[i];
      var sc = 0.0;
      for (final t in terms) {
        if (_hitAny(s, _needles(t))) sc += _termWeight(t);
      }
      if (sc <= 0) continue;
      // 编者注 / 版本说明不是作者原话，摘进引文等于替编者代言；
      // 问句更不是答案——教材常把小标题写成问句（「实践为什么是检验真理的
      // 唯一标准呢？」），只打折的话整段就一句问话时还是会被摘出来当依据。
      if (_noteRe.hasMatch(s) || _questionEndRe.hasMatch(s)) continue;
      if (fallbackScore < 0) {
        fallback = i;
        fallbackScore = sc;
      }
      if (preferDefine && _defineRe.hasMatch(s)) sc *= 1.8;
      // 转引句压权：普列汉诺夫「他说：『……』」这类二手转述照样是本行原文，
      // 但用户想看的往往是马克思本人那一条，别让别人的引用顶到最前面。
      if (_nestedQuoteRe.hasMatch(s)) sc *= 0.7;
      if (defMark.isNotEmpty && s.contains(defMark)) sc *= 3;
      if (sc > bestScore) {
        bestScore = sc;
        best = i;
      }
    }
    if (best < 0) {
      if (fallback < 0) return ('', 0);
      best = fallback;
      bestScore = fallbackScore;
    }
    final picked = <String>[sents[best]];
    // 前一句通常正是被反驳的前提/立场，带上更像完整引文；
    // 但注释行、问句、以及完全不含检索词的句子只会稀释引文。
    if (best > 0) {
      final prev = sents[best - 1];
      final brief = prev.length + picked.first.length <= 200;
      final useful = !_noteRe.hasMatch(prev) &&
          !_questionEndRe.hasMatch(prev) &&
          terms.any((t) => _hitAny(prev, _needles(t)));
      if (brief && useful) picked.insert(0, prev);
    }
    var quote = picked.join();
    if (quote.length > _maxQuote) {
      quote = '${quote.substring(0, _maxQuote)}……';
    }
    return (_balanceQuote(quote.replaceFirst(_leadAnnotation, '')), bestScore);
  }

  // 段落→章节反查表：以前每次提问都线性扫一遍全部章节节点（几千条），
  // 现在建一次表（节点数变了才重建），查表 O(1)。
  static Map<String, String>? _paraSection;
  static int _paraSectionBuilt = -1;

  static String? _sectionOfParagraph(String paragraphId) {
    if (paragraphId.isEmpty) return null;
    final nodes = OfflineContent.allNodes;
    if (_paraSection == null || _paraSectionBuilt != nodes.length) {
      final m = <String, String>{};
      for (final n in nodes) {
        final p = '${n['paragraph'] ?? ''}';
        if (p.isEmpty) continue;
        m.putIfAbsent(p, () => '${n['section_id'] ?? ''}'); // 先到先得，与原语义一致
      }
      _paraSection = m;
      _paraSectionBuilt = nodes.length;
    }
    return _paraSection![paragraphId];
  }

  /// 每种模式要的原文不同，打分口味也不同（这是「模式真的有用」的关键）
  static double _modeBoost(String mode, String text) {
    switch (mode) {
      case 'debate':
        // 辩难要的是强断言，反方才有靶子
        return _strongAssertRe.hasMatch(text) ? 1.18 : 1.0;
      case 'dig':
        // 追问要的是转折与因果，那里才有「为什么」
        return _turningRe.hasMatch(text) ? 1.18 : 1.0;
      case 'connect':
        // 关联要的是方法性表述，便于跨著作类比
        return _methodRe.hasMatch(text) ? 1.15 : 1.0;
      case 'test':
        // 应试要的是定义句，可直接作为答题依据
        return _defineRe.hasMatch(text) ? 1.15 : 1.0;
      default:
        return 1.0;
    }
  }

  /// 临时诊断开关（调参用，正式代码不再打开）。
  static bool debugTrace = false;

  static final Map<String, List<Map<String, dynamic>>> _retrieveCache = {};

  /// 按查询词给原文分片打分，返回最高分的若干条。
  /// [mode] 影响打分口味；[paragraphId] 是学习者当前所在段落（强相关锚点）。
  static List<Map<String, dynamic>> _retrieve(
      String query, String paragraphId, String mode,
      {int top = 3}) {
    final base = _keywords(query);
    if (base.isEmpty) return const [];
    // 本机语料全是中文原著：英文、纯数字提问只会在脚注页码里蹭到命中
    if (!base.any(_hasCjk)) return const [];
    // 问句点名了术语卡 → 连带它的标准名/同义词一起检，召回更稳
    final expanded = _expandTerms(base, query);

    final sectionId = _sectionOfParagraph(paragraphId);
    final meta = sectionId == null ? null : OfflineContent.sectionMeta(sectionId);
    final work = '${meta?['local_work'] ?? meta?['work_short'] ?? meta?['work'] ?? ''}';
    var pool = work.isEmpty
        ? OfflineContent.allChunksView
        : OfflineContent.chunksOfWorkView(work);
    if (pool.isEmpty) pool = OfflineContent.allChunksView;
    // 章节挂的书名在分片里对不上时，scope 退回全库，与 pool 保持一致
    final scope = identical(pool, OfflineContent.allChunksView) ? '' : work;

    // 缓存键只看「原始检索词 + 段落 + 模式」：拆词块是同一份输入必然推导出
    // 同一结果的确定性步骤，不必进键——否则每次重复提问都要先跑一遍拆词扫描。
    final terms0 = <String>[for (final pair in expanded) pair.$1];
    final key = '$mode|$paragraphId|${terms0.join('|')}';
    final cached = _retrieveCache[key];
    if (cached != null) {
      _lastTerms = terms0;
      return cached;
    }
    var weighted = expanded;
    var terms = terms0;
    _lastTerms = terms;

    // 问句点名了作者 / 书名 → 结果向那几部著作倾斜。
    // 以前「毛泽东如何看待调查研究」把别人写的著作里的编者注顶到第一条，
    // 就是因为没把「毛泽东」当限定条件、反而当成了检索词。
    final preferAuthors = _preferredAuthors(query);
    final preferWorks = _preferredWorks(query);

    final defQ = _isDefinitionQuestion(query);
    // 只拿问句里**最长的实词**当「整词加分」依据：以前用整句（含「什么是」），
    // 于是原样复述问话的引子段（「什么是商品的价值？这个问题是必须解答的」）
    // 被顶到第一，真正作答的段落反而排后面。
    final whole = terms.reduce((a, b) => b.length > a.length ? b : a);
    final all = OfflineContent.allChunksView;
    final total = all.length;
    // ── 检索打分：一次探针扫描 + 候选集内比对 ──────────────────────────
    //
    // 旧写法对每个词各扫一遍全库（实测每次约 20ms / 2.3 万段），
    // 五个词就是 100ms。现在只用**最具体的一个词**扫一遍全池拿到候选，
    // 其余词只在候选集里比，代价降到一次扫描。
    _ensureChunkIndex(all);
    // 探针词要「够具体但不至于太罕」：太热（上万段）候选爆掉，
    // 太罕（一两段）会把别处的证据全丢掉。按离目标区间 600 的距离排。
    final ordered = [...terms]..sort((a, b) {
        // 长的先扫：问「社会主义初级阶段」时，泛词「社会主义」先扫会
        // 立刻凑够 60 个候选并收手，稀有的整词一次都没扫到，那一段
        // （同时含两个词、覆盖率 1.0）永远进不了候选集。
        final d = b.length.compareTo(a.length);
        if (d != 0) return d;
        return _probeCost(a, scope).compareTo(_probeCost(b, scope));
      });
    final scanned = <String, List<int>>{};
    final candidates = <int>{};
    var probeTries = 0;
    for (var attempt = 0; attempt < ordered.length; attempt++) {
      // 最具体的两个词都没命中，就不必把剩下的词一个个扫下去
      if (attempt >= 2 && scanned.isEmpty) break;
      if (probeTries >= 3) break;
      probeTries++;
      final t = ordered[attempt];
      final hits = _scanFor(t, pool);
      if (hits.isEmpty) {
        _emptyPost.add(scope.isEmpty ? t : '#$scope$t');
        continue;
      }
      scanned[t] = hits;
      candidates.addAll(hits);
      final probeKey = scope.isEmpty ? t : '#$scope$t';
      if (hits.length <= _maxPostingLen) _postings[probeKey] = hits;
      // 候选太少说明这个词太罕，再扫一个词补召回；够用就收手
      if (candidates.length >= 60) break;
      if (scanned.length >= 3) break;
    }
    // 探针拿到的候选太少（或整轮零命中）→ 才去拆词块补召回。
    // 「辩证否定观」库里写作「否定的否定」，整词硬检一条都没有。
    // 倒排表在 _withFallback 里一遍扫描批量建好，这里直接查表，不再扫全库。
    final noStrongHit = !scanned.keys.any((t) => t.length >= 3);
    if (candidates.length < 40 || noStrongHit) {
      final fb = _withFallback(weighted, scope);
      if (fb.length > weighted.length) {
        weighted = fb;
        terms = <String>[for (final p in fb) p.$1];
        _lastTerms = terms;
        final extra = terms.where((t) => !scanned.containsKey(t)).toList()
          ..sort((a, b) => _probeCost(a, scope).compareTo(_probeCost(b, scope)));
        for (final t in extra) {
          if (candidates.length >= 60) break;
          final post = _postings[scope.isEmpty ? t : '#$scope$t'];
          if (post == null || post.isEmpty) continue;
          scanned[t] = post;
          candidates.addAll(post);
        }
      }
    }
    if (candidates.isEmpty) return const [];
    final cand = candidates.toList();

    final scoreOf = <int, double>{};
    final hitsOf = <int, int>{};
    final termHits = <(String, double, List<int>)>[];
    for (final (t, factor) in weighted) {
      final pre = scanned[t];
      if (pre != null) {
        termHits.add((t, factor, pre));
        continue;
      }
      final needles = _needles(t);
      final hits = <int>[];
      for (final i in cand) {
        if (_hitAny(all[i]['text'] as String? ?? '', needles)) hits.add(i);
      }
      if (hits.isNotEmpty) termHits.add((t, factor, hits));
    }
    for (final (t, factor, hits) in termHits) {
      // 词权按「候选集内的文档频率」折算 IDF —— 与全库 df 单调一致，
      // 省下的正是那几遍全库扫描
      final w = factor >= 1.0
          ? _weightOf(t, hits.length, total)
          : _termWeight(t) * 0.45;
      for (final i in hits) {
        scoreOf[i] = (scoreOf[i] ?? 0) + w;
        hitsOf[i] = (hitsOf[i] ?? 0) + 1;
      }
    }
    if (scoreOf.isEmpty) return const [];
    // 定义题专用：候选段里「X 是……」这种界定句相乘子。以前用 _sentences
    // 逐段断句，4 万候选时「什么是阶级」要 490ms；这里直接扫原文找词后 6 字。
    final defTerms = defQ ? terms.take(4).toList() : const <String>[];
    final topic = _subjectHead(terms);
    // 「(所谓)X，就是……」这种**句首定义框架**，是问「什么是 X」时最硬的证据。
    // 不这样钉住，「什么是阶级」会被一句带「资产阶级」的长段抢走。
    final defFrameRe = defQ && topic.length >= 2
        ? RegExp('(^|[。！？；\n])(所谓)?${RegExp.escape(topic)}[，,]?(就是|是指|是|即|乃)')
        : null;
    // 倒排表已经按 work 分桶，这里只剩「该书名没对应的分片」这一种兜底
    final filterWork = scope;
    final scored = <(double, Map<String, dynamic>)>[];
    for (final e in scoreOf.entries) {
      final c = all[e.key];
      // 热循环里不要用字符串插值取字段：2 万多段各复制一遍正文是这里最大的开销
      final text = c['text'] as String? ?? '';
      if (text.isEmpty) continue;
      var score = e.value;
      final hits = hitsOf[e.key] ?? 1;
      final src = c['source'] as String? ?? '';
      if (filterWork.isNotEmpty && src != filterWork) continue;
      // 长段不因字多占优
      if (defTerms.isNotEmpty && _defQuick(text, defTerms)) score *= 1.6;
      // 注疏层（命题概括/术语注释/哲学解析）压权：它的字句最能对上问法，
      // 于是常把真正的原文挤到后面，回答里「原文摘录」就只剩编者的话（甚至
      // 一句可摘的都没有）。改编者的话当补充可以，当主证不行。
      if (!_isOriginal(c)) score *= 0.55;
      if (defFrameRe != null && defFrameRe.hasMatch(text)) score *= 2.4;
      if (topic.length >= 2) {
        final at = text.indexOf(topic);
        // 段首点到主语 = 这段就以它为主题；但「帝国主义的主要矛盾」是
        // 「帝国主义」的下属议题（主语前一个字是「的/之」），不算主题句。
        if (at >= 0 &&
            at <= 12 &&
            (at == 0 || !'的之'.contains(text[at - 1]))) {
          score *= 1.3;
        }
      }
      score /= 1 + math.log(1 + text.length / 260);
      // 覆盖率：只命中一个词不算强证据。以前系数 0.62 太宽，
      // 《提纲》里一句带「自我矛盾」的话就能抢答「主要矛盾」。
      score *= 0.5 + 0.5 * hits / terms.length;
      if (terms.length >= 3 && hits == 1) score *= 0.8;
      // 只有够长的整词才加分：4 字的「主要矛盾」在库里到处都是，
      // 拿它加分会把「帝国主义的主要矛盾」这种顺带一提的段顶到第一。
      if (whole.length >= 5 && text.contains(whole)) score *= 1.7;
      if ((c['paragraph_id'] as String? ?? '') == paragraphId) score *= 2.2;
      // 目录/出版说明类来源直接出局：这类书分片还原后可读性变好，
      // 靠 0.3 系数压不住了，会顶掉真正的正文出处
      if (_isIndexSource(src)) continue;
      if (_isIndexLike(src, text)) score *= 0.3;
      // 整段是编者注/版本说明的，不能当原文依据
      if (_noteRe.hasMatch(text.length > 40 ? text.substring(0, 40) : text)) {
        score *= 0.25;
      }
      if (preferWorks.isNotEmpty) {
        score *= preferWorks.contains(src) ? 1.6 : 0.6;
      }
      if (preferAuthors.isNotEmpty) {
        final au = _authorOfWork?[src] ?? '';
        var ok = false;
        for (final a in preferAuthors) {
          if (au.contains(a)) {
            ok = true;
            break;
          }
        }
        score *= ok ? 1.35 : 0.85;
      }
      score *= _modeBoost(mode, text);
      scored.add((score, c));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    // 定义型问句（「X 的本质是什么」）只留**有界定句的段**：以被问的词开头、
    // 紧跟「是／就是／是指」的那一句。只「提到」被问的词不算——
    // 「还没有进一步领悟到国家的本质」是提及，不是界定（压权压不住 41.8 分），
    // 一条界定句都没有时保持原排名，别把答案清空。
    if (defQ && scored.length > 1) {
      // 只看前 24 条：输出只要 3 条，逐段断句是热路径里最贵的一步
      final subject0 = _subjectHead(terms);
      final defs = [
        for (final row in scored.take(24))
          if (_definingSentence(row.$2['text'] as String? ?? '', subject0)
              .isNotEmpty)
            row,
      ];
      if (defs.isNotEmpty) {
        scored
          ..clear()
          ..addAll(defs);
      }
    }
    if (debugTrace) {
      // ignore: avoid_print
      print('TRACE q=$query terms=$terms pool=${pool.length} ');
      for (final row in scored.take(5)) {
        final t = row.$2['text'] as String? ?? '';
        // ignore: avoid_print
        print('   ${row.$1.toStringAsFixed(1)} | ${row.$2['source']} | ${t.length}字 | ${t.substring(0, math.min(40, t.length))}');
      }
    }

    final out = <Map<String, dynamic>>[];
    final seenParagraph = <String>{};
    final seenText = <String>{};
    for (final row in scored) {
      if (out.length >= top) break;
      final pid = row.$2['paragraph_id'] as String? ?? '';

      // 同一段原文只保留一条，避免三条全是同一处的重复
      if (pid.isNotEmpty && !seenParagraph.add(pid)) continue;
      // 有些著作同一段文字被登记成两个相邻段落编号（标题/正文各一份）——
      // 按正文前 60 字去重，否则引文会重复两遍
      final head = _quoteSig(row.$2['text'] as String? ?? '');
      if (head.length >= 16 && !seenText.add(head)) continue;
      out.add(row.$2);
    }
    if (_retrieveCache.length >= 48) _retrieveCache.clear();
    _retrieveCache[key] = out;
    return out;
  }

  /// 跨著作检索：同一组关键词在**别的**著作里怎么用（「关联」模式的实料）。
  /// 一次全库扫描，实测 20—40ms，结果按关键词缓存。
  static final Map<String, List<Map<String, dynamic>>> _crossCache = {};

  static List<Map<String, dynamic>> _crossWorkHits(
      List<String> terms, String excludeWork,
      {int top = 2, Set<String> skip = const {}}) {
    if (terms.isEmpty) return const [];
    final strong = terms.where((t) => t.length >= 3).toList();
    // 只有「矛盾」「实践」这种两字泛词时不做跨著作对照：
    // 全库搜两字词必然命中一堆不相干的段落，宁可诚实说做不了。
    if (strong.isEmpty) return const [];
    final use = strong.take(3).toList();
    final key = '${use.join('|')}#$excludeWork#${skip.join(',')}';
    final cached = _crossCache[key];
    if (cached != null) return cached;

    final all = OfflineContent.allChunksView;
    _ensurePostings(use);
    final scoreOf = <int, double>{};
    final hitsOf = <int, int>{};
    for (final t in use) {
      final post = _postingsOf(t);
      if (post.isEmpty) continue;
      final w = _weightOf(t, post.length, all.length);
      for (final i in post) {
        scoreOf[i] = (scoreOf[i] ?? 0) + w;
        hitsOf[i] = (hitsOf[i] ?? 0) + 1;
      }
    }
    final scored = <(double, Map<String, dynamic>)>[];
    for (final e in scoreOf.entries) {
      final c = all[e.key];
      final src = c['source'] as String? ?? '';
      if (src == excludeWork || skip.contains(src)) continue;
      final text = c['text'] as String? ?? '';
      if (text.length < 40) continue;
      final hits = hitsOf[e.key] ?? 1;
      if (_isIndexLike(src, text)) continue;
      // 注疏层（layer≥2）是编者的话，不能进「同一说法在别的著作里（逐字）」
      if (!_isOriginal(c)) continue;
      // 只靠一个词命中的，多半是巧合（实测「实践唯物主义」跨到《唯物主义和
      // 经验批判主义》里讲记述心理学的 800 字长段：「同一说法」根本不存在）。
      if (hits < 2 || hits < use.length - 1) continue;
      // 「同一说法在别的著作里」得是能整句读的短命题，长段里凑齐两个词不算。
      if (text.length > 400) continue;
      scored.add((e.value, c));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));

    final out = <Map<String, dynamic>>[];
    final usedWork = <String>{};
    for (final row in scored) {
      if (out.length >= top) break;
      // 一部著作只出一条，才有「跨著作」的意义
      if (!usedWork.add(row.$2['source'] as String? ?? '')) continue;
      out.add(row.$2);
    }
    if (_crossCache.length >= 16) _crossCache.clear();
    _crossCache[key] = out;
    return out;
  }

  /// 概念卡命中：**问句点名优先**；问句没点名最多补一张，
  /// 且要求该术语在原文里真的反复出现（>=2 次），否则宁可空着。
  static List<Map<String, dynamic>> _conceptHits(
    String query,
    List<Map<String, dynamic>> chunks,
    String mode,
  ) {
    final picked = <Map<String, dynamic>>[];
    final seen = <String>{};
    List<String> aliasesOf(Map c) => [
          '${c['name'] ?? ''}',
          ...((c['equivalent_terms'] as List?) ?? const []).map((e) => '$e'),
        ].where((e) => e.isNotEmpty).toList();

    // ① 问句里直接点名（最可靠）
    for (final c in OfflineContent.conceptList) {
      if (aliasesOf(c).any(query.contains)) {
        if (seen.add('${c['name']}')) picked.add(c);
      }
      if (picked.length >= 3) break;
    }
    if (picked.isNotEmpty) return picked;

    // ② 不再按「命中段落里的词频」猜一张概念卡：问「矛盾的普遍性与特殊性」时
    // 它把「人的本质」顶到「一句话答」的位置，是典型的答非所问。问句没点名
    // 概念就不给概念卡，改为在引文后面按题型给拆解步骤。
    return const [];
  }

  static List<String> _questionsFor(String paragraphId, String mode) {
    final bank = (OfflineContent.knowledge['questions'] as Map?) ?? const {};
    final list = (bank[paragraphId] as List?) ?? const [];
    final wanted = switch (mode) {
      'debate' => const ['debate'],
      'test' => const ['practice', 'dig'],
      'dig' => const ['dig', 'debate'],
      'connect' => const ['dig'],
      _ => const ['dig'],
    };
    // 先按题型分桶，再**轮转**取：以前是「边遍历边数总数 <3」，
    // 第一个题型凑满 3 条就把后面的题型彻底挤掉（应试模式永远拿不到 dig 题）。
    final byType = <String, List<String>>{};
    for (final q in list) {
      if (q is! Map) continue;
      final text = '${q['q'] ?? ''}';
      if (text.isEmpty) continue;
      (byType['${q['type']}'] ??= <String>[]).add(text);
    }
    final out = <String>[];
    for (var i = 0; out.length < 3; i++) {
      var added = false;
      for (final type in wanted) {
        final bucket = byType[type];
        if (bucket == null || i >= bucket.length) continue;
        if (out.length >= 3) break;
        final text = bucket[i];
        if (out.contains(text)) continue;
        out.add(text);
        added = true;
      }
      if (!added) break;
    }
    return out;
  }

  static String _excerpt(String text) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= _maxExcerpt) return clean;
    return '${clean.substring(0, _maxExcerpt)}……';
  }

  // ------------------------------------------------------------ 检索内部件
  //
  // 倒排表（词→分片下标）：以前每次提问都对全库 2 万多段做「词数×contains」，
  // 冷问 90—150ms。现在每个词只扫库一次并缓存，之后是查表求和；
  // 顺带拿到文档频率 df，由它算 IDF——罕见词自然压过「实践」「矛盾」这类泛词。
  static final Map<String, List<int>> _postings = {};

  /// 确认零命中的词：不能反复重扫全库去找一个库里根本没有的词
  /// （「辩证否定观」这类）
  static final Set<String> _emptyPost = {};
  static int _postingsBuilt = 0;
  static const int _maxCachedTerms = 400;
  static const int _maxPostingLen = 9000;

  /// 分片在 allChunksView 里的下标（只在本文件内部用来做倒排表的键）。
  /// 写进分片 Map 里，值不进任何序列化产物。
  static const String _idxKey = '_i';
  static bool _indexed = false;

  static void _ensureChunkIndex(List<Map<String, dynamic>> all) {
    if (_indexed && all.isNotEmpty && all.first[_idxKey] == 0) return;
    for (var i = 0; i < all.length; i++) {
      all[i][_idxKey] = i;
    }
    _indexed = true;
  }

  /// 一次扫描把本轮所有没缓存的词一并建表。
  /// （逐词各扫一遍会让「第一次提问」比改造前更慢，那是拿平均换冷启动，不值。）
  ///
  /// [work] 非空时**只在那一部书里建表**：读者多半是在某章里提问，
  /// 只扫本章对应的原著（几百段）而不是全库两万多段，这是最实在的提速。
  static void _ensurePostings(List<String> terms, [String work = '']) {
    final prefix = work.isEmpty ? '' : '#$work';
    final missing = <String>[];
    for (final t in terms) {
      if (!_postings.containsKey('$prefix$t') && !_emptyPost.contains('$prefix$t')) {
        missing.add(t);
      }
    }
    if (missing.isEmpty) return;
    final all = OfflineContent.allChunksView;
    if (all.length != _postingsBuilt) {
      _postings.clear(); // 语料换了，旧表作废
      _postingsBuilt = all.length;
      _indexed = false;
    }
    final pool = work.isEmpty ? all : OfflineContent.chunksOfWorkView(work);
    if (pool.isEmpty) return;
    _ensureChunkIndex(all);
    final buckets = <String, List<int>>{for (final t in missing) t: <int>[]};
    for (final c in pool) {
      final idx = c[_idxKey];
      if (idx is! int) continue;
      final text = c['text'] as String? ?? '';
      if (text.isEmpty) continue;
      for (final t in missing) {
        if (text.contains(t)) buckets[t]!.add(idx);
      }
    }
    for (final e in buckets.entries) {
      // 太热的词（上万段命中）缓存不划算，用完即弃
      if (e.value.length <= _maxPostingLen) {
        _postings['$prefix${e.key}'] = e.value;
      }
      if (e.value.isEmpty) _emptyPost.add('$prefix${e.key}');
    }
    if (_postings.length > _maxCachedTerms) {
      _postings.clear();
      _emptyPost.clear();
    }
  }

  static List<int> _postingsOf(String term, [String work = '']) {
    final prefix = work.isEmpty ? '' : '#$work';
    final hit = _postings['$prefix$term'];
    if (hit != null) return hit;
    _ensurePostings([term], work);
    return _postings['$prefix$term'] ?? const [];
  }

  /// 长词零命中时退回它的前后词块。
  ///
  /// 库里常有「否定的否定」「主要的矛盾」这类写法，用户却写「辩证否定观」
  /// 「主要矛盾」；整词硬检只会一条都找不到，整轮回答退化成「本机没匹配到」。
  static List<(String, double)> _withFallback(
      List<(String, double)> weighted, String scope) {
    final out = <(String, double)>[...weighted];
    final seen = <String>{for (final p in weighted) p.$1};
    final added = <String>[];
    // 先一次性把「要知道有没有命中」的词全建好表（一遍扫描），
    // 再逐个判断——原来每个长词各调一次 _postingsOf 就是一遍全库扫描。
    final need = <String>[];
    for (final p in weighted) {
      final t = p.$1;
      if (t.length < 4) continue;
      if (t.codeUnits.any(_stopSet.contains)) continue;
      for (final n in _needles(t)) {
        final k = scope.isEmpty ? n : '#$scope$n';
        if (!_postings.containsKey(k) && !_emptyPost.contains(k)) need.add(n);
      }
    }
    if (need.isNotEmpty) _ensurePostings(need, scope);

    String keyOf(String t) => scope.isEmpty ? t : '#$scope$t';

    /// 整词或它的「的」变体任一有命中 → 不必拆
    bool known(String t) => _needles(t).any((n) {
          final k = keyOf(n);
          final hit = _postings[k];
          return hit != null && hit.isNotEmpty;
        });

    for (final p in weighted) {
      final t = p.$1;
      if (t.length < 4) continue;
      // 含虚词的是短语（「实践批判的活动」），拆出来的只是碎片
      if (t.codeUnits.any(_stopSet.contains)) continue;
      if (known(t)) continue;
      final subs = <String>[
        if (t.length >= 5) t.substring(t.length - 4),
        if (t.length >= 5) t.substring(0, 4),
        t.substring(0, 3),
        t.substring(t.length - 3),
        t.substring(0, 2),
        t.substring(t.length - 2),
      ];
      for (final sub in subs) {
        if (sub.length < 2) continue;
        if (!seen.add(sub)) continue;
        out.add((sub, 0.55));
        added.add(sub);
        if (added.length >= 3) break;
      }
      if (added.length >= 3) break;
    }
    // 一次批量建表：逐个补会因为每个词各扫一遍全库而变慢
    if (added.isNotEmpty) _ensurePostings(added, scope);
    return out;
  }

  /// 一个词在正文里的可能写法：库里常写「主要的矛盾」「辩证的否定观」，
  /// 用户和术语表写「主要矛盾」「辩证否定观」。同一次扫描里都比一遍，
  /// 比「先紧匹配不中再用正则补救」便宜得多（正则 310ms／次，见实测）。
  static List<String> _needles(String term) {
    final out = <String>[term];
    if (term.length >= 3 && !term.codeUnits.any(_looseCharSet.contains)) {
      out.add('${term.substring(0, 2)}的${term.substring(2)}');
    }
    return out;
  }

  static const String _looseChars = '的地得之是为和与在从到而';
  static final Set<int> _looseCharSet = {
    for (final u in _looseChars.codeUnits) u,
  };

  static bool _hitAny(String text, List<String> needles) {
    for (final n in needles) {
      if (text.contains(n)) return true;
    }
    return false;
  }

  /// 在给定池里扫一遍，拿到含该词的分片下标（唯一一次全池扫描）。
  static List<int> _scanFor(String term, List<Map<String, dynamic>> pool) {
    final needles = _needles(term);
    final out = <int>[];
    for (final c in pool) {
      final text = c['text'] as String? ?? '';
      if (text.isEmpty) continue;
      if (!_hitAny(text, needles)) continue;
      final i = c[_idxKey];
      if (i is int) out.add(i);
    }
    return out;
  }

  /// 段里是否有「X 是 / 就是 / 是指 ……」这样的界定句。
  /// 问「什么是X」时这是最该排在前面的证据。
  static final RegExp _defTurnRe =
      RegExp(r'^(所以|因此|由此可见|那末|那么|但是|然而|总之|这就是说)[，,]?\s*');
  static const String _defCops = '是就是指乃即意味着';

  /// 这段里有没有「X 是……」「X 就是……」这种**对 X 下定义**的句子。
  ///
  /// 只认**被问的那个词本身**：问「国家的本质」认的是「国家是……」，
  /// 不能因为句子里出现「社会主义就是消灭阶级」就把一段无关的话顶上来
  /// ——所以先取问句里最长的那个词，再取它「的/之」前面的中心词。
  /// 最近一次 `_keywords` 认出的问句主语（词表头部的术语整词不算主语）
  static String _lastSubject = '';

  static String _subjectHead(List<String> terms) {
    var subject = '';
    for (final t in terms) {
      if (t.length > subject.length) subject = t;
    }
    var head = subject;
    final cutD = head.indexOf('的');
    final cutZ = head.indexOf('之');
    var cut = cutD;
    if (cutD < 0) {
      cut = cutZ;
    } else if (cutZ >= 0 && cutZ < cutD) {
      cut = cutZ;
    }
    if (cut >= 2) head = head.substring(0, cut);
    return head.length >= 2 ? head : '';
  }

  /// 这段里对 [head] 下定义的那一句；只是「提到」它不算（没有则空串）。
  static String _definingSentence(String text, String head) {
    if (head.isEmpty) return '';
    for (final raw in _sentences(text)) {
      final st = raw.trimLeft().replaceFirst(_defTurnRe, '');
      if (st.length < 8) continue;
      if (!st.startsWith(head)) continue;
      final rest = st.substring(head.length).trimLeft();
      if (rest.isEmpty) continue;
      // 只认「是/就是/是指」这类判断词，且后面要有成句的内容
      if (!_defCops.contains(rest[0])) continue;
      if (rest.startsWith('不') || rest.startsWith('否')) continue;
      if (rest.length >= 6) return st;
    }
    return '';
  }

  /// 廉价界定句探测：某词之后 6 字内出现「是／就是／是指／所谓」。
  /// 只扫原文不做断句，候选上万段时也不拖慢。
  static bool _defQuick(String text, List<String> terms) {
    for (final t in terms) {
      if (t.length < 2) continue;
      var i = text.indexOf(t);
      var guard = 0;
      while (i >= 0 && guard < 6) {
        guard++;
        final from = i + t.length;
        if (from + 1 < text.length) {
          final tail = text.substring(from, math.min(text.length, from + 6));
          if (_defineAfterRe.hasMatch(tail)) return true;
        }
        i = text.indexOf(t, i + 1);
      }
    }
    return false;
  }

  static final RegExp _defineAfterRe = RegExp(r'^\s*(就是|是|是指|指的是|即是|即|乃|叫做|称为|意味着|，就是)');

  /// 挑探针词的代价：离目标频率 600 越近越小。
  /// 已知频率用真值（缓存），未知按长度估（越长越具体）。
  static double _probeCost(String term, String scope) {
    final prefix = scope.isEmpty ? '' : '#$scope';
    int est;
    final cached = _postings['$prefix$term'];
    if (cached != null) {
      est = cached.length;
    } else if (_emptyPost.contains('$prefix$term')) {
      est = 1;
    } else {
      final len = term.length;
      est = len >= 5 ? 20 : (len == 4 ? 60 : (len == 3 ? 300 : 2500));
    }
    if (est < 1) est = 1;
    return (math.log(est / 600)).abs();
  }

  /// 词权 × IDF：两个字的泛词和三个字以上的具体词不该同权
  static double _weightOf(String term, int df, int total) {
    final idf = math.log(1 + total / (1 + df));
    return _termWeight(term) * (0.55 + 0.45 * idf);
  }

  /// 最近一次检索实际使用的词表（含术语同义词与长词回退）。
  ///
  /// 摘句必须用这同一份词：只用 `_keywords` 的话，「辩证否定观」这类库里
  /// 没写成整词的问题会检索到段落、却一句引文都摘不出来。
  static List<String> _lastTerms = const [];

  static List<String> termsFor(String question) =>
      _lastTerms.isNotEmpty ? _lastTerms : _keywords(question);

  /// 问句点名了术语库里某张卡 → 把它的标准名与同义词一并用于检索。
  /// 只在「问句里真的出现别名」时触发，不会把泛词硬塞进去。
  ///
  /// 别名权重**固定打折**（且不吃 IDF）：它只补召回。否则「实践」会把
  /// 《关于费尔巴哈的提纲》里堆满「感性活动」的段落顶到第一，把真正讲
  /// 「实践是检验真理的标准」的段落挤下去。
  static List<(String, double)> _expandTerms(List<String> base, String query) {
    final out = <(String, double)>[for (final t in base) (t, 1.0)];
    final seen = base.toSet();
    if (OfflineContent.conceptList.isEmpty) return out;
    for (final c in OfflineContent.conceptList) {
      final aliases = <String>[
        '${c['name'] ?? ''}',
        ...((c['equivalent_terms'] as List?) ?? const []).map((e) => '$e'),
      ].where((e) => e.length >= 2).toList();
      if (aliases.isEmpty) continue;
      if (!aliases.any(query.contains)) continue;
      for (final a in aliases) {
        if (seen.add(a)) out.add((a, 0.5));
        if (out.length >= 10) return out;
      }
    }
    return out;
  }

  static String _clip(String text, int max) {
    final t = text.replaceAll(_wsRe, ' ').trim();
    return t.length <= max ? t : '${t.substring(0, max)}…';
  }

  /// 反方怎么攻这一句：按句子本身的话型给攻击方式，而不是每轮套同一段空话
  static String _attackOf(String sentence, String keyTerm) {
    final kw = keyTerm.isEmpty ? '这一条' : '「$keyTerm」';
    if (sentence.isEmpty) return '没有可检验的边界，说了等于没说';
    final limited = _limitRe.hasMatch(sentence);
    if (_allQuantRe.hasMatch(sentence) && !limited) {
      return '把$kw的作用说成对一切对象一律成立，通篇没有限定语——'
          '只要找到一个例外，全句就塌';
    }
    if (_onlyRe.hasMatch(sentence) && !limited) {
      return '用的是排他式说法（只能/唯一），把别的可能全排掉了——'
          '反方只要给出一个同样有效的途径就够了';
    }
    if (_causeRe.hasMatch(sentence)) {
      return '把两件事讲成单向决定，抹掉了反作用——反方会说这是把相互作用压成一条直线';
    }
    return '把有限范围内的结论说成了普遍结论，成立的边界始终没交代';
  }

  /// 这一句讲的是哪一类判断：回应时要先钉住这个环节
  static String _dimensionOf(String sentence) {
    if (_causeRe.hasMatch(sentence)) return '因果与作用次序';
    if (_defineRe.hasMatch(sentence)) return '概念界定（是什么、不是什么）';
    return '事实判断（在什么范围内成立）';
  }

  static String _limiterOf(String sentence) {
    final m = _limitRe.firstMatch(sentence);
    return m == null ? '' : m.group(0)!;
  }

  /// 各模式的引文预算：以前五个模式都铺 3 条长引文，四成篇幅完全重复
  /// 「什么是X」「X的本质是什么」「X是指什么」——这类问题要的是定义句
  static bool _isDefinitionQuestion(String question) {
    final t = question.trim();
    if (RegExp(r'什么是|什么叫|指的是|含义|定义|本质').hasMatch(t)) return true;
    return RegExp(r'(是什么|指什么|为何物)[？?]?$').hasMatch(t);
  }

  static int _quoteBudget(String mode) => switch (mode) {
        'explain' => 2,
        'dig' => 2,
        'debate' => 1,
        'connect' => 1,
        'test' => 1,
        _ => 2,
      };

  // ------------------------------------------------------------ 回答
  //
  // 「高精度」的落点：每个模式都先给**依据**（逐字引文 + 出处），再给**结论骨架**；
  // 引文只摘命中的那 1—2 句，而不是整段截前 180 字。
  // 「高效率」的落点：检索结果与查询词都按 mode+段落+关键词缓存，重复提问不重扫。
  static String _compose(
    String mode,
    String question,
    String paragraphId,
    List<Map<String, dynamic>> chunks,
    List<Map<String, dynamic>> concepts,
    bool criticalReading, {
    String selectedText = '',
  }) {
    final b = StringBuffer();
    final terms = termsFor(question);
    if (criticalReading) {
      b.writeln('【批判性阅读已开启】先复述对方立场，再作回应；对方观点不进入正面结论。\n');
    } else if (mode == 'debate') {
      // 以前这里把「辩难」也写成「批判性阅读已开启」，是误标：用户没开批判性阅读
      b.writeln('【辩难】先摆反方最强的质疑，再给回应要点；反方观点不进入正面结论。\n');
    }

    // 库里到底有没有直说这件事？最高分那一段对提问词的覆盖率低 → 只是字面擦边，
    // 老老实实标出来，别让擦边段落冒充答案（「有一段带这个词」≠「这段回答了问题」）。
    final topTexts = [for (final c in chunks.take(3)) '${c['text'] ?? ''}'];
    final topText = topTexts.isEmpty ? '' : topTexts.first;
    // 只问一件事：最高分那一段里，提问的**主词**到底在不在？
    // （同义词别名不算分母——「实践」带三个别名，一算就永远是低覆盖）
    var coveredByTop = false;
    final head = _lastSubject.isNotEmpty ? _lastSubject : _subjectHead(terms);
    if (topText.isNotEmpty && head.isNotEmpty) {
      // 允许用**词尾**命中兜底：「反对本本主义」的主语，库里只写「本本主义」。
      // 但只认词尾不认词头——「社会主义初级阶段」的主语，不能被「资产阶级的
      // 社会主义」一句顶替，那是另一个概念。
      // 看前 3 段而不是只看首段：首段常常只是擦边命中，第二段才是真正作答的
      // 那一段，只盯首段会把「库里有答案」误报成「没有直接回答这个问题的段落」。
      coveredByTop = topTexts.any((t) =>
          _hitAny(t, _needles(head)) ||
          terms.any((x) =>
              x.length >= 2 && head.endsWith(x) && _hitAny(t, _needles(x))));
    }
    // 用户点名了原文（选中一段再问）时还有一条更硬的证据：命中段落里有没有和
    // 选区**逐字重合**的长串。有，就说明他要问的那个说法确实在库里——此时主词
    // 被切坏（选中「旧唯物主义只从客体方面理解现实」，主词成了「旧唯物主义只」）
    // 而报警，是假警报。
    if (!coveredByTop && selectedText.trim().isNotEmpty) {
      coveredByTop = _sharesSpan(topTexts, selectedText);
    }
    final lowCoverage = topText.isNotEmpty && terms.isNotEmpty && !coveredByTop;

    // 问句里没有能定位原著的实词（「这段话什么意思？」只剩「段话」「意思」这种
    // 碎片）时，别从库里捞两段不相干的话冒充依据——那比承认检不到更误导。
  /// 问句里没有能定位原著的实词（「这段话什么意思？」只剩「段话」「意思」这种
  /// 碎片）时，别从库里捞两段不相干的话冒充依据——那比承认检不到更误导。
    final noRealTerm = terms.isEmpty ||
        !terms.any((t) =>
            t.length >= 3 ||
            _knownTerms().contains(t) ||
            _coreNouns.contains(t));

    // 回复要适合「手机上一屏看完」：每个模式只给最必要的东西。
    final budget = _quoteBudget(mode);
    if (chunks.isEmpty && terms.isNotEmpty && !terms.any(_hasCjk)) {
      b.writeln('【说明】本机收录的是中文原著原文，英文或纯数字提问检不到原文；'
          '换成中文术语再问（如「实践」「矛盾」「国家」）。\n');
    }
    if (noRealTerm) {
      b.writeln('【先定位】这句话里没有能定位原著的实词。'
          '请选中原文里的一段再问（或换成「实践」「矛盾」这类术语），'
          '本机才能逐字摘出依据。\n');
    } else if (lowCoverage) {
      b.writeln('【先说清楚】本机收录的正文里没有直接回答这个问题的段落，'
          '下面按字面最接近的原句给出线索，请当作线索而不是答案。\n');
    }
    // 引文只取**原文层**（layer==1）。提纲这类章节还会登记 layer 2（命题概括）/
    // 3（注释）/4（解析），那些是编者转述而不是作者原话；把它们挂在
    // 「原文摘录（逐字引用，非改写）」下面，等于替编者代言、也破了逐字门禁。
    final srcChunks = [for (final c in chunks) if (_isOriginal(c)) c];
    // 摘录再按「有没有命中主语」分两拨：问「实践唯物主义」时，《资本论》第二版跋
    // 里「马克思是最大的唯心主义哲学家」只沾了「唯心主义」这个边词，却排在正主
    // 《提纲》第 1 条前面被摘了出来。命中主语的先摘，其余垫后（组内保持原序）。
    final headNeedles = head.length >= 2 ? _needles(head) : const <String>[];
    final withHead = <Map<String, dynamic>>[];
    final withoutHead = <Map<String, dynamic>>[];
    for (final c in srcChunks) {
      final onTopic = headNeedles.isNotEmpty &&
          _hitAny('${c['text'] ?? ''}', headNeedles);
      (onTopic ? withHead : withoutHead).add(c);
    }
    final quoteSrc = [...withHead, ...withoutHead];
    final quotes = <Map<String, dynamic>>[];
    final quotedWorks = <String>{};
    if (srcChunks.isNotEmpty && !noRealTerm) {
      // 应试模式把依据句放在「得分点」里只出现一次，开头不再铺第二遍
      final showQuotes = mode != 'test';
      if (showQuotes) b.writeln('原文摘录（逐字引用，非改写）：');
      var printed = false;
      final seenQuote = <String>{};
      // 问「什么是X」时先给定义句；其余问法照常取证据句
      final preferDefine = _isDefinitionQuestion(question);
      for (final c in quoteSrc) {
        if (quotes.length >= budget) break;
        final (q, _) = _quoteOf(c, terms, preferDefine: preferDefine);
        if (q.isEmpty) continue;
        // 不同段落编号里可能藏着同一句原文（标题/正文各登一份，标点空白还不同），
        // 按去标点后的前 16 字去重，避免同一句话在回答里刷两遍
        final sig = _quoteSig(q);
        if (!seenQuote.add(sig)) continue;
        final work = '${c['source'] ?? ''}';
        quotedWorks.add(work);
        quotes.add({
          'quote': q,
          'source': work,
          'loc': '${c['source_location'] ?? ''}',
          'text': '${c['text'] ?? ''}',
        });
        if (showQuotes) {
          b.writeln('> $q');
          b.writeln('—— 《$work》 ${_shortLoc('${c['source_location'] ?? ''}')}\n');
        }
        printed = true;
      }
      if (showQuotes && !printed) {
        b.writeln('（本轮片段没有可逐字摘录的完整句）\n');
      }
    }
    final firstQuote = quotes.isEmpty ? '' : '${quotes.first['quote']}';
    final questions = _questionsFor(paragraphId, mode);

    /// 引文里出现过的最长关键词：追问、辩难都拿它当靶子，比模板变量精准
    String keyTermOf(String text) {
      var best = '';
      for (final t in terms) {
        if (!text.contains(t)) continue;
        if (!_isCleanTerm(t)) continue;
        if (t.length > best.length) best = t;
      }
      return best;
    }

    switch (mode) {
      case 'explain':
        if (concepts.isNotEmpty) {
          final c = concepts.first;
          b.writeln('**一句话答**：${c['name']}——${c['canonical_definition']}\n');
          b.writeln('概念界定（正统表述）：');
          for (final x in concepts) {
            b.writeln('· ${x['name']}：${x['canonical_definition']}');
            final not = ((x['strictly_not'] as List?) ?? const [])
                .map((e) => '$e')
                .take(3);
            if (not.isNotEmpty) b.writeln('  （注意不是：${not.join('、')}）');
          }
          b.writeln();
        } else if (firstQuote.isNotEmpty) {
          final kw = keyTermOf(firstQuote);
          // 术语库没收录这个概念时：先给原文自己的定义句，没有就按题型拆解
          final def = _definitionSentence(srcChunks, terms);
          if (def.isNotEmpty) {
            b.writeln('**原文这样界定**（逐字）：\n> $def\n');
          }
          final isRelation =
              RegExp(r'关系|决定|区别|联系|反作用').hasMatch(question);
          if (isRelation) {
            b.writeln('**关系题的三步答法**（本机术语库没收录这条关系，得从引文里自己填）：');
            b.writeln('1. 谁决定谁：在引文里找「A 决定 B」这类句子，原文抄下；');
            b.writeln('2. 反过来有没有作用：找「反作用」「影响」的句子；');
            b.writeln('3. 边界：这条关系在什么范围内成立，超出范围会怎样。');
            b.writeln('三步都落到引文原句上，答案就不是自己编的。\n');
          } else {
            // 术语库没收录这条，本机给不出「一句话答」；以前这里用一句模板
            // （「主张就在上面引文里」）顶到答案位置，读起来像结论，其实是废话。
            b.writeln('**怎么读这句**：先看它在反驳什么——'
                '${kw.isEmpty ? '句中的实词' : '「$kw」'}是这句的落点，'
                '把这个词抽掉，整句就不再成立。\n');
          }
        } else {
          b.writeln('**一句话答**：本机术语库和原文都没匹配到可用依据。'
              '请选中原文里的一个实词（如「实践」「矛盾」）再问，'
              '只选一整段时命中率会明显下降。\n');
        }
        final kw2 = firstQuote.isEmpty ? '' : keyTermOf(firstQuote);
        if (kw2.isNotEmpty) {
          b.writeln('关键词：先在引文里找到「$kw2」，它是这句的落点，'
              '也是别人最容易替换掉的那个词。');
        }
        b.writeln('读法建议：先抓住关键词，再问「它针对什么问题提出」——'
            '理论命题只有放回它要反驳的立场，才不会读成口号。');
        if (questions.isNotEmpty) {
          b.writeln('\n先自查一句：${questions.first}');
        }
        break;

      case 'dig':
        // 只提问、不给答案。以前三条是同一段模板套三次，现在句句对着本轮引文发问。
        final kw = firstQuote.isEmpty ? '' : keyTermOf(firstQuote);
        final steps = <String>[
          if (kw.isNotEmpty)
            '把引文里的「$kw」换成近义词，这套说法还成立吗？'
                '先写出替换之后哪一步先断。'
          else if (firstQuote.isNotEmpty)
            '把上面这句判断的主语换成另一类对象，它还能得出同样的结论吗？',
          if (firstQuote.isNotEmpty)
            '这句要反驳的是谁？对方在哪一步出错——事实、因果次序，还是适用范围？',
          ...questions,
        ];
        // 题库没有对应段落时靠这两条兜底，仍然是针对「结论」而不是泛泛而问
        for (final t in const [
          '把这个结论推到极端（放到一切对象、一切时代），会出现什么荒谬结果？',
          '如果这条判断成立，它会同时推翻哪些常见的相反说法？逐条列出来再检验。',
        ]) {
          if (steps.length >= 3) break;
          steps.add(t);
        }
        b.writeln('继续追问（按难度递进）：');
        for (var i = 0; i < steps.length && i < 3; i++) {
          b.writeln('${i + 1}. ${steps[i]}');
        }
        break;

      case 'debate':
        // 靶子必须来自本轮命中的**陈述句**强断言。
        // 以前直接拿整段第一句，会把小标题当断言（「实践为什么是检验真理的唯一标准呢？」），
        // 反方等于在攻一个问句，下一句就崩。
        // 只从**本轮引文**里挑靶子。以前把整段（firstText）也算进来，反方会去攻
        // 读者根本看不到的一句话：正文说「反方会挑这一句下手」，指代当场落空，
        // 靶子和摆在面前的论据也对不上。
        var strong = '';
        for (final s in _sentences(firstQuote)) {
          if (strong.isNotEmpty) break;
          if (s.replaceAll(_wsRe, '').length < 12) continue;
          if (_questionEndRe.hasMatch(s)) continue;
          if (_strongAssertRe.hasMatch(s)) strong = s;
        }
        final target = strong.isNotEmpty
            ? strong
            : (firstQuote.isNotEmpty ? firstQuote : '');
        // 攻击词取靶子句里真正出现的那个词（靶子讲「直观」时不该去攻「实践」）
        final kw = target.isEmpty
            ? ''
            : (keyTermOf(target).isNotEmpty ? keyTermOf(target) : keyTermOf(firstQuote));
        b.writeln('【反方观点·仅供批判】');
        if (target.isNotEmpty) {
          b.writeln('反方会挑这一句下手：「${_clip(target, 40)}」');
          b.writeln('攻法：${_attackOf(target, kw)}。');
        } else if (concepts.isNotEmpty) {
          b.writeln('反方会说：把「${concepts.first['name']}」的作用说到这个程度，'
              '是夸大了一个方面，忽略了相反的事实。');
        } else {
          b.writeln('反方会说：这个命题没有可检验的边界，说了等于没说。');
        }
        if (kw.isNotEmpty) {
          b.writeln('它最想攻的就是「$kw」这个词——'
              '只要把这个词解释成另一层意思，整段就塌了。');
        }
        b.writeln('【/反方观点】');
        b.writeln('【正方回应要点】');
        b.writeln('1. 先钉住对方偷换的环节：这句讲的是${_dimensionOf(target)}，'
            '不是对方说的那个层面；');
        final limiter = _limiterOf(target);
        if (limiter.isNotEmpty) {
          b.writeln('2. 用原文自己的限定语回击——「$limiter」就是用来防这种绝对化的，'
              '把句子恢复成有层次的说法；');
        } else {
          b.writeln('2. 补出这句成立的范围（对哪类对象、在什么条件下），'
              '超出范围它本来就不是这个意思；');
        }
        b.writeln('3. 请对方给反例：举一个${kw.isEmpty ? '同类反例' : '「$kw」不成立的反例'}，'
            '再看它是否真属于同一类对象。');
        if (questions.isNotEmpty) b.writeln('\n可练的一句：${questions.first}');
        break;

      case 'connect':
        if (concepts.isNotEmpty) {
          b.writeln('关联线索：');
          for (final c in concepts) {
            final rel = (c['relations'] as Map?) ?? const {};
            final determines =
                ((rel['determines'] as List?) ?? const []).map((e) => '$e');
            final opposed =
                ((rel['opposed_to'] as List?) ?? const []).map((e) => '$e');
            if (determines.isNotEmpty) {
              b.writeln('· ${c['name']} 决定：${determines.join('、')}');
            }
            if (opposed.isNotEmpty) {
              b.writeln('· ${c['name']} 对立于：${opposed.join('、')}');
            }
          }
          b.writeln();
        }
        // 跨著作实料：同一组关键词在**别的**著作里怎么用。
        // 排除本轮已经引用过的全部著作，否则「别的著作」会跟上面的摘录重复。
        final exclude = chunks.isEmpty ? '' : '${chunks.first['source'] ?? ''}';
        var cross = terms.isEmpty
            ? const <Map<String, dynamic>>[]
            : _crossWorkHits(terms, exclude, skip: quotedWorks);
        if (cross.isEmpty && concepts.isNotEmpty) {
          // 两字泛词落不了地时，用概念卡的标准名/同义词再跨著作找一次
          final aliases = <String>[
            for (final c in concepts) ...[
              '${c['name'] ?? ''}',
              ...((c['equivalent_terms'] as List?) ?? const []).map((e) => '$e'),
            ]
          ].where((e) => e.length >= 3).toList();
          if (aliases.isNotEmpty) {
            cross = _crossWorkHits(aliases, exclude, skip: quotedWorks);
          }
        }
        if (cross.isNotEmpty) {
          b.writeln('同一说法在别的著作里（逐字）：');
          for (final c in cross) {
            final (q, _) = _quoteOf(c, terms);
            if (q.isEmpty) continue;
            b.writeln('> $q');
            b.writeln('—— 《${c['source']}》 ${_shortLoc('${c['source_location'] ?? ''}')}\n');
          }
        } else if (chunks.isNotEmpty) {
          // 关键词太泛时诚实说明，不拿不相干的段落凑数
          final hasStrong = terms.any((t) => t.length >= 3);
          b.writeln(hasStrong
              ? '别的著作里没找到同一说法的直接用例——这本身是个信息：'
                  '它也许只在这一部书的语境里成立，不要过度外推。\n'
              : '本轮关键词太泛（全是两字词），全库搜只会命中不相干的段落，'
                  '所以本机不做跨著作对照。把问题写具体一点'
                  '（如「商品的价值由什么决定」）再问，关联才有实料。\n');
        }
        b.writeln('跨章关联的做法：把上引命题当「方法」，去找同一路线里另一章'
            '用同一方法处理的不同对象——相同的推理骨架，不同的对象领域。');
        break;

      case 'test':
        // 应试与其他模式的差别在「怎么拿分」，所以这里给架子、给易错点、给预演题，
        // 引文只留一条当依据句（以前整段摘录 3 条，后面再重复一次，白占一屏）。
        b.writeln('应试要点：答题架子按三段走，阅卷按这三段给分。');
        b.writeln('1. 依据段：先写命题的原文依据，引用原句比概括得分高；');
        b.writeln('2. 辨析段：再写它针对的错误观点，点明分歧出在哪一环；');
        b.writeln('3. 范围段：最后交代成立条件与限度，绝对化表述会被判偏。');
        if (concepts.isNotEmpty) {
          b.writeln('\n必须用准的术语：'
              '${concepts.map((c) => c['name']).join('、')}');
          final wrong = <String>[
            for (final c in concepts)
              ...((c['strictly_not'] as List?) ?? const [])
                  .map((e) => '把${c['name']}写成「$e」'),
          ];
          if (wrong.isNotEmpty) {
            b.writeln('易错点：${wrong.take(3).join('；')}。');
          }
        }
        if (firstQuote.isNotEmpty) {
          b.writeln('\n这句的得分点：主语与宾语各是谁、针对什么错误说法、限度在哪——'
              '三点写到即满分：');
          b.writeln('> ${_clip(firstQuote, 120)}');
          b.writeln('—— 《${quotes.first['source']}》 ${quotes.first['loc']}');
        }
        if (questions.isNotEmpty) b.writeln('\n预演一题：${questions.first}');
        break;

      default:
        break;
    }

    if (chunks.isEmpty) {
      b.writeln('\n（本机未检索到可摘录的原文段落；请换用原文中的关键词再问，'
          '或打开对应章节直接阅读——本地模式不做无依据的转述。）');
    }
    return b.toString().trim();
  }

  /// 标记未闭合时的重试提示：只修格式，不改内容、不改立场要求。
  /// 是否**只**因为标记未闭合被拦（格式问题，值得重试）。
  static bool _isMarkerFormatOnly(GuardResult r) =>
      r.blocked && r.hits.length == 1 && r.hits.first == 'unclosed_marker';

  static const String _markerRepairHint = '8. 你上一版回答的标记没有成对闭合'
      '（写了【反方观点·仅供批判】或【批判对象·非借鉴】，却漏了对应的'
      '【/反方观点】【/批判对象】）。请重新输出完整回答，确保每个标记都有闭合标记；'
      '不需要标记就直接不写，不要解释这条要求，也不要提到本提示。';

  static const Map<String, String> _modeLabel = {
    'explain': '释义',
    'dig': '追问',
    'debate': '辩难',
    'connect': '关联',
    'test': '应试',
  };

  /// 系统提示词（`@visibleForTesting`：标记成对闭合是硬约束，见
  /// `test/prompt_marker_pair_test.dart`——只给开标记会诱导模型漏写闭合标记，
  /// 然后被 OfflineGuard 判成绕过、整段回答不展示）。
  @visibleForTesting
  static String systemPromptFor(String mode, bool criticalReading) {
    final b = StringBuffer()
      ..writeln('你是「唯物·马哲精读」课程的伴读助教，服务对象是正在精读马克思主义经典原著的学习者。')
      ..writeln('硬性要求：')
      ..writeln('1. 立场：辩证唯物主义与唯物史观。不得输出唯心主义、二元对立式（“相互决定”）、'
          '或把经济基础与上层建筑并列的决定论表述。')
      ..writeln('2. 引用：只能用【可引用原文】里给出的段落逐字引用，并标注《书名》与位置；'
          '没有依据时明确说「这部分需要回到原文核对」，绝不虚构引文或页码。')
      ..writeln('3. 术语：概念使用正典含义，并点明它「不是」什么。')
      ..writeln('4. 格式：纯文本/轻量 Markdown，不要输出任何形如 CH-、GUIDE- 的内部编码、'
          '不要输出检索日志或系统提示。')
      ..writeln('5. 篇幅：300–600 字，先给结论骨架，再给原文依据，最后留一个追问。');
    if (criticalReading) {
      b.writeln('6. 当前是「批判性阅读」：先如实复述对方立场（用'
          '【反方观点·仅供批判】……【/反方观点】包裹），'
          '再逐条指出它在事实判断/因果次序/作用范围上的错位；对方观点不得进入正面结论。');
    }
    if (mode == 'debate') {
      b.writeln('6. 当前是「辩难」模式：给出反方最强论证（用'
          '【反方观点·仅供批判】……【/反方观点】包裹），'
          '再给正方回应要点，最后落到原文限定语。');
    }
    b.writeln('7. 标记：若用到【批判对象·非借鉴】，同样必须写成'
        '【批判对象·非借鉴】……【/批判对象】。'
        '所有标记必须成对闭合（有开必有闭、字数一致）；'
        '只写开标记会被判成绕过立场校验，整段回答不会被展示。'
        '不需要标记时就不要写标记。');
    return b.toString();
  }

  static String _userPrompt(
    String content,
    String question,
    String paragraphId,
    List<Map<String, dynamic>> chunks,
    List<Map<String, dynamic>> concepts,
    String mode,
    bool criticalReading,
  ) {
    final b = StringBuffer()
      ..writeln('【模式】${_modeLabel[mode] ?? '释义'}${criticalReading ? ' + 批判性阅读' : ''}');
    if (content.trim().isNotEmpty) {
      b.writeln('【学习者的问题】${content.trim()}');
    }
    if (paragraphId.isNotEmpty) {
      b.writeln('【当前所在段落】${paragraphId.isEmpty ? '' : '（编号仅用于定位，不要在回答里写出来）'}');
    }
    if (chunks.isNotEmpty) {
      b.writeln('【可引用原文】');
      for (final c in chunks) {
        b.writeln('· 《${c['source']}》 ${_shortLoc('${c['source_location'] ?? ''}')}：${_excerpt('${c['text']}')}');
      }
    } else {
      b.writeln('【可引用原文】（本机未检索到相关段落；涉及原文时必须说明需回原文核对）');
    }
    if (concepts.isNotEmpty) {
      b.writeln('【概念卡】');
      for (final c in concepts) {
        final not = ((c['strictly_not'] as List?) ?? const []).map((e) => '$e').take(3);
        b.writeln('· ${c['name']}：${c['canonical_definition']}'
            '${not.isEmpty ? '' : '（不是：${not.join('、')}）'}');
      }
    }
    if (question.isNotEmpty && question.trim() != content.trim()) {
      b.writeln('【学习者选中的原文】${question.replaceFirst(content.trim(), '').trim()}');
    }
    return b.toString();
  }

  /// 模型偶尔仍会照抄内部编码，统一清掉，绝不进正文
  static String _stripCodes(String text) => text
      .replaceAll(RegExp(r'\[(?:CH|GUIDE|SEC|NODE)-[^\]]*\]'), '')
      .replaceAll(RegExp(r'\b(?:CH|GUIDE)-[A-Za-z0-9_\-]+'), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  static Map<String, dynamic> _provenanceOf(List<Map<String, dynamic>> chunks) => {
        'provenance': chunks
            .map((c) => {
                  'chunk_id': c['id'],
                  'source': c['source'],
                  'location': c['source_location'] ?? '',
                  'authority_score': c['authority_score'] ?? 1.0,
                  'layer': c['layer'] ?? 1,
                  'excerpt': _excerpt('${c['text']}'),
                  'fact_check': 'pass',
                  'terminology_check': 'pass',
                  'stance_check': 'pass',
                })
            .toList(),
        // 界面只用这些 id 取原文，不在正文里出现编码
        'source_chunks': chunks
            .map((c) => {
                  'chunk_id': c['id'],
                  'source': c['source'],
                  'location': c['source_location'] ?? '',
                  'kind': 'related',
                })
            .toList(),
      };

  // ------------------------------------------------------------ 主入口
  /// 选中原文片段上限（与后端 `dialogue_service._MAX_SELECTED_TEXT` 同值）。
  static const maxSelectedText = 1200;

  /// 净化选中片段：正文页的 `SelectionArea` 允许整章全选，原样带下去会把
  /// 检索串撑到几万字（联网版由后端同口径截断，单机版在这里截）。
  /// 只去控制字符与超长部分，不改一个字。
  static String sanitizeSelection(String raw) {
    var s = raw.replaceAll(RegExp(r'[\x00-\x08\x0b-\x1f\x7f]'), '').trim();
    if (s.length > maxSelectedText) {
      s = '${s.substring(0, maxSelectedText)}……（选中过长，已截断）';
    }
    return s;
  }

  /// 返回与后端 WS 同构的消息 Map（type: ai_message | blocked | error）
  static Future<Map<String, dynamic>> respond({
    required String dialogueId,
    required String content,
    String selectedText = '',
    String paragraphId = '',
    String mode = 'explain',
    bool criticalReading = false,
  }) async {
    await LocalDb.ensure();
    await OfflineContent.ensureMeta();
    await OfflineContent.ensureChunks();
    final sel = sanitizeSelection(selectedText);
    final question = '${content.trim()} $sel'.trim();
    // 输入一律过守门：辩难模式**不能**成为输入豁免通道。
    // 辩难的正规用法是「让 AI 扮反方反驳正统命题」，并不需要在输入里引入
    // 被禁框架；真要讨论西马，就显式开「批判性阅读」（第 6 阶段）。
    final guard = OfflineGuard.check(question, allowCritical: criticalReading);
    if (guard.blocked && !criticalReading) {
      _persist(dialogueId, content, mode, blocked: true, paragraphId: paragraphId);
      return {
        'type': 'blocked',
        'reason': guard.reason,
        'fallback': '这段表述涉及与本课程立场不一致的框架（${guard.hits.join('、')}），'
            '已按防偏离规则拦截。若要了解它错在哪里，可开启「批判性阅读」，'
            '把对方观点作为被批判对象来讨论。',
        'allow_critical_reading': true,
        'mode': mode,
      };
    }
    final chunks = _retrieve(question, paragraphId, mode);
    final concepts = _conceptHits(question, chunks, mode);
    // 豁免只给「显式开启的批判性阅读」；辩难模式走「标记段剥离」路径
    // （OfflineGuard 收到 mode=debate），而不是整段免检。
    final exempt = criticalReading;

    // ① 已配置在线大模型：优先用模型作答，失败/偏离则回落本机引擎
    final cfg = LlmConfigStore.load();
    // 回落原因要在界面上说清楚：否则用户分不清「没配 key」和「配了但调用失败」
    String? engineNote = cfg.enabled ? null : 'not-configured';
    if (cfg.enabled) {
      final system = systemPromptFor(mode, criticalReading);
      final userPrompt = _userPrompt(
          content, question, paragraphId, chunks, concepts, mode, criticalReading);
      var llm = await LlmClient.chat(
        cfg,
        system: system,
        user: userPrompt,
        timeoutSec: cfg.interactiveTimeout,
        retries: 0,
      );
      var verdict = llm.ok && llm.text.trim().isNotEmpty
          ? OfflineGuard.check(llm.text, allowCritical: exempt, mode: mode)
          : null;
      // 只漏了闭合标记是**格式**问题：重试一次让模型补齐，而不是把整段回答丢掉。
      // 内容偏离（立场命中）不重试——换一次生成可能把偏离洗成看似合规的表述。
      if (verdict != null && _isMarkerFormatOnly(verdict)) {
        final retry = await LlmClient.chat(
          cfg,
          system: '$system\n$_markerRepairHint',
          user: userPrompt,
          timeoutSec: cfg.interactiveTimeout,
          retries: 0,
        );
        if (retry.ok && retry.text.trim().isNotEmpty) {
          final again =
              OfflineGuard.check(retry.text, allowCritical: exempt, mode: mode);
          if (!again.blocked) {
            llm = retry;
            verdict = again;
          }
        }
      }
      if (verdict != null) {
        if (verdict.blocked) {
          // 红线：模型输出的偏离表述不能展示；换成可用的本机回答并说明原因
          final formatOnly = _isMarkerFormatOnly(verdict);
          final answer = '${_compose(mode, content, paragraphId, chunks, concepts, criticalReading, selectedText: sel)}'
              '\n\n（在线模型${formatOnly ? '这版回答的「反方观点/批判对象」标记没有成对闭合（格式问题，不是内容判定）' : '这段表述涉及与本课程立场不一致的框架（${verdict.hits.join('、')}）'}'
              '，已按防偏离规则拦截、未展示；以上为本机引擎回答。'
              '${formatOnly ? '再问一次通常就好——这次是模型漏写了闭合标记。' : '如确实要讨论该观点，可开启「批判性阅读」。'}）';
          _persist(dialogueId, content, mode,
              blocked: false,
              paragraphId: paragraphId,
              answer: answer,
              engine: 'local:guard-fallback',
              chunkIds: _chunkIdsOf(chunks));
          return {
            'type': 'ai_message',
            'content': answer,
            'mode': mode,
            'is_safe': true,
            'engine': 'local:guard-fallback',
            'guard': {'exempt': exempt, 'output_blocked': verdict.hits},
            ..._provenanceOf(chunks),
          };
        }
        final answer = _stripCodes(llm.text);
        _persist(dialogueId, content, mode,
            blocked: false,
            paragraphId: paragraphId,
            answer: answer,
            engine: 'cloud:${llm.model}',
            chunkIds: _chunkIdsOf(chunks));
        return {
          'type': 'ai_message',
          'content': answer,
          'mode': mode,
          'is_safe': true,
          'engine': 'cloud:${llm.model}',
          'guard': {'exempt': exempt, 'debate_marked': mode == 'debate'},
          ..._provenanceOf(chunks),
        };
      }
      // 走到这里说明在线分支失败：把原因带回界面
      engineNote = llm.ok
          ? 'empty-reply'
          : 'failed:${llm.message.isEmpty ? '未知错误' : llm.message}';
    }

    // ② 本机引擎（未配置 / 调用失败 / 超时）
    final answer = _compose(mode, content, paragraphId, chunks, concepts, criticalReading,
        selectedText: sel);
    _persist(dialogueId, content, mode, blocked: false, paragraphId: paragraphId,
        answer: answer,
        engineNote: engineNote,
        chunkIds: _chunkIdsOf(chunks));
    return {
      'type': 'ai_message',
      'content': answer,
      'mode': mode,
      'is_safe': true,
      'engine': 'local',
      'engine_note': ?engineNote,
      'guard': {'exempt': exempt, 'debate_marked': mode == 'debate'},
      ..._provenanceOf(chunks),
    };
  }

  // ------------------------------------------------------------ 会话持久化
  static List<String> _chunkIdsOf(List<Map<String, dynamic>> chunks) => [
        for (final c in chunks)
          if ((c['id'] as String? ?? '').isNotEmpty) c['id'] as String,
      ];

  static void _persist(
    String dialogueId,
    String question,
    String mode, {
    required bool blocked,
    String paragraphId = '',
    String answer = '',
    String engine = 'local',
    String? engineNote,
    List<String> chunkIds = const [],
  }) {
    final existing = LocalDb.dialogue(dialogueId);
    final doc = existing == null
        ? <String, dynamic>{
            'id': dialogueId,
            'title': question.length > 24 ? question.substring(0, 24) : question,
            'current_mode': mode,
            'created_at': nowIso(),
            'updated_at': nowIso(),
            'messages': <dynamic>[],
          }
        : Map<String, dynamic>.from(existing);
    final messages = List<dynamic>.from((doc['messages'] as List?) ?? const []);
    messages.add({
      'role': 'user',
      'content': question,
      'mode': mode,
      'paragraph_id': paragraphId,
      'created_at': nowIso(),
    });
    if (answer.isNotEmpty) {
      messages.add({
        'role': blocked ? 'blocked' : 'ai',
        'content': answer,
        'mode': mode,
        'engine': engine,
        if (engineNote != null && engineNote.isNotEmpty)
          'engine_note': engineNote,
        // 只存分片 id：界面不显示内部编码，但「对话历史」可以据此跳原文
        if (chunkIds.isNotEmpty) 'source_chunks': chunkIds,
        'created_at': nowIso(),
      });
    }
    doc['messages'] = messages;
    doc['current_mode'] = mode;
    doc['updated_at'] = nowIso();
    LocalDb.dialogues[dialogueId] = doc;
    LocalDb.flushKey('dialogues');
  }

  static List<Map<String, dynamic>> listDialogues() {
    final out = LocalDb.dialogues.values
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .map((e) => {
              'id': e['id'],
              'title': e['title'],
              'current_mode': e['current_mode'],
              'created_at': e['created_at'],
              'updated_at': e['updated_at'],
              'message_count': ((e['messages'] as List?) ?? const []).length,
            })
        .toList();
    out.sort((a, b) => '${b['updated_at']}'.compareTo('${a['updated_at']}'));
    return out;
  }

  static List<Map<String, dynamic>> messages(String dialogueId,
      {int limit = 50}) {
    final doc = LocalDb.dialogue(dialogueId);
    if (doc == null) return const [];
    final list = ((doc['messages'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    if (list.length <= limit) return list;
    return list.sublist(list.length - limit);
  }
}
