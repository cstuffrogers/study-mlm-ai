// 勋章系统数据层（spec 001 勋章系统）
//
// 与后端 `backend/services/badge_service.py` 同口径：
//   · 29 枚勋章目录（见 BADGES），按 7 类组织；
//   · 8 项指标快照（collectMetrics），复用本机学情数据；
//   · 达成判定（isAchieved）+ 幂等授予（evaluate，授予记录存 LocalDb.badges）；
//   · mine / unseen / mark_read 供「我的勋章」页与首页提醒使用。
//
// 懒评估策略：mine/unseen 内部先调 evaluate，确保页面打开时授予记录已落盘，
// 无需在每个事件点（答题/复习/对话/路线）都触发评估，避免侵入主链路。
import 'local_db.dart';
import 'local_mastery.dart';
import 'local_insight.dart';
import 'offline_content.dart';

/// 单枚勋章定义（与后端 `badge_service.BadgeDef` 同字段）。
class BadgeDef {
  final String badgeId;
  final String name;
  final String description;
  final String category;
  final String iconKey;
  final String conditionType; // threshold | ratio | completion
  final String metricKey;
  final double threshold;
  final String? ratioMetric;
  final double? accuracyThreshold;
  final int sortOrder;
  final bool enabled;

  const BadgeDef({
    required this.badgeId,
    required this.name,
    required this.description,
    required this.category,
    required this.iconKey,
    required this.conditionType,
    required this.metricKey,
    required this.threshold,
    this.ratioMetric,
    this.accuracyThreshold,
    this.sortOrder = 0,
    this.enabled = true,
  });
}

