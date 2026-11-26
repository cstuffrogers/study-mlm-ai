// D170 门禁：收下勋章后首页红点必须立刻消失、不能点开又弹一次。
//
// 用户实报：「首页勋章，已经点击获得勋章了，还是说有显示数字，点击又弹出获得页面。
// 有 2 到 3 次数字才消失。」
//
// 根因（两条叠在一起）：
//   ① `ApiClient.post('/api/badges/read')` 没有失效 `/api/badges/*` 的 GET 短缓存
//      → 收下勋章后的 30s 内，`GET /api/badges/unseen` 仍回旧结果（count>0、
//      动画再弹一次）；TTL 到期（约 30s，正好是点 2~3 次）才突然正常。
//   ② 首页入口在**进入**勋章页之前刷新红点数量，返回后不刷新 → 数字一直挂着。
//   ③ 勋章页把 `mine` 与 `unseen` 并发读：`mine` 内部懒评估可能刚授予新勋章，
//      先返回的 `unseen` 漏掉它，要等下次进页面才弹。
//
// 本测试锁死：已读后 `unseen` 立刻归零（不论有没有绕过缓存）、`mine.read` 同步为
// true、而且这两个页面必须用 `fresh: true` + 顺序（mine 先）读取。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_badge.dart';
import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/services/api_client.dart';
import 'package:marxism_reader/services/badge_service_api.dart';

/// 造一条「已授予但未查看」的记录（badge_id 必须是勋章目录里真实存在的）。
void _seedUnseen(List<String> badgeIds) {
  for (final id in badgeIds) {
    LocalDb.badges[id] = <String, dynamic>{
      'award_id': id,
      'badge_id': id,
      'awarded_at': '2026-11-26T00:00:00.000000Z',
      'source_event': 'auto',
      'read_flag': false,
    };
  }
}

Future<List<String>> _unseenIds({bool fresh = true}) async {
  final r = await BadgeApi.unseen(routeId: 'route_A', fresh: fresh);
  return ((r['awards'] as List?) ?? const [])
      .map((e) => '${(e as Map)['award_id']}')
      .toList(growable: false);
}

String _readSource(String path) => File(path).readAsStringSync();

void main() {
  setUp(() async {
    await LocalDb.ensure();
    LocalDb.badges = <String, dynamic>{};
    ApiClient.invalidatePrefix();
  });

  test('收下勋章后 unseen 立刻归零（不需要等 30s 缓存过期）', () async {
    _seedUnseen(['mastery_1', 'mastery_5']);

    final before = await _unseenIds();
    expect(before.length, 2, reason: '两枚未查看勋章应都能读到');

    // 先让「未查看」这份结果进 GET 缓存（模拟首页刚读过）
    await BadgeApi.unseen(routeId: 'route_A');
    final updated = await BadgeApi.markRead(before, routeId: 'route_A');
    expect(updated['updated'], 2, reason: '两枚都应被标记为已读');

    // 关键：不显式 fresh，也必须读到 0（写操作要失效缓存）
    final after = await _unseenIds(fresh: false);
    expect(after, isEmpty, reason: '刚收下勋章，unseen 还回旧缓存 → 红点不消失、动画重复弹');
  });

  test('已读状态落盘：mine 里那两枚 read=true', () async {
    _seedUnseen(['mastery_1']);
    final ids = await _unseenIds();
    await BadgeApi.markRead(ids, routeId: 'route_A');

    final mine = await BadgeApi.mine(routeId: 'route_A', fresh: true);
    final row = (mine['badges'] as List)
        .map((e) => e as Map)
        .firstWhere((b) => '${b['badge_id']}' == 'mastery_1');
    expect(row['earned'], isTrue);
    expect(row['read'], isTrue, reason: '收下后勋章卡应显示为已读');
    expect(LocalDb.badges['mastery_1']['read_flag'], isTrue);
  });

  test('unseen 幂等：连读三次不会凭空多出勋章（避免重复弹窗）', () async {
    _seedUnseen(['mastery_1']);
    final ids = await _unseenIds();
    await BadgeApi.markRead(ids, routeId: 'route_A');
    for (var i = 0; i < 3; i++) {
      expect(await _unseenIds(), isEmpty, reason: '第 ${i + 1} 次读取仍应为空');
    }
  });

  test('已读的勋章不会再被当成未查看（第二次进页面不弹）', () async {
    _seedUnseen(['mastery_5']);
    await BadgeApi.markRead(await _unseenIds(), routeId: 'route_A');
    // 模拟「再进一次勋章页」：mine → unseen 都是 fresh
    await BadgeApi.mine(routeId: 'route_A', fresh: true);
    expect(await _unseenIds(), isEmpty);
  });

  group('源码门禁', () {
    test('ApiClient 写勋章后要失效 /api/badges 缓存', () {
      final src = _readSource('lib/services/api_client.dart');
      expect(src.contains("/api/badges"), isTrue,
          reason: 'post 里必须失效 /api/badges 前缀，否则收下勋章 30s 内仍判未读');
      expect(
          src.contains("invalidatePrefix('/api/badges')"), isTrue,
          reason: '要显式调用 invalidatePrefix(\'/api/badges\')');
    });

    test('首页红点数量在从勋章页返回之后刷新，而不是进入之前', () {
      final src = _readSource('lib/screens/home_screen.dart');
      final idx = src.indexOf('await _push(const BadgeScreen())');
      expect(idx, greaterThan(0), reason: '首页入口应 await 打开勋章页');
      final after = src.substring(idx);
      expect(after.contains('_loadUnseenBadges()'), isTrue,
          reason: '返回后必须重新拉未查看数量，否则红点数字一直挂着');
      expect(src.contains("routeId: 'route_A', fresh: true"), isTrue,
          reason: '拉未查看数量要绕过短缓存');
    });

    test('勋章页先 mine（懒评估落盘）再 unseen，且都绕过缓存', () {
      final src = _readSource('lib/screens/badge_screen.dart');
      final mineIdx = src.indexOf("BadgeApi.mine(routeId: widget.routeId");
      final unseenIdx = src.indexOf("BadgeApi.unseen(routeId: widget.routeId");
      expect(mineIdx, greaterThan(0));
      expect(unseenIdx, greaterThan(mineIdx),
          reason: 'unseen 必须先等 mine 落盘，否则刚授予的勋章要下次进页面才弹');
      expect(src.contains('Future.wait'), isFalse,
          reason: '这两个读不能并发（mine 会懒评估授予新勋章）');
      expect(
          src.contains("BadgeApi.mine(routeId: widget.routeId, fresh: true)"),
          isTrue);
      expect(
          src.contains("BadgeApi.unseen(routeId: widget.routeId, fresh: true)"),
          isTrue);
    });
  });
}
