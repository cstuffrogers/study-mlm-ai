// D143 门禁（第二批）：首页品牌标题 + 功能中心删「学习路线」。
//
// 锁三件事：
//  ① 首页标题是两行「唯物」/「马哲精读」，不再有「马列毛思想AI伴读」那串；
//  ② 两行都是**金色毛笔字**（AppColors.gold + 多层描边阴影模拟粗厚笔画），
//     配金色下划线/小方章，强有力、豪迈；
//  ③ 功能中心不再有「学习路线」入口，但其余入口都在（别顺手删多了）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/screens/home_screen.dart';
import 'package:marxism_reader/screens/tools_screen.dart';
import 'package:marxism_reader/services/sync_controller.dart';
import 'package:marxism_reader/theme/app_theme.dart';
import 'package:marxism_reader/widgets/brand_title.dart';
import 'package:provider/provider.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BrandTitle 品牌标题', () {
    test('文案就是「唯物」+「马哲精读」，旧标题已不在首页源码里', () {
      final src = _read('lib/screens/home_screen.dart');
      expect(src, contains('BrandTitle()'));
      expect(src, isNot(contains('马列毛思想AI伴读')),
          reason: '旧标题必须彻底消失，否则两套文案会同时存在');
      final title = _read('lib/widgets/brand_title.dart');
      expect(title, contains("'唯物'"));
      expect(title, contains("'马哲精读'"));
    });

    test('两行都是金色毛笔字，配描边阴影与金色下划线/方章', () {
      final src = _read('lib/widgets/brand_title.dart');
      // 两处 Text 都用 AppColors.gold（金色毛笔字）；
      // 用多层 shadows 做深色描边，模拟毛笔粗厚笔画的力道
      expect(src, contains('color: AppColors.gold'));
      final goldCount = src.split('AppColors.gold').length - 1;
      expect(goldCount, greaterThanOrEqualTo(2),
          reason: '金色应出现在两处文字及装饰中');
      expect(src, contains('shadows: _brushStroke'),
          reason: '金色字必须带描边阴影，模拟毛笔笔画');
      expect(src, contains('_brushStroke'),
          reason: '描边阴影列表应被引用');
      // 不再是白字
      expect(src, isNot(contains('color: Colors.white,')),
          reason: '已改为金色毛笔字，不应再是白字');
      // 保留金色下划线与小方章
      expect(src, contains('AppColors.gold.withValues'));
    });

    testWidgets('两行文字真实渲染出来，且上下排列（不是一行）', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: BrandTitle())),
      ));
      final top = t.getRect(find.text('唯物'));
      final bottom = t.getRect(find.text('马哲精读'));
      expect(bottom.top, greaterThan(top.top + top.height - 1),
          reason: '「马哲精读」必须另起一行，不能和「唯物」并排');
      expect(t.takeException(), isNull);
    });

    testWidgets('窄屏 + 大字号下不溢出（头部按 titleHeight 预留）', (t) async {
      t.view.physicalSize = const Size(360 * 3, 720 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.build(),
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(body: Center(child: BrandTitle())),
        ),
      ));
      expect(t.takeException(), isNull, reason: '大字号下标题不得溢出');
    });

    testWidgets('首页头部用的就是 BrandTitle（wiring，不是只有组件没人用）', (t) async {
      t.view.physicalSize = const Size(390 * 3, 844 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(ChangeNotifierProvider(
        create: (_) => SyncController(),
        child: const MaterialApp(home: HomeScreen()),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byType(BrandTitle), findsOneWidget);
      expect(find.text('唯物'), findsOneWidget);
      expect(find.text('马哲精读'), findsOneWidget);
      expect(find.text('马列毛思想AI伴读'), findsNothing);
    });
  });

  group('功能中心入口', () {
    testWidgets('不再有「学习路线」，其余入口保留', (t) async {
      t.view.physicalSize = const Size(400 * 2, 1600 * 2);
      t.view.devicePixelRatio = 2.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);

      await t.pumpWidget(MaterialApp(
        theme: AppTheme.build(),
        home: const ToolsScreen(),
      ));
      await t.pump(const Duration(milliseconds: 300));

      expect(find.text('学习路线'), findsNothing,
          reason: '首页本身就是选路线页，功能中心再放一份是重复入口');
      for (final keep in [
        '学习分析',
        '原著浏览',
        '对话历史',
        '错题本',
        'LLM 大模型 API 配置',
        '语音包设置',
        '本机数据',
        '关于',
        '法律与隐私',
      ]) {
        expect(find.text(keep), findsOneWidget, reason: '误删了入口：$keep');
      }
    });

    test('功能中心源码里不再 import / 构造 RoutePickerScreen', () {
      final src = _read('lib/screens/tools_screen.dart');
      expect(src, isNot(contains("import 'route_picker.dart';")));
      expect(src, isNot(contains('RoutePickerScreen(')));
    });
  });
}
