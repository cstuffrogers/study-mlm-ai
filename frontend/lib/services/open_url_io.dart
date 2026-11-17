// 外部链接打开 —— 原生平台实现（Android / iOS / Windows / macOS / Linux）。
//
// 为什么要有它：原先非 Web 平台直接落到 `open_url_stub.dart` 的**空实现**，
// 于是安卓包里「关于」页的「下载最新安卓版」「打开 GitHub」、延伸阅读的
// 「打开原文」全是点了没反应的死按钮。D142c 起改用 url_launcher 真正唤起系统浏览器。
//
// 注意 Android 11+ 的包可见性：调用方必须在 AndroidManifest.xml 里声明
// `<queries><intent><action VIEW/><data scheme="https"/></intent></queries>`，
// 否则 `canLaunchUrl` 恒为 false（见 android/app/src/main/AndroidManifest.xml）。
import 'package:url_launcher/url_launcher.dart';

void openExternal(String url) {
  // 先拿 Uri，非法地址直接吞掉（调用方也有 isValidUrl 兜底，这里防手滑）
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return;
  // launchUrl 的返回与异常都不适合冒泡到 UI：外链失败不该打断阅读。
  launchUrl(uri, mode: LaunchMode.externalApplication).catchError((Object _) => false);
}
