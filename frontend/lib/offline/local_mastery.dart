// 掌握度 / 门控 / 间隔复习（单机版）：对应 backend/services/{mastery,review}_service.py
import 'dart:math' as math;

import '../offline/offline_content.dart';
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
    final unlocked = assessed > 0 && score >= threshold;
    return {
      'section_id': sectionId,
      'section_score': score,
      'threshold': threshold,
      'assessed_nodes': assessed,
      'next_section_id': nextId,
      'needs_reinforce': need,
      'next_section_unlocked': unlocked,
      'reason': unlocked
          ? '本章达标，可进入下一章'
          : (assessed == 0 ? '尚无评估记录，先做本章测验' : '部分知识点未达门槛，建议专项回补'),
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

  static double intervalDays(double stability) {
    final base = dnum(_cfg['base_interval_days'], 1);
    final maxDays = dnum(_cfg['max_interval_days'], 60);
    return math.min(maxDays, base * math.pow(2, stability / 0.3)).toDouble();
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
        'kind': 'due',
        '_risk': (1 - keep) * (1 + dependentsCount(nodeId)),
      });
    });
    scored.sort((a, b) => dnum(b['_risk']).compareTo(dnum(a['_risk'])));
    for (final it in scored) {
      it.remove('_risk');
    }
    return scored;
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
        'next_review_at': rec['next_review_at'],
      });
    });
    final due = dueReviews(routeId);
    return {
      'route_id': routeId,
      'due_count': due.length,
      'due': due,
      'items': items,
    };
  }

  static Future<Map<String, dynamic>> applyReview(
      String routeId, String nodeId, double correctRatio) async {
    await LocalDb.ensure();
    final rec = record(routeId, nodeId);
    final basis =
        (rec['basis'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final gain = dnum(_cfg['gain'], 0.15);
    final regress = dnum(_cfg['regress'], 0.2);
    final base = dnum(basis['stability']) <= 0
        ? stabilitySeed(dnum(rec['score']))
        : dnum(basis['stability']);
    final stability = (base + (correctRatio >= 0.999 ? gain : -regress)).clamp(0.0, 1.0);
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
      'level': out['level'],
      'score': out['score'],
      'stability': round4(stability),
      'next_review_at': out['next_review_at'],
    };
  }

  static List<Map<String, dynamic>> interleaved(String routeId, {int n = 8}) {
    final cfg =
        ((OfflineContent.config['interleave']) as Map?)?.cast<String, dynamic>() ??
            const {};
    final mixRatio = dnum(cfg['mix_ratio'], 0.4);
    final picked = <Map<String, dynamic>>[];
    for (final it in dueReviews(routeId)) {
      if (picked.length >= n) break;
      picked.add({...it, 'kind': 'due'});
    }
    if (picked.length < n) {
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
      final target = math.max(n, (n * mixRatio).round());
      for (final it in extra) {
        if (picked.length >= target) break;
        picked.add(it);
      }
    }
    return _interleaveOrder(picked).take(n).toList();
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
    return {'route_id': routeId, 'sections': out};
  }

  static Future<Map<String, dynamic>> guide(
      String routeId, String sectionId) async {
    await OfflineContent.ensureMeta();
    await LocalDb.ensure();
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
