// 布局回归：全局字号放大 + 刘海屏头部高度。
//
// 两件线上问题在这里锁住：
//   1. 全局字号统一放大 7%（main.dart 的 textScaler）；放大后主要页面不能 overflow，
//      否则用户会看到黄黑条或文字被裁。
//   2. 「选择学习路线」「学习分析」的标题被下方内容遮住一截：根因是 GradientHeader
//      高度固定、内部 SafeArea 又把内容下推，状态栏一高标题就掉到容器外面。
//      现在容器高度 = 基准高度 + 状态栏高度，这里用 40px 的状态栏模拟刘海屏验证。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'package:marxism_reader/screens/analytics_dashboard.dart';
import 'package:marxism_reader/screens/source_browser_screen.dart';
import 'package:marxism_reader/screens/home_screen.dart';
import 'package:marxism_reader/screens/tools_screen.dart';
import 'package:marxism_reader/services/chat_service.dart';
import 'package:marxism_reader/services/sync_controller.dart';
import 'package:marxism_reader/theme/app_theme.dart';
import 'package:marxism_reader/widgets/anim.dart';
import 'helpers/offline_assets_guard.dart';

/// 模拟一台「状态栏 40 + 字号放大 7%」的手机
Widget _phone(Widget child) {
  return MediaQuery(
    data: const MediaQueryData(
      size: Size(390, 844),
      padding: EdgeInsets.only(top: 40),
      textScaler: TextScaler.linear(1.07),
    ),
    child: MaterialApp(theme: AppTheme.build(), home: child),
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(child);
  await tester.pumpAndSettle();
}

void main() {
  if (skipWithoutOfflineAssets()) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.ensure();
    await OfflineContent.ensureMeta();
    await OfflineContent.ensureChunks();
  });

  testWidgets('首页：放大字号 + 状态栏 40 时不溢出，头部四个入口都在', (tester) async {
    await _pump(
      tester,
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ChatService()),
          ChangeNotifierProvider(create: (_) => SyncController()),
        ],
        child: _phone(const HomeScreen()),
      ),
    );
    expect(tester.takeException(), isNull);
    for (final tip in ['功能中心', 'LLM 大模型 API 配置', '学习分析', '引导']) {
      expect(find.byTooltip(tip), findsOneWidget);
    }
  });

  testWidgets('首页（选路线）：标题完整落在头部容器内（不被下方列表遮住）', (tester) async {
    await _pump(
      tester,
      _phone(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ChatService()),
            ChangeNotifierProvider(create: (_) => SyncController()),
          ],
          child: const HomeScreen(),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    final header = tester.widget<GradientHeader>(find.byType(GradientHeader));
    final headerRect = tester.getRect(find.byType(GradientHeader));
    // 头部高度不小于「基准 + 状态栏 40」
    expect(headerRect.height, greaterThanOrEqualTo(header.height + 40 - 0.5));

    // 首页标题走 BrandTitle（分行渲染），用副标题文本验证「标题区不超出头部容器」
    final titleRect = tester.getRect(find.text('先选学习路线，再进章节精读'));
    expect(titleRect.bottom, lessThanOrEqualTo(headerRect.bottom));
    expect(titleRect.top, greaterThanOrEqualTo(headerRect.top));
  });

  testWidgets('学习分析：标题完整落在头部容器内（不被下方内容遮住）', (tester) async {
    await _pump(tester, _phone(const AnalyticsDashboardScreen(routeId: 'route_A')));
    expect(tester.takeException(), isNull);

    final headerRect = tester.getRect(find.byType(GradientHeader));
    final titleRect = tester.getRect(find.text('学习分析'));
    expect(titleRect.bottom, lessThanOrEqualTo(headerRect.bottom));
    expect(titleRect.top, greaterThanOrEqualTo(headerRect.top));
  });

  testWidgets('原著浏览：书卡墙在放大字号下不溢出', (tester) async {
    await _pump(tester, _phone(const SourceBrowserScreen()));
    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsWidgets);
    expect(find.textContaining('段原文'), findsWidgets);
  });

  testWidgets('功能中心：放大字号下不溢出', (tester) async {
    await _pump(tester, _phone(const ToolsScreen()));
    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsWidgets);
  });
}
