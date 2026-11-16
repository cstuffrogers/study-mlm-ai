// 延伸阅读卡片文案的 Markdown 清理（D110）
//
// 回归背景：`caution` 里写了 `**节选声明**` 这类强调标记，但卡片用普通 Text 渲染，
// 结果界面上直接露出两个星号。改成按 `**` 分段渲染 + 朗读前剥离。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:marxism_reader/screens/chapter_guide_screen.dart';

const _base = TextStyle(fontSize: 12);

void main() {
  group('extensionMarkupSpans', () {
    test('把 **强调** 拆成加粗片段，不带星号', () {
      final spans = extensionMarkupSpans('**节选声明**：本文系抽出成篇', _base);
      expect(spans.map((s) => s.text).join(), '节选声明：本文系抽出成篇');
      expect(spans.any((s) => s.text == '节选声明' && s.style?.fontWeight == FontWeight.w700),
          isTrue);
      expect(spans.map((s) => s.text).join().contains('*'), isFalse);
    });

    test('多处强调与前后正文都保留', () {
      final spans = extensionMarkupSpans('甲**乙**丙**丁**戊', _base);
      expect(spans.map((s) => s.text).join(), '甲乙丙丁戊');
      expect(spans.where((s) => s.style?.fontWeight == FontWeight.w700).length, 2);
    });

    test('没有标记时原样返回', () {
      final spans = extensionMarkupSpans('本篇为全文，无删节。', _base);
      expect(spans.length, 1);
      expect(spans.first.text, '本篇为全文，无删节。');
    });

    test('落单的 ** 不吞正文（宁可露出星号也不丢字）', () {
      final spans = extensionMarkupSpans('左**右', _base);
      expect(spans.map((s) => s.text).join(), '左**右');
    });
  });

  group('stripExtensionMarkup', () {
    test('朗读文本不念星号', () {
      expect(stripExtensionMarkup('**节选声明**：抽出成篇'), '节选声明：抽出成篇');
      expect(stripExtensionMarkup('**甲** 与 **乙**'), '甲 与 乙');
      expect(stripExtensionMarkup('无标记'), '无标记');
    });
  });
}
