// 「功能中心 → 关于」回归测试：入口存在、可进入、版本与字段如实展示。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/config/app_meta.dart';
import 'package:marxism_reader/screens/tools_screen.dart';
import 'package:marxism_reader/theme/app_theme.dart';

void main() {
  test('元信息口径：版本号有权威来源；仓库/作者未配置时不伪造', () {
    expect(AppMeta.appName, '唯物 · 马哲精读');
    expect(AppMeta.clientVersion, '1.2.0+9');
    expect(AppMeta.clientVersionLabel, contains('1.2.0'));
    expect(AppMeta.serverVersion, '0.1.0-mvp');
    expect(AppMeta.githubUrl, isEmpty);
    expect(AppMeta.author, isEmpty);
    expect(AppMeta.isValidUrl(''), isFalse);
    expect(AppMeta.isValidUrl('https://github.com/owner/repo'), isTrue);
    expect(AppMeta.isValidUrl('github.com/owner/repo'), isFalse);
    expect(AppMeta.isValidUrl('https://example.com/placeholder'), isFalse);
  });

  testWidgets('功能中心有「关于」入口，点开后展示版本/项目地址/作者',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: const ToolsScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('关于'), findsOneWidget);
    expect(find.textContaining('软件版本'), findsOneWidget);

    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();

    expect(find.text('关于'), findsOneWidget); // AppBar
    expect(find.text('软件信息'), findsOneWidget);
    expect(find.text('项目地址与作者'), findsOneWidget);
    expect(find.text('唯物 · 马哲精读'), findsWidgets); // Hero 卡 + 软件信息行
    expect(find.textContaining('1.2.0'), findsWidgets);
    expect(find.text('0.1.0-mvp（构建期导出 assets/offline）'), findsOneWidget);
    // 未配置时如实标注，且不显示可点击的假 GitHub 链接
    expect(find.text('未配置'), findsOneWidget);
    expect(find.text('未声明'), findsOneWidget);
    final openBtn = find.widgetWithText(OutlinedButton, '打开 GitHub');
    expect(openBtn, findsOneWidget);
    expect(tester.widget<OutlinedButton>(openBtn).onPressed, isNull);
    // 有编辑入口与使用说明
    expect(find.text('编辑项目信息'), findsOneWidget);
    expect(find.text('查看软件使用说明'), findsOneWidget);
    // 合规入口：隐私政策 / 用户协议 / 免责声明 必须能从关于页直接打开
    expect(find.text('隐私政策 · 用户协议 · 免责声明'), findsOneWidget);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('编辑项目信息：填真实 GitHub 与作者后，打开按钮启用', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: const ToolsScreen(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('编辑项目信息'));
    await tester.pumpAndSettle();
    expect(find.text('GitHub 仓库地址'), findsOneWidget);
    expect(find.text('作者 / 组织 / 版权'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'GitHub 仓库地址'),
        'https://github.com/example-owner/xxmz');
    await tester.enterText(
        find.widgetWithText(TextFormField, '作者 / 组织 / 版权'), '测试作者');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('example-owner/xxmz'), findsWidgets);
    expect(find.text('测试作者'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '打开 GitHub')).onPressed, isNotNull);

    await tester.binding.setSurfaceSize(null);
  });
}
