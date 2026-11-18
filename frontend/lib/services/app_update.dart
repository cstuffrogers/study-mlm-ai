// 应用内更新：查 GitHub 最新 Release → 直接下载 APK → 调系统安装器装。
//
// 为什么要自己做（而不是「打开网页手动下载」）：
// 用户要求「自动提示有新版本 + 点一下自动下载安装」，开浏览器再手点下载装包
// 对普通用户门槛太高（下到 Downloads 里还要自己去文件管理器点）。
//
// 口径（别越线，也别骗用户）：
//  · 只查 GitHub Releases API —— 不引入任何第三方升级 SDK、不采集设备信息；
//  · 只比 versionName（1.3.7），不比 versionCode —— 两者在发布时同步递增，
//    但 versionName 是用户能看到的那个；
//  · **不静默安装**：下载完交给系统安装器，用户确认才算数（安卓不允许 App 静默装包）；
//  · **只有安卓能自装**：iOS/Web 上没有这回事，platform 不匹配就直接不提示更新；
//  · 网络失败一律当「无更新」，绝不弹错误打扰阅读。
//
// 换 APK 装包的坑（已在 Manifest 里配好，见 AndroidManifest.xml）：
//  ① Android 7+ 必须用 FileProvider 出 content:// URI，直接给 file:// 会
//     FileUriExposedException 崩掉；
//  ② Android 8+ 需要 REQUEST_INSTALL_PACKAGES 权限 + 用户允许「安装未知应用」；
//  ③ file_paths 里要声明 cache-path，因为 APK 下到缓存目录。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_meta.dart';

/// 最新 Release 的摘要信息。
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.tagName,
    required this.apkUrl,
    required this.apkSize,
    required this.notes,
  });

  /// 去掉前缀 v 的版本号，如 `1.3.7`。
  final String version;
  final String tagName;

  /// APK 直链（`browser_download_url`）；没有 APK 附件时为 null。
  final String? apkUrl;
  final int apkSize;

  /// Release 说明（正文），用于提示框里显示「更新了什么」。
  final String notes;

  /// 是否有可用的 APK 附件（没有就只提示、引导去网页）。
  bool get hasApk => apkUrl != null && apkUrl!.isNotEmpty;
}

/// 把 `1.3.7` / `1.3.7+18` / `v1.3.7` 归一成可比较的整数列表。
List<int> parseVersion(String raw) {
  var s = raw.trim();
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  // 去掉 +build 部分与任何预发布后缀
  s = s.split('+').first;
  s = s.split('-').first;
  final out = <int>[];
  for (final part in s.split('.')) {
    final n = int.tryParse(part);
    out.add(n ?? 0);
  }
  while (out.length < 3) {
    out.add(0);
  }
  return out;
}

/// `remote` 是否比 `local` 新。逐段比较，缺位按 0。
bool isNewerVersion(String remote, String local) {
  final r = parseVersion(remote);
  final l = parseVersion(local);
  final n = r.length > l.length ? r.length : l.length;
  for (var i = 0; i < n; i++) {
    final a = i < r.length ? r[i] : 0;
    final b = i < l.length ? l[i] : 0;
    if (a != b) return a > b;
  }
  return false;
}

/// 发布地址（GitHub API），可被测试替换。
const String kReleaseApiUrl =
    'https://api.github.com/repos/cstuffrogers/study-mlm-ai/releases/latest';

/// 拉最新 Release。失败（网络/限流/无 Release）返回 null —— 调用方按「无更新」处理。
Future<ReleaseInfo?> fetchLatestRelease({http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final resp = await c
        .get(Uri.parse(kReleaseApiUrl), headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'xxmz-${AppMeta.clientVersion}',
        })
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      debugPrint('检查更新失败：HTTP ${resp.statusCode}');
      return null;
    }
    final map = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final tag = '${map['tag_name'] ?? ''}';
    if (tag.isEmpty) return null;
    final assets = (map['assets'] as List?) ?? const [];
    String? apkUrl;
    var apkSize = 0;
    for (final a in assets) {
      final m = (a as Map).cast<String, dynamic>();
      final name = '${m['name'] ?? ''}';
      if (name.toLowerCase().endsWith('.apk')) {
        apkUrl = '${m['browser_download_url'] ?? ''}';
        apkSize = (m['size'] as num?)?.toInt() ?? 0;
        break;
      }
    }
    return ReleaseInfo(
      version: tag.replaceFirst(RegExp('^[vV]'), ''),
      tagName: tag,
      apkUrl: apkUrl,
      apkSize: apkSize,
      notes: '${map['body'] ?? ''}',
    );
  } catch (e) {
    debugPrint('检查更新异常：$e');
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// 当前已安装的版本名（`1.3.7`，不含 +build）。取不到就返回 null。
Future<String?> currentVersionName() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  } catch (_) {
    return null;
  }
}

