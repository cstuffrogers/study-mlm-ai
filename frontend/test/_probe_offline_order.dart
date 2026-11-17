// D136 探针（单机侧）：**列表顺序 / 排序稳定性 / 并列打破**。
//
// 与 `.local/p192_offline_order.py` 同一套用例、同一套提取规则（每个列表 → 有序 id 序列），
// 输出 `ORDER_JSON:` 供逐路径比对。只比顺序，不比数值。
//
// 坑（D135 教训沿用）：`LocalRouter.get(path, query)` **只认第二参** —— path 里带的
// `?n=5` 会被 `Uri.parse(path).pathSegments` 丢掉，参数必须放进 map。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_router.dart';

// 与 `.local/p192_offline_order.py` 的 ID_KEYS 必须逐字同序（见那里的注释）。
const _idKeys = [
  'chunk_id', 'quiz_id', 'node_id', 'section_id', 'attempt_id', 'test_id',
  'id', 'dim', 'label', 'target_node_id',
];

Map<String, List<String>> _seq(Object? v, [String prefix = '', Map<String, List<String>>? out]) {
  final res = out ?? <String, List<String>>{};
  if (v is Map) {
    v.forEach((k, v2) => _seq(v2, prefix.isEmpty ? '$k' : '$prefix.$k', res));
  } else if (v is List) {
    final items = <String>[];
    for (final e in v) {
      if (e is Map) {
        String? hit;
        for (final k in _idKeys) {
          if (e.containsKey(k)) {
            hit = '$k=${e[k]}';
            break;
          }
        }
        items.add(hit ?? 'dict');
      } else {
        items.add(jsonEncode(e));
      }
    }
    res[prefix] = items;
  }
  return res;
}

class _Case {
  const _Case(this.name, this.path, [this.query = const {}]);
  final String name;
  final String path;
  final Map<String, String> query;
}

const _cases = <_Case>[
  _Case('profile', '/api/mastery/profile'),
  _Case('weak5', '/api/recommendation/weak-top', {'n': '5'}),
  _Case('weak50', '/api/recommendation/weak-top', {'n': '50'}),
  _Case('due', '/api/review/due', {'n': '50'}),
  _Case('interleaved', '/api/review/interleaved', {'n': '8'}),
  _Case('status', '/api/review/status'),
  _Case('sections', '/api/routes/route_A/sections'),
  _Case('gating', '/api/routes/route_A/sections/sec_A_00/gating'),
  _Case('guide', '/api/routes/route_A/sections/sec_A_00/guide'),
  _Case('node', '/api/mastery/node/kn_a00_basic'),
  _Case('works', '/api/chunks/works'),
  _Case('bywork', '/api/chunks/by_work/all'),
  _Case('analytics', '/api/analytics/overview'),
  _Case('calibration', '/api/analytics/calibration'),
  _Case('motivation', '/api/motivation/state'),
];

const _seedSections = ['sec_A_00', 'sec_A_01', 'sec_A_02'];

Future<Map<String, List<String>>> _one(_Case c) async {
  final r = await LocalRouter.get(c.path, {
    'user_id': 'demo_user',
    'route_id': 'route_A',
    ...c.query,
  });
  return _seq(r);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('order probe', () async {
    final out = <String, Map<String, List<String>>>{};
    for (final c in _cases) {
      out[c.name] = await _one(c);
    }
    for (final sid in _seedSections) {
      final started = await LocalRouter.post('/api/quiz/section/$sid/start',
          const {'user_id': 'demo_user', 'route_id': 'route_A'});
      await LocalRouter.post('/api/quiz/${started['test_id']}/submit',
          const {'user_id': 'demo_user', 'answers': <dynamic>[]});
      // 与后端探针同步：三章之间隔 1.05s，让「按时间倒序」有区分度。
      await Future<void>.delayed(const Duration(milliseconds: 1050));
    }
    for (final c in _cases) {
      if (const ['works', 'bywork', 'sections', 'guide', 'node'].contains(c.name)) continue;
      out['${c.name}_seed'] = await _one(c);
    }
    final hist = await LocalRouter.get('/api/quiz/history', {
      'user_id': 'demo_user',
      'route_id': 'route_A',
      'limit': '10',
    });
    out['history_seed'] = _seq(hist);
    // ignore: avoid_print — 探针的产出就是这一行 JSON
    print('ORDER_JSON:${jsonEncode(out)}');
  });
}
