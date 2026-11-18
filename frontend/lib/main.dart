// 正统马哲深度学习系统 — MVP 前端入口
// 首页（选学习路线）+ 路线地图 + 章节精读 + 原文阅读器 + 溯源卡片
// + 选中文本唤起五模式 AI 对话浮窗 + 离线断点续学

import 'dart:async';

import 'package:flutter/material.dart';
import 'offline/data_compat.dart';
import 'offline/local_db.dart';
import 'offline/offline_content.dart';
import 'screens/home_screen.dart';
import 'services/app_update.dart';
import 'services/chat_service.dart';
import 'services/tts.dart';
import 'services/sync_controller.dart';
import 'services/tts_autostop.dart';
import 'theme/app_theme.dart';
import 'widgets/update_dialog.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 单机版：启动时先装载轻量元数据与本地学习档案；
  // 14MB 的原文分片与题库在进入相关页面前再懒加载，避免拖慢冷启动。
  await LocalDb.ensure();
  // 升级兼容闸门：只补字段、只登记数据版本，绝不删除/改名用户数据。
  await DataCompat.run();
  await OfflineContent.ensureMeta();
  // 初始化朗读引擎（安卓走系统 TTS；Web 预取浏览器语音）。不等待结果，避免拖慢冷启动。
  ttsInit();
  runApp(const MarxismReaderApp());
  // 应用内更新检查：放到首帧之后再查，绝不参与冷启动关键路径（网络慢也不拖慢进首页）。
  // 只有安卓会真的弹框——桌面/Web 没有自装这回事，见 services/app_update.dart。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_checkUpdateAfterLaunch());
    // 顺手清掉上次更新留下的安装包（70+MB）：装完不能立刻删，只能等下次启动。
    unawaited(cleanDownloadedApks());
  });
}

/// 启动后的更新检查（首帧之后跑，不占冷启动）。
///
/// 用 NavigatorState 而不是 BuildContext：`showDialog` 需要一个仍然挂载的
/// context，而这里跨了网络 await。NavigatorState 有自己的 mounted，
/// 且它活着就说明界面在，比裸 context 稳。
Future<void> _checkUpdateAfterLaunch() async {
  final info = await checkUpdate();
  if (info == null) return;
  final nav = _appNavKey.currentState;
  if (nav == null || !nav.mounted) return;
  await showUpdateDialog(nav.context, info);
}

/// 应用级 Navigator key：更新提示框需要「当前有界面的 context」，
/// 而启动检查发生在首帧之后、此时还没有别的 context 可用。
final GlobalKey<NavigatorState> _appNavKey = GlobalKey<NavigatorState>();

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
          return TtsAutoStopScope(
            child: MediaQuery.withClampedTextScaling(
              minScaleFactor: scale,
              maxScaleFactor: scale,
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
        // 两个观察者分工：换页面停、弹层关闭停（弹层打开时不停，见 tts_autostop.dart）。
        navigatorObservers: [TtsStopOnRouteChange(), TtsStopOnSheetClose()],
        navigatorKey: _appNavKey,
        home: const HomeScreen(),
      ),
    );
  }
}