// ------------------------------------------------------------------ 目录
// 分类顺序与后端一致：知识掌握 / 贯通 / 里程碑 / 答题 / 路线 / 连续学习 / 对话
final List<BadgeDef> _badges = [
  // ---- 知识掌握（mastered_count）----
  const BadgeDef(badgeId: 'mastery_1', name: '初窥门径',
      description: '掌握 1 个知识点，迈出学习第一步', category: '知识掌握',
      iconKey: 'knowledge', conditionType: 'threshold',
      metricKey: 'mastered_count', threshold: 1, sortOrder: 101),
  const BadgeDef(badgeId: 'mastery_5', name: '知识新苗',
      description: '掌握 5 个知识点，知识开始扎根', category: '知识掌握',
      iconKey: 'knowledge', conditionType: 'threshold',
      metricKey: 'mastered_count', threshold: 5, sortOrder: 102),
  const BadgeDef(badgeId: 'mastery_10', name: '知识学人',
      description: '掌握 10 个知识点，学习渐入佳境', category: '知识掌握',
      iconKey: 'knowledge', conditionType: 'threshold',
      metricKey: 'mastered_count', threshold: 10, sortOrder: 103),
  const BadgeDef(badgeId: 'mastery_25', name: '知识行家',
      description: '掌握 25 个知识点，已成行家里手', category: '知识掌握',
      iconKey: 'knowledge', conditionType: 'threshold',
      metricKey: 'mastered_count', threshold: 25, sortOrder: 104),
  const BadgeDef(badgeId: 'mastery_50', name: '知识贤者',
      description: '掌握 50 个知识点，学识广博深厚', category: '知识掌握',
      iconKey: 'knowledge', conditionType: 'threshold',
      metricKey: 'mastered_count', threshold: 50, sortOrder: 105),
  const BadgeDef(badgeId: 'mastery_100', name: '知识宗师',
      description: '掌握 100 个知识点，登峰造极', category: '知识掌握',
      iconKey: 'knowledge', conditionType: 'threshold',
      metricKey: 'mastered_count', threshold: 100, sortOrder: 106),

  // ---- 贯通（journey_count）----
  const BadgeDef(badgeId: 'journey_5', name: '启程之步',
      description: '贯通 5 个知识点，思路开始贯通', category: '贯通',
      iconKey: 'journey', conditionType: 'threshold',
      metricKey: 'journey_count', threshold: 5, sortOrder: 201),
  const BadgeDef(badgeId: 'journey_15', name: '行途初启',
      description: '贯通 15 个知识点，脉络渐次清晰', category: '贯通',
      iconKey: 'journey', conditionType: 'threshold',
      metricKey: 'journey_count', threshold: 15, sortOrder: 202),
  const BadgeDef(badgeId: 'journey_30', name: '行途渐广',
      description: '贯通 30 个知识点，视野不断拓宽', category: '贯通',
      iconKey: 'journey', conditionType: 'threshold',
      metricKey: 'journey_count', threshold: 30, sortOrder: 203),
  const BadgeDef(badgeId: 'journey_60', name: '行途通达',
      description: '贯通 60 个知识点，融会贯通', category: '贯通',
      iconKey: 'journey', conditionType: 'threshold',
      metricKey: 'journey_count', threshold: 60, sortOrder: 204),

  // ---- 里程碑（milestones_achieved）----
  const BadgeDef(badgeId: 'milestone_1', name: '首个里程碑',
      description: '达成 1 个里程碑，目标初现', category: '里程碑',
      iconKey: 'milestone', conditionType: 'threshold',
      metricKey: 'milestones_achieved', threshold: 1, sortOrder: 301),
  const BadgeDef(badgeId: 'milestone_5', name: '里程碑探索者',
      description: '达成 5 个里程碑，探索见成果', category: '里程碑',
      iconKey: 'milestone', conditionType: 'threshold',
      metricKey: 'milestones_achieved', threshold: 5, sortOrder: 302),
  const BadgeDef(badgeId: 'milestone_10', name: '里程碑达人',
      description: '达成 10 个里程碑，步步为营', category: '里程碑',
      iconKey: 'milestone', conditionType: 'threshold',
      metricKey: 'milestones_achieved', threshold: 10, sortOrder: 303),
  const BadgeDef(badgeId: 'milestone_15', name: '里程碑守护者',
      description: '达成 15 个里程碑，坚持不懈', category: '里程碑',
      iconKey: 'milestone', conditionType: 'threshold',
      metricKey: 'milestones_achieved', threshold: 15, sortOrder: 304),

  // ---- 答题（quiz_correct_total / quiz_attempt_total）----
  const BadgeDef(badgeId: 'quiz_10', name: '初次答对',
      description: '累计答对 10 题，答题初见成效', category: '答题',
      iconKey: 'quiz', conditionType: 'threshold',
      metricKey: 'quiz_correct_total', threshold: 10, sortOrder: 401),
  const BadgeDef(badgeId: 'quiz_50', name: '答题新秀',
      description: '累计答对 50 题，答题渐入佳境', category: '答题',
      iconKey: 'quiz', conditionType: 'threshold',
      metricKey: 'quiz_correct_total', threshold: 50, sortOrder: 402),
  const BadgeDef(badgeId: 'quiz_100', name: '答题能手',
      description: '累计答对 100 题，答题驾轻就熟', category: '答题',
      iconKey: 'quiz', conditionType: 'threshold',
      metricKey: 'quiz_correct_total', threshold: 100, sortOrder: 403),
  const BadgeDef(badgeId: 'quiz_200', name: '答题宗师',
      description: '累计答对 200 题，答题炉火纯青', category: '答题',
      iconKey: 'quiz', conditionType: 'threshold',
      metricKey: 'quiz_correct_total', threshold: 200, sortOrder: 404),
  const BadgeDef(badgeId: 'quiz_acc_50', name: '精准之声',
      description: '累计作答 ≥50 题且正确率 ≥90%，精准过人', category: '答题',
      iconKey: 'quiz', conditionType: 'ratio',
      metricKey: 'quiz_attempt_total', threshold: 50,
      ratioMetric: 'quiz_correct_total', accuracyThreshold: 0.9, sortOrder: 405),

  // ---- 路线（routes_completed）----
  const BadgeDef(badgeId: 'route_1', name: '首路达成',
      description: '完成 1 条路线学习，首条路线圆满', category: '路线',
      iconKey: 'route', conditionType: 'threshold',
      metricKey: 'routes_completed', threshold: 1, sortOrder: 501),
  const BadgeDef(badgeId: 'route_3', name: '路线行者',
      description: '完成 3 条路线学习，行路渐远', category: '路线',
      iconKey: 'route', conditionType: 'threshold',
      metricKey: 'routes_completed', threshold: 3, sortOrder: 502),
  const BadgeDef(badgeId: 'route_5', name: '路线通晓',
      description: '完成 5 条路线学习，通晓多路', category: '路线',
      iconKey: 'route', conditionType: 'threshold',
      metricKey: 'routes_completed', threshold: 5, sortOrder: 503),
  const BadgeDef(badgeId: 'route_all', name: '全路先锋',
      description: '完成当前系统内全部已开放路线，全路贯通', category: '路线',
      iconKey: 'route', conditionType: 'completion',
      metricKey: 'routes_completed', threshold: 0, sortOrder: 504),

  // ---- 连续学习（streak_days）----
  const BadgeDef(badgeId: 'streak_7', name: '七日坚持',
      description: '连续学习 7 天，养成坚持的习惯', category: '连续学习',
      iconKey: 'streak', conditionType: 'threshold',
      metricKey: 'streak_days', threshold: 7, sortOrder: 601),
  const BadgeDef(badgeId: 'streak_21', name: '月度恒心',
      description: '连续学习 21 天，月度恒心可嘉', category: '连续学习',
      iconKey: 'streak', conditionType: 'threshold',
      metricKey: 'streak_days', threshold: 21, sortOrder: 602),
  const BadgeDef(badgeId: 'streak_60', name: '季度长跑',
      description: '连续学习 60 天，季度长跑不辍', category: '连续学习',
      iconKey: 'streak', conditionType: 'threshold',
      metricKey: 'streak_days', threshold: 60, sortOrder: 603),
  const BadgeDef(badgeId: 'streak_100', name: '百日不辍',
      description: '连续学习 100 天，百日坚持不辍', category: '连续学习',
      iconKey: 'streak', conditionType: 'threshold',
      metricKey: 'streak_days', threshold: 100, sortOrder: 604),

  // ---- 对话（dialogues_completed）----
  const BadgeDef(badgeId: 'dialogue_10', name: '对话初成',
      description: '完成 10 次对话学习，问答渐有收获', category: '对话',
      iconKey: 'dialogue', conditionType: 'threshold',
      metricKey: 'dialogues_completed', threshold: 10, sortOrder: 701),
  const BadgeDef(badgeId: 'dialogue_30', name: '对话熟手',
      description: '完成 30 次对话学习，问答驾轻就熟', category: '对话',
      iconKey: 'dialogue', conditionType: 'threshold',
      metricKey: 'dialogues_completed', threshold: 30, sortOrder: 702),
];

