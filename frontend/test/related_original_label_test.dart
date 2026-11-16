// 「相关原文」按钮上绝不能出现分片编号。
//
// 故障现象：按钮显示成「相关原文 CH-YZB-063」，用户不知道那串编码是什么，
// 也破坏了「界面不暴露内部编号」的红线。修法是在按钮文案出口处统一过滤。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/widgets/chat_markdown.dart';
import 'package:marxism_reader/widgets/chunk_tag.dart';
import 'package:marxism_reader/widgets/related_original_button.dart';

void main() {
  test('stripChunkCodes 删除裸编码与方括号编码', () {
    expect(stripChunkCodes('相关原文 CH-YZB-063'), '相关原文');
    expect(stripChunkCodes('相关原文 [CH-YZB-063]'), '相关原文');
    expect(stripChunkCodes('CH-YZB-063'), '');
    expect(stripChunkCodes('[GUIDE-abc] 相关原文'), '相关原文');
    expect(stripChunkCodes('《大众哲学》'), '《大众哲学》');
    expect(stripChunkCodes(''), '');
  });

  testWidgets('RelatedOriginalButton 只显示「相关原文」，不带编号', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: RelatedOriginalButton(
          chunkIds: ['CH-YZB-063'],
          label: '相关原文 CH-YZB-063',
        ),
      ),
    ));
    expect(find.text('相关原文'), findsOneWidget);
    expect(find.textContaining('CH-YZB'), findsNothing);
    expect(find.textContaining('CH-'), findsNothing);
  });

  testWidgets('ChunkTag 只显示「相关原文」，不带编号', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ChunkTag(chunkId: 'CH-YZB-063', label: '相关原文 CH-YZB-063'),
      ),
    ));
    expect(find.text('相关原文'), findsOneWidget);
    expect(find.textContaining('CH-'), findsNothing);
  });

  testWidgets('测试结果页的溯源按钮显示「溯源 原文分片」', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ChunkTag(chunkId: 'CH-DZ-018', label: '溯源 原文分片'),
      ),
    ));
    expect(find.text('溯源 原文分片'), findsOneWidget);
    expect(find.textContaining('CH-'), findsNothing);
  });

  testWidgets('AI 回答里的编号继续被剥离，按钮只剩一个', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          ChatMarkdown(text: '实践是对象性活动。[CH-YZB-063]'),
          RelatedOriginalButton(chunkIds: ['CH-YZB-063']),
        ]),
      ),
    ));
    expect(find.textContaining('CH-'), findsNothing);
    expect(find.text('相关原文'), findsOneWidget);
  });
}
