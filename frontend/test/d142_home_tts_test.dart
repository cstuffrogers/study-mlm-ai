// D142 门禁：首页 = 选学习路线 + 朗读自动停止 + 大模型配置页去掉「本机数据」卡片。
//
// 锁三件事：
//   1. 首页就是「选学习路线」屏：三条路线卡片直达章节地图，旧首页的「② 选择起始章节」
//      与底部「深入学习」不再出现；头部只留 功能中心 / LLM 大模型 API 配置 / 学习分析 / 引导，
//      **不再有「学习路线」按钮**（首页自身即选路线页，留着是自指跳转）。
//   2. 朗读自动停止：路由 push/pop 停；弹窗（PopupRoute）不停；APP 退到后台（hidden/paused）停，
//      只是失去焦点（inactive，如拉通知栏）不停。
//   3. 「AI 对话引擎」页不再有「本机数据」卡片（数据规模另有「功能中心 → 本机数据」页）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'package:marxism_reader/screens/home_screen.dart';
import 'package:marxism_reader/screens/llm_config_screen.dart';
import 'package:marxism_reader/screens/route_map.dart';
import 'package:marxism_reader/services/chat_service.dart';
import 'package:marxism_reader/services/sync_controller.dart';
import 'package:marxism_reader/services/tts.dart';
import 'package:marxism_reader/services/tts_autostop.dart';
import 'package:marxism_reader/theme/app_theme.dart';
import 'package:marxism_reader/widgets/anim.dart';
import 'helpers/offline_assets_guard.dart';

Widget _home() => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatService()),
        ChangeNotifierProvider(create: (_) => SyncController()),
      ],
      child: MaterialApp(theme: AppTheme.build(), home: const HomeScreen()),
    );

Future<void> _pump(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(w);
  await tester.pumpAndSettle();
}

/// 弹窗类路由（不该打断朗读）。
class _FakePopupRoute<T> extends PopupRoute<T> {
  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => null;
  @override
  Duration get transitionDuration => Duration.zero;
  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      const SizedBox.shrink();
}

