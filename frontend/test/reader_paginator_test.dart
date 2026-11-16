import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/services/reader_paginator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const style = TextStyle(fontSize: 18, height: 1.9, fontFamily: 'Deng');

  /// 复现 `_AnnotatedPage` 的真实渲染高度：文本按实际可用宽度排版，
  /// 每个段落块外加上下内边距，块与块之间插入 paraGap。
  double renderedPageHeight(ReaderPage page, double width, TextStyle style) {
    final blocks = page.text.split('\n\n').where((b) => b.trim().isNotEmpty).toList();
    var h = 0.0;
    for (var b = 0; b < blocks.length; b++) {
      if (b > 0) h += ReaderPaginator.paraGap;
      final tp = TextPainter(
        text: TextSpan(text: blocks[b], style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: ReaderPaginator.textWidth(width));
      for (final m in tp.computeLineMetrics()) {
        h += m.height;
      }
      tp.dispose();
      h += ReaderPaginator.blockOverhead();
    }
    return h;
  }

  test('分页不丢字、不重复：所有页拼起来等于原文', () {
    final paras = List<String>.generate(40, (i) {
      return '这是第$i段。${'辩证唯物主义认为世界的本原是物质的，意识是物质的反映。' * (2 + i % 5)}';
    });
    final doc = ReaderPaginator.paginate(paragraphs: paras, width: 320, height: 480, style: style);

    expect(doc.pages.length, greaterThan(1), reason: '长文应被分成多页');

    // 原文（去换行、去空白）
    final original = paras.map((p) => p.replaceAll(RegExp(r'\s'), '')).join();
    // 分页后（各页去换行、去空白）
    final paged = doc.pages.map((p) => p.text.replaceAll(RegExp(r'\s'), '')).join();

    expect(paged, original, reason: '分页前后文本必须完全一致（不丢字、不重复）');
  });

  test('每页高度不超过可用高度（不溢出、不需滚动）', () {
    final paras = List<String>.generate(20, (i) => '第$i段${'内容内容内容内容内容内容内容内容内容内容' * (3 + i)}');
    const width = 300.0;
    const height = 420.0;
    final doc = ReaderPaginator.paginate(paragraphs: paras, width: width, height: height, style: style);

    final usable = height - ReaderPaginator.cushion;
    for (var i = 0; i < doc.pages.length; i++) {
      final h = renderedPageHeight(doc.pages[i], width, style);
      expect(h, lessThanOrEqualTo(usable + 0.5), reason: '第 $i 页渲染高度 $h 超过可用 $usable');
    }
  });

  test('回归：多个短段落块同页时，块内边距不会把最后一行挤出可视区', () {
    // 约 1280x800 浏览器的真实阅读区：21 段、每段 4 行，旧算法会造出
    // 5 个 block 的 670px 页面，超过 660px 预算，最后一行被裁掉上半截。
    final paras = <String>[
      '我们共产党人无论进行何项工作，有两个方法是必须采用的，一是一般和个别相结合，二是领导和群众相结合。这是一段用于测量的文字。',
      for (var i = 0; i < 20; i++)
        '第 $i 段。${'从群众中来，到群众中去，一般号召与个别指导相结合，领导骨干和广大群众相结合，调查研究，反对主观主义和官僚主义。' * 4}',
    ];
    const width = 1240.0;
    const height = 676.0;
    final doc = ReaderPaginator.paginate(paragraphs: paras, width: width, height: height, style: style);
    final usable = height - ReaderPaginator.cushion;

    expect(doc.pages.length, greaterThan(1), reason: '长文必须分页');
    for (var i = 0; i < doc.pages.length; i++) {
      final blocks = doc.pages[i].text.split('\n\n').where((b) => b.trim().isNotEmpty).toList();
      final h = renderedPageHeight(doc.pages[i], width, style);
      expect(
        h,
        lessThanOrEqualTo(usable + 0.5),
        reason: '第 $i 页 ${blocks.length} 个段落块渲染高度 $h 超过可用 $usable；最后一行会被裁切',
      );
    }

    final original = paras.map((p) => p.replaceAll(RegExp(r'\s'), '')).join();
    final paged = doc.pages.map((p) => p.text.replaceAll(RegExp(r'\s'), '')).join();
    expect(paged, original, reason: '扣除块内边距后仍不能丢字或重复');
  });

  test('目录非空', () {
    final paras = ['第一章 总论', '这是正文段落内容。' * 30, '第二章 分论', '更多正文。' * 30];
    final doc = ReaderPaginator.paginate(paragraphs: paras, width: 320, height: 400, style: style);
    expect(doc.toc, isNotEmpty);
  });

  test('空输入返回一页空页', () {
    final doc = ReaderPaginator.paginate(paragraphs: const [], width: 300, height: 400, style: style);
    expect(doc.pages.length, 1);
    expect(doc.pages.first.text, '');
  });
}
