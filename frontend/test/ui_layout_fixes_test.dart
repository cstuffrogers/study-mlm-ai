// D138 三个界面缺陷的永久门禁。
//
// ① 对话输入框被键盘挡住：浮窗挂在 Overlay 里，不参与 Scaffold 的
//    resizeToAvoidBottomInset，必须自己按 viewInsets 上移。
// ② 原文页最后一行显示不全：分页测量没带 textScaler，系统字号放大后每页都溢出。
// ③ 深入学习顶部大标题被红白人物像遮住：放宽头像（red1.png 706x463，116 高时宽 177），
//    旧实现只预留 104。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/services/reader_paginator.dart';
import 'package:marxism_reader/theme/app_theme.dart';
import 'package:marxism_reader/widgets/anim.dart';
import 'package:marxism_reader/widgets/author_art.dart';
import 'package:marxism_reader/widgets/floating_chat.dart';

// 注意：MediaQuery 必须放在 MaterialApp **里面**。WidgetsApp 会用
// MediaQuery.fromView 覆盖祖先的 MediaQuery，套在外面读不到 viewInsets。
Widget _chatHost({required Size screen, required double keyboard, Offset at = const Offset(16, 40)}) {
  return MaterialApp(
    theme: AppTheme.build(),
    home: MediaQuery(
      data: MediaQueryData(
        size: screen,
        viewInsets: EdgeInsets.only(bottom: keyboard),
      ),
      // 不能套 Scaffold：Scaffold 会按 resizeToAvoidBottomInset 把 body 的
      // viewInsets 吃掉（实测 body 里读到 0），而真实环境里浮窗挂在 Overlay 上、
      // 位于 Scaffold 之外，读到的是窗口真实 viewInsets。
      child: Stack(children: [
          FloatingChat(
            turns: const [],
            status: '已连接 · 释义',
            criticalReading: false,
            onToggleCritical: () {},
            onSend: (_) {},
            onClear: () {},
            onClose: () {},
            initialOffset: at,
            bounds: screen,
            size: const Size(348, 520),
          ),
      ]),
    ),
  );
}

