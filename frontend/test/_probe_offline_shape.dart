// 一次性探针（D134）：把单机版各接口的**返回键集合**打出来，供 Python 侧与
// 联网后端同路径返回键集合做比对，找出「单机版少键 / 键名不同」的真缺陷。
// 先做一次测验（start + submit）造出非空数据，否则列表项的形状（weak_points[]、
// due[]、items[] …）两边都是空数组，比对不到。
// 输出格式：一行 JSON，`{"<method> <path>": {...keys...}}`，键为 `父.子` 形式（深度 2）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_router.dart';

import 'helpers/offline_assets_guard.dart';

const _get = <String>[
  '/api/routes',
  '/api/routes/route_A/sections',
  '/api/routes/route_A/sections/sec_A_00/guide',
  '/api/routes/route_A/sections/sec_A_00/gating',
  '/api/routes/route_A/sections/sec_A_02/gating',
  '/api/mastery/profile',
  '/api/mastery/node/kn_practice',
  '/api/recommendation/today',
  '/api/recommendation/next',
  '/api/recommendation/weak-top',
  '/api/review/due',
  '/api/review/interleaved',
  '/api/review/status',
  '/api/motivation/state',
  '/api/analytics/overview',
  '/api/analytics/calibration',
  '/api/quiz/history',
  '/api/chunks/works',
  '/api/sync/pull',
  '/api/profile',
];

Map<String, List<String>> _shape(dynamic v, [String prefix = '', int depth = 0]) {
  final out = <String, List<String>>{};
  if (v is List) {
    if (v.isNotEmpty) out.addAll(_shape(v.first, '$prefix[]', depth)); // 列表本身不算一层
    return out;
  }
  if (v is Map) {
    if (depth > 1) return out;
    out[prefix.isEmpty ? '.' : prefix] = (v.keys.map((k) => '$k').toList()..sort());
    for (final e in v.entries) {
      out.addAll(_shape(e.value, prefix.isEmpty ? '${e.key}' : '$prefix.${e.key}', depth + 1));
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (skipWithoutOfflineAssets()) return;

  test('dump offline shape', () async {
    // —— 造数据：一章测验全答 A（客观题对错不重要，只为留下 attempts/mastery）
    final started =
        await LocalRouter.post('/api/quiz/section/sec_A_00/start', const {});
    final items = (started['items'] as List?) ?? const [];
    if (items.isNotEmpty) {
      // 故意空作答 → 全错，分数 < 0.8，weak_points 非空（否则两侧列表都空、
      // 列表项形状比对不到）。
      await LocalRouter.post('/api/quiz/${started['test_id']}/submit', {
        'answers': const [],
      });
    }

    final all = <String, dynamic>{};
    final post = <String, Map<String, dynamic>>{
      '/api/quiz/section/sec_A_02/start': const {},
      '/api/mastery/summary': const {'user_id': 'demo_user', 'route_id': 'route_A'},
      '/api/review/submit': const {'node_id': 'kn_practice', 'correct_ratio': 1.0},
    };
    for (final p in _get) {
      try {
        final res = await LocalRouter.get(p, const {});
        all['GET $p'] = _shape(res);
      } catch (e) {
        all['GET $p'] = {'error': ['$e']};
      }
    }
    for (final e in post.entries) {
      try {
        final res = await LocalRouter.post(e.key, e.value);
        all['POST ${e.key}'] = _shape(res);
      } catch (err) {
        all['POST ${e.key}'] = {'error': ['$err']};
      }
    }
    // ignore: avoid_print
    print('SHAPE_JSON:${jsonEncode(all)}');
  });
}
