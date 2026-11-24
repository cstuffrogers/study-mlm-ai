// D165 门禁：版本更新说明（changelog）——「本次更新内容」必须与真实版本对得上，
// 且升级后第一次启动只弹一次。
//
// 钉住这几件事：
//  ① 最新一条说明的版本号 == AppMeta.clientVersion（发版忘了写说明 → 直接报红）；
//  ② 说明本身自洽：版本唯一、从新到旧、日期 YYYY-MM-DD、每条分组都有内容；
//  ③ 跨版本升级要把中间几版一并给用户看（他确实错过了），旧包不显示「未来版本」；
//  ④ 弹框时机：全新安装不弹、老用户升级弹一次、看过之后不再弹；
//  ⑤ 「关于」页能主动看到本版说明（页面入口，不靠启动弹框）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/config/app_meta.dart';
import 'package:marxism_reader/config/changelog.dart';
import 'package:marxism_reader/offline/local_store_keys.dart';
import 'package:marxism_reader/screens/about_screen.dart';
import 'package:marxism_reader/services/changelog_seen.dart';
import 'package:marxism_reader/theme/app_theme.dart';
import 'package:marxism_reader/widgets/whats_new_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('① 发版必须写更新说明', () {
    test('最新一条的版本号 == 客户端版本（pubspec 同步的那一个）', () {
      expect(kChangelog, isNotEmpty);
      final top = kChangelog.first;
      expect(top.version, normalizeVersion(AppMeta.clientVersion),
          reason: '发了 v${normalizeVersion(AppMeta.clientVersion)} 却没在 '
              'lib/config/changelog.dart 里补一条更新说明');
    });

    test('当前版本一定能查到说明（启动弹框依赖它）', () {
      final cur = currentChangelog;
      expect(cur, isNotNull);
      expect(cur!.version, normalizeVersion(AppMeta.clientVersion));
      expect(cur.itemCount, greaterThan(0));
    });
  });

  group('② 说明内容自洽', () {
    test('版本号唯一、日期格式正确、三段式', () {
      final seen = <String>{};
      for (final e in kChangelog) {
        expect(e.version, matches(RegExp(r'^\d+\.\d+\.\d+$')),
            reason: '${e.version} 要写成三段式、不带 v / 构建号');
        expect(seen.add(e.version), isTrue, reason: '${e.version} 重复登记');
        expect(e.date, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
            reason: '${e.version} 的日期要写成 YYYY-MM-DD');
      }
    });

    test('从新到旧排列，且每组分组成员都非空', () {
      for (var i = 1; i < kChangelog.length; i++) {
        expect(isNewerVersion(kChangelog[i - 1].version, kChangelog[i].version),
            isTrue,
            reason: '${kChangelog[i - 1].version} 应比 ${kChangelog[i].version} 新'
                '（kChangelog 约定最新在前）');
      }
      for (final e in kChangelog) {
        expect(e.groups, isNotEmpty, reason: '${e.version} 没有任何分组');
        for (final g in e.groups) {
          expect(g.title.trim(), isNotEmpty);
          expect(g.items, isNotEmpty, reason: '${e.version} 的「${g.title}」是空的');
          for (final it in g.items) {
            expect(it.trim().length, greaterThan(8), reason: '文案太短说不清：$it');
          }
        }
      }
    });

    test('文案写给用户看：不出现代码路径 / 文件名 / 提交信息口吻', () {
      for (final e in kChangelog) {
        for (final g in e.groups) {
          for (final it in g.items) {
            expect(it, isNot(contains('.dart')), reason: it);
            expect(it, isNot(contains('.kt')), reason: it);
            expect(it, isNot(contains('lib/')), reason: it);
            expect(it, isNot(contains('commit')), reason: it);
          }
        }
      }
    });
  });

  group('③ 版本比较与跨版本展示', () {
    test('归一化能吃下 v 前缀与构建号', () {
      expect(normalizeVersion('v1.4.19'), '1.4.19');
      expect(normalizeVersion('1.4.19+40'), '1.4.19');
      expect(normalizeVersion(' V1.4.19+40 '), '1.4.19');
      expect(changelogFor('1.4.19+40')?.version, '1.4.19');
      expect(changelogFor('v1.4.16')?.version, '1.4.16');
      expect(changelogFor('9.9.9'), isNull);
    });

    test('isNewerVersion 按数字段比，不按字符串比', () {
      expect(isNewerVersion('1.4.19', '1.4.9'), isTrue);
      expect(isNewerVersion('1.4.9', '1.4.19'), isFalse);
      expect(isNewerVersion('1.5', '1.4.19'), isTrue);
      expect(isNewerVersion('1.4.19', '1.4.19'), isFalse);
    });

    test('跨版本升级：把 seen 之后的几版都给出来（新→旧）', () {
      final list = changelogSince('1.4.16');
      expect(list, isNotEmpty);
      expect(list.first.version, normalizeVersion(AppMeta.clientVersion));
      expect(list.map((e) => e.version), isNot(contains('1.4.16')),
          reason: '已看过的版本不再重复展示');
      expect(list.map((e) => e.version), contains('1.4.18'));
    });

    test('没见过任何版本（老版本升上来）时只给当前这一版', () {
      final list = changelogSince(null);
      expect(list.length, 1);
      expect(list.single.version, normalizeVersion(AppMeta.clientVersion));
    });
  });

  group('④ 启动弹框只看一次', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> pumpHost(WidgetTester tester, {required bool fresh}) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    maybeShowWhatsNew(ctx, freshInstall: fresh),
                child: const Text('启动'),
              ),
            ),
          ),
        ),
      ));
    }

    testWidgets('全新安装：不弹「本次更新内容」，只登记一次', (tester) async {
      await pumpHost(tester, fresh: true);
      await tester.tap(find.text('启动'));
      await tester.pumpAndSettle();
      expect(find.text('本次更新内容'), findsNothing,
          reason: '刚装上的人没有「更新」可言，别一开屏就弹框');
      expect(await ChangelogSeen.read(), normalizeVersion(AppMeta.clientVersion));
    });

    testWidgets('老用户升级：弹出本版说明并登记', (tester) async {
      await pumpHost(tester, fresh: false);
      await tester.tap(find.text('启动'));
      await tester.pumpAndSettle();
      expect(find.text('本次更新内容'), findsOneWidget);
      expect(find.text('v${normalizeVersion(AppMeta.clientVersion)}'),
          findsWidgets);
      // 关闭即登记
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.text('本次更新内容'), findsNothing);
      expect(await ChangelogSeen.read(), normalizeVersion(AppMeta.clientVersion));
    });

    testWidgets('已经看过这一版：再启动不再弹', (tester) async {
      SharedPreferences.setMockInitialValues({
        LocalStoreKeys.changelogSeen: normalizeVersion(AppMeta.clientVersion),
      });
      await pumpHost(tester, fresh: false);
      await tester.tap(find.text('启动'));
      await tester.pumpAndSettle();
      expect(find.text('本次更新内容'), findsNothing);
    });

    testWidgets('跨版本升级：中间几版一并展示', (tester) async {
      SharedPreferences.setMockInitialValues(
          {LocalStoreKeys.changelogSeen: '1.4.16'});
      await pumpHost(tester, fresh: false);
      await tester.tap(find.text('启动'));
      await tester.pumpAndSettle();
      expect(find.textContaining('共'), findsWidgets);
      expect(find.text('v1.4.18'), findsOneWidget,
          reason: '跨过的版本也要告诉用户改了什么');
    });

    testWidgets('登记键写在 SharedPreferences（不污染学习数据）', (tester) async {
      await ChangelogSeen.markSeen('1.4.19+40');
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString(LocalStoreKeys.changelogSeen), '1.4.19');
      await ChangelogSeen.clear();
      expect(await ChangelogSeen.read(), isNull);
    });
  });

  group('⑤ 「关于」页能看到本版更新说明', () {
    testWidgets('展示更新说明卡片与本版条目，并能打开历史版本', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(900, 2400));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(),
        home: const AboutScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('更新说明'), findsOneWidget);
      expect(find.text('v${normalizeVersion(AppMeta.clientVersion)}'),
          findsWidgets);
      final cur = currentChangelog!;
      // 至少能看到本版的第一条文案（其余可能滚出视口）
      expect(find.textContaining(cur.groups.first.items.first.substring(0, 6)),
          findsWidgets);

      await tester.tap(find.text('历史版本'));
      await tester.pumpAndSettle();
      expect(find.text('更新说明'), findsWidgets, reason: '弹框标题');
      if (kChangelog.length > 1) {
        expect(find.text('v${kChangelog.last.version}'), findsWidgets,
            reason: '历史版本里应该有更旧的版本');
      }
    });
  });
}
