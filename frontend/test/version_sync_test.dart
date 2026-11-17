// 版本号同步门禁：发布前最容易踩的坑是「改了 pubspec 忘了改 app_meta」，
// 结果是关于页显示 1.2.1、安装包却是 1.3.0，用户投诉「升级了但版本没变」。
// 另外这里顺手钉住升级前提：applicationId 与签名配置不能变（否则覆盖安装会变成另一个应用）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/config/app_meta.dart';

void main() {
  test('pubspec 的 version 与 app_meta.clientVersion 必须一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec);
    expect(m, isNotNull, reason: 'pubspec.yaml 缺 version 行');
    expect(AppMeta.clientVersion, m!.group(1),
        reason: 'pubspec.yaml 与 app_meta.dart 的版本号必须同步改');
    expect(AppMeta.clientVersion, matches(RegExp(r'^\d+\.\d+\.\d+\+\d+$')),
        reason: '版本号要带 build 号（+N），Android 升级靠它判断新旧');
  });

  test('升级前提：applicationId 与 release 签名走 key.properties', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    // 覆盖安装保留数据的前提之一：包名一动，系统就当成另一个应用
    expect(gradle.contains('applicationId = "com.weiwu.marxism_reader"'), isTrue,
        reason: 'applicationId 是数据归属的根，改了就升级不上去、数据也读不到');
    expect(gradle.contains('namespace = "com.weiwu.marxism_reader"'), isTrue);
    // 签名：有 key.properties 用 release keystore，且必须与旧版本同一个 keystore
    expect(gradle.contains('key.properties'), isTrue);
    expect(gradle.contains('signingConfigs.getByName("release")'), isTrue);
    // 版本号必须来自 pubspec（两处不同步的常见根因）
    expect(gradle.contains('versionCode = flutter.versionCode'), isTrue);
    expect(gradle.contains('versionName = flutter.versionName'), isTrue);
  });

  test('不在清单里开启系统云备份（隐私页承诺「不上传」）', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest.contains('android:allowBackup="false"'), isTrue,
        reason: '默认 true 会把对话与 API Key 送到系统云备份，与隐私页矛盾');
  });
}