/// 全量目录（按 sort_order 排序）。
List<BadgeDef> allBadges({bool enabledOnly = true}) {
  if (enabledOnly) return _badges.where((b) => b.enabled).toList();
  return List.unmodifiable(_badges);
}

BadgeDef? badgeDef(String badgeId) {
  for (final b in _badges) {
    if (b.badgeId == badgeId) return b;
  }
  return null;
}

/// 指标键 -> 中文标签（用于 condition_text / 进度展示）。
String metricLabel(String key) {
  const labels = <String, String>{
    'mastered_count': '掌握知识点',
    'journey_count': '贯通知识点',
    'milestones_achieved': '达成里程碑',
    'quiz_correct_total': '累计答对题',
    'quiz_attempt_total': '累计作答题',
    'routes_completed': '完成路线',
    'streak_days': '连续学习',
    'dialogues_completed': '完成对话',
  };
  return labels[key] ?? key;
}

class LocalBadge {
  LocalBadge._();

  // ------------------------------------------------------------ 指标采集

  /// 采集 8 项勋章指标快照（与后端 `badge_service.collect_metrics` 同口径）。
  static Map<String, double> collectMetrics(String routeId) {
    final mastery = LocalMastery.masteryMap(routeId);
    final attempts = LocalDb.attemptsForRoute(routeId);

    var mastered = 0;
    var journey = 0;
    for (final rec in mastery.values) {
      final lv = rec['level'] as String? ?? 'unseen';
      if (lv != 'unseen') journey++;
      if (lv == 'mastered') mastered++;
    }

    var quizCorrect = 0;
    for (final a in attempts) {
      if (a['is_correct'] == true) quizCorrect++;
    }

    final streak = LocalInsight.streakOf(attempts);
    final routesCompleted = _routesCompleted();
    final dialoguesCompleted = LocalDb.dialogues.values.whereType<Map>().length;

    return <String, double>{
      'mastered_count': mastered.toDouble(),
      'journey_count': journey.toDouble(),
      'milestones_achieved': _milestonesAchieved(mastered, streak, attempts.length).toDouble(),
      'quiz_correct_total': quizCorrect.toDouble(),
      'quiz_attempt_total': attempts.length.toDouble(),
      'routes_completed': routesCompleted.toDouble(),
      'streak_days': streak.toDouble(),
      'dialogues_completed': dialoguesCompleted.toDouble(),
    };
  }

  /// 已达成里程碑数（复用动机系统里程碑口径）。
  static int _milestonesAchieved(int mastered, int streak, int attempts) {
    var achieved = 0;
    for (final step in [1, 5, 10, 25]) {
      if (mastered >= step) achieved++;
    }
    for (final step in [7, 21]) {
      if (streak >= step) achieved++;
    }
    for (final step in [10, 25, 50]) {
      if (attempts >= step) achieved++;
    }
    return achieved;
  }

