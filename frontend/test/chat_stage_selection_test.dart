// 「选中原文 → 点『对话』」必须先等用户输入，不许替他发问（D161 用户实报）。
//
// 旧行为：点面板里的「对话」直接 `send('这段在说什么？')` —— 用户还没输入提示词，
// 消息就已经发出去、AI 已经开始答了。
// 新行为：`ChatService.stageSelection()` 只把选中原文挂起，浮窗里显示
// 「已带入你选的原句，输入问题后一起发送」，等用户打完字由 `send()` 合并成一条提问；
// 发出去之后挂起态立即清空（一条提问只带一次选区）。
// 释义 / 追问 / 辩难 / 关联仍是一点即发的一次性指令，不受影响。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/models/message.dart';
import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'package:marxism_reader/services/chat_service.dart';
import 'package:marxism_reader/widgets/floating_chat.dart';
import 'helpers/offline_assets_guard.dart';

String _read(String p) => File(p).readAsStringSync();

/// 取出源码里从 [start] 到与之配对的 `}` 的那一段（足够定位 _ask 的分支）。
String _braceSlice(String src, String start) {
  final i = src.indexOf(start);
  expect(i, greaterThan(0), reason: '找不到 $start');
  var depth = 0;
  for (var k = i; k < src.length; k++) {
    if (src[k] == '{') depth++;
    if (src[k] == '}') {
      depth--;
      if (depth == 0) return src.substring(i, k + 1);
    }
  }
  fail('$start 的大括号没有闭合');
}

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Stack(children: [child])));

