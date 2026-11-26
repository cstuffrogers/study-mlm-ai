// 离线立场守门（单机版）：把 backend/core/guard/orthodoxy.py 的规则搬到本机。
// 只做「明显偏移拦截 + 术语误用提示」，不做权威判定；命中即回退为提示语。
//
// D171（整体标尺）：旧实现「字串命中就拦」，只要回答里出现批判对象术语
// （物化/总体性/文化领导权…）或偏离句式，就整段 block —— 用户指出反面例子、
// 或者只是在**提问**里引用一种错误说法，都被判成宣扬。现在按**句子**判主张归属：
//   引号内 / 带引述框架 / 同句有转折纠偏词 / （输入侧）用户在提问 → citation（放行）
//   批判对象术语的定义-比较-教学式使用                     → neutral（标注，不拦）
//   作者自己的结论句                                       → deviation（拦）
import 'offline_content.dart';

class GuardResult {
  final String status; // pass | block
  final String reason;
  final List<String> hits; // 命中的规则名（block 用）
  final List<String> terms; // 命中的术语误用
  /// D171：可疑但不构成自述偏离的命中（术语中性使用 / 被引述的反面例子）。
  /// status 仍是 pass —— UI 据此提示「立场待核」，**不阻住回答**。
  final List<Map<String, String>> notes;

  const GuardResult({
    required this.status,
    required this.reason,
    required this.hits,
    required this.terms,
    this.notes = const [],
  });

  bool get blocked => status == 'block';

  Map<String, dynamic> toJson() => {
        'status': status,
        'reason': reason,
        'hits': hits,
        'terms': terms,
        'notes': notes,
      };
}

class OfflineGuard {
  OfflineGuard._();

  /// 批判语境词（与 backend/core/guard/orthodoxy.py 的 `_CRITICAL_CONTEXT_WORDS` 同口径）
  static const _criticalContextWords = [
    '批判', '错误', '反对', '歪曲', '否定', '揭露', '驳斥', '谬误', '攻击', '背离', '修正主义',
  ];

  /// 提问标记（D171，仅输入侧生效）：用户在提问里引述一种错误说法 ≠ 用户自己主张它
  static const _questionMarkers = [
    '？', '?', '为什么', '为何', '怎么理解', '如何理解', '如何看待', '是否', '对不对',
    '错在哪', '错在哪里', '这种说法', '这一说法', '这个观点', '这句话', '什么是', '何谓',
    '凭什么', '何以',
  ];

  /// 引述框架：出现这些词说明该句是在复述别人的观点（不能把「主张/声称」列进来，
  /// 那是作者自己的推介，收了会给宣扬句式开后门）
  static const _quoteFrameWords = [
    '有人说', '有人认为', '有观点', '有人主张', '有人问', '错误观点', '所谓', '据说',
    '据称', '被说成', '被描述为', '归结为', '贴上',
  ];

  /// 转折/纠偏词：同句出现即视为「引述 + 反驳」。
  /// 不得加入「唯物」（常与西马自我标榜同现），也不能加「但」这类纯连接词。
  static const _rebuttalWords = [
    '错', '谬', '荒谬', '唯心', '不是一回事', '不能混', '区别于', '不同', '相对立',
    '非正统', '误区', '曲解', '庸俗', '恰恰相反', '问题在于', '这说明', '应当指出',
    '不属于', '不是马克思主义', '无法', '不能', '并非',
  ];

  /// 成对引号（含书名号）：引号内的字是「被引用的说法」，不是作者表态
  static const _quotePairs = [
    ['「', '」'], ['『', '』'], ['“', '”'], ['‘', '’'], ['"', '"'], ['《', '》'],
  ];

  /// 「宣扬」谓语（与后端 `_ENDORSE_RE` 同源）：批判对象术语被当成**有效理论**
  /// 推介时才判偏离。术语本身是教材词汇，出现不等于偏离。
  static final _endorseRe = RegExp(
    r'(丰富|超越|发展|补充|完善|提供|奠定|揭示|证明|印证|深化|拓展).{0,10}'
    r'(马克思主义|唯物史观|历史唯物主义|辩证唯物主义|正统|真谛|本质|新境界|新基础|新视野)'
    r'|(解释|说明|表明|标志着|揭示)(了)?.{0,16}(起源|根源|秘密|本质|规律|根本对立|两个马克思)'
    r'|(是|乃|堪称|属于).{0,8}(合理|科学|正确|真理|根本方法|核心|精髓)'
    r'|(超越|摆脱|替代|取代).{0,8}(局限|束缚|无产阶级专政|暴力革命|阶级斗争|剩余价值)'
    r'|(已经|正在)(终结|解体|失效|破产)'
    r'|(只是|不过是|仅是).{0,8}(一种|之一)'
    r'|比.{0,10}(更重要|更根本|更为根本)'
    r'|(根本方法|核心病症|唯一出路|真正出路)',
  );