  /// 完成路线数（复用后端 `_routes_completed_in_memory` 口径）。
  static int _routesCompleted() {
    var completed = 0;
    for (final r in OfflineContent.routes.whereType<Map>()) {
      final rid = '${r['id'] ?? ''}';
      if (rid.isEmpty) continue;
      final secs = OfflineContent.allSections
          .whereType<Map>()
          .where((s) => '${s['route_id'] ?? ''}' == rid)
          .toList();
      if (_routeComplete(rid, secs)) completed++;
    }
    return completed;
  }

  static bool _routeComplete(String rid, List<Map> secs) {
    if (secs.isEmpty) return false;
    for (final s in secs) {
      final sid = '${s['id'] ?? ''}';
      if (sid.isEmpty) continue;
      final meta = OfflineContent.sectionMeta(sid) ?? const <String, dynamic>{};
      final prog = LocalMastery.progressOf(rid, sid);
      final nodes = OfflineContent.allNodes
          .whereType<Map>()
          .where((n) => '${n['section_id'] ?? ''}' == sid)
          .toList();
      if (nodes.isEmpty) {
        // 占位章：用进度状态/锚点降级判定
        final status = '${prog['status'] ?? ''}';
        if (status == 'completed' || status == 'done') continue;
        final anchor = (prog['current_anchor'] as num?)?.toDouble() ?? 0.0;
        if (anchor > 0) continue;
        return false;
      }
      // 有知识点章：用章节掌握度判定
      final score = LocalMastery.sectionMasteryScore(LocalMastery.masteryMap(rid), sid);
      final threshold =
          (meta['unlock_threshold'] as num?)?.toDouble() ?? 0.8;
      if (score < threshold) return false;
    }
    return true;
  }

  // ------------------------------------------------------------ 达成判定

  /// 判定单枚勋章是否达成（与后端 `_is_achieved` 同口径）。
  static bool isAchieved(BadgeDef b, Map<String, double> m) {
    final cur = m[b.metricKey] ?? 0.0;
    if (b.conditionType == 'threshold') return cur >= b.threshold;
    if (b.conditionType == 'ratio') {
      if (cur < b.threshold) return false;
      final numerator = m[b.ratioMetric ?? ''] ?? 0.0;
      if (numerator <= 0) return false;
      return numerator / cur >= (b.accuracyThreshold ?? 0.0);
    }
    if (b.conditionType == 'completion') {
      // completion 型（如 route_all）：达成数 == 系统内全部路线数
      return _totalRoutes() > 0 && cur >= _totalRoutes();
    }
    return false;
  }

  static int _totalRoutes() => OfflineContent.routes.whereType<Map>().length;

  /// 人类可读的条件描述（与后端 `condition_text` 同口径）。
  static String conditionText(BadgeDef b) {
    final label = metricLabel(b.metricKey);
    if (b.conditionType == 'threshold') {
      return '$label ≥ ${_fmtNum(b.threshold)}';
    }
    if (b.conditionType == 'ratio') {
      return '$label ≥ ${_fmtNum(b.threshold)} 且正确率 ≥ '
          '${(b.accuracyThreshold! * 100).round()}%';
    }
    return b.description;
  }

  static String _fmtNum(double n) => n.toInt().toString();

  // ------------------------------------------------------------ 授予记录

  /// 授予记录：award_id 取 badge_id（每枚只授予一次，幂等）。
  static Map<String, dynamic> _grantedMap() {
    final out = <String, dynamic>{};
    for (final e in LocalDb.badges.entries) {
      if (e.value is Map) out[e.key] = e.value.cast<String, dynamic>();
    }
    return out;
  }

  static String? _awardedAt(Map<String, dynamic> rec) {
    final v = rec['awarded_at'];
    return v is String && v.isNotEmpty ? v : null;
  }

  // ------------------------------------------------------------ 评估 / 授予

  /// 达成检测 + 幂等授予。返回新授予勋章列表（供事件响应携带 badges_awarded）。
  ///
  /// 任何异常均兜底返回 []，不阻断主流程（spec FR-03 约束）。
  static List<Map<String, dynamic>> evaluate(String routeId,
      {String sourceEvent = 'auto'}) {
    try {
      final metrics = collectMetrics(routeId);
      final granted = _grantedMap();
      final now = DateTime.now().toUtc().toIso8601String();
      final newly = <Map<String, dynamic>>[];
      for (final b in allBadges(enabledOnly: false)) {
        if (!isAchieved(b, metrics)) continue;
        if (granted.containsKey(b.badgeId)) continue; // 幂等：已授予不重复
        final rec = <String, dynamic>{
          'award_id': b.badgeId,
          'badge_id': b.badgeId,
          'awarded_at': now,
          'source_event': sourceEvent,
          'read_flag': false,
        };
        LocalDb.badges[b.badgeId] = rec;
        newly.add(<String, dynamic>{
          'award_id': b.badgeId,
          'badge_id': b.badgeId,
          'name': b.name,
          'category': b.category,
          'icon_key': b.iconKey,
          'awarded_at': now,
        });
      }
      if (newly.isNotEmpty) LocalDb.flushKey('badges');
      return newly;
    } catch (_) {
      return [];
    }
  }

