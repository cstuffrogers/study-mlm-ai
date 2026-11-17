// 首页 = 选学习路线（三条路线卡片），红白渐变头部沿用原首页。
//
// 为什么改：旧首页把「路线 chips + 章节列表 + 底部主操作按钮」挤在一屏，
// 首屏信息过载；现在首页只负责「选哪条路线」，章节与「深入学习 / 查看原文」
// 交给路线地图页（screens/route_map.dart），动线变成 选路线 → 看章节 → 进章节。
//
// 头部入口（四个，等等）：功能中心 / LLM 大模型 API 配置 / 学习分析 / 使用说明。
// 「学习路线」按钮已去掉——首页本身就是选路线页，留着是自指跳转。
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/sync_controller.dart';
import '../widgets/anim.dart';
import '../widgets/author_art.dart';
import '../widgets/brand_title.dart';
import '../widgets/guide_dialog.dart';
import '../widgets/route_cards.dart';
import '../widgets/sync_notice.dart';
import 'analytics_dashboard.dart';
import 'llm_config_screen.dart';
import 'tools_screen.dart';

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

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  /// 头部红白图高度：窄屏收小，宽屏恢复 116。
  static double _artHeight(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return (w * 0.30).clamp(88.0, 116.0);
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
            Expanded(
              child: AuroraBackground(
                child: Column(
                  children: [
                    GradientHeader(
                      // 标题走自定义组件（两行「唯物」/「马哲精读」），
                      // titleHeight 是它在未缩放下的实测总高，供头部预留空间。
                      title: '唯物 马哲精读',
                      titleWidget: const BrandTitle(),
                      titleHeight: BrandTitle.baseHeight,
                      subtitle: '先选学习路线，再进章节精读',
                      // 头像高度随屏宽收一点：窄屏（360dp）上 116 高的横幅图宽达 177，
                      // 占掉近一半头部宽度会把标题挤成省略号。
                      art: AuthorArt(asset: kHomeArt, height: _artHeight(context)),
                      artWidth: AuthorArt.widthFor(
                          asset: kHomeArt, height: _artHeight(context)),
                      // 入口放在头部而不是右下浮动按钮：浮动按钮会压住底部主操作。
                      actions: [
                        _HeaderAction(
                          tooltip: '功能中心',
                          icon: Icons.grid_view_rounded,
                          onTap: () => _push(const ToolsScreen()),
                        ),
                        _HeaderAction(
                          tooltip: 'LLM 大模型 API 配置',
                          icon: Icons.smart_toy_outlined,
                          onTap: () => _push(const LlmConfigScreen()),
                        ),
                        _HeaderAction(
                          tooltip: '学习分析',
                          icon: Icons.insights_rounded,
                          onTap: () =>
                              _push(const AnalyticsDashboardScreen(routeId: 'route_A')),
                        ),
                        _HeaderAction(
                          tooltip: '引导',
                          icon: Icons.help_outline_rounded,
                          onTap: () => showUsageGuide(context),
                        ),
                      ],
                    ),
                    const Expanded(child: RouteCardsView()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 首页头部的圆形图标入口（白描边、半透明底，压在红色渐变上可读）。
class _HeaderAction extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.white.withValues(alpha: 0.16),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Icon(icon, size: 19, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
