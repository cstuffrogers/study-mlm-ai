// 使用说明弹窗回归测试：防止「批判性阅读」按钮说明再次从引导里缺失，
// 并锁住「AI 回答不再暴露内部原文编码」这一交互约定。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/widgets/guide_dialog.dart';

void main() {
  testWidgets('引导说明包含批判性阅读按钮的位置/开启方式/作用/关闭方式',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) => ElevatedButton(
          onPressed: () => showUsageGuide(ctx),
          child: const Text('打开引导'),
        )),
      ),
    ));
    await tester.tap(find.text('打开引导'));
    await tester.pumpAndSettle();

    expect(find.text('软件使用说明'), findsOneWidget);
    // 有专门一节
    expect(find.text('四、对话浮窗里的「批判性阅读」按钮　【重点】'), findsOneWidget);
    // 位置、状态、生效时机、批判姿态标记、与辩难的区别、关闭方式
    expect(find.textContaining('顶部标题栏'), findsOneWidget);
    expect(find.textContaining('红色高亮为「开」'), findsOneWidget);
    expect(find.textContaining('再发送的问题才会'), findsOneWidget);
    expect(find.textContaining('【批判对象·非借鉴】'), findsOneWidget);
    expect(find.textContaining('与「辩难」模式的区别'), findsOneWidget);
    expect(find.textContaining('再点一次按钮关掉'), findsOneWidget);
    // 配置一节也说明真实模型为何会回退 Mock，避免用户误判为「没配上」
    expect(find.textContaining('关闭思维链'), findsOneWidget);
    // 新口径：只保留「相关原文」按钮，不教用户认分片编号
    expect(find.textContaining('不显示任何内部编号'), findsOneWidget);
    expect(find.textContaining('相关原文'), findsWidgets);
    expect(find.textContaining('CH-ME-TH-02-1'), findsNothing);
    expect(find.textContaining('带下划线的可点'), findsNothing);

    await tester.binding.setSurfaceSize(null);
  });
}
