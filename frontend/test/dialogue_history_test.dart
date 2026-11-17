// 「对话历史」页回归测试。
//
// 修复前的两个真问题（都在真机上能看到）：
//  ① 数据读的是后端 `/api/dialogue/*` —— 单机包没有后端，列表永远空；
//  ② 布局是固定 `Row(SizedBox(width:260), Expanded)` —— 手机上就是「左右分两半、
//     左边一片空白」。窄屏还可能因为气泡固定 width:560 横向溢出。
// 这里按本机数据 + 自适应布局钉住。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/screens/dialogue_history_screen.dart';
import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/theme/app_theme.dart';

String _seed() {
  final now = DateTime.now().toIso8601String();
  return jsonEncode({
    'd-20260101': {
      'id': 'd-20260101',
      'title': '实践是检验真理的唯一标准',
      'current_mode': 'debate',
      'created_at': now,
      'updated_at': now,
      'messages': [
        {'role': 'user', 'content': '为什么说实践是检验真理的唯一标准？', 'mode': 'debate', 'created_at': now},
        {
          'role': 'ai',
          'content': '原文摘录（逐字引用，非改写）：\n\n> 人的思维是否具有客观的真理性，这不是一个理论的问题，而是一个实践的问题。',
          'mode': 'debate',
          'engine': 'local',
          'created_at': now,
        },
        {'role': 'blocked', 'content': '这段表述涉及与本课程立场不一致的框架（阶级斗争过时）。', 'mode': 'explain', 'created_at': now},
      ],
    },
  });
}

Future<void> _pump(WidgetTester t, Size size) async {
  await t.binding.setSurfaceSize(size);
  await t.pumpWidget(MaterialApp(theme: AppTheme.build(), home: const DialogueHistoryScreen()));
  await t.pumpAndSettle();
}

void main() {
  setUp(() async {
    LocalDb.dialogues.clear();
    await LocalDb.ensure();
    LocalDb.dialogues
      ..clear()
      ..addAll((jsonDecode(_seed()) as Map).cast<String, dynamic>());
  });

  tearDown(() {
    LocalDb.dialogues.clear();
  });

  testWidgets('窄屏：单列，先列表后钻取，不出现左右分栏', (t) async {
    await _pump(t, const Size(390, 844));

    // 列表可见
    expect(find.text('实践是检验真理的唯一标准'), findsOneWidget);
    expect(find.byType(VerticalDivider), findsNothing, reason: '窄屏不该做左右分栏');
    expect(find.textContaining('为什么说实践是检验'), findsNothing, reason: '进会话前不该显示消息');

    // 点进去 → 消息
    await t.tap(find.text('实践是检验真理的唯一标准'));
    await t.pumpAndSettle();
    expect(find.textContaining('为什么说实践是检验'), findsOneWidget);
    expect(find.textContaining('人的思维是否具有客观的真理性'), findsOneWidget);
    expect(find.text('防偏离拦截'), findsOneWidget);
    expect(t.takeException(), isNull, reason: '窄屏出现横向溢出');

    // 返回列表
    await t.tap(find.byTooltip('返回列表'));
    await t.pumpAndSettle();
    expect(find.text('实践是检验真理的唯一标准'), findsOneWidget);

    // 再进一次，用系统返回键：应回列表，而不是直接退出整页
    await t.tap(find.text('实践是检验真理的唯一标准'));
    await t.pumpAndSettle();
    expect(find.textContaining('人的思维是否具有客观的真理性'), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('实践是检验真理的唯一标准'), findsOneWidget,
        reason: '系统返回键应当先回列表');

    await t.binding.setSurfaceSize(null);
  });

  testWidgets('宽屏：左列有内容（不是空白），右侧同时显示消息', (t) async {
    await _pump(t, const Size(1100, 800));

    expect(find.byType(VerticalDivider), findsOneWidget);
    // 左侧列表项与右侧消息**同时**可见
    expect(find.text('实践是检验真理的唯一标准'), findsWidgets);
    expect(find.textContaining('人的思维是否具有客观的真理性'), findsOneWidget);

    await t.binding.setSurfaceSize(null);
  });

  testWidgets('空数据时给可执行提示，不是一片空白', (t) async {
    LocalDb.dialogues.clear();
    await _pump(t, const Size(390, 844));

    expect(find.text('还没有对话记录'), findsOneWidget);
    expect(find.textContaining('点浮窗里的模式追问'), findsOneWidget);

    await t.binding.setSurfaceSize(null);
  });
}
