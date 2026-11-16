// 「功能中心 → 关于」回归测试：入口存在、可进入、版本与字段如实展示。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/config/app_meta.dart';
import 'package:marxism_reader/screens/tools_screen.dart';
import 'package:marxism_reader/theme/app_theme.dart';

void main() {
  test('元信息口径：版本号有权威来源；仓库地址与署名已固定且可校验', () {
    expect(AppMeta.appName, '唯物 · 马哲精读');
    expect(AppMeta.clientVersion, '1.2.1+10');
    expect(AppMeta.clientVersionLabel, contains('1.2.1'));
    expect(AppMeta.serverVersion, '0.1.0-mvp');
    // 仓库已上线：地址固定、必须是合法 URL、且指向真实仓库（不是 example 占位）
    expect(AppMeta.githubUrl, 'https://github.com/cstuffrogers/study-mlm-ai');
    expect(AppMeta.isValidUrl(AppMeta.githubUrl), isTrue);
    expect(AppMeta.githubUrl, isNot(contains('example')));
    // 下载页指向 GitHub Releases
    expect(AppMeta.releasesUrl, startsWith(AppMeta.githubUrl));
    expect(AppMeta.releasesUrl, contains('/releases'));
    expect(AppMeta.isValidUrl(AppMeta.releasesUrl), isTrue);
    // 署名与 LICENSE 一致
    expect(AppMeta.author, 'xxmz contributors');
    expect(AppMeta.licenseName, 'MIT');
    expect(AppMeta.isValidUrl(''), isFalse);
    expect(AppMeta.isValidUrl('github.com/owner/repo'), isFalse);
    expect(AppMeta.isValidUrl('https://example.com/placeholder'), isFalse);
  });

  testWidgets('功能中心有「关于」入口，点开后展示版本/项目地址/作者',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
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
    expect(find.textContaining('1.2.1'), findsWidgets);
    expect(find.text('0.1.0-mvp（构建期导出 assets/offline）'), findsOneWidget);
    // 地址已固定：直接展示真实仓库、可复制、可跳转、可下载
    expect(find.textContaining('github.com/cstuffrogers/study-mlm-ai'),
        findsWidgets);
    expect(find.text('xxmz contributors'), findsOneWidget);
    expect(find.textContaining('MIT'), findsWidgets);
    expect(find.text('最新版本下载'), findsOneWidget);
    final openBtn = find.widgetWithText(OutlinedButton, '打开 GitHub');
    expect(openBtn, findsOneWidget);
    expect(tester.widget<OutlinedButton>(openBtn).onPressed, isNotNull);
    final dlBtn = find.widgetWithText(FilledButton, '下载最新安卓版');
    expect(dlBtn, findsOneWidget);
    expect(tester.widget<FilledButton>(dlBtn).onPressed, isNotNull);
    // 有自定义入口与使用说明
    expect(find.text('自定义地址'), findsOneWidget);
    expect(find.text('查看软件使用说明'), findsOneWidget);
    // 合规入口：隐私政策 / 用户协议 / 免责声明 必须能从关于页直接打开
    expect(find.text('隐私政策 · 用户协议 · 免责声明'), findsOneWidget);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('自定义地址：改成本机覆盖值后仍生效（fork 场景）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: const ToolsScreen(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('自定义地址'));
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