  // ------------------------------------------------------------ 查询接口

  /// 「我的勋章」页数据：全部勋章 + 授予状态 + 进度 + 指标快照。
  static Map<String, dynamic> mine(String routeId) {
    evaluate(routeId); // 懒评估：确保授予记录已落盘
    final metrics = collectMetrics(routeId);
    final granted = _grantedMap();
    final badges = <Map<String, dynamic>>[];
    var earned = 0;
    for (final b in allBadges(enabledOnly: false)) {
      final g = granted[b.badgeId];
      final earnedHere = g != null;
      if (earnedHere && b.enabled) earned++;
      badges.add(<String, dynamic>{
        'badge_id': b.badgeId,
        'name': b.name,
        'description': b.description,
        'category': b.category,
        'icon_key': b.iconKey,
        'condition_text': conditionText(b),
        'earned': earnedHere,
        'awarded_at': earnedHere ? _awardedAt(g.cast<String, dynamic>()) : null,
        'source_event': earnedHere ? g.cast<String, dynamic>()['source_event'] : null,
        'read': earnedHere ? (g.cast<String, dynamic>()['read_flag'] == true) : false,
        'progress': _progress(b, metrics),
        'disabled': !b.enabled,
      });
    }
    final total = allBadges(enabledOnly: false).length;
    return <String, dynamic>{
      'metrics': metrics,
      'badges': badges,
      'summary': <String, dynamic>{
        'total': total,
        'earned': earned,
        'unearned': total - earned,
      },
    };
  }

  /// 单枚勋章的进度（与后端 `_progress` 同口径）。
  static Map<String, dynamic> _progress(BadgeDef b, Map<String, double> m) {
    final cur = (m[b.metricKey] ?? 0.0).toInt();
    if (b.conditionType == 'threshold') {
      return <String, dynamic>{
        'current': cur,
        'target': b.threshold.toInt(),
        'display': '$cur/${b.threshold.toInt()}',
      };
    }
    if (b.conditionType == 'ratio') {
      final acc = m[b.ratioMetric ?? ''] != null && cur > 0
          ? (m[b.ratioMetric!]! / cur).clamp(0.0, 1.0)
          : 0.0;
      return <String, dynamic>{
        'current': cur,
        'target': b.threshold.toInt(),
        'accuracy': round4(acc),
        'display': '$cur/${b.threshold.toInt()}，正确率 ${(acc * 100).round()}%',
      };
    }
    // completion
    final total = _totalRoutes();
    return <String, dynamic>{
      'current': cur,
      'target': total,
      'display': '$cur/$total',
    };
  }

  /// 未查看的新勋章（首页提醒 / 开箱动画触发兜底）。
  static Map<String, dynamic> unseen(String routeId) {
    evaluate(routeId);
    final awards = <Map<String, dynamic>>[];
    for (final e in LocalDb.badges.entries) {
      final rec = e.value;
      if (rec is! Map) continue;
      final r = rec.cast<String, dynamic>();
      if (r['read_flag'] == true) continue;
      final b = badgeDef('${r['badge_id'] ?? ''}');
      if (b == null) continue;
      awards.add(<String, dynamic>{
        'award_id': r['award_id'] ?? e.key,
        'badge_id': b.badgeId,
        'name': b.name,
        'description': b.description,
        'category': b.category,
        'icon_key': b.iconKey,
        'awarded_at': _awardedAt(r),
      });
    }
    return <String, dynamic>{'awards': awards, 'count': awards.length};
  }

  /// 标记已查看（不存在的 award_id 静默忽略）。
  static int markRead(List<String> awardIds) {
    var updated = 0;
    for (final id in awardIds) {
      final rec = LocalDb.badges[id];
      if (rec is Map && rec['read_flag'] != true) {
        rec['read_flag'] = true;
        updated++;
      }
    }
    if (updated > 0) LocalDb.flushKey('badges');
    return updated;
  }

  static double round4(double v) {
    final f = (v * 10000).round();
    return (f / 10000).toDouble();
  }
}