void main() {
  if (skipWithoutOfflineAssets()) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await OfflineContent.ensureMeta();
    await LocalDb.resetAll();
  });

  group('① ChatService 挂起选区，发送时合并', () {
    testWidgets('点了「对话」之后没有任何提问进 turns', (tester) async {
      final svc = ChatService(dialogueId: 'stage-none');
      addTearDown(svc.dispose);
      svc.stageSelection(text: '实践是检验真理的唯一标准', paragraphId: 'x:p1');
      await tester.pump();
      expect(svc.turns, isEmpty, reason: '挂起选区不等于发问');
      expect(svc.stagedSelection, '实践是检验真理的唯一标准');
      expect(svc.currentMode, ChatMode.chat);
    });

    testWidgets('用户输入后，选区与问题合成同一条提问，挂起态清空', (tester) async {
      final svc = ChatService(dialogueId: 'stage-send');
      addTearDown(svc.dispose);
      svc.stageSelection(text: '实践是检验真理的唯一标准', paragraphId: 'x:p1');
      await tester.pump();
      svc.send(content: '这句话和认识论什么关系？');

      // send 同步添加 user turn；离线响应是异步的（.then(_handle)），
      // 不依赖它是否在同一帧内完成（chunks 加载变快后响应会更快完成），
      // 先验证合并逻辑，再 pump 让响应落定。
      expect(svc.turns.length, 1);
      final t = svc.turns.first;
      expect(t.role, 'user');
      expect(t.content, '这句话和认识论什么关系？', reason: '发的是用户自己写的，不是替发的默认句');
      expect(t.selectedText, '实践是检验真理的唯一标准', reason: '选中的原文要一起进提示词');
      expect(t.mode, ChatMode.chat.name);
      expect(svc.stagedSelection, isEmpty, reason: '一条提问只带一次选区');
      await tester.pump(); // 让离线响应完成，避免 clear 后 _handle 再入队
      svc.clear();
    });

    testWidgets('显式传选区的提问（释义等一次性模式）不会被挂起态覆盖', (tester) async {
      final svc = ChatService(dialogueId: 'stage-explicit');
      addTearDown(svc.dispose);
      svc.stageSelection(text: '挂起的旧选区');
      await tester.pump();
      svc.switchMode(ChatMode.explain);
      svc.send(
          content: ChatMode.explain.askPrompt(),
          selectedText: '这一次选中的原句',
          paragraphId: 'x:p2');
      await tester.pump();
      expect(svc.turns.first.selectedText, '这一次选中的原句');
      expect(svc.stagedSelection, isEmpty);
      svc.clear();
    });

    testWidgets('取消挂起后，提问不带选区', (tester) async {
      final svc = ChatService(dialogueId: 'stage-clear');
      addTearDown(svc.dispose);
      svc.stageSelection(text: '不要这句了');
      await tester.pump();
      svc.clearStagedSelection();
      await tester.pump();
      svc.send(content: '随便问问');
      await tester.pump();
      expect(svc.turns.first.selectedText, isEmpty);
      svc.clear();
    });
  });

  group('② 浮窗提示条', () {
    testWidgets('显示「已带入你选的原句」，并给出对应输入提示', (tester) async {
      await tester.pumpWidget(_host(FloatingChat(
        turns: const <ChatTurn>[],
        status: '已就绪',
        criticalReading: false,
        onToggleCritical: () {},
        onSend: (_) {},
        onClear: () {},
        onClose: () {},
        stagedSelection: '实践是检验真理的唯一标准，这是马克思主义认识论的基本观点。',
        initialOffset: const Offset(10, 10),
        bounds: const Size(800, 900),
        size: const Size(360, 520),
      )));
      await tester.pump();
      expect(find.textContaining('已带入你选的原句'), findsOneWidget);
      expect(find.textContaining('实践是检验真理的唯一标准'), findsOneWidget);
      expect(find.text('就你选的那句提问…'), findsOneWidget);
    });

    testWidgets('没有挂起选区时不显示提示条', (tester) async {
      await tester.pumpWidget(_host(FloatingChat(
        turns: const <ChatTurn>[],
        status: '已就绪',
        criticalReading: false,
        onToggleCritical: () {},
        onSend: (_) {},
        onClear: () {},
        onClose: () {},
        initialOffset: const Offset(10, 10),
        bounds: const Size(800, 900),
        size: const Size(360, 520),
      )));
      await tester.pump();
      expect(find.textContaining('已带入你选的原句'), findsNothing);
      expect(find.text(ChatMode.chat.inputHint), findsOneWidget);
    });

    testWidgets('点 × 取消带入', (tester) async {
      var cleared = 0;
      await tester.pumpWidget(_host(FloatingChat(
        turns: const <ChatTurn>[],
        status: '已就绪',
        criticalReading: false,
        onToggleCritical: () {},
        onSend: (_) {},
        onClear: () {},
        onClose: () {},
        stagedSelection: '被选中的一句',
        onClearStaged: () => cleared++,
        initialOffset: const Offset(10, 10),
        bounds: const Size(800, 900),
        size: const Size(360, 520),
      )));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close).last);
      expect(cleared, 1);
    });
  });

  group('③ 阅读器的 _ask：对话只挂起不发问', () {
    test('chat 分支里没有 svc.send', () {
      final src = _read('lib/screens/work_reader_screen.dart');
      final body = _braceSlice(src, 'void _ask(String text, String mode) {');
      final chatBranch = _braceSlice(body, 'if (m == ChatMode.chat) {');
      expect(chatBranch, contains('stageSelection'));
      expect(chatBranch, isNot(contains('svc.send(')),
          reason: '点「对话」不能替用户发问，必须等他输入');
      // 其余四枚模式仍是一点即发
      expect(body.replaceFirst(chatBranch, ''), contains('svc.send('));
    });

    test('导读页的 _askWith：chat 分支同样只挂起不发问', () {
      final src = _read('lib/screens/chapter_guide_screen.dart');
      final body = _braceSlice(src, 'void _askWith(String text, ChatMode mode) {');
      final chatBranch = _braceSlice(body, 'if (mode == ChatMode.chat) {');
      expect(chatBranch, contains('stageSelection'));
      expect(chatBranch, isNot(contains('svc.send(')),
          reason: '深入学习页点「对话」也不能替用户发问');
      expect(body.replaceFirst(chatBranch, ''), contains('svc.send('));
      // 导读页浮窗同样要显示「已带入你选的原句」
      expect(src, contains('stagedSelection: svc.stagedSelection'));
      expect(src, contains('onClearStaged: svc.clearStagedSelection'));
    });

    test('浮窗接上了挂起选区与取消回调', () {
      final src = _read('lib/screens/work_reader_screen.dart');
      expect(src, contains('stagedSelection: svc.stagedSelection'));
      expect(src, contains('onClearStaged: svc.clearStagedSelection'));
    });
  });
}
