// 分页引擎（纯逻辑，可单测）——把连续正文按「行」精确切分为多页。
// 用 TextPainter 逐行测量（真实行高，而非字号×行距估算），按可用高度累加，保证：
//   · 每页渲染高度不超过可视区（不溢出、不需滚动）
//   · 把所有页按序拼接 == 原文（不丢字、不重复）

import 'package:flutter/material.dart';

class ReaderPage {
  final String text; // 段间以 \n\n 分隔
  final List<int> paraIndexes; // 本页涉及的全局段落下标（升序去重）
  const ReaderPage(this.text, this.paraIndexes);
}

class TocEntry {
  final String title;
  final int page; // 0-based
  const TocEntry(this.title, this.page);
}

class ReaderDoc {
  final List<ReaderPage> pages;
  final List<TocEntry> toc;
  const ReaderDoc(this.pages, this.toc);
}

class _Line {
  final String text;
  final double height;
  const _Line(this.text, this.height);
}

class ReaderPaginator {
  static const double paraGap = 12; // 段间距（分页与渲染必须一致）
  static const double cushion = 16; // 底部安全余量
  // 渲染时每个段落块外层 Container 的左右/上下内边距；分页测量必须扣除，
  // 否则「测出来装得下」的最后一行会被容器下沿挤出可视区（只露上半截）。
  static const double blockPaddingH = 2;
  static const double blockPaddingV = 1;
  // 文本实际可用宽度 = 阅读器传入的内容宽度 - 每个段落块左右内边距。
  static double textWidth(double width) => width - blockPaddingH * 2;
  // 每个段落块在渲染时比纯文字行高多出的垂直开销（上下内边距）。
  static double blockOverhead() => blockPaddingV * 2;

  /// [textScaler] 必须与渲染侧一致：系统「字体大小/显示大小」放大后，
  /// 渲染出来的行比按 1.0 测出来的高，分页就会多塞一行，最后一行被裁掉
  /// （用户实报「原文页最后一行显示不全」）。实测 1.3 倍时**每一页**都溢出。
  static ReaderDoc paginate(
      {required List<String> paragraphs,
      required double width,
      required double height,
      required TextStyle style,
      TextScaler textScaler = TextScaler.noScaling}) {
    final usable = height - cushion;
    final measureWidth = textWidth(width);
    final pages = <ReaderPage>[];
    var buf = StringBuffer();
    final pars = <int>[];
    var curH = 0.0;

    void flush() {
      if (pars.isEmpty && buf.isEmpty) return;
      pages.add(ReaderPage(buf.toString(), List.of(pars)));
      buf = StringBuffer();
      pars.clear();
      curH = 0.0;
    }

    for (var i = 0; i < paragraphs.length; i++) {
      final text = paragraphs[i].replaceAll('\r', '').replaceAll('\n', '').trim();
      if (text.isEmpty) continue;
      final lines = _splitLines(text, measureWidth, style, textScaler);
      var idx = 0;
      while (idx < lines.length) {
        final needGap = pars.isNotEmpty;
        // 每个新段落块在渲染时额外占 blockOverhead()，段间另有 paraGap。
        final avail = usable - curH - blockOverhead() - (needGap ? paraGap : 0);
        // 贪心取「实际高度累加不超过可用高度」的整行
        var take = 0;
        var acc = 0.0;
        while (idx + take < lines.length) {
          final lh = lines[idx + take].height;
          if (acc + lh > avail) break;
          acc += lh;
          take++;
        }
        if (take == 0) {
          if (pars.isNotEmpty) {
            // 当前页已有内容，且连一行都放不下 → 先满页，换新页重排本段
            flush();
            continue;
          }
          // 空页仍放不下（超长单行）→ 至少放一行，避免死循环
          take = 1;
          acc = lines[idx].height;
        }
        final piece = lines.sublist(idx, idx + take).map((l) => l.text).join('');
        if (buf.isNotEmpty) buf.write('\n\n');
        buf.write(piece);
        if (pars.isEmpty || pars.last != i) pars.add(i);
        curH += blockOverhead() + (needGap ? paraGap : 0) + acc;
        idx += take;
        if (idx < lines.length) flush();
      }
    }
    flush();
    if (pages.isEmpty) pages.add(const ReaderPage('', []));

    // 目录：以「短标题类」段落（未以句末标点结尾、长度适中）作为章节锚点
    final toc = <TocEntry>[];
    for (var p = 0; p < pages.length; p++) {
      for (final pi in pages[p].paraIndexes) {
        final t = paragraphs[pi].replaceAll('\n', ' ').trim();
        if (t.isNotEmpty && t.length <= 32 && !t.endsWith('。') && !t.endsWith('，') && !t.endsWith('、') && !t.endsWith('：') && !t.endsWith('；')) {
          toc.add(TocEntry(t.length > 26 ? '${t.substring(0, 26)}…' : t, p));
        }
      }
    }
    if (toc.length < 2) {
      toc.clear();
      for (var p = 0; p < pages.length; p += 20) {
        toc.add(TocEntry('第 ${p + 1} 页', p));
      }
    }
    return ReaderDoc(pages, toc);
  }

  /// 把一段无换行文本按给定宽度切成若干「行」，并给出每行真实高度。
  static List<_Line> _splitLines(String text, double width, TextStyle style,
      [TextScaler textScaler = TextScaler.noScaling]) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: width);
    final metrics = tp.computeLineMetrics();
    final lines = <_Line>[];
    var prevEnd = 0;
    for (var ln = 0; ln < metrics.length; ln++) {
      final m = metrics[ln];
      final y = m.baseline - 2;
      var s = tp.getPositionForOffset(Offset(0, y)).offset;
      var e = tp.getPositionForOffset(Offset(width, y)).offset;
      if (s < prevEnd) s = prevEnd;
      if (e < s) e = s;
      if (ln == metrics.length - 1) e = text.length;
      s = s.clamp(0, text.length);
      e = e.clamp(0, text.length);
      lines.add(_Line(text.substring(s, e), m.height));
      prevEnd = e;
    }
    tp.dispose();
    if (lines.isEmpty) lines.add(_Line(text, style.fontSize! * style.height!));
    return lines;
  }
}
