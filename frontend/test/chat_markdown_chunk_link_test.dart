// AI 回答「内部原文编码不外显」回归测试。
//
// 旧版本把 `[CH-...]` 渲染成带编码的可点链接；新口径：正文、朗读、预览都
// 不显示编码，只在气泡层按提取到的 id 提供一个「相关原文」按钮。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/theme/app_theme.dart';
import 'package:marxism_reader/widgets/chat_markdown.dart';

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.build(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  test('href 解析工具保留兼容：只认 chunk: 协议，且能还原分片 id', () {
    expect(isChunkTagHref('chunk:CH-ME-TH-02-1'), isTrue);
    expect(isChunkTagHref('chunk:CH-SHJ-102'), isTrue);
    expect(isChunkTagHref('https://example.com'), isFalse);
    expect(isChunkTagHref(null), isFalse);
    expect(chunkIdFromHref('chunk:CH-ME-TH-02-1'), 'CH-ME-TH-02-1');
  });

  test('内部编码提取：去重保序，供统一「相关原文」入口取数', () {
    const src = '甲[CH-ME-TH-02-1] 乙[GUIDE-A-1] 丙[CH-ME-TH-02-1]';
    expect(ChatMarkdown.chunkIdsIn(src), ['CH-ME-TH-02-1', 'GUIDE-A-1']);
    expect(ChatMarkdown.stripChunkTags(src), '甲 乙 丙');
  });

  testWidgets('AI 回答里的 [CH-...] 标记不再渲染成分片编码链接', (t) async {
    const md = '实践是物质活动。[CH-ME-TH-02-1] 见[备注]与[CH-SHJ-102]。';
    await t.pumpWidget(_host(const ChatMarkdown(text: md, baseColor: Colors.black87)));
    await t.pumpAndSettle();

    // 正文干净：普通中括号保留，内部编码一个都不出现。
    expect(find.textContaining('实践是物质活动'), findsWidgets);
    expect(find.textContaining('[备注]'), findsWidgets);
    expect(find.textContaining('CH-ME-TH-02-1'), findsNothing);
    expect(find.textContaining('CH-SHJ-102'), findsNothing);
    expect(find.textContaining('GUIDE-'), findsNothing);
  });

  test('朗读/折叠预览不念溯源编号，但保留普通中括号', () {
    const src = '实践是物质活动。[CH-ME-TH-02-1] 见[备注]与[CH-SHJ-102]。';
    final speech = ChatMarkdown.toSpeech(src);
    expect(speech.contains('CH-ME-TH-02-1'), isFalse);
    expect(speech.contains('CH-SHJ-102'), isFalse);
    expect(speech.contains('[备注]'), isTrue);
    final preview = ChatMarkdown.plainPreview(src, maxLen: 200);
    expect(preview.contains('CH-ME-TH-02-1'), isFalse);
    expect(preview.contains('[备注]'), isTrue);
  });

  testWidgets('普通中括号文本不被误判为分片链接', (t) async {
    const md = '这是普通说明[备注]，以及一个外部链接 [示例](https://example.com)。';
    await t.pumpWidget(_host(const ChatMarkdown(text: md, baseColor: Colors.black87)));
    await t.pumpAndSettle();
    expect(find.textContaining('这是普通说明'), findsWidgets);
  });
}
