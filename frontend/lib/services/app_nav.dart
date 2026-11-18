// 全局 Navigator key：跨页面的提示（更新框、下载进度）需要一个**仍然挂载**
// 的 context，而这类动作常常发生在网络 await 之后、甚至发生在别的页面上。
//
// 为什么单独一个文件：main.dart 与 widgets/update_host.dart 都要用它，
// 让 UI 层 import main.dart 会绕成环。
import 'package:flutter/material.dart';

/// 应用根 Navigator（MaterialApp.navigatorKey）。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// 当前是否真的有一棵可用的界面树（拿它判断能不能弹框）。
BuildContext? get appRootContext {
  final nav = appNavigatorKey.currentState;
  if (nav == null || !nav.mounted) return null;
  return nav.context;
}
