// D145 门禁：朗读该停的地方必须停。
//
// 用户实报两处漏停：
//  ① 「相关原文」弹层里点小喇叭，关掉弹层后声音还在念；
//  ② 原文阅读器翻页（上一页/下一页/滑动/滑块/跳页）后，上一页的声音还在念。
//
// 这两处都很容易「看起来修好了但没修」：
//  · 弹层是 PopupRoute，原观察者**特意豁免**了它 —— 所以要单独一条规则；
//  · 翻页不走路由，只有 onPageChanged / _goto 知道页码变了。
// 所以门禁分两类：真实 Navigator 行为测试 + 源码接线核对。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marxism_reader/services/tts.dart';
import 'package:marxism_reader/services/tts_autostop.dart';

String readFile(String p) => File(p).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 每个用例前把「正在朗读」的状态清掉，避免相互污染
    ttsCurrent.value = null;
  });

  group('弹层关闭即停朗读', () {
    testWidgets('关闭底部弹层会停朗读', (t) async {
      await t.pumpWidget(MaterialApp(
        navigatorObservers: [TtsStopOnSheetClose()],
        home: const Scaffold(body: Text('base')),
      ));
      ttsCurrent.value = 'chunk-X';
      // 打开一个 PopupRoute
      final ctx = t.element(find.text('base'));
      showModalBottomSheet<void>(
        context: ctx,
        builder: (_) => const SizedBox(height: 100, child: Text('sheet')),
      );
      await t.pumpAndSettle();
      expect(ttsCurrent.value, 'chunk-X', reason: '打开弹层不该打断朗读');

      // 关闭弹层
      Navigator.of(t.element(find.text('sheet'))).pop();
      await t.pumpAndSettle();
      expect(ttsCurrent.value, isNull, reason: '关闭弹层必须停朗读');
    });

    testWidgets('打开弹层本身不停朗读（不能误伤正在听的正文）', (t) async {
      await t.pumpWidget(MaterialApp(
        navigatorObservers: [TtsStopOnSheetClose(),
          // 同时挂上页面切换观察者，模拟真实装配
          TtsStopOnRouteChange()],
        home: const Scaffold(body: Text('base')),
      ));
      // 注意顺序：必须先挂载再设「正在朗读」。
      // pumpWidget 挂 home 本身会 didPush 一条 MaterialPageRoute，触发换页停读；
      // 真实 App 首帧时还没人朗读，所以那不是缺陷，是测试环境的时序差异。
      ttsCurrent.value = 'reader-page-Book-3';
      final ctx = t.element(find.text('base'));
      showModalBottomSheet<void>(
        context: ctx,
        builder: (_) => const SizedBox(height: 100, child: Text('sheet')),
      );
      await t.pumpAndSettle();
      expect(ttsCurrent.value, 'reader-page-Book-3',
          reason: 'PopupRoute 打开时不应停朗读（TtsStopOnRouteChange 已豁免）');
    });

    testWidgets('关闭普通页面仍由 TtsStopOnRouteChange 负责', (t) async {
      ttsCurrent.value = 'x';
      await t.pumpWidget(MaterialApp(
        navigatorObservers: [TtsStopOnRouteChange(), TtsStopOnSheetClose()],
        home: const Scaffold(body: Text('base')),
      ));
      await t.pumpAndSettle();
      ttsCurrent.value = 'x';
      Navigator.of(t.element(find.text('base'))).push(
        MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('second'))),
      );
      await t.pumpAndSettle();
      expect(ttsCurrent.value, isNull, reason: '换页面必须停朗读');
    });
  });

  group('阅读器翻页即停', () {
    test('翻页路径（onPageChanged / _goto）都调用停止', () {
      final src = readFile('lib/screens/work_reader_screen.dart');
      // 统一入口必须存在，且内部真的调 ttsStop
      expect(src, contains('_stopSpeechIfPageChanged'));
      final i = src.indexOf('void _stopSpeechIfPageChanged(');
      expect(i, greaterThan(-1));
      final body = src.substring(i, src.indexOf('Future<void> _goto('));
      expect(body, contains('if (next == _page) return;'),
          reason: '页码没变就不该打断朗读');
      expect(body, contains('ttsStop()'));

      // 两条翻页路径都要接上
      final iPage = src.indexOf('onPageChanged: (i)');
      expect(iPage, greaterThan(-1));
      expect(src.substring(iPage, iPage + 400), contains('_stopSpeechIfPageChanged'));
      final iGoto = src.indexOf('Future<void> _goto(');
      expect(src.substring(iGoto, iGoto + 500), contains('_stopSpeechIfPageChanged'));
    });

    test('喇叭 id 带页码 → 翻页必须停（否则听到的和看到的对不上）', () {
      final src = readFile('lib/screens/work_reader_screen.dart');
      // 这条是本次缺陷的成因：id 随页码变化，旧 id 的朗读没人负责停
      expect(src, contains("'reader-page-\${widget.work}-\$_page'"));
    });
  });

  group('装配门禁：main.dart 真的挂了两个观察者', () {
    test('naviatorObservers 同时含换页停与弹层停', () {
      final src = readFile('lib/main.dart');
      expect(src, contains('TtsStopOnRouteChange()'));
      expect(src, contains('TtsStopOnSheetClose()'));
      final i = src.indexOf('navigatorObservers:');
      expect(i, greaterThan(-1));
      final line = src.substring(i, src.indexOf(']', i));
      expect(line, contains('TtsStopOnRouteChange()'));
      expect(line, contains('TtsStopOnSheetClose()'));
    });

    test('tts_autostop 里弹层规则只对 PopupRoute 生效', () {
      final src = readFile('lib/services/tts_autostop.dart');
      final i = src.indexOf('class TtsStopOnSheetClose');
      expect(i, greaterThan(-1));
      final body = src.substring(i, src.indexOf('class TtsAutoStopScope'));
      expect(body, contains('route is PopupRoute'));
      expect(body, contains('ttsStop()'));
      // 只挂 didPop：挂了 didPush 就会在打开弹层时误停
      expect(body, contains('void didPop'));
      expect(body, isNot(contains('void didPush')));
    });
  });
}