  /// 句读边界：自指批判语境只在同一句内判定，不跨句串味
  static const _clauseTerminators = ['。', '！', '？', '；', '!', '?', ';', '\n'];
  /// 正统限定语豁免的否决词（与后端 EXEMPT_VETO_WORDS 同口径）。
  static const _exemptVetoWords = [
    '同样决定',
    '同等',
    '并列',
    '一样决定',
    '共同决定',
    '相互决定',
    '互为决定',
  ];

  /// 批判对象/辩难标记字面：内含「批判」二字，**不得充当批判语境证据**。
  static const _markerLiterals = [
    '【批判对象·非借鉴】', '【/批判对象】',
    '【反方观点·仅供批判】', '【/反方观点】',
  ];

  /// 把标记字面换成等长占位符（**保持下标不变**），避免标记自己当语境词。
  static String _maskMarkers(String text) {
    var s = text;
    for (final lit in _markerLiterals) {
      if (s.contains(lit)) s = s.replaceAll(lit, '□' * lit.length);
    }
    return s;
  }

  /// 豁免标记对（与后端 core/guard/orthodoxy.py 同名常量同字串）。
  static const _exemptOpen = '【反方观点·仅供批判】';
  static const _exemptClose = '【/反方观点】';
  static const _criticalOpen = '【批判对象·非借鉴】';
  static const _criticalClose = '【/批判对象】';

  static final _exemptRe =
      RegExp(r'【反方观点·仅供批判】[\s\S]*?【/反方观点】');
  static final _criticalRe = RegExp(r'【批判对象·非借鉴】[\s\S]*?【/批判对象】');

  /// 剥离标记段（这些段不参与立场校验）。
  ///
  /// 相当于后端的 `_strip_exempt_segments`：辩难模式允许 AI 摆反方观点，
  /// 但只允许**被标记包裹的**那部分；标记外的内容仍按正统标准校验。
  static String _stripMarkerSegments(String text) =>
      text.replaceAll(_exemptRe, '').replaceAll(_criticalRe, '');

  /// 删掉标记字面（含未闭合的），用于**格式问题救援**。
  ///
  /// 未闭合标记原本判「疑似绕过」→ 整段回答不展示；但多数情况只是模型漏写闭合，
  /// 内容本身没问题。这里只删标记字面、**不给任何豁免**：删完仍按普通内容逐条校验，
  /// 真有偏离照样拦。这样格式问题不再吃掉整段回答。
  static String stripMarkerLiterals(String text) {
    var s = text;
    for (final lit in _markerLiterals) {
      s = s.replaceAll(lit, '');
    }
    return s;
  }

  /// 标记是否成对。未闭合 → 返回该标记名，否则 null。
  ///
  /// 相当于后端的 `_has_unclosed_exempt_marker`：写一个开标记就整段免检，
  /// 等于给了一个绕过校验的后门（未闭合标记防绕过）。
  static String? _unclosedMarkerName(String text) {
    int count(String sub) => sub.isEmpty ? 0 : text.split(sub).length - 1;
    if (count(_exemptOpen) != count(_exemptClose)) return '辩难豁免';
    if (count(_criticalOpen) != count(_criticalClose)) return '批判对象';
    return null;
  }

  static final Map<String, RegExp> _compiled = {};
  /// 正统限定语豁免（如「反作用」「归根到底」「能动的革命的反映论」）。
  /// 与后端 STANCE_PATTERNS[..]['exempt'] 同口径，随 knowledge.json 导出。
  static final Map<String, RegExp> _exemptPatterns = {};
  static List<String> _deviation = const [];
  static List<String> _criticalKeys = const [];
  static Map<String, dynamic> _critical = const {};

  static void _warm() {
    if (_compiled.isNotEmpty) return;
    final guard = OfflineContent.guard;
    final patterns = (guard['stance_patterns'] as Map?) ?? const {};
    patterns.forEach((k, v) {
      final src = '${(v as Map)['pattern'] ?? ''}';
      if (src.isEmpty) return;
      try {
        _compiled['$k'] = RegExp(src);
      } catch (_) {
        // 单机版对不兼容的正则静默跳过，不影响其余规则
      }
    });
    patterns.forEach((k, v) {
      final src = '${(v as Map)['exempt'] ?? ''}';
      if (src.isEmpty) return;
      try {
        _exemptPatterns['$k'] = RegExp(src);
      } catch (_) {}
    });
    _deviation = ((guard['deviation_keywords'] as List?) ?? const [])
        .map((e) => '$e')
        .toList();
    _critical = ((guard['critical_objects'] as Map?) ?? const {}).cast<String, dynamic>();
    _criticalKeys = _critical.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
  }

