// 正统马哲深度学习系统 — MVP 前端入口
// 学习首页（路线/章节选择）+ 深入学习页 + 原文阅读器 + 溯源卡片
// + 选中文本唤起五模式 AI 对话浮窗 + 学习路线闭环 + 离线断点续学

import 'package:flutter/material.dart';
import 'offline/local_db.dart';
import 'offline/offline_content.dart';
import 'screens/study_home_screen.dart';
import 'services/chat_service.dart';
import 'services/sync_controller.dart';
import 'widgets/sync_notice.dart';
import 'theme/app_theme.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 单机版：启动时先装载轻量元数据与本地学习档案；
  // 14MB 的原文分片与题库在进入相关页面前再懒加载，避免拖慢冷启动。
  await LocalDb.ensure();
  await OfflineContent.ensureMeta();
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
          return MediaQuery.withClampedTextScaling(
            minScaleFactor: scale,
            maxScaleFactor: scale,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // 启动时合并离线暂存并拉取断点（断点续学）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SyncController>().flush();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncController>();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 仅在有离线暂存或同步状态提示时显示
            if (sync.pending > 0 || !sync.online)
              SyncNotice(
                message: sync.message.isNotEmpty ? sync.message : '离线暂存 ${sync.pending} 条进度',
                offline: !sync.online,
                onRetry: () => context.read<SyncController>().flush(),
              ),
            Expanded(child: const StudyHomeScreen()),
          ],
        ),
      ),
      // 入口（功能中心 / 学习路线 / 学习分析 / 引导）已移到首页头部图标：
      // 右下浮动按钮会压住底部「深入学习」「查看原文」主操作。
    );
  }
}
