// 朗读自动停止：页面切换 / APP 退到后台 → 立刻静音。
//
// 为什么要有它：朗读是「后台还在响」的典型场景——用户点开喇叭后随手进入下一章、
// 或者按 Home 键切到别的应用，声音却一直念下去，只能再回到那一页去找停止按钮。
// 这里在**应用层**兜住，任何页面都不用自己写停止逻辑：
//   · TtsStopOnRouteChange —— NavigatorObserver，路由 push/pop/replace/remove 即停；
//   · TtsAutoStopScope      —— 监听 App 生命周期，hidden/paused/detached（切后台、息屏、隐藏）即停。
// 弹窗类路由（PopupRoute：对话框/底部弹层）打开时不算「切换页面」，不打断朗读；
// 但**关闭时**要停 —— 用户实报「相关原文」弹层里点小喇叭，关掉弹层声音还在念。
// 这条由 TtsStopOnSheetClose 负责：只监 didPop，且只针对 PopupRoute。
//
// 两个例外（都是有意的，别当成漏停）：
//   · ttsBackgroundKeepAlive —— 原文阅读器的「自动连续发声」要求后台继续念；
//   · ttsSkipStopOnNextSheetClose —— 弹层里选了「开始连续朗读」，关弹层正是起头动作。
// 性能红线：无常驻 Timer / 动画，只在事件回调里调一次 ttsStop()。
import 'package:flutter/material.dart';

import 'tts.dart';

/// 「后台继续朗读」开关。
///
/// 原文阅读器的「自动连续发声」打开时置 true：用户要的就是「切后台/息屏也继续念」，
/// 所以这时 [TtsAutoStopScope] 不再停它。关掉连续朗读、退出原文页时必须复位，
/// 否则切后台就不停了——那会绕过所有「该停就停」的规则。
final ValueNotifier<bool> ttsBackgroundKeepAlive = ValueNotifier<bool>(false);

/// 一次性豁免：设为 true 后，**下一次**弹层关闭不停朗读。
///
/// 场景：「自动连续发声」的选模式弹层——关掉弹层正是为了开始念，
/// 不该被「关弹层就停」那条规则误伤。用完自动复位，避免长期免停。
bool ttsSkipStopOnNextSheetClose = false;

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

/// 弹层（对话框 / 底部弹层）**关闭**即停止朗读。
///
/// 为什么不合并进 [TtsStopOnRouteChange]：那条 observer 明确豁免 PopupRoute，
/// 免得弹个提示框就把正在听的正文打断。但「弹层里点了小喇叭 → 关弹层」
/// 是明确的用户意图切换，必须停，否则朗读会在弹层消失后继续念。
///
/// 实现要点：
///  · 只挂 `didPop`（关闭），不挂 `didPush`；
///  · 只对 `PopupRoute` 生效，普通页面 pop 由 [TtsStopOnRouteChange] 处理，
///    两处都停是幂等的（`ttsStop()` 连点无副作用），不会双重报错；
///  · **不**用 NavigatorObserver 的 didRemove --- 那是测试里手动移除路由的路径。
class TtsStopOnSheetClose extends NavigatorObserver {
  TtsStopOnSheetClose();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      // 「关弹层就是为了开始念」的一次性豁免（如连续朗读选完模式）。
      if (ttsSkipStopOnNextSheetClose) {
        ttsSkipStopOnNextSheetClose = false;
        return;
      }
      // 连续朗读进行中：用户只是看一眼目录/书签再回来，不能把声音弄停。
      if (ttsBackgroundKeepAlive.value) return;
      ttsStop();
    }
  }
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
      // 连续朗读（原文阅读器）要求后台继续念，由它自己管生命周期。
      if (ttsBackgroundKeepAlive.value) return;
      ttsStop();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
