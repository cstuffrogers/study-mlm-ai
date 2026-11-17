// D133 门禁：离线同步队列的合并口径（前端侧）。
//
// 原状两处真缺陷：
//  1. `flush()` 调 `_api.push(q)` **不带 routeId**（默认 route_A），而队列里可能
//     混着用户在 route_B 离线学完的事件 → 进度被写到错的路线；
//  2. `flush()` 成功后 `_saveQueue([])` 整队清空，连服务端明确拒绝的事件一起丢掉。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_store_keys.dart';
import 'package:marxism_reader/services/sync_controller.dart';
import 'package:marxism_reader/services/sync_service_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记录每次上报的 routeId 与事件，并按预设回 applied/skipped。
class _FakeSyncApi implements SyncApi {
  final List<({String routeId, List<Map<String, dynamic>> events})> calls = [];
  final Set<String> rejectSectionIds;

  _FakeSyncApi({this.rejectSectionIds = const {}});

  @override
  Future<Map<String, dynamic>> push(List<Map<String, dynamic>> events,
      {String routeId = 'route_A', String userId = 'demo_user'}) async {
    calls.add((routeId: routeId, events: events));
    final rejected = events
        .where((e) => rejectSectionIds.contains('${e['section_id']}'))
        .toList();
    return {
      'applied': events.length - rejected.length,
      'skipped': rejected.length,
      'details': [
        for (final e in rejected) {'event': e, 'reason': 'section_missing'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> pull(
          {String routeId = 'route_A', String userId = 'demo_user'}) async =>
      {'route_id': routeId, 'progress': const [], 'mastery': const {}};

  @override
  Future<Map<String, dynamic>> saveProgress(String sectionId, int lastPosition,
          {String routeId = 'route_A',
          String status = 'in_progress',
          String userId = 'demo_user'}) async =>
      {'section_id': sectionId};
}

Future<List<Map<String, dynamic>>> _queued() async {
  final sp = await SharedPreferences.getInstance();
  final raw = sp.getString(LocalStoreKeys.syncQueue);
  if (raw == null || raw.isEmpty) return const [];
  return (jsonDecode(raw) as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}

Future<void> _seed(List<Map<String, dynamic>> events) async {
  final sp = await SharedPreferences.getInstance();
  await sp.setString(LocalStoreKeys.syncQueue, jsonEncode(events));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('按事件 route_id 分组上报，不再整批按 route_A', () async {
    SharedPreferences.setMockInitialValues({});
    await _seed([
      {'type': 'progress', 'section_id': 'sec_A_02', 'route_id': 'route_A'},
      {'type': 'progress', 'section_id': 'sec_B_01', 'route_id': 'route_B'},
      {'type': 'progress', 'section_id': 'sec_B_02', 'route_id': 'route_B'},
    ]);
    final api = _FakeSyncApi();
    final c = SyncController(api: api);
    await c.flush();

    final byRoute = {for (final call in api.calls) call.routeId: call.events};
    expect(api.calls.map((e) => e.routeId).toSet(), {'route_A', 'route_B'});
    expect(byRoute['route_A']!.map((e) => e['section_id']), ['sec_A_02']);
    expect(byRoute['route_B']!.map((e) => e['section_id']),
        ['sec_B_01', 'sec_B_02']);
    expect(await _queued(), isEmpty);
    expect(c.message, contains('已合并 3 条'));
  });

  test('被服务端拒绝的事件留在队列重试，满三次才丢弃', () async {
    SharedPreferences.setMockInitialValues({});
    final bad = {
      'type': 'progress',
      'section_id': 'sec_ZZZ',
      'route_id': 'route_A',
    };
    await _seed([bad]);
    final api = _FakeSyncApi(rejectSectionIds: {'sec_ZZZ'});

    var c = SyncController(api: api);
    await c.flush();
    var q = await _queued();
    expect(q.length, 1, reason: '第一次被拒应保留');
    expect(q.first['tries'], 1);
    expect(c.message, contains('被服务端拒绝'));

    c = SyncController(api: api);
    await c.flush();
    q = await _queued();
    expect(q.length, 1);
    expect(q.first['tries'], 2);

    c = SyncController(api: api);
    await c.flush();
    q = await _queued();
    expect(q, isEmpty, reason: '重试 3 次仍失败则丢弃，不能无限重试');
    expect(c.message, contains('已丢弃'));
  });

  test('reportProgress 的事件带着 route_id 入队（离线分支）', () async {
    SharedPreferences.setMockInitialValues({});
    final c = SyncController(api: _FakeSyncApi());
    await c.reportProgress('sec_C_01', 3, routeId: 'route_C');
    // 假 API 永远成功，因此这里不进队列；改用离线替身确认事件字段
    final failing = _FailPushApi();
    final c2 = SyncController(api: failing);
    await c2.reportProgress('sec_C_01', 3, routeId: 'route_C');
    final q = await _queued();
    expect(q, hasLength(1));
    expect(q.first['route_id'], 'route_C');
    expect(q.first['section_id'], 'sec_C_01');
  });

  test('在线路径被服务端拒收时也入队，不谎报「已同步」', () async {
    SharedPreferences.setMockInitialValues({});
    final api = _FakeSyncApi(rejectSectionIds: {'sec_A_09'});
    final c = SyncController(api: api);
    await c.reportProgress('sec_A_09', 1, routeId: 'route_A');
    final q = await _queued();
    expect(q, hasLength(1));
    expect(q.first['section_id'], 'sec_A_09');
    expect(c.message, isNot(contains('已同步')));
    expect(c.pending, 1);
  });

  test('离线队列有上限，超了丢最旧的（保留最近进度）', () async {
    SharedPreferences.setMockInitialValues({});
    final c = SyncController(api: _FailPushApi());
    final old = <Map<String, dynamic>>[
      for (var i = 0; i < SyncController.maxQueuedEvents; i++)
        {'type': 'progress', 'section_id': 'sec_A_00', 'idx': i},
    ];
    await _seed(old);
    await c.reportProgress('sec_A_02', 5, routeId: 'route_A');
    final q = await _queued();
    expect(q, hasLength(SyncController.maxQueuedEvents));
    expect(q.last['section_id'], 'sec_A_02', reason: '最新一条必须保留');
    expect(q.first['idx'], 1, reason: '最旧的一条被丢掉');
  });
}

class _FailPushApi extends _FakeSyncApi {
  @override
  Future<Map<String, dynamic>> push(List<Map<String, dynamic>> events,
          {String routeId = 'route_A', String userId = 'demo_user'}) async {
    throw Exception('offline');
  }
}
