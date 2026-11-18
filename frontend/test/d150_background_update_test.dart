// D150 门禁：更新提示的时机 + 后台下载 + 下完问「装不装」。
//
// 用户口径（原话）：「有新版本，第一次打开 app 时弹出更新提示（app 已经在后台时
// 不提示，第一次打开 app 会自动检查更新），点下载更新后在后台下载，
// 下载完毕提示是否安装。」
//
// 拆成四条铁律钉住：
//  ① 冷启动只查一次、只弹一次；从后台回来不重查（不能一解锁就跳框）；
//  ② 查的过程中人切走了就不弹，等他下次冷启动；
//  ③ 点「下载更新」= 关框 + 后台下载，可以继续读书；重复点不会拉两遍 73MB；
//  ④ 下完单独问「现在装吗」，装不装由用户点（不做静默安装）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:marxism_reader/services/app_update.dart';
import 'package:marxism_reader/services/update_download.dart';

String readFile(String path) => File(path).readAsStringSync();

String slice(String src, String from, String to) {
  final i = src.indexOf(from);
  // 这里会在 group 体（非 test 体）里被调用，不能用 expect（会 OutsideTestException）
  if (i < 0) throw StateError('找不到锚点：$from');
  final j = src.indexOf(to, i);
  return j < 0 ? src.substring(i) : src.substring(i, j);
}

