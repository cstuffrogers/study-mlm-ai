// 原文页「一页正好装下」回归测试。
//
// 用户实报：原文界面每页都要往下拉一点才能看全最后几行，字号越大越明显。
// 根因：分页尺寸取的是**整个屏幕高度**（mq.size.height），而正文实际区域只是
// Scaffold 的 body（已扣掉 AppBar / 状态栏 / 底部翻页栏，手机上差 ~110px）。
// 多算出来的高度让分页每页多塞 2~4 行，超出部分只能靠滚动补看。
//
// 这里锁住：任意字号（含系统字号缩放）下，当前页的滚动范围必须是 0。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_store_keys.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'package:marxism_reader/screens/work_reader_screen.dart';
import 'package:marxism_reader/theme/app_theme.dart';
import 'helpers/offline_assets_guard.dart';

const String _work = '大众哲学';

Future<void> _pumpReader(WidgetTester tester, {double fontSize = 18, double scale = 1.0}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    LocalStoreKeys.reader(_work, LocalStoreKeys.readerFontSize): fontSize,
  });
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 844),
        padding: const EdgeInsets.only(top: 24),
        textScaler: TextScaler.linear(scale),
      ),
      child: MaterialApp(
        theme: AppTheme.build(),
        home: const WorkReaderScreen(work: _work, title: _work),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 当前已渲染页里最大的「需要滚动多少才能看全」距离。
double _maxOverflow(WidgetTester tester) {
  var worst = 0.0;
  final scrollers = find.descendant(
    of: find.byType(SingleChildScrollView),
    matching: find.byType(Scrollable),
  );
  for (var i = 0; i < scrollers.evaluate().length; i++) {
    final pos = tester.state<ScrollableState>(scrollers.at(i)).position;
    worst = math.max(worst, pos.maxScrollExtent);
  }
  return worst;
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

  for (final fs in <double>[13, 18, 24, 30]) {
    testWidgets('字号 ${fs.toInt()}：一页完整显示，不需要下拉', (tester) async {
      await _pumpReader(tester, fontSize: fs);
      expect(find.byType(SingleChildScrollView), findsWidgets, reason: '原文页应已渲染');
      final overflow = _maxOverflow(tester);
      expect(
        overflow,
        lessThanOrEqualTo(0.5),
        reason: '字号 ${fs.toInt()} 时每页还要往下拉 ${overflow.toStringAsFixed(1)}px 才看全，'
            '分页高度没扣掉 AppBar/底栏（用了屏幕高度而非 body 高度）',
      );
    });
  }

  testWidgets('系统字号放大 1.3 倍：一页仍完整显示', (tester) async {
    await _pumpReader(tester, fontSize: 18, scale: 1.3);
    final overflow = _maxOverflow(tester);
    expect(overflow, lessThanOrEqualTo(0.5),
        reason: '系统字号放大后每页还要下拉 ${overflow.toStringAsFixed(1)}px');
  });
}
