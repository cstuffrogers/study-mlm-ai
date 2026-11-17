// 基本冒烟测试 — 验证首页（D142 起首页即「选学习路线」：三条路线卡 → 章节地图）

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:marxism_reader/main.dart';
import 'package:marxism_reader/services/chat_service.dart';

void main() {
  testWidgets('首页渲染路线入口（不再有章节列表与底部主操作）', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ChatService(),
        child: const MarxismReaderApp(),
      ),
    );
    // 不 init 本地库：路线列表会一直转圈，所以这里只 pump 固定帧，不 pumpAndSettle
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // 顶部标题与副标题
    expect(find.text('马列毛思想AI伴读'), findsOneWidget);
    expect(find.text('先选学习路线，再进章节精读'), findsOneWidget);
    // 首页只到「选路线」为止：章节列表与底部主操作已交给章节地图页
    expect(find.text('深入学习'), findsNothing);
    expect(find.text('② 选择起始章节'), findsNothing);
    // 「引导」与功能入口在头部图标（浮动按钮会压住主操作）
    expect(find.text('会话'), findsNothing);
    expect(find.byTooltip('引导'), findsOneWidget);
    expect(find.byTooltip('功能中心'), findsOneWidget);
    expect(find.byTooltip('LLM 大模型 API 配置'), findsOneWidget);
    expect(find.byTooltip('学习分析'), findsOneWidget);
    // 首页自身即选路线页 → 不再有「学习路线」自指按钮
    expect(find.byTooltip('学习路线'), findsNothing);
    // 首页无 FAB
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
