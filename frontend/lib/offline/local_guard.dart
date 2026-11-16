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

  static final Map<String, RegExp> _compiled = {};
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

  /// 对一段文本做立场检查。
  /// [allowCritical] 为 true 时视为「批判语境」（第 6 阶段），命中批判对象只提示不拦截。
  static GuardResult check(String text, {bool allowCritical = false}) {
    _warm();
    final content = (text).trim();
    if (content.isEmpty) {
      return const GuardResult(status: 'pass', reason: '', hits: [], terms: []);
    }
    final hits = <String>[];
    final cited = <String>[];
    String reason = '';
    for (final entry in _compiled.entries) {
      if (!entry.value.hasMatch(content)) continue;
      // 自指批判语境（用户在批判这个错误论调本身）→ 只记录，不拦截
      if (_allMatchesCritical(entry.value, content)) {
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
      if (!content.contains(k)) continue;
      if (allowCritical) continue;
      // 批判语境标记必须**真的把这个术语包在里面**才算立场已表明，
      // 仅全文出现一次标记就全放行，等于给了个免费后门。
      final open = content.indexOf('【批判对象·非借鉴】');
      final closed = open == -1
          ? -1
          : content.indexOf('【/批判对象】', open + '【批判对象·非借鉴】'.length);
      final termAt = content.indexOf(k);
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
