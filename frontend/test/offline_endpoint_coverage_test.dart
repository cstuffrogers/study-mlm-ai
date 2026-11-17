// D131 门禁：前端用到的每个接口，离线路由器都要有对应实现。
//
// 单机版（APK）没有后端，所有请求走 `LocalRouter`；少实现一个分支，
// 用户点下去就是「未知接口 404」——而这种漏要在真机上才暴露。
// 这里按 `frontend/lib` 里实际出现过的接口逐个打一遍。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_router.dart';

import 'helpers/offline_assets_guard.dart';

const _get = <String>[
  '/api/routes',
  '/api/routes/route_A/sections',
  '/api/routes/route_A/sections/sec_A_00/guide',
  '/api/routes/route_A/sections/sec_A_00/gating',
  '/api/chunks/works',
  '/api/chunks/by_work/实践论',
  '/api/chunks/$_sampleChunkId',
  '/api/quiz/history',
  '/api/mastery/profile',
  '/api/mastery/summary',
  '/api/mastery/node/kn_practice',
  '/api/recommendation/today',
  '/api/recommendation/next',
  '/api/recommendation/weak-top',
  '/api/review/due',
  '/api/review/interleaved',
  '/api/motivation/state',
  '/api/analytics/overview',
  '/api/analytics/calibration',
  '/api/dialogue/list/demo_user',
  '/api/sync/progress',
  '/api/profile',
];

// 分片 id 由 assets 决定；取《提纲》第一条（全库一定有的锚点）
const _sampleChunkId = 'CH-MLTH-001';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (skipWithoutOfflineAssets()) return;

  test('离线路由器覆盖前端全部 GET 接口', () async {
    final missing = <String>[];
    for (final p in _get) {
      try {
        await LocalRouter.get(p, const {});
      } catch (e) {
        final msg = e.toString();
        // 「未知 xxx 接口」= 分支没实现（原文案不一定带 404 字样）；
        // 其它异常说明分支进去过，只是数据/参数不对，不算缺实现。
        if (msg.contains('未知')) missing.add('$p → $msg');
      }
    }
    expect(missing, isEmpty, reason: '离线模式缺这些接口：${missing.join('\n')}');
  });

  test('离线路由器覆盖前端全部 POST 接口', () async {
    final cases = <String, Map<String, dynamic>>{
      '/api/routes/route_A/select': const {},
      '/api/routes/route_A/diagnostic': const {},
      '/api/quiz/section/sec_A_00/start': const {},
      '/api/review/submit': const {'item_id': 'x', 'quality': 3},
      '/api/sync/push': const {'progress': <String, dynamic>{}},
      '/api/sync/pull': const {},
      '/api/quiz/t_local_1/submit': const {'answers': <String, dynamic>{}},
      '/api/quiz/appeal': const {'test_id': 't_local_1', 'reason': 'x'},
      '/api/dialogue/d_local_1/messages': const {},
      '/api/llm-config': const {},
      '/api/auth/register': const {'username': 'u', 'password': 'p'},
      '/api/auth/login': const {'username': 'u', 'password': 'p'},
    };
    final missing = <String>[];
    for (final e in cases.entries) {
      try {
        await LocalRouter.post(e.key, e.value);
      } catch (err) {
        final msg = err.toString();
        if (msg.contains('未知')) missing.add('${e.key} → $msg');
      }
    }
    expect(missing, isEmpty, reason: '离线模式缺这些接口：${missing.join('\n')}');
  });
}