/// 下载 APK 到缓存目录，返回本地文件。失败返回 null。
///
/// 走流式下载并回调进度（0~1，总大小未知时为 null），因为 73MB 的包
/// 一次性读进内存再写盘在低端机上容易 OOM。
Future<File?> downloadApk(
  ReleaseInfo info, {
  void Function(double? progress)? onProgress,
  http.Client? client,
}) async {
  final url = info.apkUrl;
  if (url == null || url.isEmpty) return null;
  final c = client ?? http.Client();
  try {
    final resp = await c.send(http.Request('GET', Uri.parse(url)));
    if (resp.statusCode != 200) {
      debugPrint('下载 APK 失败：HTTP ${resp.statusCode}');
      return null;
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/xxmz-${info.version}.apk');
    if (await file.exists()) await file.delete();
    final sink = file.openWrite();
    final total = resp.contentLength ?? info.apkSize;
    var got = 0;
    await for (final chunk in resp.stream) {
      sink.add(chunk);
      got += chunk.length;
      if (onProgress != null) {
        onProgress(total > 0 ? (got / total).clamp(0.0, 1.0) : null);
      }
    }
    await sink.close();
    // 校验大小：GitHub CDN 偶尔半截断流，装坏包比不装更糟
    if (info.apkSize > 0 && got != info.apkSize) {
      debugPrint('APK 大小不符：$got != ${info.apkSize}');
      await file.delete();
      return null;
    }
    return file;
  } catch (e) {
    debugPrint('下载 APK 异常：$e');
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// 清掉上次更新留下的安装包（每个 70+ MB，一直躺在临时目录里等系统回收太浪费）。
///
/// 为什么不在装完就删：系统安装器是**异步**读这个文件的，
/// 一唤起安装就删会让安装失败；所以放到下次启动时清，
/// 只清「xxmz-*.apk」这种自己下载的包，不动临时目录里的其它东西。
Future<int> cleanDownloadedApks({Directory? dir}) async {
  // 显式传目录时（测试）不做平台限制；生产环境只有安卓会下载安装包。
  if (dir == null && !Platform.isAndroid) return 0;
  var removed = 0;
  try {
    final d = dir ?? await getTemporaryDirectory();
    if (!await d.exists()) return 0;
    await for (final e in d.list()) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last.toLowerCase();
      if (!name.startsWith('xxmz-') || !name.endsWith('.apk')) continue;
      try {
        await e.delete();
        removed++;
      } catch (err) {
        debugPrint('删安装包失败：$err');
      }
    }
  } catch (e) {
    debugPrint('清理安装包失败：$e');
  }
  return removed;
}

/// 原生安装通道（见 MainActivity.kt 的 xxmz/app）。
///
/// 单独抽成常量是为了让门禁能直接核对通道名与 Kotlin 侧一致 ——
/// 名字写错不会编译报错，只会运行时静默失效。
const MethodChannel kAppChannel = MethodChannel('xxmz/app');

/// 拉起系统安装器。返回是否成功唤起。
///
/// **不能把 `file://` 直接交给系统**：Android 7+ 会抛 FileUriExposedException 崩掉，
/// 所以必须让原生侧用 FileProvider 转成 `content://`（Java API，Dart 侧没有对应能力）。
Future<bool> installApk(File apk) async {
  if (!Platform.isAndroid) return false;
  try {
    final ok = await kAppChannel.invokeMethod<bool>('installApk', {
      'path': apk.path,
    });
    return ok == true;
  } on MissingPluginException catch (e) {
    // 测试环境 / 旧版 APK 没有这条通道：退化为浏览器打开下载页，至少不是死按钮
    debugPrint('安装通道不可用（$e），回退到下载页');
    return openDownloadPage();
  } catch (e) {
    debugPrint('唤起安装器失败：$e');
    return false;
  }
}

/// 打开 GitHub Releases 下载页（兜底路径）。
Future<bool> openDownloadPage() async {
  try {
    return await launchUrl(
      Uri.parse(AppMeta.releasesUrl),
      mode: LaunchMode.externalApplication,
    );
  } catch (e) {
    debugPrint('打开下载页失败：$e');
    return false;
  }
}

/// 是否值得显示「有新版本」：只有安卓、且能取到当前版本、且远端更新时才返回 true。
Future<ReleaseInfo?> checkUpdate({http.Client? client}) async {
  if (!Platform.isAndroid) return null;
  final local = await currentVersionName();
  if (local == null) return null;
  final latest = await fetchLatestRelease(client: client);
  if (latest == null) return null;
  if (!isNewerVersion(latest.version, local)) return null;
  return latest;
}
