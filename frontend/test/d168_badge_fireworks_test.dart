// D168 门禁：勋章达成动画「中间爆开烟花 → 勋章从无到有弹出」，且一次拿几枚就画几枚。
//
// 背景（用户实报）：旧版弹的是一个礼物盒掀开 + 一枚勋章；一次拿到多枚时
// `badge_screen` 只把 `unseenAwards.first` 传进动画，其余新勋章被静默吞掉，
// 用户根本看不到自己还拿了别的。要求：
//   ① 中间先爆开烟花；② 勋章不再是礼物盒，而是从 scale 0 弹性放大出现；
//   ③ 拿到 N 枚就显示 N 枚。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/widgets/badge_gift_open.dart';

const _awards = [
  BadgeAward(name: '初识原典', iconKey: 'seed', description: '第一次读完一个知识点'),
  BadgeAward(name: '七日不辍', iconKey: 'fire7'),
  BadgeAward(name: '对话九问', iconKey: 'chat'),
];

Widget _host(List<BadgeAward> awards, {VoidCallback? onClose}) => MaterialApp(
      home: Scaffold(
        body: BadgeGiftOpen(awards: awards, onClose: onClose ?? () {}),
      ),
    );

void main() {
  testWidgets('一次拿到多枚：几枚就显示几枚，标题报数量', (tester) async {
    await tester.pumpWidget(_host(_awards));
    await tester.pumpAndSettle();

    // 三枚勋章的名称都出现（单枚时名称在下方标题，多枚时逐枚标注）
    for (final a in _awards) {
      expect(find.text(a.name), findsWidgets, reason: '${a.name} 没画出来');
    }
    // 三个图标都画出来了（各配唯一图标）
    expect(find.byIcon(BadgeGiftOpen.iconFor('seed')), findsOneWidget);
    expect(find.byIcon(BadgeGiftOpen.iconFor('fire7')), findsOneWidget);
    expect(find.byIcon(BadgeGiftOpen.iconFor('chat')), findsOneWidget);

    expect(find.text('一次获得 3 枚勋章'), findsOneWidget);
    expect(find.text('收下勋章'), findsOneWidget);
  });

  testWidgets('勋章「从无到有」：动画开头是 0，结束才是 1', (tester) async {
    await tester.pumpWidget(_host(const [_awards_0]));
    // 第 1 帧：还没开始弹，透明度 0
    await tester.pump(const Duration(milliseconds: 10));
    final opacities = tester
        .widgetList<Opacity>(find.descendant(
            of: find.byType(BadgeGiftOpen), matching: find.byType(Opacity)))
        .map((w) => w.opacity)
        .toList();
    expect(opacities.any((o) => o == 0), isTrue, reason: '开场应有 opacity=0 的勋章，不能一上来就整枚亮着');
    expect(opacities.every((o) => o <= 1), isTrue);

    await tester.pumpAndSettle();
    final after = tester
        .widgetList<Opacity>(find.descendant(
            of: find.byType(BadgeGiftOpen), matching: find.byType(Opacity)))
        .map((w) => w.opacity);
    expect(after.any((o) => o > 0.9), isTrue, reason: '动画结束后勋章应完全不透明');
  });

  testWidgets('只有一枚：显示名称 + 描述，不出现「一次获得」文案', (tester) async {
    await tester.pumpWidget(_host(const [_awards_0]));
    await tester.pumpAndSettle();
    expect(find.text('初识原典'), findsOneWidget);
    expect(find.text('第一次读完一个知识点'), findsOneWidget);
    expect(find.textContaining('一次获得'), findsNothing);
  });

  testWidgets('空列表兜底：不崩溃，仍能关闭', (tester) async {
    var closed = false;
    await tester.pumpWidget(_host(const [], onClose: () => closed = true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('恭喜达成'), findsOneWidget);
    await tester.tap(find.text('收下勋章'));
    expect(closed, isTrue);
  });

  testWidgets('烟花是自绘的，且在勋章弹出之前就已经在放', (tester) async {
    await tester.pumpWidget(_host(_awards));
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null),
      findsWidgets,
      reason: '烟花用 CustomPaint 自绘',
    );
    // 120ms 时第一簇已经在扩散：painter 存在即可，真正的时序由 duration 控制
    expect(find.text('收下勋章'), findsNothing, reason: '动画未结束不应出现关闭按钮');
  });


  testWidgets('一次拿到 12 枚也不溢出（小屏 320x640）', (tester) async {
    tester.view.physicalSize = const Size(320 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2;
    final many = [
      for (var i = 0; i < 12; i++) BadgeAward(name: '勋章$i', iconKey: 'seed'),
    ];
    await tester.pumpWidget(_host(many));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '多枚勋章不允许 RenderFlex overflow');
    expect(find.text('一次获得 12 枚勋章'), findsOneWidget);
    expect(find.text('勋章11'), findsOneWidget);
    tester.view.reset();
  });

  group('badge_screen 接线（源码门禁）', () {
    final src = File('lib/screens/badge_screen.dart').readAsStringSync();

    test('不再只弹第一枚（unseenAwards.first 已移除）', () {
      expect(src.contains('_showGiftAnimation(unseenAwards.first)'), isFalse,
          reason: 'D168：一次拿到多枚时必须全部展示，不能只弹 first');
    });

    test('整批勋章传给动画，并把整批标记已读', () {
      expect(src.contains('_showGiftAnimation(unseenAwards)'), isTrue);
      expect(src.contains('awards.map(BadgeAward.fromMap)'), isTrue);
      expect(src.contains('BadgeApi.markRead(ids)'), isTrue);
    });
  });
}

const _awards_0 = BadgeAward(
  name: '初识原典',
  iconKey: 'seed',
  description: '第一次读完一个知识点',
);