/// 普通页面路由（该打断朗读）。
class _FakePageRoute<T> extends PageRoute<T> {
  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;
  @override
  bool get maintainState => true;
  @override
  Duration get transitionDuration => Duration.zero;
  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      const SizedBox.shrink();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('朗读自动停止（纯逻辑）', () {
    final observer = TtsStopOnRouteChange();

    setUp(() => ttsCurrent.value = null);

    test('普通路由 push / pop / replace / remove 都停', () {
      for (final fire in [
        () => observer.didPush(_FakePageRoute<void>(), null),
        () => observer.didPop(_FakePageRoute<void>(), null),
        () => observer.didReplace(newRoute: _FakePageRoute<void>()),
        () => observer.didRemove(_FakePageRoute<void>(), null),
      ]) {
        ttsCurrent.value = 'chunk-1';
        fire();
        expect(ttsCurrent.value, isNull, reason: '路由变化后必须停止朗读');
      }
    });

    test('弹窗（PopupRoute）不算页面切换，不打断朗读', () {
      ttsCurrent.value = 'chunk-1';
      observer.didPush(_FakePopupRoute<void>(), null);
      observer.didPop(_FakePopupRoute<void>(), null);
      expect(ttsCurrent.value, 'chunk-1');
    });

    testWidgets('真导航：push 新页面即停，关掉弹窗不停', (tester) async {
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [TtsStopOnRouteChange()],
        home: const Scaffold(body: Text('首页')),
      ));
      final nav = tester.state<NavigatorState>(find.byType(Navigator));

      // 弹窗（对话框）不打断
      ttsCurrent.value = 'chunk-dlg';
      final dialogClosed = showDialog<void>(
          context: tester.element(find.text('首页')),
          builder: (_) => const AlertDialog(title: Text('对话框')));
      await tester.pumpAndSettle();
      expect(ttsCurrent.value, 'chunk-dlg');
      nav.pop();
      await tester.pumpAndSettle();
      await dialogClosed;

      // 真页面切换则停
      ttsCurrent.value = 'chunk-page';
      nav.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('第二页'))));
      await tester.pumpAndSettle();
      expect(ttsCurrent.value, isNull);
      expect(find.text('第二页'), findsOneWidget);
    });
  });

  test('main.dart 真的挂上了自动停止钩子', () {
    final src = File('lib/main.dart').readAsStringSync();
    // D145：观察者从 1 个变 2 个 —— 换页面停（TtsStopOnRouteChange）
    // + 弹层关闭停（TtsStopOnSheetClose）。断言改成「都在同一个
    // navigatorObservers 列表里」，而不是钉死整串字面量。
    final i = src.indexOf('navigatorObservers:');
    expect(i, greaterThan(-1), reason: '页面切换停朗读靠 navigatorObservers');
    final list = src.substring(i, src.indexOf(']', i));
    expect(list.contains('TtsStopOnRouteChange()'), isTrue);
    expect(list.contains('TtsStopOnSheetClose()'), isTrue,
        reason: '弹层（相关原文）关闭也要停朗读，见 D145');
    expect(src.contains('TtsAutoStopScope('), isTrue,
        reason: '切后台停朗读靠 MaterialApp.builder 外层包一层');
    expect(src.contains('home: const HomeScreen()'), isTrue);
    expect(src.contains('study_home_screen.dart'), isFalse,
        reason: '旧首页已删除，不应再有引用');
  });

  group('朗读自动停止（生命周期）', () {
    testWidgets('退到后台 hidden / paused 停，inactive 不停', (tester) async {
      await tester.pumpWidget(const TtsAutoStopScope(child: SizedBox.shrink()));

      Future<void> send(String state) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'flutter/lifecycle',
          const StringCodec().encodeMessage(state),
          (_) {},
        );
        await tester.pump();
      }

      ttsCurrent.value = 'chunk-2';
      await send('AppLifecycleState.inactive'); // 拉通知栏 / 来电横幅
      expect(ttsCurrent.value, 'chunk-2', reason: 'inactive 只是失去焦点，不应停');

      await send('AppLifecycleState.hidden');
      expect(ttsCurrent.value, isNull, reason: '切到后台必须停');

      ttsCurrent.value = 'chunk-3';
      await send('AppLifecycleState.paused');
      expect(ttsCurrent.value, isNull, reason: '息屏/切应用必须停');
    });
  });

  group('首页 = 选学习路线', () {
    if (skipWithoutOfflineAssets()) return;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await LocalDb.ensure();
      await OfflineContent.ensureMeta();
      await OfflineContent.ensureChunks();
    });

    testWidgets('首页显示三条路线卡片，点一张进章节地图', (tester) async {
      await _pump(tester, _home());
      expect(tester.takeException(), isNull);

      // 三条路线各一张卡片（GradientCard），每张都有「共享地基」徽标
      expect(find.byType(GradientCard), findsNWidgets(3));
      expect(find.textContaining('共享地基'), findsAtLeastNWidgets(1));
      // D152：干脆写明地基是哪三章（只写「马恩哲学基础」会让《大众哲学》看起来可跳过）
      expect(find.textContaining('三条路线共享公共地基：《大众哲学》两章'), findsOneWidget);
      expect(find.textContaining('《关于费尔巴哈的提纲》'), findsOneWidget);

      // 旧首页的东西不该再出现
      expect(find.text('② 选择起始章节'), findsNothing);
      expect(find.text('深入学习'), findsNothing);
      expect(find.textContaining('① 选择学习路线'), findsNothing);

      // 点第一张卡 → 进路线地图
      await tester.tap(find.byType(GradientCard).first);
      await tester.pumpAndSettle();
      expect(find.byType(RouteMapScreen), findsOneWidget,
          reason: '首页卡片必须直达章节地图');
    });

    testWidgets('头部四个入口，且没有「学习路线」按钮', (tester) async {
      await _pump(tester, _home());
      for (final tip in ['功能中心', 'LLM 大模型 API 配置', '学习分析', '引导']) {
        expect(find.byTooltip(tip), findsOneWidget, reason: '头部应有 $tip');
      }
      expect(find.byTooltip('学习路线'), findsNothing,
          reason: '首页本身就是选路线页，不该再有自指跳转按钮');
      expect(find.byTooltip('软件使用说明'), findsNothing);
      // 引导按钮的 tooltip 是「引导」，弹出的是「软件使用说明」
      await tester.tap(find.byTooltip('引导'));
      await tester.pumpAndSettle();
      expect(find.textContaining('使用说明'), findsAtLeastNWidgets(1));
    });

    testWidgets('点「LLM 大模型 API 配置」进配置页', (tester) async {
      await _pump(tester, _home());
      await tester.tap(find.byTooltip('LLM 大模型 API 配置'));
      await tester.pumpAndSettle();
      expect(find.byType(LlmConfigScreen), findsOneWidget);
      expect(find.text('AI 对话引擎'), findsOneWidget);
    });
  });

  group('大模型配置页', () {
    if (skipWithoutOfflineAssets()) return;

    testWidgets('不再有「本机数据」卡片', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await LocalDb.ensure();
      await OfflineContent.ensureMeta();
      await _pump(tester, const MaterialApp(home: LlmConfigScreen()));
      expect(tester.takeException(), isNull);
      expect(find.text('本机数据'), findsNothing, reason: '本机数据卡片已按要求删除');
      // 其余区块仍在
      expect(find.text('AI 对话引擎'), findsOneWidget);
    });
  });
}
