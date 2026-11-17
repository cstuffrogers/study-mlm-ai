// D144 门禁：应用内自动更新（查 GitHub Release → 下载 APK → 唤起安装器）。
//
// 为什么这些点必须各自钉住：
//  · 版本比较写错 = 「永远说已是最新」或「天天说我更新了」，两者都是不可接受的缺陷；
//  · 通道名写错（xxmz/app）不会编译报错，只会运行时静默不装包；
//  · Manifest 少了 REQUEST_INSTALL_PACKAGES / FileProvider，装包那一刻才崩；
//  · 下载不校验大小，断流会装出一个坏包 —— 比不更新更糟。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:marxism_reader/config/app_meta.dart';
import 'package:marxism_reader/services/app_update.dart';

String readFile(String p) => File(p).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('版本号解析与比较', () {
    test('parseVersion 归一 v 前缀 / +build / 缺位补 0', () {
      expect(parseVersion('v1.3.7'), [1, 3, 7]);
      expect(parseVersion('1.3.7+18'), [1, 3, 7]);
      expect(parseVersion('V1.3.7'), [1, 3, 7]);
      expect(parseVersion('1.4'), [1, 4, 0]);
      expect(parseVersion('2'), [2, 0, 0]);
      expect(parseVersion('1.3.7-beta'), [1, 3, 7]);
    });

    test('isNewerVersion 各段逐位比较，不是字符串比较', () {
      // 字符串比较会认为 '1.3.10' < '1.3.9'，这是最常见的错法
      expect(isNewerVersion('1.3.10', '1.3.9'), isTrue);
      expect(isNewerVersion('1.3.9', '1.3.10'), isFalse);
      expect(isNewerVersion('1.4.0', '1.3.7'), isTrue);
      expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
    });

    test('相同版本不算更新（避免每次启动都弹框）', () {
      expect(isNewerVersion('1.3.7', '1.3.7'), isFalse);
      expect(isNewerVersion('v1.3.7', '1.3.7'), isFalse);
      expect(isNewerVersion('1.3.7+18', '1.3.7+17'), isFalse);
    });

    test('本地版本比远端新时不提示（用测试版/自己编译的包）', () {
      expect(isNewerVersion('1.3.6', '1.3.7'), isFalse);
      expect(isNewerVersion('1.2.1', '1.3.7'), isFalse);
    });
  });

  group('ReleaseInfo', () {
    test('有 APK 附件时 hasApk 为真，没有则为假', () {
      const withApk = ReleaseInfo(
        version: '1.3.7',
        tagName: 'v1.3.7',
        apkUrl: 'https://x/y.apk',
        apkSize: 100,
        notes: '',
      );
      const noApk = ReleaseInfo(
        version: '1.3.7',
        tagName: 'v1.3.7',
        apkUrl: null,
        apkSize: 0,
        notes: '',
      );
      expect(withApk.hasApk, isTrue);
      expect(noApk.hasApk, isFalse);
      // 空串也必须当「没有」，否则会去下载一个空 URL
      const emptyUrl = ReleaseInfo(
        version: '1.3.7',
        tagName: 'v1.3.7',
        apkUrl: '',
        apkSize: 0,
        notes: '',
      );
      expect(emptyUrl.hasApk, isFalse);
    });
  });

  group('查最新版本的接口地址', () {
    test('走 GitHub Releases API，且仓库与 AppMeta 一致', () {
      expect(kReleaseApiUrl,
          'https://api.github.com/repos/cstuffrogers/study-mlm-ai/releases/latest');
      // 仓库名必须和「关于」页展示的仓库同一份，不能出现两处各写各的
      expect(AppMeta.githubUrl, contains('cstuffrogers/study-mlm-ai'));
    });
  });

  group('原生安装通道', () {
    test('Dart 侧通道名与 Kotlin 侧完全一致', () {
      expect(kAppChannel.name, 'xxmz/app');
      final kt = readFile(
          'android/app/src/main/kotlin/com/weiwu/marxism_reader/MainActivity.kt');
      expect(kt, contains('"xxmz/app"'));
      expect(kt, contains('"installApk"'));
    });

    test('Kotlin 用 FileProvider 转 content://（file:// 在 7+ 会崩）', () {
      final kt = readFile(
          'android/app/src/main/kotlin/com/weiwu/marxism_reader/MainActivity.kt');
      expect(kt, contains('FileProvider.getUriForFile'));
      expect(kt, contains('application/vnd.android.package-archive'));
      // 少了这个 flag，安装器读不到文件
      expect(kt, contains('FLAG_GRANT_READ_URI_PERMISSION'));
    });

    test('Manifest 声明 REQUEST_INSTALL_PACKAGES 与 FileProvider', () {
      final mf = readFile('android/app/src/main/AndroidManifest.xml');
      expect(mf, contains('android.permission.REQUEST_INSTALL_PACKAGES'));
      expect(mf, contains('androidx.core.content.FileProvider'));
      expect(mf, contains('.fileprovider'));
      expect(mf, contains('@xml/file_paths'));
    });

    test('file_paths.xml 覆盖 cache-path（APK 就下在缓存目录）', () {
      final fp = readFile('android/app/src/main/res/xml/file_paths.xml');
      expect(fp, contains('cache-path'));
    });

    test('通道不可用（旧版/测试）时回退到下载页，不做死按钮', () {
      final src = readFile('lib/services/app_update.dart');
      expect(src, contains('MissingPluginException'));
      expect(src, contains('openDownloadPage'));
    });
  });

  group('启动即检查 + 手动检查入口', () {
    test('main.dart 在首帧后静默检查更新', () {
      final src = readFile('lib/main.dart');
      expect(src, contains('_checkUpdateAfterLaunch'));
      expect(src, contains('addPostFrameCallback'));
      // 必须在首帧之后（runApp 之后），不能占冷启动关键路径
      final iRun = src.indexOf('runApp(const MarxismReaderApp())');
      final iCheck = src.indexOf('_checkUpdateAfterLaunch');
      expect(iRun, greaterThan(-1));
      expect(iCheck, greaterThan(iRun));
    });

    test('关于页有「检查更新」按钮，且检查中禁用防连点', () {
      final src = readFile('lib/screens/about_screen.dart');
      expect(src, contains('检查更新'));
      expect(src, contains('_checking'));
      expect(src, contains('checkUpdate()'));
      // 查不到也要有反馈，不能点了没动静
      expect(src, contains('已是最新版本'));
    });

    test('更新框给的是「下载并安装」，不是「打开网页」', () {
      final src = readFile('lib/widgets/update_dialog.dart');
      expect(src, contains('下载并安装'));
      expect(src, contains('去网页下载'));
      expect(src, contains('downloadApk'));
      expect(src, contains('installApk'));
    });
  });

  group('平台门禁', () {
    test('checkUpdate 只在安卓返回结果，其他平台 null', () {
      final src = readFile('lib/services/app_update.dart');
      // 非安卓直接返回 null，避免桌面/Web 弹一个装不了的框
      expect(src, contains('if (!Platform.isAndroid) return null;'));
    });

    test('测试进程中不是安卓，checkUpdate 应返回 null', () async {
      if (Platform.isAndroid) return;
      expect(await checkUpdate(), isNull);
    });
  });

  group('下载完整性', () {
    test('下载后校验字节数，不符就删掉不装（坏包比不更新更糟）', () {
      final src = readFile('lib/services/app_update.dart');
      expect(src, contains('got != info.apkSize'));
      expect(src, contains('await file.delete()'));
    });

    test('流式下载 + 进度回调（73MB 不整块读进内存）', () {
      // 用代码切片核对 downloadApk 内部实现：checkUpdate 里没有 send/openWrite，
      // 直接断言整个文件会误伤
      final src = readFile('lib/services/app_update.dart');
      final i = src.indexOf('Future<File?> downloadApk(');
      expect(i, greaterThan(-1));
      final body = src.substring(i, src.indexOf('Future<bool> installApk('));
      expect(body, contains('c.send('));
      expect(body, contains('openWrite'));
      expect(body, contains('onProgress'));
      // 必须逐块写盘，不能把整包读成 Uint8List（低端机会 OOM）
      expect(body, contains('await for (final chunk in resp.stream)'));
    });
  });
}
