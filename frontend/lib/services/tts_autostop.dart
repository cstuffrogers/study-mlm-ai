// 朗读自动停止：页面切换 / APP 退到后台 → 立刻静音。
//
// 为什么要有它：朗读是「后台还在响」的典型场景——用户点开喇叭后随手进入下一章、
// 或者按 Home 键切到别的应用，声音却一直念下去，只能再回到那一页去找停止按钮。
// 这里在**应用层**兜住，任何页面都不用自己写停止逻辑：
//   · TtsStopOnRouteChange —— NavigatorObserver，路由 push/pop/replace/remove 即停；
//   · TtsAutoStopScope      —— 监听 App 生命周期，hidden/paused/detached（切后台、息屏、隐藏）即停。
// 弹窗类路由（PopupRoute：对话框/底部弹层）不算「切换页面」，不打断朗读。
// 性能红线：无常驻 Timer / 动画，只在事件回调里调一次 ttsStop()。
import 'package:flutter/material.dart';

import 'tts.dart';

/// 路由变化即停止朗读。
class TtsStopOnRouteChange extends NavigatorObserver {
  TtsStopOnRouteChange();

  void _stopUnlessPopup(Route<dynamic>? route) {
    if (route is PopupRoute) return; // 弹窗/对话框/底部弹层不算页面切换
    ttsStop();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _stopUnlessPopup(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _stopUnlessPopup(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _stopUnlessPopup(newRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _stopUnlessPopup(route);
}

/// APP 退到后台（切应用 / 息屏 / 隐藏）即停止朗读。包在 MaterialApp.builder 外层即可。
class TtsAutoStopScope extends StatefulWidget {
  final Widget child;

  const TtsAutoStopScope({super.key, required this.child});

  @override
  State<TtsAutoStopScope> createState() => _TtsAutoStopScopeState();
}

class _TtsAutoStopScopeState extends State<TtsAutoStopScope>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // inactive 只是「失去焦点」（拉通知栏、来电横幅），不算退到后台，不打断朗读；
    // 真正的后台是 hidden / paused，进程退出是 detached。
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ttsStop();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
