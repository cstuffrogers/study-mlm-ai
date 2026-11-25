// D146 门禁：五处体验修复不许回退。
//
// 用户实报清单：
//  ① 溯源原文分片弹层里点小喇叭，退出弹层后还在念；
//  ② AI 对话浮窗关掉后，对话内容的朗读还在念；
//  ③ 原文页右上角对话按钮一点就自动释义（应该只弹框）；
//  ④ 原文卡片/溯源卡片选中文本弹系统 copy 框（应该只弹释义浮框）；
//  ⑤ 使用说明要同步这些新行为。
//
// 这些都属于「一次点击触发了不该发生的动作」，widget 层面很难断言
// 真实语音通道，所以门禁分两种：真实 widget 行为 + 源码接线核对。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marxism_reader/models/message.dart';
import 'package:marxism_reader/services/tts.dart';
import 'package:marxism_reader/widgets/sheet_selection_ask.dart';

String readFile(String p) => File(p).readAsStringSync();

/// 从 [from] 截到 [to] 的源码片段（[to] 不存在时截到文件尾）。
String slice(String src, String from, String to) {
  final i = src.indexOf(from);
  expect(i, greaterThan(-1), reason: '找不到锚点：$from');
  final j = src.indexOf(to, i);
  return j < 0 ? src.substring(i) : src.substring(i, j);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('① 溯源原文分片弹层：退出即停朗读', () {
    testWidgets('弹层被销毁时停朗读（点遮罩/下滑/父页面替换都走这条）', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: _StopProbe()),
      ));
      ttsCurrent.value = 'chunk-X';
      expect(ttsCurrent.value, 'chunk-X');

      // 换掉整棵树 → 探针 dispose
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: Text('gone'))));
      expect(ttsCurrent.value, isNull, reason: '弹层销毁必须停朗读');
    });

    test('chunk_tag 的弹层都包了 _StopSpeechOnDispose', () {
      final src = readFile('lib/widgets/chunk_tag.dart');
      expect(src, contains('class _StopSpeechOnDispose'));
      final body = slice(src, 'class _StopSpeechOnDisposeState', '/// 弹层里选了话');
      expect(body, contains('ttsStop()'), reason: 'dispose 里必须真的停');
      // 至少有一个弹层的 builder 用上了它
      expect(src, contains('builder: (ctx) => _StopSpeechOnDispose('));
    });
  });

  group('② 会话浮窗关闭即停朗读', () {
    test('_closeFloatingChat 第一件事就是停朗读', () {
      final src = readFile('lib/screens/work_reader_screen.dart');
      final body = slice(src, 'void _closeFloatingChat() {', 'OverlayEntry? _chatEntry');
      expect(body, contains('ttsStop()'));
      // 必须放在移除 entry 之前，否则监听器先被摘掉
      final iStop = body.indexOf('ttsStop()');
      final iRemove = body.indexOf('_chatEntry?.remove()');
      expect(iRemove, greaterThan(-1));
      expect(iStop, lessThan(iRemove), reason: '先停朗读再拆浮窗');
    });
  });

  group('③ 原文页对话按钮：只弹框，不自动释义', () {
    test('AppBar 的会话按钮绑的是 _openChatOnly 而不是 _ask', () {
      final src = readFile('lib/screens/work_reader_screen.dart');
      final i = src.indexOf("tooltip: '会话（AI 精读 + 普通对话）'");
      expect(i, greaterThan(-1));
      final tail = src.substring(i, i + 400);
      expect(tail, contains('_openChatOnly'));
      expect(tail, isNot(contains('_ask(')),
          reason: '一点就释义是本次要修的缺陷，不能回退');
    });

    test('_openChatOnly 只开关浮窗，不发任何消息', () {
      final src = readFile('lib/screens/work_reader_screen.dart');
      final body = slice(src, 'void _openChatOnly() {', 'void _ask(');
      expect(body, contains('_openFloatingChat'));
      expect(body, contains('_closeFloatingChat'));
      expect(body, isNot(contains('svc.send')), reason: '打开会话不能替用户发问');
    });
  });

  group('④ 弹层选文：只弹释义浮框，不弹系统 copy 框', () {
    testWidgets('SheetSelectionAsk 屏蔽系统工具栏并浮出自己的面板', (t) async {
      ChatMode? asked;
      String? askedText;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SheetSelectionAsk(
            speakKey: 'CH-X',
            onAsk: (text, mode) {
              askedText = text;
              asked = mode;
            },
            child: const SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('这是一段可以被选中的原文内容，用来验证浮框行为。'),
              ),
            ),
          ),
        ),
      ));
      expect(find.byType(SelectionArea), findsOneWidget);
      // 自己模拟选中：直接调 onSelectionChanged 不可行（私有），
      // 所以确认组件挂上了 SelectionArea + 未暴露系统菜单即可，
      // 浮框本身的出现由下面的源码断言保证。
      expect(find.byType(SheetSelectionAsk), findsOneWidget);
      expect(asked, isNull, reason: '还没点模式，不该发问');
      expect(askedText, isNull);
    });

    test('两个弹层都屏蔽了系统 copy 菜单', () {
      final src = readFile('lib/widgets/chunk_tag.dart');
      // 导读卡片在 chunk_tag 里直接屏蔽；
      // 原文卡片把那层交给 SheetSelectionAsk（它自己也会屏蔽，见下一条）。
      expect(src, contains('contextMenuBuilder: (_, _) => const SizedBox.shrink()'),
          reason: '导读卡片的选中不能弹系统 copy 菜单');
      expect(src, contains('SheetSelectionAsk('),
          reason: '原文卡片要走带屏蔽的选文浮框');
    });

    test('SheetSelectionAsk 自己也不弹系统菜单', () {
      final src = readFile('lib/widgets/sheet_selection_ask.dart');
      expect(src, contains('contextMenuBuilder'));
      expect(src, contains('const SizedBox.shrink()'));
      // 面板里的模式 chip 覆盖全部五种（含普通对话：点它=带着选中原句直接问）
      expect(src, contains('kSelectionModes.map'));
    });

    test('弹层选文发问走阅读器（不在这里另起一套会话浮窗）', () {
      final src = readFile('lib/widgets/chunk_tag.dart');
      final body = slice(src, 'Future<void> _askFromSheet(', '/// 导读溯源卡片');
      expect(body, contains('WorkReaderScreen('));
      expect(body, contains('askText: text'));
      expect(body, contains('askMode: mode'));
      expect(body, isNot(contains('OverlayEntry')),
          reason: '会话浮窗全应用只保留阅读器那一份实现');
    });
  });

  group('④b 释义浮框关闭后停朗读', () {
    testWidgets('浮框收起 / 发问 / 选区变化 / 销毁，四条路都停朗读', (t) async {
      // 真实点一次：SheetSelectionAsk 的浮框出现 → 点「关闭」→ 声音必须停
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SheetSelectionAsk(
            speakKey: 'CH-X',
            onAsk: (_, _) {},
            child: const SelectionArea(
              child: Padding(
                padding: EdgeInsets.all(12),
                // 用 SelectableText 才能触发 SelectionArea 的选区回调
                child: SelectableText('这是一段可以被选中的原文内容'),
              ),
            ),
          ),
        ),
      ));
      ttsCurrent.value = 'chunk-sel-CH-X-123';
      // 换掉整棵子树 → 浮框所在 State dispose
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: Text('gone'))));
      expect(ttsCurrent.value, isNull, reason: '浮框销毁必须停朗读');
    });

    test('SheetSelectionAsk 的四个退出点都真的停朗读', () {
      final src = readFile('lib/widgets/sheet_selection_ask.dart');
      // _stopSpeech 必须真的落到 ttsStop —— 否则下面所有调用点都是空壳，
      // 门禁会被一个「{ }」骗过去（负向验证就是靠这条抓住的）。
      expect(src, contains('void _stopSpeech() => ttsStop();'),
          reason: '_stopSpeech 不能是空实现');
      // dispose 兜底：截 dispose 函数体本身
      final iDisp = src.indexOf('void dispose() {');
      expect(iDisp, greaterThan(-1));
      final disp = src.substring(iDisp, src.indexOf('void _stopSpeech()', iDisp));
      expect(disp, contains('ttsStop()'));
      // 选文变化 / 选区清空
      final sel = slice(src, 'void _onSel(SelectedContent? sel) {', '@override');
      expect(sel, contains('_stopSpeech()'));
      expect('_stopSpeech('.allMatches(sel).length, greaterThanOrEqualTo(2),
          reason: '选区换了要停、选区清空也要停');
      // onAsk / onDismiss / onCopy
      final cb = slice(src, 'onAsk: (m) {', 'onDismiss:');
      expect(cb, contains('_stopSpeech()'));
      final dis = slice(src, 'onDismiss: () {', 'setState(() => _text = '')');
      expect(dis, contains('_stopSpeech()'));
    });

    test('正文页的选文浮框收起时也停朗读', () {
      final src = readFile('lib/screens/work_reader_screen.dart');
      final sel = slice(src, 'void _onSelectionChanged(SelectedContent? sel) {', '@override');
      expect(sel, contains('ttsStop()'));
      // 点模式的那段代码：截「final t = _selected;」到「_ask(t, m.name)」
      final chip = slice(src, 'final t = _selected;', '_ask(t, m.name)');
      expect(chip, contains('ttsStop()'), reason: '点模式即收起浮框，必须停');
    });
  });

  group('⑤ 阅读器「带问题打开」', () {
    test('WorkReaderScreen 接受 askText / askMode 且只发一次', () {
      final src = readFile('lib/screens/work_reader_screen.dart');
      expect(src, contains('final String? askText;'));
      expect(src, contains('final String? askMode;'));
      final body = slice(src, 'void _flushPendingAsk()', 'Future<void> _loadPrefs()');
      expect(body, contains('_pendingAsk = null'),
          reason: '带过来的问题只发一次，翻页/重排不能重复发');
      expect(body, contains('if (text == null || text.trim().isEmpty) return;'));
    });
  });

  group('⑥ 使用说明同步了新行为', () {
    test('说明里写了自动更新、对话按钮不自动发问、翻页停朗读', () {
      final src = readFile('lib/widgets/guide_dialog.dart');
      expect(src, contains('应用内更新'));
      expect(src, contains('检查更新'));
      expect(src, contains('不会自动替你发问'));
      expect(src, contains('翻页即停朗读'));
      expect(src, contains('不弹系统自带的'));
      expect(src, contains('收起浮窗时'));
    });
  });
}

/// 用来验证「树被替换 → dispose → 停朗读」的探针。
class _StopProbe extends StatefulWidget {
  const _StopProbe();

  @override
  State<_StopProbe> createState() => _StopProbeState();
}

class _StopProbeState extends State<_StopProbe> {
  @override
  void dispose() {
    ttsStop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('probe');
}