  /// 偏离关键词（供判分复用）
  static List<String> get deviationKeywords {
    _warm();
    return _deviation;
  }

  /// 命中所在的句子（含下标）—— 主张归属按句子判定，不跟串味
  static List<int> _clauseBounds(String text, int start, int end) {
    var left = -1;
    for (final t in _clauseTerminators) {
      final i = text.lastIndexOf(t, start == 0 ? 0 : start - 1);
      if (i > left) left = i;
    }
    var right = text.length;
    for (final t in _clauseTerminators) {
      final i = text.indexOf(t, end);
      if (i != -1 && i < right) right = i;
    }
    return [left + 1, right];
  }

  /// 命中是否落在成对引号内（引述材料，不是作者表态）
  static bool _inQuotes(String text, int start, int end) {
    for (final pair in _quotePairs) {
      final lq = pair[0], rq = pair[1];
      final lo = text.lastIndexOf(lq, start == 0 ? 0 : start - 1);
      if (lo == -1) continue;
      final closedBefore = text.indexOf(rq, lo + lq.length);
      if ((closedBefore == -1 || closedBefore >= start) &&
          text.indexOf(rq, end) != -1) {
        return true;
      }
    }
    return false;
  }

  static bool _isQuestion(String clause) =>
      _questionMarkers.any(clause.contains);

  /// 判定单处命中属于哪种主张类型（与后端 `_assess_occurrence` 同口径）。
  ///
  /// citation —— 引述/复述/被批判/用户在提问，不算作者主张
  /// deviation —— 作者自己主张（唯一会触发拦截的一类）
  /// neutral —— 中性使用（仅批判对象术语：定义、比较、教学口径）
  static String _assessOccurrence(String text, int start, int end,
      {required String kind, required String contextMode}) {
    if (_inQuotes(text, start, end)) return 'citation';
    final masked = _maskMarkers(text);
    final b = _clauseBounds(masked, start, end);
    final clause = masked.substring(b[0], b[1]);
    if (_criticalContextWords.any(clause.contains)) return 'citation';
    if (_rebuttalWords.any(clause.contains)) return 'citation';
    if (_quoteFrameWords.any(clause.contains)) return 'citation';
    // 输入侧：用户提问/追问里引用错误说法，不等于用户自己主张它
    if (contextMode == 'input' && _isQuestion(clause)) return 'citation';
    if (kind == 'critical') {
      return _endorseRe.hasMatch(clause) ? 'deviation' : 'neutral';
    }
    return 'deviation';
  }

  /// 命中是否全部落在「自指批判语境」里。
  ///
  /// 修复前：把「阶级斗争已经过时的错误论调，应当批判」这类**正确的批判性表述**
  /// 也判成偏离，用户明明在批判错误观点却被拦截。
  /// 判定思路与后端的批判语境机制一致，不新增「抓偏离」的规则：
  ///   「阶级斗争已经过时」                    → 无语境词 → 仍拦截
  ///   「阶级斗争已经过时的错误论调，应当批判」  → 同句有语境词 → 放行
  /// 保守约束：① 必须全部命中都带语境词；② 语境词必须同处一句。
  static bool _allMatchesExempt(RegExp pattern, RegExp? exempt, String content) {
    if (exempt == null) return false;
    final matches = pattern.allMatches(content).toList();
    if (matches.isEmpty) return false;
    for (final m in matches) {
      final b = _clauseBounds(content, m.start, m.end);
      final clause = content.substring(b[0], b[1]);
      if (!exempt.hasMatch(clause)) return false;
      // 否决词：同句出现「同样决定/并列/共同决定」这类真偏离的并列说法就不给豁免，
      // 否则「经济不是唯一决定，文化同样决定」会被「不是唯一」放过。
      for (final veto in _exemptVetoWords) {
        if (clause.contains(veto)) return false;
      }
    }
    return true;
  }

