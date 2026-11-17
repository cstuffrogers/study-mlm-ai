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
    // 模式标签出现在两处：输入区的选择器 + 每条回答的模式标记
    expect(find.text(ChatMode.explain.label), findsWidgets);
    expect(find.byType(PopupMenuButton<ChatMode>), findsOneWidget);

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

  // D138：浮窗打开时 State 是新建的，ScrollController 从 0 开始。选中原文追问
  // 时 turns 里已经有历史（甚至已含刚发出的那句），旧实现只在「条数变化」时贴底，
  // 于是打开瞬间停在最早那句，用户得自己往下拖。
  testWidgets('打开浮窗即贴到最新一条（不需要手动往下拉）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    final turns = <ChatTurn>[
      for (var i = 0; i < 12; i++)
        ChatTurn(
            role: i.isEven ? 'user' : 'ai',
            content: '第$i条消息：${'这是用来撑高内容以便产生滚动的中文文本。' * 3}',
            mode: 'explain'),
    ];
    await tester.pumpWidget(host(FloatingChat(
      turns: turns,
      status: '已连接 · 释义',
      currentMode: ChatMode.explain,
      criticalReading: false,
      onModeChanged: (_) {},
      onToggleCritical: () {},
      onSend: (_) {},
      onClear: () {},
      onClose: () {},
      initialOffset: const Offset(60, 60),
      bounds: const Size(800, 900),
      size: const Size(372, 400),
    )));
    await tester.pumpAndSettle();

    final scrollable = tester.widget<ListView>(find.byType(ListView)).controller!;
    expect(scrollable.position.pixels, greaterThan(0),
        reason: '打开时应当已经滚到底，而不是停在最上方');
    expect(scrollable.position.pixels,
        closeTo(scrollable.position.maxScrollExtent, 1.0),
        reason: '应当贴到最大滚动位置（最新一条完整可见）');
    // 最后一条消息确实在可视区内
    final last = tester.getRect(find.textContaining('第11条消息'));
    expect(last.top, greaterThanOrEqualTo(tester.getRect(find.byType(ListView)).top - 0.5));
    expect(last.bottom, lessThanOrEqualTo(tester.getRect(find.byType(ListView)).bottom + 0.5));

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

  // 回归：模式选择曾放在标题栏，输入框在底部，中间隔着消息列表——
  // 用户在底部打字时看不见当前模式，切模式要跑到顶部找。
  testWidgets('模式选择与输入框同处一行（不再与对话框脱离）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    await tester.pumpWidget(host(FloatingChat(
      turns: const <ChatTurn>[],
      status: '已连接 · 释义',
      currentMode: ChatMode.explain,
      criticalReading: false,
      onModeChanged: (_) {},
      onToggleCritical: () {},
      onSend: (_) {},
      onClear: () {},
      onClose: () {},
      initialOffset: const Offset(60, 60),
      bounds: const Size(800, 900),
      size: const Size(372, 520),
    )));
    await tester.pump();

    final modeBtn = find.byType(PopupMenuButton<ChatMode>);
    expect(modeBtn, findsOneWidget, reason: '模式选择只有输入区这一处入口');

    final modeRect = tester.getRect(modeBtn);
    final inputRect = tester.getRect(find.byType(TextField));
    // 同一水平带（中心线对齐），且在输入框左侧
    expect((modeRect.center.dy - inputRect.center.dy).abs(), lessThan(8));
    expect(modeRect.right, lessThanOrEqualTo(inputRect.left + 1));

    // 输入框提示语体现当前模式
    expect(find.text('以「释义」追问…'), findsOneWidget);

    // 展开菜单：5 个模式都在，且带说明
    await tester.tap(modeBtn);
    await tester.pumpAndSettle();
    for (final m in ChatMode.values) {
      expect(find.text(m.label), findsWidgets, reason: '菜单缺模式 ${m.label}');
      expect(find.text(m.desc), findsOneWidget, reason: '菜单缺说明 ${m.label}');
    }

    // 选「辩难」关掉菜单（无回调也不应报错）
    await tester.tap(find.text(ChatMode.debate.label).last);
    await tester.pumpAndSettle();
    expect(find.text(ChatMode.debate.desc), findsNothing, reason: '选完应关闭菜单');

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('选模式会回调 onModeChanged（含 5 个选项）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    final picked = <ChatMode>[];
    await tester.pumpWidget(host(FloatingChat(
      turns: const <ChatTurn>[],
      status: '已连接 · 释义',
      currentMode: ChatMode.explain,
      criticalReading: false,
      onModeChanged: picked.add,
      onToggleCritical: () {},
      onSend: (_) {},
      onClear: () {},
      onClose: () {},
      initialOffset: const Offset(60, 60),
      bounds: const Size(800, 900),
      size: const Size(372, 520),
    )));
    await tester.pump();

    await tester.tap(find.byType(PopupMenuButton<ChatMode>));
    await tester.pumpAndSettle();
    expect(find.text(ChatMode.values.last.desc), findsOneWidget);
    await tester.tap(find.text(ChatMode.test.label).last);
    await tester.pumpAndSettle();
    expect(picked, [ChatMode.test]);

    await tester.binding.setSurfaceSize(null);
  });

  test('五模式必须五色（NFR-019）', () {
    final colors = ChatMode.values.map((m) => m.color).toSet();
    expect(colors.length, ChatMode.values.length, reason: '存在同色模式：$colors');
  });

  test('每个模式都有说明，且不是空话', () {
    for (final m in ChatMode.values) {
      expect(m.desc.trim().length, greaterThan(6), reason: '${m.label} 缺说明');
      expect(m.inputHint, contains(m.label));
    }
  });

  testWidgets('窄屏 360 下输入区不溢出：模式 chip / 输入框 / 发送同排', (tester) async {
    const vp = Size(360, 700);
    await tester.binding.setSurfaceSize(vp);
    await tester.pumpWidget(host(FloatingChat(
      turns: const <ChatTurn>[],
      status: '本机引擎 · 已就绪',
      currentMode: ChatMode.connect,
      criticalReading: true,
      onModeChanged: (_) {},
      onToggleCritical: () {},
      onSend: (_) {},
      onClear: () {},
      onClose: () {},
      initialOffset: const Offset(8, 40),
      bounds: vp,
      size: const Size(296, 480), // (360-64).clamp(280,372)
    )));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: '窄屏出现布局溢出');

    final input = tester.getRect(find.byType(TextField));
    final mode = tester.getRect(find.byType(PopupMenuButton<ChatMode>));
    expect(input.width, greaterThan(100), reason: '模式 chip 挤掉了输入框');
    expect(mode.right, lessThanOrEqualTo(input.left + 1));
    // header 里已没有第二个模式入口
    expect(find.byType(PopupMenuButton<ChatMode>), findsOneWidget);

    await tester.binding.setSurfaceSize(null);
  });
}
