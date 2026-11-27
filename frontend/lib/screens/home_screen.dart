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
import '../services/badge_service_api.dart';
import '../services/backup_reminder.dart';
import '../theme/app_theme.dart';
import '../widgets/anim.dart';
import '../widgets/author_art.dart';
import '../widgets/brand_title.dart';
import '../widgets/guide_dialog.dart';
import '../widgets/route_cards.dart';
import '../widgets/sync_notice.dart';
import 'analytics_dashboard.dart';
import 'data_backup_screen.dart';
import 'llm_config_screen.dart';
import 'tools_screen.dart';
import 'badge_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _unseenBadges = 0;
  /// 上次备份时间戳（毫秒）；null = 从未备份或尚未读出。
  int? _lastBackupTs;

  @override
  void initState() {
    super.initState();
    _loadUnseenBadges();
    _loadLastBackupTs();
    // 启动时合并离线暂存并拉取断点（断点续学）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SyncController>().flush();
    });
  }

  /// 读上次备份时间：决定首页要不要弹「该备份了」提醒。
  /// 读取失败不阻断首页（最坏情况 = 一直提醒，用户点一下就消失）。
  Future<void> _loadLastBackupTs() async {
    try {
      final ts = await BackupReminder.readLastTs();
      if (mounted) setState(() => _lastBackupTs = ts);
    } catch (_) {} // 提醒失败不阻断首页
  }

  Future<void> _loadUnseenBadges() async {
    try {
      final r = await BadgeApi.unseen(routeId: 'route_A', fresh: true);
      final n = (r['count'] as num?)?.toInt() ?? 0;
      if (mounted) setState(() => _unseenBadges = n);
    } catch (_) {} // 提醒失败不阻断首页
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
            // 本机数据是唯一副本（allowBackup=false），N 天没导出就提示备份
            if (_lastBackupTs != null &&
                BackupReminder.overdue(_lastBackupTs))
              _BackupReminderBanner(
                onTap: () => _push(const DataBackupScreen()),
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
                          tooltip: '我的勋章',
                          icon: Icons.emoji_events_rounded,
                          badgeCount: _unseenBadges,
                          onTap: () async {
                            // 必须在从勋章页**返回之后**再刷新红点数量：
                            // 以前是进页面之前刷一次，收下勋章回来数字照旧挂着。
                            await _push(const BadgeScreen());
                            await _loadUnseenBadges();
                          },
                        ),
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
  final int badgeCount;

  const _HeaderAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
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
              child: Stack(
                alignment: Alignment.topRight,
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 19, color: Colors.white),
                  if (badgeCount > 0)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 16,
                        height: 16,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 2, vertical: 0),
                        constraints: const BoxConstraints(minWidth: 16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.danger,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 首页顶部的「该备份了」提醒横幅。
///
/// 与 SyncNotice 同形态：一行图标 + 文案 + 操作按钮。点击直接进备份页，
/// 由用户自己决定什么时候导出（App 不强制弹窗打断阅读）。
class _BackupReminderBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _BackupReminderBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = const Color(0xFFB45309);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: color.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(Icons.backup_rounded, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '本机数据是唯一副本，建议每周导出一份备份，防丢机或卸载重装',
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
          TextButton(
            onPressed: onTap,
            child: const Text('去备份', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
