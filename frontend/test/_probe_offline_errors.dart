// D135 探针（临时）：异常输入 / 边界值的错误语义 —— 单机侧。
//
// 与 `.local/p190_offline_errors.py`（后端侧）跑**同一套矩阵**，打印一行
// `ERR_JSON:` 供比对：每个用例记 {status, keys, detail}。
//
// 单机侧的错误是 `LocalApiException(status, detail)`；正常返回的 Map 记 status=200。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_router.dart';

import 'helpers/offline_assets_guard.dart';

// 注意：`LocalRouter.get(path, query)` 只认第二参的 query map，
// **path 里带的 `?n=0` 会被 `Uri.parse(path).pathSegments` 丢掉**（探针第一版就
// 栽在这上面：n/limit 用例两边都走了默认值，差异被掩盖）。
const _cases = <List<dynamic>>[
  ['node-unknown', 'GET', '/api/mastery/node/kn_not_exist', <String, String>{}],
  ['guide-unknown', 'GET', '/api/routes/route_A/sections/sec_Z_99/guide', <String, String>{}],
  ['gating-unknown', 'GET', '/api/routes/route_A/sections/sec_Z_99/gating', <String, String>{}],
  ['guide-flat-unknown', 'GET', '/api/guide/sec_Z_99', <String, String>{}],
  ['routes-unknown', 'GET', '/api/routes/route_Z/sections', <String, String>{}],
  ['quiz-get-unknown', 'GET', '/api/quiz/nope', <String, String>{}],
  ['chunk-unknown', 'GET', '/api/chunks/nope', <String, String>{}],
  ['chunks-bywork-unknown', 'GET', '/api/chunks/by_work/不存在的书', <String, String>{}],
  ['review-due-n0', 'GET', '/api/review/due', <String, String>{'n': '0'}],
  ['review-interleaved-n0', 'GET', '/api/review/interleaved', <String, String>{'n': '0'}],
  ['review-interleaved-nneg', 'GET', '/api/review/interleaved', <String, String>{'n': '-3'}],
  ['weak-top-n0', 'GET', '/api/recommendation/weak-top', <String, String>{'n': '0'}],
  ['weak-top-nneg', 'GET', '/api/recommendation/weak-top', <String, String>{'n': '-1'}],
  ['history-limit-neg', 'GET', '/api/quiz/history', <String, String>{'limit': '-1'}],
  ['history-limit-zero', 'GET', '/api/quiz/history', <String, String>{'limit': '0'}],
];

const _postCases = <String, Map<String, dynamic>>{
  '/api/quiz/section/sec_Z_99/start': {'user_id': 'demo_user', 'route_id': 'route_A'},
  '/api/quiz/nope/submit': {'user_id': 'demo_user', 'answers': <dynamic>[]},
  '/api/recommendation/next': {'user_id': 'demo_user', 'current_section_id': 'sec_Z_99'},
  '/api/review/submit': {'user_id': 'demo_user', 'node_id': 'kn_not_exist'},
  '/api/mastery/summary': {'user_id': 'demo_user', 'period': 'bogus'},
  '/api/sync/progress': {'user_id': 'demo_user', 'section_id': ''},
  '/api/sync/push': {
    'user_id': 'demo_user',
    'events': [
      {'type': 'bogus'}
    ]
  },
};

Map<String, dynamic> _vals(Map m) {
  int len(Object? v) => v is List ? v.length : (v is Map ? v.length : 0);
  return {
    'sections': len(m['sections']),
    'due': len(m['due']),
    'items': len(m['items']),
    'rows': len(m['rows']),
    'weak_points': len(m['weak_points']),
    'applied': m['applied'],
    'skipped': m['skipped'],
    'target': m['target_section_id'],
    'period': m['period'],
    'reply_len': '${m['reply'] ?? m['summary'] ?? ''}'.length,
  };
}

Map<String, dynamic> _res(Object? r) => {
      'status': r is Map ? 200 : 0,
      'keys': r is Map ? (r.keys.map((e) => '$e').toList()..sort()) : <String>[],
      'detail': '',
      'vals': r is Map ? _vals(r) : null,
    };

Future<Map<String, dynamic>> _run(String method, String path,
    [Map<String, dynamic>? body, Map<String, String> extra = const {}]) async {
  final q = <String, String>{
    'user_id': 'demo_user',
    'route_id': 'route_A',
    ...extra,
  };
  try {
    final r = method == 'GET'
        ? await LocalRouter.get(path, q)
        : await LocalRouter.post(path, body ?? const {});
    return _res(r);
  } on LocalApiException catch (e) {
    return {'status': e.status, 'keys': <String>[], 'detail': e.detail};
  } catch (e) {
    return {'status': 'EXC', 'keys': <String>[], 'detail': '$e'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (skipWithoutOfflineAssets()) return;

  test('dump offline error matrix', () async {
    final out = <String, dynamic>{};
    // 先造一条作答记录，否则 history 用例两边「都空」，limit 钳制的差异被掩盖
    // （后端探针同样先 seed 一份）。
    final seed = await LocalRouter.post(
        '/api/quiz/section/sec_A_00/start', const {'user_id': 'demo_user'});
    await LocalRouter.post('/api/quiz/${seed['test_id']}/submit',
        const {'user_id': 'demo_user', 'answers': <dynamic>[]});
    for (final c in _cases) {
      out[c[0]] = await _run(c[1], c[2], null, c[3] as Map<String, String>);
    }
    for (final e in _postCases.entries) {
      final name = e.key
          .replaceAll('/api/', '')
          .replaceAll('/', '-')
          .replaceAll('_', '-');
      out['POST $name'] = await _run('POST', e.key, e.value);
    }
    // 变体：空 node_id / ratio 2 / 空事件
    out['review-submit-empty-node'] =
        await _run('POST', '/api/review/submit', {'user_id': 'demo_user', 'node_id': ''});
    out['review-submit-ratio-2'] = await _run('POST', '/api/review/submit',
        {'user_id': 'demo_user', 'node_id': 'kn_a00_basic', 'correct_ratio': 2.0});
    out['next-empty-section'] = await _run(
        'POST', '/api/recommendation/next', {'user_id': 'demo_user', 'current_section_id': ''});
    out['sync-push-empty-events'] =
        await _run('POST', '/api/sync/push', {'user_id': 'demo_user', 'events': <dynamic>[]});
    // 重复提交
    final started = await LocalRouter.post(
        '/api/quiz/section/sec_A_02/start', const {'user_id': 'demo_user'});
    final tid = '${started['test_id']}';
    await LocalRouter.post('/api/quiz/$tid/submit', const {'user_id': 'demo_user'});
    out['quiz-submit-twice'] = await _run('POST', '/api/quiz/$tid/submit', {'user_id': 'demo_user'});
    // ignore: avoid_print — 探针的产出就是这一行 JSON，供 p190 比对
    print('ERR_JSON:${jsonEncode(out)}');
  });
}