void main() {
  const screen = Size(400, 800);

  group('① 键盘不挡输入框', () {
    testWidgets('键盘弹起后输入框完整落在键盘上方', (tester) async {
      await tester.binding.setSurfaceSize(screen);
      // 故意把浮窗初始位置放到最底，模拟用户拖到底部
      await tester.pumpWidget(_chatHost(screen: screen, keyboard: 0, at: const Offset(16, 260)));
      await tester.pump();
      final noKb = tester.getRect(find.byType(TextField));
      expect(noKb.bottom, lessThanOrEqualTo(screen.height));

      const keyboard = 320.0;
      await tester.pumpWidget(_chatHost(screen: screen, keyboard: keyboard, at: const Offset(16, 260)));
      await tester.pumpAndSettle();

      final input = tester.getRect(find.byType(TextField));
      final visibleBottom = screen.height - keyboard;
      expect(input.bottom, lessThanOrEqualTo(visibleBottom + 0.5),
          reason: '输入框被键盘挡住：bottom=${input.bottom} 键盘上沿=$visibleBottom');
      expect(input.height, greaterThan(20), reason: '输入框不能被压缩到看不见');
    });

    testWidgets('键盘弹起后浮窗整体仍完整贴屏内（不越界、不被压成负高）', (tester) async {
      await tester.binding.setSurfaceSize(screen);
      const keyboard = 340.0;
      await tester.pumpWidget(_chatHost(screen: screen, keyboard: keyboard, at: const Offset(16, 300)));
      await tester.pumpAndSettle();
      final panel = tester.getRect(find.byType(FloatingChat));
      expect(panel.top, greaterThanOrEqualTo(0));
      expect(panel.bottom, lessThanOrEqualTo(screen.height - keyboard + 0.5));
      expect(panel.height, greaterThanOrEqualTo(220));
      // 头部也在屏内（拖动条不能跑到屏幕外）
      expect(tester.getRect(find.byIcon(Icons.drag_indicator)).top, greaterThanOrEqualTo(0));
    });

    testWidgets('键盘收起后回到用户拖到的位置', (tester) async {
      await tester.binding.setSurfaceSize(screen);
      await tester.pumpWidget(_chatHost(screen: screen, keyboard: 0, at: const Offset(16, 120)));
      await tester.pumpAndSettle();
      final before = tester.getRect(find.byType(FloatingChat));
      await tester.pumpWidget(_chatHost(screen: screen, keyboard: 320, at: const Offset(16, 120)));
      await tester.pumpAndSettle();
      final during = tester.getRect(find.byType(FloatingChat));
      expect(during.top, lessThan(before.top), reason: '键盘弹起要上移');
      await tester.pumpWidget(_chatHost(screen: screen, keyboard: 0, at: const Offset(16, 120)));
      await tester.pumpAndSettle();
      final after = tester.getRect(find.byType(FloatingChat));
      expect(after.top, closeTo(before.top, 0.5), reason: '收起键盘应回到原位');
    });
  });

  group('③ 头像不压住大标题', () {
    // MediaQuery 放在 MaterialApp 里面，否则 textScaler 会被 WidgetsApp 换成 1.0
    Widget header({required double artHeight, TextScaler scaler = TextScaler.noScaling}) {
      return MaterialApp(
        theme: AppTheme.build(),
        home: MediaQuery(
          data: MediaQueryData(size: const Size(360, 800), textScaler: scaler),
          child: Scaffold(
            body: GradientHeader(
              title: '马列毛思想AI伴读',
              subtitle: '先选学习路线，再选起始章节',
              art: AuthorArt(asset: kHomeArt, height: artHeight),
              artWidth: AuthorArt.widthFor(asset: kHomeArt, height: artHeight),
            ),
          ),
        ),
      );
    }

    test('宽高比与资源真实像素一致（red1 是横向横幅图）', () {
      expect(AuthorArt.widthFor(asset: kHomeArt, height: 116), closeTo(116 * 706 / 463, 0.01));
      expect(AuthorArt.widthFor(asset: 'pic/red/red6.png', height: 100), closeTo(75, 0.01));
      // 未知资源按竖版人像中位比例（0.85）预留，不至于把宽度算成 0
      expect(AuthorArt.widthFor(asset: 'pic/red/nope.png', height: 100), closeTo(85, 0.01));
    });

    testWidgets('窄屏 360dp：标题右边界不进入头像矩形', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      await tester.pumpWidget(header(artHeight: 116));
      await tester.pump();
      final title = tester.getRect(find.text('马列毛思想AI伴读'));
      final art = tester.getRect(find.byType(AuthorArt));
      expect(title.right, lessThanOrEqualTo(art.left + 0.5),
          reason: '标题 ${title.right} 压到头像 ${art.left} 上了');
    });

    testWidgets('系统字号 1.3 倍：标题折行后仍不压头像', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      await tester.pumpWidget(header(artHeight: 116, scaler: const TextScaler.linear(1.3)));
      await tester.pump();
      final title = tester.getRect(find.text('马列毛思想AI伴读'));
      final art = tester.getRect(find.byType(AuthorArt));
      expect(title.right, lessThanOrEqualTo(art.left + 0.5));
    });
  });

  group('② 原文页最后一行不被裁', () {
    const style = TextStyle(fontSize: 18, height: 1.9, fontFamily: 'Deng');

    double rendered(ReaderPage page, double width, TextScaler scaler) {
      final blocks = page.text.split('\n\n').where((b) => b.trim().isNotEmpty).toList();
      var h = 0.0;
      for (var b = 0; b < blocks.length; b++) {
        if (b > 0) h += ReaderPaginator.paraGap;
        final tp = TextPainter(
          text: TextSpan(text: blocks[b], style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout(maxWidth: ReaderPaginator.textWidth(width));
        for (final m in tp.computeLineMetrics()) {
          h += m.height;
        }
        tp.dispose();
        h += ReaderPaginator.blockOverhead();
      }
      return h;
    }

    test('字号放大 1.3 倍时分页仍不溢出（修复前每页都溢出）', () {
      final paras = List<String>.generate(
          30, (i) => '第$i段。${'辩证唯物主义认为世界的本原是物质的，意识是物质的反映。' * (1 + i % 4)}');
      const width = 320.0;
      const height = 616.0;
      const scaler = TextScaler.linear(1.3);
      final doc = ReaderPaginator.paginate(
          paragraphs: paras, width: width, height: height, style: style, textScaler: scaler);
      final usable = height - ReaderPaginator.cushion;
      for (var i = 0; i < doc.pages.length; i++) {
        final h = rendered(doc.pages[i], width, scaler);
        expect(h, lessThanOrEqualTo(usable + 0.5),
            reason: '第 $i 页高 $h 超过可用 $usable（末行会被裁掉）');
      }
    });

    test('缩放后分页仍不丢字、不重复', () {
      final paras = List<String>.generate(12, (i) => '第$i段${'内容内容内容内容内容内容' * (2 + i)}');
      final doc = ReaderPaginator.paginate(
          paragraphs: paras,
          width: 300,
          height: 420,
          style: style,
          textScaler: const TextScaler.linear(1.5));
      final original = paras.map((p) => p.replaceAll(RegExp(r'\s'), '')).join();
      final paged = doc.pages.map((p) => p.text.replaceAll(RegExp(r'\s'), '')).join();
      expect(paged, original);
    });
  });
}