  /// 对一段文本做立场检查。
  /// [allowCritical] 为 true 时视为「批判语境」（第 6 阶段），命中批判对象只提示不拦截。
  /// [mode] 为 `debate` 时：标记段剥离后校验，标记未闭合直接判绕过。
  ///   与后端 `OrthodoxyGuard.check(text, mode=...)` 同口径。
  static GuardResult check(String text,
      {bool allowCritical = false,
      String mode = 'explain',
      String contextMode = 'output'}) {
    _warm();
    final content = (text).trim();
    if (content.isEmpty) {
      return const GuardResult(status: 'pass', reason: '', hits: [], terms: []);
    }
    // ① 未闭合标记 = 绕过尝试，优先于其它所有判定（不降级为正常校验）
    final unclosed = _unclosedMarkerName(content);
    if (unclosed != null) {
      return GuardResult(
        status: 'block',
        reason: '$unclosed标记未闭合，疑似绕过立场校验',
        hits: const ['unclosed_marker'],
        terms: const [],
      );
    }
    // ② 辩难模式：被标记包裹的反方/批判对象段不参与校验，其余照常校验
    final scan = mode == 'debate' ? _stripMarkerSegments(content) : content;
    final hits = <String>[];
    final cited = <String>[];
    final notes = <Map<String, String>>[];
    String reason = '';
    for (final entry in _compiled.entries) {
      final matches = entry.value.allMatches(scan).toList();
      if (matches.isEmpty) continue;
      // 正统原话（恩格斯「不是唯一决定因素」、毛「机械反映论是错误的」）→ 不拦
      if (_allMatchesExempt(
          entry.value, _exemptPatterns[entry.key], scan)) {
        cited.add(entry.key);
        continue;
      }
      // D171：按句子判归属，只要有一处是作者自己在主张 → 拦截
      final verdicts = matches
          .map((m) => _assessOccurrence(scan, m.start, m.end,
              kind: 'stance', contextMode: contextMode))
          .toList();
      if (verdicts.every((v) => v == 'citation')) {
        cited.add(entry.key);
      } else {
        hits.add(entry.key);
      }
    }
    final patterns = (OfflineContent.guard['stance_patterns'] as Map?) ?? const {};
    if (hits.isNotEmpty) {
      final first = (patterns[hits.first] as Map?) ?? const {};
      reason = '${first['reason'] ?? '存在偏离马克思主义立场的表述'}';
    }
    final termHits = <String>[];
    final endorsed = <String>[];
    for (final k in _criticalKeys) {
      if (!scan.contains(k)) continue;
      if (allowCritical) continue;
      // 批判语境标记必须**真的把这个术语包在里面**才算立场已表明，
      // 仅全文出现一次标记就全放行，等于给了个免费后门。
      final open = scan.indexOf(_criticalOpen);
      final closed = open == -1
          ? -1
          : scan.indexOf(_criticalClose, open + _criticalOpen.length);
      final termAt = scan.indexOf(k);
      final wrapped = open != -1 && closed != -1 && open < termAt && termAt < closed;
      if (wrapped) continue;
      // D171：术语本身不判偏离 —— 定义/比较/教学式使用（neutral）只标注，
      // 只有「宣扬谓语」（丰富了马克思主义 / 揭示了…本质）才是作者采纳。
      final hitsOfTerm = RegExp(RegExp.escape(k)).allMatches(scan).toList();
      final verdicts = hitsOfTerm
          .map((m) => _assessOccurrence(scan, m.start, m.end,
              kind: 'critical', contextMode: contextMode))
          .toList();
      final info = (_critical[k] as Map?) ?? const {};
      final school = '${info['school'] ?? ''}';
      if (verdicts.contains('deviation')) {
        endorsed.add(k);
        reason = reason.isNotEmpty
            ? reason
            : '把批判对象「$k」当有效理论推介'
                '${info['error'] == null ? '' : '（${info['error']}）'}，属偏离原教旨';
      } else if (verdicts.isNotEmpty && verdicts.every((v) => v == 'citation')) {
        cited.add('term:$k');
      } else {
        termHits.add(k);
        notes.add({
          'term': k,
          'school': school,
          'reason': '涉及批判对象「$k」${school.isEmpty ? '' : '（$school）'}，'
              '未见明确批判姿态；标注待核，不拦截',
        });
      }
    }
    final blocked = hits.isNotEmpty || endorsed.isNotEmpty;
    return GuardResult(
      status: blocked ? 'block' : 'pass',
      reason: blocked
          ? reason
          : (termHits.isEmpty
              ? (cited.isEmpty ? '' : '已识别为批判性引用（语境含批判词/引述框架），按正确表述处理')
              : '涉及批判对象术语，注意标明立场（非借鉴）'),
      hits: [...hits, ...endorsed.map((k) => 'endorsed:$k')],
      terms: termHits,
      notes: notes,
    );
  }

  /// 极简术语/立场占位检查（供主观题三维评分使用）
  static Map<String, dynamic> terminologyCheck(String text,
      {String context = ''}) {
    final guard = check(text);
    return {
      'stance': {'status': guard.status, 'reason': guard.reason},
      'terminology': {
        'status': guard.terms.isEmpty ? 'pass' : 'warn',
        'terms': guard.terms,
      },
    };
  }
}
