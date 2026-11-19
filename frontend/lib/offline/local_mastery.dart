// 掌握度 / 门控 / 间隔复习（单机版）：对应 backend/services/{mastery,review}_service.py
import 'dart:math' as math;

import '../offline/offline_content.dart';
import 'local_api_exception.dart';
import 'local_db.dart';

const List<String> kDims = [
  'materialism',
  'dialectics',
  'epistemology',
  'historical_materialism',
  'political_economy',
];
const List<String> kLevels = [
  'unseen',
  'beginner',
  'familiar',
  'proficient',
  'mastered',
];
const List<String> _weightKeys = [
  'accuracy',
  'difficulty',
  'stability',
  'dialogue',
  'feynman',
];

double dnum(dynamic v, [double fallback = 0.0]) =>
    (v as num?)?.toDouble() ?? fallback;
int inum(dynamic v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;
double round4(num v) => double.parse(v.toStringAsFixed(4));
String nowIso() => DateTime.now().toUtc().toIso8601String();
DateTime? parseTime(dynamic v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toUtc() : null;

class LocalMastery {
  LocalMastery._();

  // ------------------------------------------------------------ 基础
  static double computeScore(Map<String, dynamic> basis) {
    final weights =
        ((OfflineContent.config['mastery_weights']) as Map?) ?? const {};
    var num = 0.0;
    var den = 0.0;
    for (final k in _weightKeys) {
      final v = basis[k];
      if (v == null) continue;
      final w = dnum(weights[k], 0.1);
      num += w * dnum(v);
      den += w;
    }
    return den > 0 ? round4(num / den) : 0.0;
  }

  static String levelFromScore(double score, [Map<String, dynamic>? basis]) {
    final t = ((OfflineContent.config['mastery_thresholds']) as Map?) ?? const {};
    String level;
    if (score < dnum(t['unseen'], 0.2)) {
      level = 'unseen';
    } else if (score < dnum(t['beginner'], 0.45)) {
      level = 'beginner';
    } else if (score < dnum(t['familiar'], 0.7)) {
      level = 'familiar';
    } else if (score < dnum(t['proficient'], 0.85)) {
      level = 'proficient';
    } else {
      level = 'mastered';
    }
    if (level == 'mastered') {
      final fey = basis?['feynman'];
      if (fey == null || dnum(fey) < 0.8) level = 'proficient';
    }
    return level;
  }

  static double stabilitySeed(double score) {
    if (score < 0.2) return 0.1;
    if (score < 0.45) return 0.3;
    if (score < 0.7) return 0.5;
    if (score < 0.85) return 0.7;
    return 0.9;
  }

  static Map<String, dynamic> _newRecord(String nodeId) => {
        'node_id': nodeId,
        'score': 0.0,
        'level': 'unseen',
        'basis': <String, dynamic>{},
        'source_flags': <String, dynamic>{},
        'review_count': 0,
        'last_reviewed_at': null,
        'next_review_at': null,
        'updated_at': nowIso(),
      };

  static Map<String, dynamic> masteryMap(String routeId) {
    final out = <String, dynamic>{};
    LocalDb.masteryFor(routeId).forEach((k, v) {
      if (v is Map) out[k] = v.cast<String, dynamic>();
    });
    return out;
  }

  static Map<String, dynamic> record(String routeId, String nodeId) {
    final cur = LocalDb.masteryFor(routeId)[nodeId];
    return cur is Map ? cur.cast<String, dynamic>() : _newRecord(nodeId);
  }

  static Future<Map<String, dynamic>> upsert(
    String routeId,
    String nodeId,
    Map<String, dynamic> patch,
    String source, {
    bool scheduleReview = false,
  }) async {
    await LocalDb.ensure();
    final rec = record(routeId, nodeId);
    final basis =
        (rec['basis'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    patch.forEach((k, v) {
      if (v != null) basis[k] = v;
    });
    if (basis['stability'] == null) basis['stability'] = stabilitySeed(computeScore(basis));
    final score = computeScore(basis);
    rec['basis'] = basis;
    rec['score'] = score;
    rec['level'] = levelFromScore(score, basis);
    rec['updated_at'] = nowIso();
    final flags =
        (rec['source_flags'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    flags[source] = true;
    rec['source_flags'] = flags;
    if (scheduleReview) {
      final now = DateTime.now().toUtc();
      rec['last_reviewed_at'] = now.toIso8601String();
      rec['next_review_at'] = scheduleNext(dnum(basis['stability']), now: now);
      rec['review_count'] = inum(rec['review_count']) + 1;
    }
    LocalDb.putMastery(routeId, nodeId, rec);
    await LocalDb.flushKey('mastery');
    return rec;
  }

  // ------------------------------------------------------------ 章节
  static double sectionMasteryScore(
      Map<String, dynamic> mastery, String sectionId) {
    final nodes = OfflineContent.nodesOf(sectionId);
    if (nodes.isEmpty) return 0.0;
    final assessed = <double>[];
    for (final n in nodes) {
      final rec = mastery[n['id']];
      if (rec is Map) assessed.add(dnum(rec['score']));
    }
    if (assessed.isEmpty) return 0.0;
    return round4(assessed.reduce((a, b) => a + b) / assessed.length);
  }

  static Map<String, dynamic> progressOf(String routeId, String sectionId) {
    final cur = LocalDb.progressFor(routeId)[sectionId];
    return cur is Map ? cur.cast<String, dynamic>() : const {};
  }

  /// {bank, completed, score, threshold, assessed}
  static Map<String, dynamic> sectionProgress(
      String routeId, String sectionId, Map<String, dynamic> mastery) {
    final nodes = OfflineContent.nodesOf(sectionId);
    final score = sectionMasteryScore(mastery, sectionId);
    final threshold = OfflineContent.thresholdOf(sectionId);
    final bank = OfflineContent.sectionMeta(sectionId)?['has_bank'] == true;
    if (nodes.isEmpty) {
      final prog = progressOf(routeId, sectionId);
      final st = '${prog['status'] ?? ''}';
      return {
        'bank': bank,
        'completed':
            st == 'completed' || st == 'done' || inum(prog['last_position']) > 0,
        'score': score,
        'threshold': threshold,
        'assessed': 0,
      };
    }
    final assessed = nodes.where((n) => mastery.containsKey(n['id'])).length;
    return {
      'bank': bank,
      'completed': assessed > 0 && score >= threshold,
      'score': score,
      'threshold': threshold,
      'assessed': assessed,
    };
  }

  /// 门控：本章是否达标可解锁下一章。
  ///
  /// 与后端 `route_service.gating()` **同口径**（D134 修正）：
  ///  · 有题库章 → `unlocked = 已评估且章节分 ≥ 门槛`；
  ///  · 无题库章（纯阅读章）→ `unlocked = 通读后标记完成`（后端专用分支，
  ///    单机早先没实现，导致阅读章在单机永远解锁不了下一章）；
  ///  · 键名 `need_reinforce`（后端口径）与 `blocking_nodes`（后端补充键）都出，
  ///    旧键 `needs_reinforce` 保留兼容。
  static Map<String, dynamic> computeGating(
      Map<String, dynamic> mastery, String routeId, String sectionId) {
    final secs = OfflineContent.sectionsOf(routeId);
    final idx = secs.indexWhere((s) => s['id'] == sectionId);
    final score = sectionMasteryScore(mastery, sectionId);
    final threshold = OfflineContent.thresholdOf(sectionId);
    final nodes = OfflineContent.nodesOf(sectionId);
    final need = nodes
        .where((n) =>
            mastery.containsKey(n['id']) && dnum(mastery[n['id']]['score']) < threshold)
        .map((n) => n['id'])
        .toList();
    final assessed = nodes.where((n) => mastery.containsKey(n['id'])).length;
    final nextId = idx >= 0 && idx + 1 < secs.length ? secs[idx + 1]['id'] : null;
    final bank = OfflineContent.sectionMeta(sectionId)?['has_bank'] == true;
    final completed = sectionProgress(routeId, sectionId, mastery)['completed'] == true;
    final unlocked = bank ? (assessed > 0 && score >= threshold) : completed;
    return {
      'section_id': sectionId,
      'section_score': score,
      'threshold': threshold,
      'assessed_nodes': assessed,
      'next_section_id': nextId,
      'next_section_unlocked': unlocked,
      'unlocked': unlocked,
      'bank': bank,
      'blocking_nodes': need,
      'need_reinforce': need,
      'needs_reinforce': need,
      // 后端 `route_service.gating()` 只在「无题库（阅读章）」分支补 `completed`；
      // 单机原先从不给，阅读章的「已通读完成」状态在门控响应里读不到。
      if (!bank) 'completed': completed,
      'reason': !bank
          ? (completed
              ? '本章为阅读章，已标记完成'
              : '本章为阅读章，通读全文后标记完成即可解锁下一章')
          : (unlocked
              ? '本章达标，可进入下一章'
              : (assessed == 0 ? '尚无评估记录，先做本章测验' : '部分知识点未达门槛，建议专项回补')),
    };
  }

  // ------------------------------------------------------------ 复习
  static Map<String, dynamic> get _cfg =>
      ((OfflineContent.config['review']) as Map?)?.cast<String, dynamic>() ??
      const {};

  static double halfLife(double stability) {
    final lo = dnum(_cfg['half_life_min_days'], 3);
    final hi = dnum(_cfg['half_life_max_days'], 15);
    return lo + (hi - lo) * stability.clamp(0.0, 1.0);
  }

  static double retention(double elapsedDays, double stability) {
    final hl = halfLife(stability);
    if (hl <= 0) return 0.0;
    return math.pow(0.5, elapsedDays / hl).toDouble();
  }

  /// 建议复习间隔（天）—— 与后端 `review_service.interval_days` 逐字同式：
  /// `min(MAX, max(0.5, base × 2^(max(0,stability)/0.3)))`。
  /// 少了下限 0.5 与负 stability 归零，两端口径会在极低稳定度下差半天。
  static double intervalDays(double stability) {
    final base = dnum(_cfg['base_interval_days'], 1);
    final maxDays = dnum(_cfg['max_interval_days'], 60);
    final raw = base * math.pow(2, math.max(0.0, stability) / 0.3);
    return math.min(maxDays, math.max(0.5, raw)).toDouble();
  }

  static String scheduleNext(double stability, {DateTime? now}) {
    final at = (now ?? DateTime.now().toUtc())
        .add(Duration(seconds: (intervalDays(stability) * 86400).round()));
    return at.toUtc().toIso8601String();
  }

  static List<String> _dependents(String nodeId) {
    final node = OfflineContent.node(nodeId);
    return ((node?['dependents'] as List?) ?? const []).map((e) => '$e').toList();
  }

  static int dependentsCount(String nodeId) {
    final seen = <String>{};
    var stack = _dependents(nodeId);
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      if (!seen.add(cur)) continue;
      stack = [...stack, ..._dependents(cur)];
    }
    return seen.length;
  }

  static int blockingSections(String nodeId) {
    final node = OfflineContent.node(nodeId);
    if (node == null) return 0;
    final out = <String>{};
    final seen = <String>{};
    var stack = _dependents(nodeId);
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      if (!seen.add(cur)) continue;
      final n = OfflineContent.node(cur);
      if (n == null) continue;
      final sid = '${n['section_id'] ?? ''}';
      if (sid.isNotEmpty && sid != '${node['section_id']}') out.add(sid);
      stack = [...stack, ..._dependents(cur)];
    }
    return out.length;
  }

  static List<Map<String, dynamic>> dueReviews(String routeId, {DateTime? now}) {
    final at = now ?? DateTime.now().toUtc();
    final dueRetention = dnum(_cfg['due_retention'], 0.9);
    final scored = <Map<String, dynamic>>[];
    masteryMap(routeId).forEach((nodeId, value) {
      final rec = value as Map<String, dynamic>;
      final score = dnum(rec['score']);
      if (score < 0.2) return;
      final basis =
          (rec['basis'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      final stability = dnum(basis['stability']);
      final last = parseTime(rec['last_reviewed_at']) ??
          parseTime(rec['updated_at']) ??
          at;
      final elapsed = at.difference(last).inSeconds / 86400.0;
      final keep = retention(elapsed, stability);
      final next = parseTime(rec['next_review_at']);
      final isDue =
          keep < dueRetention || (next != null && !next.isAfter(at));
      if (!isDue) return;
      final node = OfflineContent.node(nodeId);
      scored.add({
        'node_id': nodeId,
        'name': node?['name'] ?? nodeId,
        'section_id': node?['section_id'] ?? '',
        'score': score,
        'stability': round4(stability),
        'retention': round4(keep),
        'elapsed_days': round4(elapsed),
        // 与后端 `review_service.due_reviews()` 同键：补齐下次复习时间，
        // 复习页可直接展示「何时再复习」而不必再查单节点详情。
        'next_review_at': rec['next_review_at'],
        'kind': 'due',
        '_risk': (1 - keep) * (1 + dependentsCount(nodeId)),
      });
    });
    // D136：并列写死 tie-break（`_risk` 相同再按 node_id 升序）。
    // Dart 的 `List.sort` **不稳定**，只比一个键时同分项顺序由实现细节决定；
    // 后端稳定排序也只能「保持 SQL 返回序」，SQL 本身没有 ORDER BY → 两套顺序。
    scored.sort(_byRisk);
    for (final it in scored) {
      it.remove('_risk');
    }
    return scored;
  }

  /// 到期队列排序：风险降序 → node_id 升序（与后端 `due_reviews()` 同式）。
  static int _byRisk(Map<String, dynamic> a, Map<String, dynamic> b) {
    final c = dnum(b['_risk']).compareTo(dnum(a['_risk']));
    return c != 0 ? c : '${a['node_id']}'.compareTo('${b['node_id']}');
  }

  /// 复习概览排序：稳定度升序 → node_id 升序（与后端 `review_status()` 同式）。
  /// 不按 `next_review_at`：它是「写入时刻 + 间隔」，写入时刻各端 wall clock 不同，
  /// 稳定度相同时排序退化成写入序 —— 同一份数据会排出两种顺序。
  static int _byStability(Map<String, dynamic> a, Map<String, dynamic> b) {
    final c = dnum(a['stability']).compareTo(dnum(b['stability']));
    return c != 0 ? c : '${a['node_id']}'.compareTo('${b['node_id']}');
  }

  static Map<String, dynamic> reviewStatus(String routeId) {
    final now = DateTime.now().toUtc();
    final items = <Map<String, dynamic>>[];
    masteryMap(routeId).forEach((nodeId, value) {
      final rec = value as Map<String, dynamic>;
      final basis =
          (rec['basis'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      final stability = dnum(basis['stability']);
      final last =
          parseTime(rec['last_reviewed_at']) ?? parseTime(rec['updated_at']);
      final elapsed =
          last == null ? 0.0 : now.difference(last).inSeconds / 86400.0;
      final node = OfflineContent.node(nodeId);
      items.add({
        'node_id': nodeId,
        'name': node?['name'] ?? nodeId,
        'section_id': node?['section_id'] ?? '',
        'score': dnum(rec['score']),
        'level': rec['level'],
        'stability': round4(stability),
        'retention': round4(retention(elapsed, stability)),
        'elapsed_days': round4(elapsed),
        // 与后端 `review_status()` 同键（D134）：缺它则“复习次数”两端口径不一。
        'review_count': inum(rec['review_count']),
        'next_review_at': rec['next_review_at'],
      });
    });
    // D136：`items` 契约与后端 `review_service.review_status()` 同式 ——
    // 稳定度低的先复习（stability 升序）→ 并列按 node_id。
    items.sort(_byStability);
    final due = dueReviews(routeId);
    return {
      'route_id': routeId,
      'due_count': due.length,
      'due': due,
      'items': items,
    };
  }

  /// 复习结果回写。与后端 `review_service.apply_review()` 同口径（D134）：
  ///  · 无掌握记录 → `applied: false` + `reason: '尚无掌握记录'`（不再凭空建档）；
  ///  · 增益门槛 `correct_ratio >= 0.8`（旧实现是 `>= 0.999`，期 0.9 的“基本记得”
  ///    在联网算增益、单机算衰减）；
  ///  · 返回体补齐 `applied` / `reason` / `retention_now` / `review_count_delta`。
  static Future<Map<String, dynamic>> applyReview(
      String routeId, String nodeId, double correctRatio) async {
    await LocalDb.ensure();
    final existing = LocalDb.masteryFor(routeId)[nodeId];
    if (existing is! Map) {
      return {
        'node_id': nodeId,
        'applied': false,
        'reason': '尚无掌握记录',
      };
    }
    final rec = record(routeId, nodeId);
    final basis =
        (rec['basis'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final gain = dnum(_cfg['gain'], 0.15);
    final regress = dnum(_cfg['regress'], 0.2);
    final base = dnum(basis['stability']) <= 0
        ? stabilitySeed(dnum(rec['score']))
        : dnum(basis['stability']);
    final stability =
        (base + (correctRatio >= 0.8 ? gain : -regress)).clamp(0.0, 1.0);
    final acc = dnum(basis['accuracy']);
    final out = await upsert(
      routeId,
      nodeId,
      {
        'stability': round4(stability),
        if (acc > 0) 'accuracy': round4((acc + correctRatio) / 2),
      },
      'review',
      scheduleReview: true,
    );
    return {
      'node_id': nodeId,
      'applied': true,
      'stability': round4(stability),
      'retention_now': round4(retention(0.0, stability)),
      'next_review_at': out['next_review_at'],
      'review_count_delta': 1,
      'level': out['level'],
      'score': out['score'],
    };
  }

  static List<Map<String, dynamic>> interleaved(String routeId, {int n = 8}) {
    // D135：`n` 来自 query，负值会让 `take(n)` 抛
    // `RangeError (end): Invalid value`（单机上表现为整页报错，联网侧只是回空表）。
    // 与后端同式钳制。
    final lim = n.clamp(0, 50);
    final cfg =
        ((OfflineContent.config['interleave']) as Map?)?.cast<String, dynamic>() ??
            const {};
    final mixRatio = dnum(cfg['mix_ratio'], 0.4);
    final picked = <Map<String, dynamic>>[];
    for (final it in dueReviews(routeId)) {
      if (picked.length >= lim) break;
      picked.add({...it, 'kind': 'due'});
    }
    if (picked.length < lim) {
      final extra = <Map<String, dynamic>>[];
      masteryMap(routeId).forEach((nodeId, value) {
        final rec = value as Map<String, dynamic>;
        if (dnum(rec['score']) < 0.6) return;
        if (picked.any((p) => p['node_id'] == nodeId)) return;
        final node = OfflineContent.node(nodeId);
        final basis =
            (rec['basis'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
        extra.add({
          'node_id': nodeId,
          'name': node?['name'] ?? nodeId,
          'section_id': node?['section_id'] ?? '',
          'score': dnum(rec['score']),
          'stability': round4(dnum(basis['stability'])),
          'retention': 1.0,
          'elapsed_days': 0.0,
          'kind': 'interleave',
        });
      });
      // D136：巩固池排序 + 跨小节轮转，与后端 `interleaved_reviews()` 逐字同式。
      // 原先单机按 `masteryMap` 迭代序直接塞（无排序、无轮转），同一份数据两套队列。
      extra.sort((a, b) {
        final c = dnum(a['score']).compareTo(dnum(b['score']));
        return c != 0 ? c : '${a['node_id']}'.compareTo('${b['node_id']}');
      });
      final rotated = _rotateBySection(extra);
      final target = math.max(lim, (lim * mixRatio).round());
      for (final it in rotated) {
        if (picked.length >= target) break;
        picked.add(it);
      }
    }
    return _interleaveOrder(picked).take(lim).toList();
  }

  /// 按小节轮转（与后端 `_rotate_by_section()` 同式）：不同小节的节点交替排列。
  static List<Map<String, dynamic>> _rotateBySection(
      List<Map<String, dynamic>> items) {
    final buckets = <String, List<Map<String, dynamic>>>{};
    for (final it in items) {
      buckets.putIfAbsent('${it['section_id'] ?? ''}', () => []).add(it);
    }
    final out = <Map<String, dynamic>>[];
    while (buckets.values.any((v) => v.isNotEmpty)) {
      for (final k in buckets.keys.toList()) {
        final b = buckets[k]!;
        if (b.isNotEmpty) out.add(b.removeAt(0));
      }
    }
    return out;
  }

  static List<Map<String, dynamic>> _interleaveOrder(
      List<Map<String, dynamic>> items) {
    final remaining = List<Map<String, dynamic>>.from(items);
    final out = <Map<String, dynamic>>[];
    String? prevNode;
    String? prevSec;
    while (remaining.isNotEmpty) {
      var pickIdx = 0;
      for (var i = 0; i < remaining.length; i++) {
        final it = remaining[i];
        if (it['node_id'] != prevNode && it['section_id'] != prevSec) {
          pickIdx = i;
          break;
        }
      }
      final picked = remaining.removeAt(pickIdx);
      out.add(picked);
      prevNode = picked['node_id'] as String?;
      prevSec = picked['section_id'] as String?;
    }
    return out;
  }

  static Map<String, dynamic> fitParameters() {
    final rows = LocalDb.attempts
        .whereType<Map>()
        .map((a) => a.cast<String, dynamic>())
        .where((a) => a['node_id'] != null)
        .toList();
    final cfg = _cfg;
    final current = {
      'gain': dnum(cfg['gain'], 0.15),
      'regress': dnum(cfg['regress'], 0.2),
    };
    if (rows.length < 8) {
      return {
        'available': false,
        'message': '样本不足（${rows.length}/8），继续积累复习记录',
        'current': current,
        'suggested': null,
      };
    }
    final succ = rows.where((a) => a['is_correct'] == true).length / rows.length;
    return {
      'available': true,
      'message': '基于 ${rows.length} 条本机作答估算的参数建议',
      'succ_rate': round4(succ),
      'current': current,
      'suggested': {
        'gain': round4(current['gain']! * (0.8 + succ * 0.4)),
        'regress': round4(1.0 - succ),
      },
      'note': '单机版仅用本机作答流水，参数仅供参考',
    };
  }

  // ------------------------------------------------------------ 路线
  static Future<Map<String, dynamic>> listRoutes() async {
    await OfflineContent.ensureMeta();
    return {'routes': OfflineContent.routes};
  }

  static Future<Map<String, dynamic>> routesSections(String routeId) async {
    await OfflineContent.ensureMeta();
    await LocalDb.ensure();
    final mastery = masteryMap(routeId);
    final out = <Map<String, dynamic>>[];
    var prevDone = true;
    for (final sec in OfflineContent.sectionsOf(routeId)) {
      final sid = sec['id'] as String;
      final prog = sectionProgress(routeId, sid, mastery);
      String status;
      if (prog['completed'] == true) {
        status = 'completed';
      } else if (inum(prog['assessed']) > 0 ||
          progressOf(routeId, sid).isNotEmpty) {
        status = 'in_progress';
      } else {
        // 单机版允许自由跳章，不再硬锁
        status = 'unlocked';
      }
      out.add({
        'id': sid,
        'order_index': sec['order_index'],
        'stage_no': sec['stage_no'],
        'stage_label': sec['stage_label'],
        'work': sec['work'],
        'title': sec['title'],
        'is_foundation': sec['is_foundation'],
        'local_work': sec['local_work'],
        'work_short': sec['work_short'],
        'status': status,
        'mastery_score': prog['score'],
        'unlock_threshold': prog['threshold'],
        'has_bank': prog['bank'],
        'prev_completed': prevDone,
      });
      prevDone = prog['completed'] == true;
    }
    return {
      'route_id': routeId,
      'sections': out,
      'foundation': _foundationRows(routeId, out.map((e) => e['id'] as String).toSet()),
    };
  }

  /// 公共地基（D152）：三条路线共用三章（《大众哲学》×2 + 《提纲》），只排在路线 A。
  ///
  /// 单机版为什么也要算：B/C 的章节列表里没有《大众哲学》两章，不补一张地基卡，
  /// 切到 B 的人会以为地基已经过关。三个坑与后端 `shared_foundation()` 同口径：
  ///   ① 地基章只排在路线 A → B/C 靠这张卡补；
  ///   ② 但《提纲》在 B/C 有占位章（sec_B_00 / sec_C_00）→ 按 `is_foundation` 占位章
  ///      匹配，**不能**按 local_work 匹配（《大众哲学》两章共用同一部原著）；
  ///   ③ 掌握度按「用户 × 路线」存 → 占位章读当前路线，其余锚 route_A，
  ///      否则从 A 切到 B 会看到刚学完的地基又归零。
  static List<Map<String, dynamic>> _foundationRows(String routeId, Set<String> ownIds) {
    final route = OfflineContent.routes
        .cast<Map<String, dynamic>?>()
        .firstWhere((r) => r != null && r['id'] == routeId, orElse: () => null);
    if (route == null || route['shares_foundation'] != true) return const [];
    // 老资产里 B/C 的 foundation_ref 可能是 "shared"，此时按「全部地基章」处理
    final ref = '${route['foundation_ref'] ?? ''}'.trim();
    final declared = (ref.isEmpty || ref == 'shared')
        ? null
        : ref.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    // 地基章本体只排在路线 A（B/C 只有《提纲》占位章），所以基准清单取 A 的
    // is_foundation 章，再按 foundation_ref 过滤；旧资产写 "shared" 时就是全部三章。
    const anchorRoute = 'route_A';
    final target = OfflineContent.sectionsOf(anchorRoute)
        .where((sec) => sec['is_foundation'] == true &&
            (declared == null || declared.contains(sec['id'])))
        .toList();
    if (target.isEmpty) return const [];

    // 本路线的《提纲》占位章（sec_B_00 / sec_C_00）——只认标了 is_foundation 的
    final placeholders = <String, Map<String, dynamic>>{};
    for (final sec in OfflineContent.sectionsOf(routeId)) {
      if (sec['is_foundation'] != true || (declared?.contains(sec['id']) ?? false)) continue;
      final lw = '${sec['local_work'] ?? ''}'.trim();
      if (lw.isNotEmpty) placeholders.putIfAbsent(lw, () => sec);
    }

    const anchor = 'route_A';
    final anchorMap = masteryMap(anchor);
    final curMap = routeId == anchor ? anchorMap : masteryMap(routeId);
    final rows = <Map<String, dynamic>>[];
    for (final sec in target) {
      final sid = sec['id'] as String;
      final lw = '${sec['local_work'] ?? ''}'.trim();
      final bool inRoute = ownIds.contains(sid);
      final placeholder = inRoute ? null : (lw.isEmpty ? null : placeholders[lw]);
      final readRoute = inRoute || placeholder != null ? routeId : anchor;
      final progId = inRoute ? sid : (placeholder?['id'] as String? ?? sid);
      final prog = sectionProgress(readRoute, progId, readRoute == anchor ? anchorMap : curMap);
      String status;
      if (prog['completed'] == true) {
        status = 'completed';
      } else if (inum(prog['assessed']) > 0 || progressOf(readRoute, progId).isNotEmpty) {
        status = 'in_progress';
      } else {
        status = 'unlocked';
      }
      rows.add({
        'id': sid,
        'route_id': anchor,
        'in_route': inRoute || placeholder != null,
        'covered_by': placeholder?['id'],
        'order_index': sec['order_index'],
        'stage_no': sec['stage_no'],
        'stage_label': sec['stage_label'],
        'work': sec['work'],
        'title': sec['title'],
        'is_foundation': true,
        'local_work': sec['local_work'],
        'work_short': sec['work_short'],
        'status': status,
        'mastery_score': prog['score'],
        'unlock_threshold': prog['threshold'],
        'has_bank': prog['bank'],
      });
    }
    rows.sort((a, b) => (a['order_index'] as num).compareTo(b['order_index'] as num));
    return rows;
  }

  static Future<Map<String, dynamic>> guide(
      String routeId, String sectionId) async {
    await OfflineContent.ensureMeta();
    await LocalDb.ensure();
    // D135：未知章节在后端是 404（原先那里还会 `AttributeError` 500）；
    // 单机若照样回一张空导读，界面会显示「本章暂无导读」这种假事实。
    await OfflineContent.ensureMeta();
    if (OfflineContent.sectionMeta(sectionId) == null) {
      throw LocalApiException(404, '章节不存在: $sectionId');
    }
    final payload = await OfflineContent.sectionPayload(sectionId);
    markProgress(routeId, sectionId);
    final meta = OfflineContent.sectionMeta(sectionId) ?? const {};
    return {
      'section_id': sectionId,
      'route_id': routeId,
      'guide': payload['guide'] ?? const {},
      'nodes': payload['nodes'] ?? const [],
      'section_work': payload['section_work'] ?? meta['work'],
      'section_title': payload['section_title'] ?? meta['title'],
      'local_work': payload['local_work'] ?? meta['local_work'],
      'work_short': payload['work_short'] ?? meta['work_short'],
      'source_links': payload['source_links'] ?? const {},
      'extensions': payload['extensions'] ?? const [],
      'extensions_blacklist': payload['extensions_blacklist'] ?? const [],
    };
  }

  static Map<String, dynamic> markProgress(String routeId, String sectionId,
      {String status = 'in_progress', int lastPosition = 0}) {
    final merged = <String, dynamic>{...progressOf(routeId, sectionId)};
    merged['section_id'] = sectionId;
    merged['status'] = status;
    merged['last_position'] = math.max(inum(merged['last_position']), lastPosition);
    merged['updated_at'] = nowIso();
    LocalDb.putProgress(routeId, sectionId, merged);
    LocalDb.flushKey('progress');
    return {
      'section_id': sectionId,
      'last_position': merged['last_position'],
      'status': merged['status'],
    };
  }

  static Map<String, dynamic> pullSnapshot(String routeId) {
    final prog = LocalDb.progressFor(routeId);
    final last = prog.values.whereType<Map>().fold<Map?>(null, (acc, cur) {
      if (acc == null) return cur;
      final a = '${acc['updated_at'] ?? ''}';
      final b = '${cur['updated_at'] ?? ''}';
      return b.compareTo(a) > 0 ? cur : acc;
    });
    // 形状对齐后端 /api/sync/pull：progress 是列表（便于逐条断点续学）
    final rows = prog.entries
        .where((e) => e.value is Map)
        .map((e) => {
              'section_id': e.key,
              'last_position': inum((e.value as Map)['last_position']),
              'status': '${(e.value as Map)['status'] ?? 'in_progress'}',
              'updated_at': (e.value as Map)['updated_at'],
            })
        .toList();
    return {
      'route_id': routeId,
      'progress': rows,
      'mastery': masteryMap(routeId),
      'anchor': last == null
          ? null
          : {
              'section_id': last['section_id'] ?? '',
              'last_position': last['last_position'] ?? 0,
              'status': last['status'] ?? 'in_progress',
            },
      'server_time': nowIso(),
    };
  }
}
