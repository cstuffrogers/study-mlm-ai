// FloatingChat / MovableBox 基本行为测试：能渲染、可拖动、发送。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/models/message.dart';
import 'package:marxism_reader/services/chat_service.dart';
import 'package:marxism_reader/widgets/floating_chat.dart';
import 'package:marxism_reader/theme/app_theme.dart';

void main() {
  Widget host(Widget child, {Size size = const Size(800, 900)}) => MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: Stack(children: [child]),
        ),
      );

  testWidgets('FloatingChat 渲染标题/模式，并可拖动头部改变位置', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    final turns = <ChatTurn>[
      ChatTurn(role: 'user', content: '为什么说实践是检验真理的唯一标准？', mode: 'explain'),
      ChatTurn(role: 'ai', content: '因为**实践**把主观认识与客观实在联结起来……', mode: 'explain'),
    ];
    var sent = '';
    await tester.pumpWidget(host(FloatingChat(
      turns: turns,
      status: '已连接 · 释义',
      currentMode: ChatMode.explain,
      criticalReading: false,
      onModeChanged: (_) {},
      onToggleCritical: () {},
      onSend: (t) => sent = t,
      onClear: () {},
      onClose: () {},
      initialOffset: const Offset(60, 60),
      bounds: const Size(800, 900),
      size: const Size(372, 520),
    )));
    await tester.pump();

    expect(find.text('已连接 · 释义'), findsOneWidget);
    // 模式下拉显示当前模式标签
    expect(find.text(ChatMode.explain.label), findsOneWidget);

    // 找到浮窗左上角，拖动头部
    final before = tester.getTopLeft(find.byType(FloatingChat));
    final header = find.byIcon(Icons.drag_indicator);
    expect(header, findsOneWidget);
    await tester.drag(header, const Offset(120, 90));
    await tester.pump();
    final after = tester.getTopLeft(find.byType(FloatingChat));
    expect(after.dx, greaterThan(before.dx + 80));
    expect(after.dy, greaterThan(before.dy + 60));

    // 输入并发送
    await tester.enterText(find.byType(TextField), '再讲讲真理的相对性');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(sent, '再讲讲真理的相对性');

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('FloatingChat 显示等待/失败状态，并可点重试', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    var retries = 0;
    Widget panel({required bool pending, String? error}) => host(FloatingChat(
          turns: const <ChatTurn>[],
          status: '已连接 · 释义',
          currentMode: ChatMode.explain,
          criticalReading: false,
          onModeChanged: (_) {},
          onToggleCritical: () {},
          onSend: (_) {},
          onClear: () {},
          onClose: () {},
          pending: pending,
          error: error,
          onRetry: () => retries++,
          initialOffset: const Offset(60, 60),
          bounds: const Size(800, 900),
          size: const Size(372, 520),
        ));

    await tester.pumpWidget(panel(pending: true));
    await tester.pump();
    expect(find.textContaining('正在生成回复'), findsOneWidget);

    await tester.pumpWidget(panel(pending: false, error: '生成超时，请重试'));
    await tester.pump();
    expect(find.textContaining('生成超时'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(retries, 1);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('MovableBox 可自由拖动且不越界', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 800));
    await tester.pumpWidget(host(
      Stack(children: [
        MovableBox(
          bounds: const Size(600, 800),
          size: const Size(200, 80),
          initialOffset: const Offset(10, 10),
          child: Container(key: const Key('box'), color: Colors.red, height: 80),
        ),
      ]),
    ));
    await tester.pump();
    final before = tester.getTopLeft(find.byKey(const Key('box')));
    await tester.drag(find.byKey(const Key('box')), const Offset(300, 300));
    await tester.pump();
    final after = tester.getTopLeft(find.byKey(const Key('box')));
    expect(after.dx, greaterThan(before.dx + 200));
    expect(after.dy, greaterThan(before.dy + 200));
    // 越界钳制：拖到极右下也不会超出屏幕
    await tester.drag(find.byKey(const Key('box')), const Offset(1000, 1000));
    await tester.pump();
    final clamped = tester.getTopLeft(find.byKey(const Key('box')));
    expect(clamped.dx, lessThanOrEqualTo(600 - 200));
    expect(clamped.dy, lessThanOrEqualTo(800 - 80));

    await tester.binding.setSurfaceSize(null);
  });
}
