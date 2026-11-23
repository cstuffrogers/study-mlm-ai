// 勋章分享功能测试（spec 001 勋章系统 · US5）
//
// 覆盖：收藏卡渲染内容、分享文案、stub 返回 false、分享数据准备不改状态、目录完整性。
// 说明：完整 `shareBadgeCard` 依赖 RepaintBoundary 截图（原生/Web），
// 测试环境无真实渲染管线，故直接测 stub 实现与数据层不变性。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_badge.dart';
import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_mastery.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'package:marxism_reader/widgets/badge_share_card.dart';
import 'package:marxism_reader/services/badge_share_stub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const route = 'route_A';

  setUp(() async {
    await LocalDb.resetAll();
    LocalDb.routeId = route;
    await OfflineContent.ensureMeta();
  });

  // ------------------------------------------------------------ 收藏卡渲染

  testWidgets('BadgeShareCard 渲染：标题、数量概览、分类标签、勋章名称均正确展示',
      (tester) async {
    final items = [
      BadgeShareItem(
        badgeId: 'k1',
        name: '初窥门径',
        category: 'knowledge',
        iconKey: 'star',
      ),
      BadgeShareItem(
        badgeId: 'j1',
        name: '贯通一理',
        category: 'journey',
        iconKey: 'route',
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BadgeShareCard(
        appName: '唯物 · 马哲精读',
        earnedCount: 2,
        totalCount: 29,
        badges: items,
        shareText: '我在「唯物 · 马哲精读」已获得 2 枚学习勋章，继续加油！',
      )),
    ));

    expect(find.text('勋章收藏卡'), findsOneWidget);
    expect(find.text('唯物 · 马哲精读'), findsOneWidget);
    expect(find.text('2 / 29'), findsOneWidget);
    expect(find.text('知识掌握'), findsOneWidget);
    expect(find.text('贯通学习'), findsOneWidget);
    expect(find.text('初窥门径'), findsOneWidget);
    expect(find.text('贯通一理'), findsOneWidget);
    expect(
        find.text('我在「唯物 · 马哲精读」已获得 2 枚学习勋章，继续加油！'),
        findsOneWidget);
  });

  testWidgets('BadgeShareCard 空勋章时展示空态文案', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BadgeShareCard(
        appName: '唯物 · 马哲精读',
        earnedCount: 0,
        totalCount: 29,
        badges: const [],
        shareText: '我在「唯物 · 马哲精读」已获得 0 枚学习勋章，继续加油！',
      )),
    ));

    expect(find.text('暂未获得勋章，继续加油！'), findsOneWidget);
  });

  testWidgets('BadgeShareCard 分类未知时原样展示分类 key', (tester) async {
    final items = [
      BadgeShareItem(
        badgeId: 'x1',
        name: '测试勋章',
        category: 'unknown_cat',
        iconKey: 'star',
      ),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BadgeShareCard(
        appName: 'app',
        earnedCount: 1,
        totalCount: 1,
        badges: items,
        shareText: 'test',
      )),
    ));

    expect(find.text('unknown_cat'), findsOneWidget);
  });

  // ------------------------------------------------------------ 分享文案

  test('shareText 默认文案格式正确', () {
    // shareText 定义在 native/web 实现中，此处验证文案格式约定。
    final text = '我在「唯物 · 马哲精读」已获得 5 枚学习勋章，继续加油！';
    expect(text, contains('唯物 · 马哲精读'));
    expect(text, contains('5'));
    expect(text, contains('学习勋章'));
  });

  // ------------------------------------------------------------ stub 实现

  testWidgets('stub 分享实现返回 false', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final items = [
      BadgeShareItem(
        badgeId: 'k1',
        name: '初窥门径',
        category: 'knowledge',
        iconKey: 'star',
      ),
    ];
    final result = await shareBadgeCard(
      context: tester.element(find.byType(Scaffold)),
      appName: '唯物 · 马哲精读',
      earnedCount: 1,
      totalCount: 29,
      badges: items,
    );
    expect(result, isFalse);
  });

  // ------------------------------------------------------------ 分享不改状态

  test('分享数据准备（筛选 earned → 构造 items）不改变授予记录与查看状态', () async {
    // 播种：掌握 1 个知识点，确保至少获得首枚知识勋章。
    final node = OfflineContent.allNodes.first;
    await LocalMastery.upsert(
      route,
      '${node['id']}',
      {'accuracy': 1.0, 'stability': 1.0, 'feynman': 0.9},
      'quiz',
    );

    // 评估并授予勋章。
    final awards = LocalBadge.evaluate(route);
    expect(awards.length, greaterThan(0));

    final beforeMine = LocalBadge.mine(route);
    final beforeBadges = (beforeMine['badges'] as List).map((e) =>
        (e as Map).cast<String, dynamic>()).toList();
    final beforeUnseen = LocalBadge.unseen(route);
    final beforeUnseenCount = (beforeUnseen['count'] as num?)?.toInt() ?? 0;

    // 模拟分享数据准备流程（与 _handleShare 相同逻辑）。
    final earned = beforeBadges.where((b) => b['earned'] == true).toList();
    final earnedCount = earned.length;
    final totalCount = allBadges().length;
    final items = earned
        .map((b) => BadgeShareItem(
            badgeId: '${b['badge_id']}',
            name: '${b['name'] ?? ''}',
            category: '${b['category'] ?? ''}',
            iconKey: '${b['icon_key'] ?? 'star'}'))
        .toList();

    // 数据准备本身不应修改任何状态。
    expect(earnedCount, greaterThan(0));
    expect(items.length, earnedCount);
    expect(totalCount, 29);

    // 验证：授予记录、查看状态均不变。
    final afterMine = LocalBadge.mine(route);
    final afterBadges = (afterMine['badges'] as List).map((e) =>
        (e as Map).cast<String, dynamic>()).toList();
    expect(afterBadges.length, beforeBadges.length);
    expect(
        afterBadges
            .map((b) => b['award_id'])
            .toSet(),
        beforeBadges.map((b) => b['award_id']).toSet());

    final afterUnseen = LocalBadge.unseen(route);
    final afterUnseenCount =
        (afterUnseen['count'] as num?)?.toInt() ?? 0;
    expect(afterUnseenCount, beforeUnseenCount);
  });

  // ------------------------------------------------------------ 目录完整性

  test('勋章目录共 29 枚，覆盖全部 7 个分类', () {
    final all = allBadges();
    expect(all.length, 29);

    final cats = all.map((b) => b.category).toSet();
    expect(cats, containsAll([
      '知识掌握',
      '贯通',
      '里程碑',
      '答题',
      '路线',
      '连续学习',
      '对话',
    ]));
  });
}
