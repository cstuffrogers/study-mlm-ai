// 离线立场守门（单机版）：把 backend/core/guard/orthodoxy.py 的规则搬到本机。
// 只做「明显偏移拦截 + 术语误用提示」，不做权威判定；命中即回退为提示语。
import 'offline_content.dart';

class GuardResult {
  final String status; // pass | block
  final String reason;
  final List<String> hits; // 命中的规则名
  final List<String> terms; // 命中的术语误用

  const GuardResult({
    required this.status,
    required this.reason,
    required this.hits,
    required this.terms,
  });

  bool get blocked => status == 'block';

  Map<String, dynamic> toJson() => {
        'status': status,
        'reason': reason,
        'hits': hits,
        'terms': terms,
      };
}

class OfflineGuard {
  OfflineGuard._();

  /// 批判语境词（与 backend/core/guard/orthodoxy.py 的 `_CRITICAL_CONTEXT_WORDS` 同口径）
  static const _criticalContextWords = [
    '批判', '错误', '反对', '歪曲', '否定', '揭露', '驳斥', '谬误', '攻击', '背离', '修正主义',
  ];

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

  /// 命中是否全部落在「自指批判语境」里。
  ///
  /// 修复前：把「阶级斗争已经过时的错误论调，应当批判」这类**正确的批判性表述**
  /// 也判成偏离，用户明明在批判错误观点却被拦截。
  /// 判定思路与后端的批判语境机制一致，不新增「抓偏离」的规则：
  ///   「阶级斗争已经过时」                    → 无语境词 → 仍拦截
  ///   「阶级斗争已经过时的错误论调，应当批判」  → 同句有语境词 → 放行
  /// 保守约束：① 必须全部命中都带语境词；② 语境词必须同处一句。
  static bool _allMatchesCritical(RegExp pattern, String content) {
    final matches = pattern.allMatches(content).toList();
    if (matches.isEmpty) return false;
    // 标记字面不得充当批判语境证据（其内含「批判」二字）
    final masked = _maskMarkers(content);
    for (final m in matches) {
      var left = -1;
      for (final t in _clauseTerminators) {
        final i = masked.lastIndexOf(t, m.start == 0 ? 0 : m.start - 1);
        if (i > left) left = i;
      }
      var right = masked.length;
      for (final t in _clauseTerminators) {
        final i = masked.indexOf(t, m.end);
        if (i != -1 && i < right) right = i;
      }
      final clause = masked.substring(left + 1, right);
      if (!_criticalContextWords.any(clause.contains)) return false;
    }
    return true;
  }

  /// 每一次偏离命中是否都落在**带正统限定语**的同一句里。
  ///
  /// 与 `_allMatchesCritical` 同一思路，只把「批判语境词」换成「正统限定语」：
  ///   「经济状况是基础……并非只有经济状况才是唯一决定性的因素」→ 同句有「唯一决定性的因素」→ 放行
  ///   「经济基础与上层建筑相互决定」                            → 无正统限定语 → 仍拦
  static bool _allMatchesExempt(RegExp pattern, RegExp? exempt, String content) {
    if (exempt == null) return false;
    final matches = pattern.allMatches(content).toList();
    if (matches.isEmpty) return false;
    for (final m in matches) {
      var left = -1;
      for (final t in _clauseTerminators) {
        final i = content.lastIndexOf(t, m.start == 0 ? 0 : m.start - 1);
        if (i > left) left = i;
      }
      var right = content.length;
      for (final t in _clauseTerminators) {
        final i = content.indexOf(t, m.end);
        if (i != -1 && i < right) right = i;
      }
      final clause = content.substring(left + 1, right);
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
      {bool allowCritical = false, String mode = 'explain'}) {
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
    String reason = '';
    for (final entry in _compiled.entries) {
      if (!entry.value.hasMatch(scan)) continue;
      // 自指批判语境（用户在批判这个错误论调本身）→ 只记录，不拦截
      if (_allMatchesCritical(entry.value, scan)) {
        cited.add(entry.key);
      } else if (_allMatchesExempt(
          entry.value, _exemptPatterns[entry.key], scan)) {
        // 正统原话（恩格斯「不是唯一决定因素」、毛「机械反映论是错误的」）→ 不拦
        cited.add(entry.key);
      } else {
        hits.add(entry.key);
      }
    }
    if (hits.isNotEmpty) {
      final patterns = (OfflineContent.guard['stance_patterns'] as Map?) ?? const {};
      final first = (patterns[hits.first] as Map?) ?? const {};
      reason = '${first['reason'] ?? '存在偏离马克思主义立场的表述'}';
    }
    final termHits = <String>[];
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
      termHits.add(k);
    }
    final blocked = hits.isNotEmpty;
    return GuardResult(
      status: blocked ? 'block' : 'pass',
      reason: blocked
          ? reason
          : (termHits.isEmpty
              ? (cited.isEmpty ? '' : '已识别为批判性引用（语境含批判词），按正确表述处理')
              : '涉及批判对象术语，注意标明立场（非借鉴）'),
      hits: hits,
      terms: termHits,
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
