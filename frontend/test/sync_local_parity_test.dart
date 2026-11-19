// D133 门禁：单机版 `/api/sync/push` 必须与后端 `sync_service.push()` 同口径。
//
// 原状（单机版三缺一，联网版全对）：
//  · 只处理 `progress`：`section_complete` 不写 completed、`quiz_attempt` /
//    `struggle_signal` 静默丢弃；
//  · 返回 `{accepted, snapshot}`，而 `SyncController.flush()` 读
//    `applied/skipped/details` → 单机模式文案永远「已合并 0 条离线进度」。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_mastery.dart';
import 'package:marxism_reader/offline/local_router.dart';

import 'helpers/offline_assets_guard.dart';

Future<Map<String, dynamic>> _push(List<Map<String, dynamic>> events,
        {String routeId = 'route_A'}) =>
    LocalRouter.post('/api/sync/push', {'events': events, 'route_id': routeId});

Map<String, dynamic>? _progressOf(String routeId, String sectionId) {
  final snap = LocalMastery.pullSnapshot(routeId);
  for (final row in (snap['progress'] as List).whereType<Map>()) {
    if ('${row['section_id']}' == sectionId) return row.cast<String, dynamic>();
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (skipWithoutOfflineAssets()) return;

  setUp(() async {
    await LocalDb.ensure();
    await LocalDb.resetAll();
  });

  test('返回体与后端同键：applied / skipped / details', () async {
    final res = await _push([
      {'type': 'progress', 'section_id': 'sec_A_02', 'last_position': 4},
      {'type': 'bogus_type'},
    ]);
    expect(res['applied'], 1);
    expect(res['skipped'], 1);
    expect((res['details'] as List).single['reason'], 'unknown_type');
    // 兼容旧读法仍保留
    expect(res['accepted'], 2);
  });

  test('section_complete 落成 completed，不再假成功', () async {
    final res = await _push([
      {'type': 'section_complete', 'section_id': 'sec_A_03', 'last_position': 9},
    ]);
    expect(res['applied'], 1);
    final p = _progressOf('route_A', 'sec_A_03');
    expect(p, isNotNull);
    expect(p!['status'], 'completed');
    expect(p['last_position'], 9);
  });

  test('quiz_attempt / struggle_signal 不再静默丢弃', () async {
    final attemptsBefore = LocalDb.attempts.length;
    final signalsBefore = LocalDb.signals.length;
    final res = await _push([
      {
        'type': 'quiz_attempt',
        'quiz_id': 'q_a02_1',
        'test_id': 't_offline_1',
        'is_correct': true,
        'score': 1.0,
      },
      {
        'type': 'struggle_signal',
        'node_id': 'kn_practice',
        'signal_type': 'offline',
        'intensity': 0.4,
      },
    ]);
    expect(res['applied'], 2);
    expect(LocalDb.attempts.length, attemptsBefore + 1);
    expect(LocalDb.signals.length, signalsBefore + 1);
    final attempt = LocalDb.attempts.whereType<Map>().last;
    expect('${attempt['quiz_id']}', 'q_a02_1',
        reason: '作答落库键为 quiz_id（与 LocalQuiz.submit 同键，弃用旧 item_id）');
    expect(attempt['is_correct'], true);
    final signal = LocalDb.signals.whereType<Map>().last;
    expect('${signal['node_id']}', 'kn_practice');
    expect('${signal['source']}', 'offline');
  });

  test('事件自带的 route_id 优先，不整批落到请求的路线', () async {
    await _push([
      {'type': 'progress', 'section_id': 'sec_A_02', 'last_position': 1},
      {
        'type': 'progress',
        'section_id': 'sec_B_01',
        'last_position': 7,
        'route_id': 'route_B',
      },
    ], routeId: 'route_A');
    expect(_progressOf('route_A', 'sec_A_02'), isNotNull);
    expect(_progressOf('route_A', 'sec_B_01'), isNull);
    final b = _progressOf('route_B', 'sec_B_01');
    expect(b, isNotNull);
    expect(b!['last_position'], 7);
  });
}
