// D147 门禁：原文页「自动连续发声」不许回退。
//
// 用户要求（逐条落到断言）：
//  ① 原文页多一个自动连续发声按钮，点开弹三个选项：
//    当前页循环播放 / 从当前页播到结束 / 播完再整篇循环；
//  ② 念到下一页，页面要自动跳到下一页；
//  ③ 后台也能播，除非退出原文页才关声；
//  ④ 连续播放不要全文预生成，最多提前生成下一页的音频，防断档。
//
// ①的「念完念哪一页」是纯逻辑（nextAutoPage），直接断言；
// ②③④靠真实 widget 行为 + 源码接线核对 —— 语音通道无法在单测里真发声，
// 所以既断言行为，也钉住接线，避免「改了但没接上」。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marxism_reader/services/reader_autoplay.dart';
import 'package:marxism_reader/services/tts.dart';
import 'package:marxism_reader/services/tts_autostop.dart';

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

  setUp(() {
    ttsCurrent.value = null;
    ttsBackgroundKeepAlive.value = false;
    ttsSkipStopOnNextSheetClose = false;
  });

  tearDown(() {
    ttsBackgroundKeepAlive.value = false;
    ttsSkipStopOnNextSheetClose = false;
  });

  group('① 三个模式「念完这一页念哪一页」', () {
    test('当前页循环：永远返回自己', () {
      for (var p = 0; p < 5; p++) {
        expect(
          nextAutoPage(mode: ReaderAutoMode.pageLoop, current: p, pageCount: 5),
          p,
          reason: '第 $p 页读完应回到自己',
        );
      }
    });

    test('当前页播到结束：逐页前进，末页停（返回 null）', () {
      expect(nextAutoPage(mode: ReaderAutoMode.toEnd, current: 0, pageCount: 3), 1);
      expect(nextAutoPage(mode: ReaderAutoMode.toEnd, current: 1, pageCount: 3), 2);
      expect(nextAutoPage(mode: ReaderAutoMode.toEnd, current: 2, pageCount: 3), isNull,
          reason: '末页读完必须停，不能越界');
    });

    test('播完再整篇循环：末页回到第 0 页继续', () {
      expect(nextAutoPage(mode: ReaderAutoMode.bookLoop, current: 0, pageCount: 3), 1);
      expect(nextAutoPage(mode: ReaderAutoMode.bookLoop, current: 2, pageCount: 3), 0,
          reason: '末页读完要回卷到第一页');
    });

    test('单页书：循环模式仍在念，播到结束模式直接停', () {
      expect(nextAutoPage(mode: ReaderAutoMode.pageLoop, current: 0, pageCount: 1), 0);
      expect(nextAutoPage(mode: ReaderAutoMode.bookLoop, current: 0, pageCount: 1), 0);
      expect(nextAutoPage(mode: ReaderAutoMode.toEnd, current: 0, pageCount: 1), isNull);
    });

    test('页数异常与越界页号不崩、不念不存在的页', () {
      expect(nextAutoPage(mode: ReaderAutoMode.toEnd, current: 0, pageCount: 0), isNull);
      expect(nextAutoPage(mode: ReaderAutoMode.pageLoop, current: 0, pageCount: -1), isNull);
      // 越界的 current 先夹到合法区间，再按模式算
      expect(nextAutoPage(mode: ReaderAutoMode.toEnd, current: 99, pageCount: 3), isNull);
      expect(nextAutoPage(mode: ReaderAutoMode.bookLoop, current: 99, pageCount: 3), 0);
      expect(nextAutoPage(mode: ReaderAutoMode.pageLoop, current: -5, pageCount: 3), 0);
    });

    test('三种模式都写清了「念完会怎样」（弹层里要给人看）', () {
      expect(ReaderAutoMode.values.length, 3);
      for (final m in ReaderAutoMode.values) {
        expect(m.label.trim(), isNotEmpty);
        expect(m.hint.trim(), isNotEmpty);
        expect(m.short.trim(), isNotEmpty);
        expect(m.short.length, lessThanOrEqualTo(6),
            reason: '底部栏只有那么宽，短名太长会折行把底栏撞高');
      }
    });
  });

  group('③ 后台继续念（只要没退出原文页）', () {
    testWidgets('开着连续朗读时，切后台/息屏不停声', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: TtsAutoStopScope(child: Scaffold(body: Text('reading'))),
      ));
      ttsBackgroundKeepAlive.value = true;
      ttsCurrent.value = 'reader-auto-某书-3';

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      expect(ttsCurrent.value, 'reader-auto-某书-3',
          reason: '连续朗读要求后台继续念，不能被生命周期兜底停掉');

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await t.pump();
      expect(ttsCurrent.value, isNotNull);
    });

    testWidgets('关掉连续朗读后，切后台照旧必须停（不能留后门）', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: TtsAutoStopScope(child: Scaffold(body: Text('reading'))),
      ));
      ttsBackgroundKeepAlive.value = false;
      ttsCurrent.value = 'chunk-X';

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      expect(ttsCurrent.value, isNull, reason: '没开连续朗读时切后台必须停');
    });
  });

  group('① 弹层里选了模式 → 关弹层不许把刚起头的声音掐掉', () {
    testWidgets('一次性豁免生效：关弹层不停，且豁免用完即失效', (t) async {
      await t.pumpWidget(MaterialApp(
        navigatorObservers: [TtsStopOnSheetClose()],
        home: const Scaffold(body: Text('base')),
      ));
      final ctx = t.element(find.text('base'));

      // 第一次：带豁免关闭 —— 相当于「选了连续朗读模式」
      ttsCurrent.value = 'reader-auto-某书-0';
      ttsSkipStopOnNextSheetClose = true;
      showModalBottomSheet<void>(
        context: ctx,
        builder: (_) => const SizedBox(height: 100, child: Text('sheet-1')),
      );
      await t.pumpAndSettle();
      Navigator.of(t.element(find.text('sheet-1'))).pop();
      await t.pumpAndSettle();
      expect(ttsCurrent.value, 'reader-auto-某书-0',
          reason: '关弹层正是开始念的动作，不能被误伤');
      expect(ttsSkipStopOnNextSheetClose, isFalse, reason: '豁免是一次性的');

      // 第二次：没有豁免 —— 必须停
      showModalBottomSheet<void>(
        context: t.element(find.text('base')),
        builder: (_) => const SizedBox(height: 100, child: Text('sheet-2')),
      );
      await t.pumpAndSettle();
      Navigator.of(t.element(find.text('sheet-2'))).pop();
      await t.pumpAndSettle();
      expect(ttsCurrent.value, isNull, reason: '普通关弹层仍要停朗读');
    });
  });

  group('③ 连续朗读中开关弹层（目录/书签）不许打断', () {
    testWidgets('开着连续朗读时关掉弹层，声音继续', (t) async {
      await t.pumpWidget(MaterialApp(
        navigatorObservers: [TtsStopOnSheetClose()],
        home: const Scaffold(body: Text('base')),
      ));
      ttsBackgroundKeepAlive.value = true;
      ttsCurrent.value = 'reader-auto-某书-7';
      showModalBottomSheet<void>(
        context: t.element(find.text('base')),
        builder: (_) => const SizedBox(height: 100, child: Text('toc-sheet')),
      );
      await t.pumpAndSettle();
      Navigator.of(t.element(find.text('toc-sheet'))).pop();
      await t.pumpAndSettle();
      expect(ttsCurrent.value, 'reader-auto-某书-7',
          reason: '看一眼目录就回来，不该把正在念的书弄停');
    });

    testWidgets('没开连续朗读时，关弹层仍必停（原规则不变）', (t) async {
      await t.pumpWidget(MaterialApp(
        navigatorObservers: [TtsStopOnSheetClose()],
        home: const Scaffold(body: Text('base')),
      ));
      ttsCurrent.value = 'chunk-X';
      showModalBottomSheet<void>(
        context: t.element(find.text('base')),
        builder: (_) => const SizedBox(height: 100, child: Text('sheet-3')),
      );
      await t.pumpAndSettle();
      Navigator.of(t.element(find.text('sheet-3'))).pop();
      await t.pumpAndSettle();
      expect(ttsCurrent.value, isNull);
    });
  });

  group('②③④ 原文页接线（源码核对，防止改了没接上）', () {
    final src = readFile('lib/screens/work_reader_screen.dart');

    test('三个模式选项都是从 ReaderAutoMode 生成，不会只写死一个', () {
      expect(src, contains('ReaderAutoMode.values.map'));
      expect(src, contains('自动连续发声'));
      expect(src, contains('_startAuto('));
      expect(src, contains('nextAutoPage('));
    });

    test('② 念到下一页就把页面跳过去（jumpToPage，不用动画）', () {
      final body = slice(src, 'void _autoGoto(int page)', 'void _finishAuto(');
      expect(body, contains('jumpToPage'));
      expect(body, isNot(contains('animateToPage')),
          reason: '切后台/息屏不出帧，动画会停在半路，页码就对不上了');
      expect(body, contains('setState'), reason: '页码状态要立刻同步');
    });

    test('② 自动翻页不被「翻页即停」误伤，手动翻页则把朗读跟过去', () {
      final guard = slice(src, 'void _stopSpeechIfPageChanged(int next)', 'Future<void> _goto(');
      expect(guard, contains('_autoMode != null'),
          reason: '连续朗读中翻页不能掐声');

      final changed = slice(src, 'onPageChanged: (i) {', 'itemBuilder:');
      expect(changed, contains('_autoMode != null && i != _autoPage'),
          reason: '手动滑页要把朗读跟到新的一页');

      final gotoBody = slice(src, 'Future<void> _goto(int page)', 'void _setFont(');
      expect(gotoBody, contains('_autoSpeak(p)'),
          reason: '按钮翻页同样要跟着念新的一页');
    });

    test('③ 退出原文页（dispose）才收声，并复位后台开关', () {
      final body = slice(src, 'void dispose() {', '_chatEntry?.remove()');
      expect(body, contains('ttsCurrent.removeListener'));
      expect(body, contains('ttsBackgroundKeepAlive.value = false'),
          reason: '不复位就会留下「切后台也不停」的后门');
      expect(body, contains('ttsStop()'));
    });

    test('③ 开始连续朗读时打开后台保活，结束时关掉', () {
      final start = slice(src, 'void _startAuto(ReaderAutoMode mode)', 'void _autoSpeak(');
      expect(start, contains('ttsBackgroundKeepAlive.value = true'));
      final finish = slice(src, 'void _finishAuto(', 'void _onTtsChanged(');
      expect(finish, contains('ttsBackgroundKeepAlive.value = false'));
      expect(finish, contains('ttsStop()'));
    });

    test('④ 只提前生成下一页，且是「一段」不是整篇', () {
      final body = slice(src, 'void _autoSpeak(int page)', 'void _onAutoPageDone(');
      expect(body, contains('ttsPrefetch(_pageSpeechAt(next))'),
          reason: '换页前要预热下一页，防断档');
      expect(body, isNot(contains('for (')),
          reason: '不许把余下所有页都送去合成');

      // 预热只取一段：ttsPrefetch 内部只合成首段（_splitForTts(...).first）
      final web = readFile('lib/services/tts_web.dart');
      final prefetch = slice(web, 'void ttsPrefetch(', 'List<String> _splitForTts(');
      expect(prefetch, contains('segs.first'),
          reason: '最多只提前生成一段，不许全文合成');
      expect(prefetch, contains('_warm.length > 3'), reason: '预热缓存要封顶，别越拉越多');
    });

    test('④ 念完一页靠 onDone 接下一页，不靠定时器轮询', () {
      final body = slice(src, 'void _onAutoPageDone()', 'void _autoGoto(');
      expect(body, contains('nextAutoPage('));
      expect(body, contains('_autoSpeak(next)'));
      expect(body, isNot(contains('Timer(')), reason: '性能红线：不留常驻定时器');
      expect(body, isNot(contains('.repeat()')));
    });
  });

  group('⑤ 开关连续朗读不许把排版搞乱（用户实报：本页带了上一页几行）', () {
    // 机理：分页宽度/高度来自 `_buildDoc(size)`，而 size 来自 PageView 外的
    // LayoutBuilder。只要开关连续朗读改变了底栏高度，PageView 可视高度就变，
    // `_docSize != size` 触发重新分页 → 每页装的行数变少 → 当前页顶部
    // 冒出「上一页的尾巴」。所以朗读状态只能长在底栏里面，不能新增一条。
    final src = readFile('lib/screens/work_reader_screen.dart');

    test('底栏不能再包一层去插状态条（否则高度一变就重新分页）', () {
      final nav = slice(src, 'bottomNavigationBar:', 'Widget _errorView()');
      expect(nav, contains('_buildBottomBar()'));
      expect(nav, isNot(contains('Column(')),
          reason: '底栏外面再套 Column 加上状态条，就会把 PageView 撞矮');
      expect(nav, isNot(contains('_autoStrip')),
          reason: '旧做法就是这条，别回来');
    });

    test('连续朗读的状态位只能替掉底栏里原有的按钮，不能另占一行', () {
      final bar = slice(src, 'Widget _buildBottomBar()', 'Widget _selectionFab()');
      expect(bar, contains('if (_autoMode != null)'));
      expect(bar, contains('_autoInlineStatus()'));
      expect(bar, contains('SafeArea('), reason: '底栏自身的结构不能为了状态位改');

      final inline = slice(src, 'Widget _autoInlineStatus()', 'Widget _errorView()');
      expect(inline, isNot(contains('SizedBox(height')), reason: '不能加竖向间距');
      expect(inline, isNot(contains('Container(')), reason: '不能自己画一块底色条');
      expect(inline, isNot(contains('SafeArea(')), reason: '不能另起一层安全区');
    });

    test('底栏两种状态的高度锚点一致（前后翻页按钮两种状态都在）', () {
      final bar = slice(src, 'Widget _buildBottomBar()', 'Widget _selectionFab()');
      // 行高由最高的子件决定：左右翻页的 IconButton 在两种状态下都在，行高不变
      final before = bar.split('if (_autoMode != null)').first;
      final after = bar.split('if (_autoMode != null)').last;
      for (final seg in [before, after]) {
        expect(seg.contains('IconButton('), isTrue,
            reason: '两种状态都得有 IconButton 撑着高度');
      }
    });

    test('排版只跟尺寸/字号缩放走，不跟朗读状态走', () {
      final body = slice(src, 'Future<void> _buildDoc(Size size)', '/// 翻页即停朗读。');
      // 分页入参里没有朗读相关的东西
      final call = slice(body, 'ReaderPaginator.paginate(', ';');
      expect(call, isNot(contains('_auto')));
      // _autoMode 只在分页完成、setState 之后出现（重新定位朗读），
      // 不能在分页之前就掺进去 -> 分页永远只由尺寸决定
      final beforeFirstAuto = body.split('_autoMode').first;
      expect(beforeFirstAuto, contains('ReaderPaginator'),
          reason: '分页必须在任何 _autoMode 判断之前完成');
      expect(body, contains('_autoSpeak(target)'), reason: '重排后要跟到新的页号');
    });
  });

  group('④ 朗读门面三个平台的签名一致', () {
    test('web/native/stub 都支持 onDone 与 ttsPrefetch', () {
      for (final f in [
        'lib/services/tts_web.dart',
        'lib/services/tts_native.dart',
        'lib/services/tts_stub.dart',
      ]) {
        final s = readFile(f);
        expect(s, contains('void Function()? onDone'), reason: '$f 缺 onDone');
        expect(s, contains('void ttsPrefetch(String text'), reason: '$f 缺 ttsPrefetch');
      }
    });

    test('web 端 onDone 在整段念完时回调一次（不是每段都回调）', () {
      final web = readFile('lib/services/tts_web.dart');
      final chain = slice(web, 'void _finishChain()', 'void _playSegment()');
      expect(chain, contains('_segOnDone = null'), reason: '回调要只取一次');
      expect(chain, contains('done?.call()'));
      // 中断/停止必须清掉回调，否则停止后还会往下念
      final stop = slice(web, 'void ttsStop()', 'void ttsPrefetch(');
      expect(stop, contains('_segOnDone = null'));
    });
  });
}
