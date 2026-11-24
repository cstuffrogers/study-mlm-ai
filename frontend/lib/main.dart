// 正统马哲深度学习系统 — MVP 前端入口
// 首页（选学习路线）+ 路线地图 + 章节精读 + 原文阅读器 + 溯源卡片
// + 选中文本唤起五模式 AI 对话浮窗 + 离线断点续学

import 'dart:async';

import 'package:flutter/material.dart';
import 'offline/data_compat.dart';
import 'offline/local_db.dart';
import 'offline/offline_content.dart';
import 'screens/home_screen.dart';
import 'services/app_nav.dart';
import 'services/app_update.dart';
import 'services/cache_sweep.dart';
import 'services/chat_service.dart';
import 'services/tts.dart';
import 'services/sync_controller.dart';
import 'services/tts_autostop.dart';
import 'theme/app_theme.dart';
import 'widgets/update_dialog.dart';
import 'widgets/update_host.dart';
import 'widgets/whats_new_dialog.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 单机版：启动时先装载轻量元数据与本地学习档案；
  // 14MB 的原文分片与题库在进入相关页面前再懒加载，避免拖慢冷启动。
  await LocalDb.ensure();
  // 首次安装还是升级？——DataCompat.run() 会给所有人登记 data_schema，
  // 所以必须在它之前读：此刻为空 = 本机以前没跑过任何版本（全新安装）。
  // 用途：全新安装不弹「本次更新内容」（没更新可言），见 widgets/whats_new_dialog.dart。
  final freshInstall = LocalDb.settings['data_schema'] == null;
  // 升级兼容闸门：只补字段、只登记数据版本，绝不删除/改名用户数据。
  await DataCompat.run();
  await OfflineContent.ensureMeta();
  // 初始化朗读引擎（安卓走系统 TTS；Web 预取浏览器语音）。不等待结果，避免拖慢冷启动。
  ttsInit();
  // 只想知道「人还在不在前台」——查更新跨了网络 await，回来时可能已经切走了。
  WidgetsBinding.instance.addObserver(_lifecycle);
  runApp(const MarxismReaderApp());
  // 应用内更新检查：放到首帧之后再查，绝不参与冷启动关键路径（网络慢也不拖慢进首页）。
  // 只有安卓会真的弹框——桌面/Web 没有自装这回事，见 services/app_update.dart。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_afterLaunch(freshInstall));
    // 顺手清掉上次更新留下的安装包（70+MB）：装完不能立刻删，只能等下次启动。
    unawaited(cleanDownloadedApks());
    // 朗读音频一律不留盘：防厂商语音引擎把合成结果写进 App 缓存目录。
    unawaited(cleanTempAudio());
  });
}

/// 首帧之后的启动杂活：先弹「本次更新内容」，再查新版本。
///
/// 两件事必须串行：更新提示框是 barrierDismissible=false 的模态框，
/// 两个框同时弹会叠在一起、用户不知道该先关哪个。
/// 更新检查本身要联网（几十毫秒到几秒），所以先给用户看本次更新内容不拖时间。
Future<void> _afterLaunch(bool freshInstall) async {
  await _showWhatsNewAfterLaunch(freshInstall);
  await _checkUpdateAfterLaunch();
}

/// 升级后第一次启动弹「本次更新内容」（一个版本只弹一次，见 changelog_seen.dart）。
///
/// 只在人还在前台时弹：冷启动首帧可能还夹着系统动画/切走，弹了也看不见。
Future<void> _showWhatsNewAfterLaunch(bool freshInstall) async {
  final nav = appNavigatorKey.currentState;
  if (nav == null || !nav.mounted) return;
  if (!_lifecycle.inForeground) return;
  try {
    await maybeShowWhatsNew(nav.context, freshInstall: freshInstall);
  } catch (e) {
    // 更新说明只是「顺告知」，不能因为它把启动流程搞崩
    debugPrint('WhatsNew: 展示更新说明失败（忽略）：$e');
  }
}

/// 启动后的更新检查（首帧之后跑，不占冷启动）。
///
/// 三条铁律：
///  ① **每次冷启动只查/只提示一次**：从后台回到前台不再重查（不要一解锁就跳框）；
///  ② 查的过程中人切走了（按 home 键 / 切到别的应用）就**不弹**，
///     等他下次冷启动自己看到；
///  ③ 用 NavigatorState 而不是裸 BuildContext：这里跨了网络 await，
///     NavigatorState 自己有 mounted，比传 context 稳。
Future<void> _checkUpdateAfterLaunch() async {
  if (_launchUpdateChecked) return;
  _launchUpdateChecked = true;
  final info = await checkUpdate();
  if (info == null) return;
  // 冷启动首帧时 lifecycleState 可能还是 null，按前台算。
  if (!_lifecycle.inForeground) return;
  // 从根 Navigator 取 context（dispatch 前先判 mounted，避免跨 await 用 context）
  final nav = appNavigatorKey.currentState;
  if (nav == null || !nav.mounted) return;
  await showUpdateDialog(nav.context, info);
}

/// 本进程是否已经查过更新 —— 冷启动查一次就够，不让「切后台再回来」重复打扰。
bool _launchUpdateChecked = false;

/// 跟踪前后台状态（只用来决定「现在该不该弹框」）。
class _LifecycleTracker with WidgetsBindingObserver {
  AppLifecycleState? state;

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) => state = s;

  /// 冷启动时 state 为 null（还没收到第一次回调），视为前台。
  bool get inForeground =>
      state == null ||
      state == AppLifecycleState.resumed ||
      state == AppLifecycleState.inactive;
}

final _LifecycleTracker _lifecycle = _LifecycleTracker();

class MarxismReaderApp extends StatelessWidget {
  const MarxismReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatService()..connect()),
        ChangeNotifierProvider(create: (_) => SyncController()..init()),
      ],
      child: MaterialApp(
        title: '唯物 · 马哲精读',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        // 全局字号整体放大约 7%：正文 14→15、说明 12→13 左右。
        // 用 textScaler 而不是逐个改 fontSize，避免各处硬编码字号漏改；
        // 与系统无障碍字号叠加时取较大者，上限 1.25 防止极端值把卡片撑破。
        builder: (context, child) {
          final system = MediaQuery.textScalerOf(context);
          final scale = system.scale(1.0) <= 1.0
              ? 1.07
              : (system.scale(1.0) * 1.07).clamp(1.0, 1.25);
          return UpdateHost(
            child: TtsAutoStopScope(
              child: MediaQuery.withClampedTextScaling(
                minScaleFactor: scale,
                maxScaleFactor: scale,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          );
        },
        // 两个观察者分工：换页面停、弹层关闭停（弹层打开时不停，见 tts_autostop.dart）。
        navigatorObservers: [TtsStopOnRouteChange(), TtsStopOnSheetClose()],
        navigatorKey: appNavigatorKey,
        home: const HomeScreen(),
      ),
    );
  }
}