ReleaseInfo _info(String version) => ReleaseInfo(
      version: version,
      tagName: 'v$version',
      apkUrl: 'https://example.com/xxmz-$version.apk',
      apkSize: 76579044,
      notes: '- 修复若干问题',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => resetUpdateDownload(deleteFile: true));

  group('① 冷启动只查一次、只弹一次', () {
    final main = readFile('lib/main.dart');

    test('进程内有「只查一次」的闸门', () {
      expect(main, contains('_launchUpdateChecked'));
      final fn = slice(main, 'Future<void> _checkUpdateAfterLaunch()', '/// 本进程是否已经查过更新');
      expect(fn, contains('if (_launchUpdateChecked) return;'),
          reason: '没有闸门就会每次回前台都查一遍、反复弹框');
      expect(fn, contains('_launchUpdateChecked = true;'));
    });

    test('冷启动才查：后台/切页回来自查的重入点不存在', () {
      // 只有「定义 + 首帧回调里那一次调用」；lifecycle 回调里不许再触发检查
      expect(RegExp(r'_checkUpdateAfterLaunch\(\)').allMatches(main).length, 2,
          reason: '除定义外只应在首帧回调里出现一次调用');
      final startup = slice(main, 'addPostFrameCallback', '}');
      expect(startup, contains('_checkUpdateAfterLaunch'));
      final tracker = slice(main, 'class _LifecycleTracker', 'final _LifecycleTracker');
      expect(tracker, isNot(contains('checkUpdate')));
      expect(tracker, isNot(contains('_checkUpdateAfterLaunch')));
    });

    test('必须先把观察者挂上，才有前后台可判断', () {
      expect(main, contains('addObserver(_lifecycle)'));
      expect(main, contains('didChangeAppLifecycleState'));
    });
  });

  group('② 人切走了就不弹', () {
    final main = readFile('lib/main.dart');
    final fn = slice(main, 'Future<void> _checkUpdateAfterLaunch()', '/// 本进程是否已经查过更新');

    test('弹框前先判前台状态', () {
      final iGuard = fn.indexOf('_lifecycle.inForeground');
      final iShow = fn.indexOf('showUpdateDialog');
      expect(iGuard, greaterThan(-1), reason: '必须判「现在是不是前台」');
      expect(iShow, greaterThan(iGuard), reason: '判断必须在弹框之前');
    });

    test('前台口径：null（首帧还没回调）与 inactive 都算前台', () {
      final tracker = slice(main, 'bool get inForeground', 'final _LifecycleTracker');
      expect(tracker, contains('state == null'));
      expect(tracker, contains('AppLifecycleState.resumed'));
      expect(tracker, contains('AppLifecycleState.inactive'));
      // paused/hidden/detached 不能算前台
      expect(tracker, isNot(contains('AppLifecycleState.paused')));
    });
  });

  group('③ 点「下载更新」= 关框 + 后台下载', () {
    final dialog = readFile('lib/widgets/update_dialog.dart');
    final dl = readFile('lib/services/update_download.dart');

    test('框里不再自己下包：下载逻辑搬到了 update_download', () {
      expect(dialog, isNot(contains('downloadApk(')),
          reason: '框里下包就会挡住界面 73MB 的进度');
      expect(dl, contains('downloadApk'));
    });

    test('点按钮先关框、再起后台下载（不 await）', () {
      final fn = slice(dialog, 'void _startBackgroundDownload()', '/// 打开下载页并关掉本框');
      expect(fn, contains('nav.pop()'));
      expect(fn, contains('startUpdateDownload(widget.info)'));
      final iPop = fn.indexOf('nav.pop()');
      final iStart = fn.indexOf('startUpdateDownload');
      expect(iStart, greaterThan(iPop), reason: '先关框，下载才不会卡着用户');
      expect(fn, isNot(contains('await startUpdateDownload')));
    });

    test('关于页手动更新也走同一条后台下载链路（不挡使用）', () {
      final about = readFile('lib/screens/about_screen.dart');
      expect(about, contains('showUpdateDialog'));
      expect(about, isNot(contains('downloadApk(')),
          reason: '关于页自己下包就会把界面卡在进度条上');
      // 页内要能看见后台进度（否则点完框一关像什么都没发生）
      expect(about, contains('updateState'));
      expect(about, contains('_downloadStrip'));
    });

    test('按钮文案是「下载更新」，且没有附件时不显示下载按钮', () {
      expect(dialog, contains("'下载更新'"));
      expect(dialog, contains('widget.info.hasApk'));
    });

    test('下载中/已下好同版本时不重复拉，没附件直接走失败提示', () {
      expect(dl, contains('if (current.busy) return;'));
      expect(dl, contains('if (current.ready && current.version == info.version) return;'));
      expect(dl, contains('if (!info.hasApk)'));
    });

    test('状态机：downloading → ready，进度透传', () async {
      final seen = <UpdatePhase>[];
      double? lastProgress;
      updateState.addListener(() => seen.add(updateState.value.phase));
      var calls = 0;

      await startUpdateDownload(_info('1.4.4'), downloader: (info, onProgress) async {
        calls++;
        onProgress(0.25);
        lastProgress = updateState.value.progress;
        onProgress(1);
        return File('${Directory.systemTemp.path}/fake-1.4.4.apk');
      });

      expect(calls, 1);
      expect(lastProgress, 0.25);
      expect(seen, contains(UpdatePhase.downloading));
      expect(updateState.value.phase, UpdatePhase.ready);
      expect(updateState.value.version, '1.4.4');
      expect(updateState.value.percentLabel, '100%');
    });

    test('下载失败进 failed 并给出人话原因', () async {
      await startUpdateDownload(_info('1.4.5'), downloader: (info, onProgress) async => null);
      expect(updateState.value.phase, UpdatePhase.failed);
      expect(updateState.value.error, contains('浏览器下载'));
    });

    test('下载异常（throw）也归成失败，不把异常抛给界面', () async {
      await startUpdateDownload(_info('1.4.6'),
          downloader: (info, onProgress) async => throw const SocketException('断网'));
      expect(updateState.value.phase, UpdatePhase.failed);
    });

    test('正在下载时再点一次，不会拉第二遍', () async {
      var calls = 0;
      await startUpdateDownload(_info('1.4.7'), downloader: (_, onProgress) async {
        calls++;
        // 模拟下载途中用户又点了一次
        await startUpdateDownload(_info('1.4.7'));
        onProgress(1);
        return File('${Directory.systemTemp.path}/fake-1.4.7.apk');
      });
      expect(calls, 1);
      expect(updateState.value.phase, UpdatePhase.ready);
    });

    test('同版本已下好时再点一次，也不重下', () async {
      var calls = 0;
      Future<File?> dlFake(ReleaseInfo i, void Function(double?) p) async {
        calls++;
        return File('${Directory.systemTemp.path}/fake-${i.version}.apk');
      }

      await startUpdateDownload(_info('1.4.8'), downloader: dlFake);
      await startUpdateDownload(_info('1.4.8'), downloader: dlFake);
      expect(calls, 1);
    });
  });

  group('④ 下完问「装不装」，不静默安装', () {
    final host = readFile('lib/widgets/update_host.dart');
    final dialog = readFile('lib/widgets/update_dialog.dart');

    test('进度用底部提示条，不挡内容，并写明「可以继续阅读」', () {
      expect(host, contains('showSnackBar'));
      expect(host, contains('LinearProgressIndicator'));
      expect(host, contains('可以继续阅读'));
    });

    test('ready 时收起进度并弹确认框，且只弹一次', () {
      expect(host, contains('showInstallReadyDialog'));
      expect(host, contains('_askedInstall'));
      expect(host, contains('_closeProgress()'));
    });

    test('确认框给的是「立即安装 / 稍后」，装机交给系统安装器', () {
      expect(dialog, contains('showInstallReadyDialog'));
      expect(dialog, contains('立即安装'));
      expect(dialog, contains("'稍后'"));
      final fn = slice(dialog, 'Future<void> _install()', 'String? get _sizeLabel');
      expect(fn, contains('installApk(file)'));
      expect(fn, contains('resetUpdateDownload()'));
      // 装不上要说人话（引导去开「安装未知应用」），不能只转圈
      expect(fn, contains('安装未知应用'));
    });

    test('「稍后」归位但保留安装包（下次启动由 cleanDownloadedApks 清）', () {
      expect(dialog, contains('resetUpdateDownload()'));
      final dlSrc = readFile('lib/services/update_download.dart');
      final fn = dlSrc.substring(dlSrc.indexOf('void resetUpdateDownload('));
      expect(fn, contains('deleteFile'));
      expect(fn, contains('updateState.value = UpdateState.idle'));
    });

    test('Host 挂在 MaterialApp.builder 里（跨页面也能提示）', () {
      final main = readFile('lib/main.dart');
      expect(main, contains('UpdateHost('));
      expect(main, contains('navigatorKey: appNavigatorKey'));
    });
  });
}
