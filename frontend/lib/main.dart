// 正统马哲深度学习系统 — MVP 前端入口
// 首页（选学习路线）+ 路线地图 + 章节精读 + 原文阅读器 + 溯源卡片
// + 选中文本唤起五模式 AI 对话浮窗 + 离线断点续学

import 'package:flutter/material.dart';
import 'offline/data_compat.dart';
import 'offline/local_db.dart';
import 'offline/offline_content.dart';
import 'screens/home_screen.dart';
import 'services/chat_service.dart';
import 'services/tts.dart';
import 'services/sync_controller.dart';
import 'services/tts_autostop.dart';
import 'theme/app_theme.dart';
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
}

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
        navigatorObservers: [TtsStopOnRouteChange()],
        home: const HomeScreen(),
      ),
    );
  }
}
