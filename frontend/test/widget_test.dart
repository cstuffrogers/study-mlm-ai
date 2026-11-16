// 基本冒烟测试 — 验证学习首页（先选路线→选章节→深入学习/查看原文）能渲染

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:marxism_reader/main.dart';
import 'package:marxism_reader/services/chat_service.dart';

void main() {
  testWidgets('学习首页渲染路线/章节入口', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ChatService(),
        child: const MarxismReaderApp(),
      ),
    );
    await tester.pump();
    // 顶部标题与副标题
    expect(find.text('马列毛思想AI伴读'), findsOneWidget);
    expect(find.text('先选学习路线，再选起始章节'), findsOneWidget);
    // 底部主操作按钮
    expect(find.text('深入学习'), findsOneWidget);
    // 首页已删除「会话」按钮；「引导」与功能入口移到头部图标（浮动按钮会压住主操作）
    expect(find.text('会话'), findsNothing);
    expect(find.byTooltip('引导'), findsOneWidget);
    expect(find.byTooltip('功能中心'), findsOneWidget);
    expect(find.byTooltip('学习路线'), findsOneWidget);
    expect(find.byTooltip('学习分析'), findsOneWidget);
    // 底部主操作不再被浮动按钮覆盖：首页无 FAB
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
