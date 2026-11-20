// 「功能中心 → 关于」回归测试：入口存在、可进入、版本与字段如实展示。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/config/app_meta.dart';
import 'package:marxism_reader/screens/tools_screen.dart';
import 'package:marxism_reader/theme/app_theme.dart';

void main() {
  test('元信息口径：版本号有权威来源；仓库地址与署名已固定且可校验', () {
    expect(AppMeta.appName, '唯物 · 马哲精读');
    // 版本号本身不写死（改版本就报红没意义），只校验形态与两处同步，
    // 真正的同步门禁在 version_sync_test.dart。
    expect(AppMeta.clientVersion, matches(RegExp(r'^\d+\.\d+\.\d+\+\d+$')));
    expect(AppMeta.clientVersionLabel,
        contains(AppMeta.clientVersion.split('+').first));
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
    expect(AppMeta.licenseName, 'CC BY-NC 4.0');
    expect(AppMeta.licenseName, isNot('MIT'),
        reason: '项目已改为开源但禁止商用，许可名不能是 MIT');
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
    expect(find.textContaining(AppMeta.clientVersion.split('+').first), findsWidgets);
    expect(find.text('0.1.0-mvp（构建期导出 assets/offline）'), findsOneWidget);
    // 地址已固定：直接展示真实仓库、可复制、可跳转、可下载
    expect(find.textContaining('github.com/cstuffrogers/study-mlm-ai'),
        findsWidgets);
    expect(find.text('xxmz contributors'), findsOneWidget);
    expect(find.textContaining('CC BY-NC'), findsWidgets);
    expect(find.text('最新版本下载'), findsOneWidget);
    final openBtn = find.widgetWithText(OutlinedButton, '打开 GitHub');
    expect(openBtn, findsOneWidget);
    expect(tester.widget<OutlinedButton>(openBtn).onPressed, isNotNull);
    // D144：主按钮改成「检查更新」（应用内直接下载装包），
    // 「去下载页」退为次按钮 —— 两者都必须有回调，不能是死按钮。
    final updBtn = find.widgetWithText(FilledButton, '检查更新');
    expect(updBtn, findsOneWidget);
    expect(tester.widget<FilledButton>(updBtn).onPressed, isNotNull);
    final dlBtn = find.widgetWithText(OutlinedButton, '去下载页');
    expect(dlBtn, findsOneWidget);
    expect(tester.widget<OutlinedButton>(dlBtn).onPressed, isNotNull);
    // 地址不可在客户端改（不接受「自定义地址」入口），但使用说明必须有
    expect(find.text('自定义地址'), findsNothing);
    expect(find.text('查看软件使用说明'), findsOneWidget);
    // 关于页不再暴露「运营者信息未配置」这类待办提示
    expect(find.textContaining('运营者信息尚未配置'), findsNothing);
    // 合规入口：隐私政策 / 用户协议 / 免责声明 必须能从关于页直接打开
    expect(find.text('隐私政策 · 用户协议 · 免责声明'), findsOneWidget);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('地址固定不可在客户端修改（无编辑入口、无表单）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: const ToolsScreen(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();

    // 没有任何可改为任意地址的控件
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.textContaining('自定义'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    // 展示的一律是代码常量
    expect(find.textContaining(AppMeta.githubUrl), findsWidgets);

    await tester.binding.setSurfaceSize(null);
  });
}
