// 延伸阅读（扩展读物）渲染冒烟测试
// 校验：经典条目正常渲染；争议条目用【批判对象·非借鉴】包裹后渲染为标注框。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/widgets/chat_markdown.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('经典条目：Markdown 正文与要点渲染', (t) async {
    const md = '实践是认识的基础。\n\n- 真理的标准只能是社会的实践。\n- 感性认识与理性认识辩证统一。';
    await t.pumpWidget(_host(const ChatMarkdown(text: md, baseColor: Colors.black87)));
    await t.pumpAndSettle();
    expect(find.textContaining('实践是认识的基础'), findsOneWidget);
  });

  testWidgets('争议条目：包裹【批判对象·非借鉴】后渲染为标注框', (t) async {
    const md = '【批判对象·非借鉴】\n'
        '**『关于社会主义社会阶级斗争』的争议版本**（原教旨 MLM 文本）\n\n'
        '- 错误倾向一：把一定范围的阶级斗争扩大化。\n'
        '【/批判对象】';
    await t.pumpWidget(_host(const ChatMarkdown(text: md, baseColor: Colors.black87)));
    await t.pumpAndSettle();
    // 标注框标题存在
    expect(find.text('批判对象 · 非借鉴'), findsOneWidget);
    // 框内正文可见（未当纯文本，也已去掉标记符号）
    expect(find.textContaining('错误倾向一'), findsOneWidget);
  });

  test('toSpeech 去除 Markdown/公式标记', () {
    final s = ChatMarkdown.toSpeech(r'## 标题 **加粗** 与 $x^2$ 以及 `code`');
    expect(s.contains('##'), false);
    expect(s.contains('**'), false);
    expect(s.contains('\$'), false);
    expect(s.contains('标题'), true);
  });
}
