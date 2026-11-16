// 原著浏览页回归测试：书卡墙 + 按作者/书名搜索 + 点卡直接进阅读器。
//
// 锁住四件事：
//   1. 一部著作一张卡（不再有中间的分片列表），点卡进 WorkReaderScreen 阅读器；
//   2. 能按书名搜、按作者搜、也能「作者 + 书名片段」组合搜；
//   3. 作者筛选条按著作过滤；作者未标注时不编造作者；
//   4. 查不到时给空状态与清空入口。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'package:marxism_reader/screens/source_browser_screen.dart';
import 'package:marxism_reader/screens/work_reader_screen.dart';
import 'package:marxism_reader/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.build(),
    home: const SourceBrowserScreen(),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.ensure();
    await OfflineContent.ensureMeta();
    await OfflineContent.ensureChunks();
  });

  testWidgets('每部著作一张书卡，首屏是卡片墙而不是分片列表', (tester) async {
    await _pump(tester);
    final total = OfflineContent.works.length;
    expect(find.textContaining('共 $total 部著作'), findsOneWidget);
    // 作者筛选条本身也是横向 ListView，这里按「竖向书单」断言
    expect(find.byType(ListView), findsWidgets);
    // 卡片墙：书名与「N 段」出现在书卡上（懒构建，首屏只建一部分）
    expect(find.textContaining('段'), findsWidgets);
    // 不应再出现原文分片的「权威度」行
    expect(find.textContaining('权威度'), findsNothing);
  });

  testWidgets('按书名搜索命中', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField).first, '矛盾论');
    await tester.pumpAndSettle();

    expect(find.text('矛盾论'), findsWidgets);
    expect(find.textContaining('命中 1 部著作'), findsOneWidget);
    expect(find.text('大众哲学'), findsNothing);
  });

  testWidgets('按作者搜索命中其全部著作', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField).first, '周恩来');
    await tester.pumpAndSettle();

    final expected = OfflineContent.works
        .where((w) => '${w['author']}' == '周恩来')
        .length;
    expect(expected, greaterThan(0));
    expect(find.textContaining('命中 $expected 部著作'), findsOneWidget);
    // 卡片下方署名即作者
    expect(find.text('周恩来'), findsWidgets);
  });

  testWidgets('作者 + 书名组合搜索按「与」匹配', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField).first, '毛泽东 实践');
    await tester.pumpAndSettle();
    expect(find.text('实践论'), findsWidgets);
    expect(find.text('矛盾论'), findsNothing);

    // 反例：作者与书名不匹配 → 空状态 + 清空入口
    await tester.enterText(find.byType(TextField).first, '列宁 实践论');
    await tester.pumpAndSettle();
    expect(find.textContaining('没有匹配'), findsOneWidget);
    expect(find.text('清空条件'), findsOneWidget);
  });

  testWidgets('作者筛选条点选后只保留该作者著作', (tester) async {
    await _pump(tester);
    final rows = OfflineContent.works;
    final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
    expect(chips.length, greaterThan(3));

    final maoCount = rows.where((w) => '${w['author']}' == '毛泽东').length;
    final maoChip = find.widgetWithText(ChoiceChip, '毛泽东 · $maoCount');
    expect(maoChip, findsOneWidget);

    await tester.tap(maoChip);
    await tester.pumpAndSettle();
    expect(find.textContaining('命中 $maoCount 部著作'), findsOneWidget);

    // 切回「全部作者」恢复完整清单
    await tester.tap(find.widgetWithText(ChoiceChip, '全部作者 · ${rows.length}'));
    await tester.pumpAndSettle();
    expect(find.textContaining('共 ${rows.length} 部著作'), findsOneWidget);
  });

  testWidgets('点书卡进入阅读器（与「查看原文」同一个阅读器）', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField).first, '矛盾论');
    await tester.pumpAndSettle();

    // 注意：搜索框里的输入也会被 find.text 命中（EditableText），
    // 因此限定在卡片墙内找书卡上的书名。
    await tester.tap(
        find.descendant(of: find.byType(ListView).last, matching: find.text('矛盾论')).first);
    await tester.pumpAndSettle();

    final reader = tester.widget<WorkReaderScreen>(find.byType(WorkReaderScreen));
    expect(reader.work, '矛盾论');
    expect(reader.title, '矛盾论');
  });
}
