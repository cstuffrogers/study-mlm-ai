// 「我的勋章」页（spec 001 勋章系统）
//
// 数据源：`BadgeApi.mine()` → 单机版 LocalBadge.mine / 联网后端 /api/badges/mine。
// 展示：指标快照 → 分类分组勋章列表 → 每枚勋章的达成条件与进度。
// 开箱动画：进入页面时若有未查看新勋章，自动播放礼物开箱动画。
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../offline/local_badge.dart';
import '../widgets/anim.dart';
import '../widgets/badge_gift_open.dart';
import '../widgets/badge_share_card.dart';
import '../services/badge_service_api.dart';
import '../services/badge_share.dart';
import '../config/app_meta.dart';

class BadgeScreen extends StatefulWidget {
  const BadgeScreen({super.key, this.routeId = 'route_A'});

  final String routeId;

  @override
  State<BadgeScreen> createState() => _BadgeScreenState();
}

class _BadgeScreenState extends State<BadgeScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _badges = const [];
  Map<String, dynamic> _metrics = const {};
  Map<String, dynamic> _summary = const {};
  bool _animPlayed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final [mine, unseen] = await Future.wait([
        BadgeApi.mine(routeId: widget.routeId),
        BadgeApi.unseen(routeId: widget.routeId),
      ]);
      final unseenAwards = ((unseen['awards'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      final badges = ((mine['badges'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      setState(() {
        _badges = badges;
        _metrics = (mine['metrics'] as Map?)?.cast<String, dynamic>() ?? const {};
        _summary = (mine['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
        _loading = false;
      });
      if (!mounted || _animPlayed) return;
      if (unseenAwards.isNotEmpty) {
        _animPlayed = true;
        _showGiftAnimation(unseenAwards.first);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showGiftAnimation(Map<String, dynamic> award) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BadgeGiftOpen(
              name: '${award['name'] ?? ''}',
              iconKey: '${award['icon_key'] ?? 'star'}',
              description: '${award['description'] ?? ''}',
              onClose: () => Navigator.of(context).pop(),
            )));
    // 动画关闭后标记已读，刷新列表。
    await BadgeApi.markRead([award['award_id'] as String]);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的勋章'),
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: _badges.isEmpty ? null : _handleShare,
            tooltip: '分享勋章收藏卡',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : RefreshIndicator(
              color: AppColors.brand,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _buildSummary(),
                  const SizedBox(height: 16),
                  if (_metrics.isNotEmpty) _buildMetrics(),
                  const SizedBox(height: 16),
                  for (final cat in _categories()) _buildCategory(cat),
                ],
              ),
            ),
    );
  }

  // ------------------------------------------------------------ 分享

  /// 将已获得勋章渲染为收藏卡并调起系统分享面板。
  Future<void> _handleShare() async {
    try {
      final earned = _badges.where((b) => b['earned'] == true).toList();
      if (earned.isEmpty) return;
      final earnedCount = earned.length;
      final totalCount =
          (_summary['total'] as num?)?.toInt() ??
          allBadges().length;
      final items = earned
          .map((b) => BadgeShareItem(
              badgeId: '${b['badge_id']}',
              name: '${b['name'] ?? ''}',
              category: '${b['category'] ?? ''}',
              iconKey: '${b['icon_key'] ?? 'star'}'))
          .toList();
      final ok = await shareBadgeCard(
        context: context,
        appName: AppMeta.appName,
        earnedCount: earnedCount,
        totalCount: totalCount,
        badges: items,
      );
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('分享不可用，请尝试其他方式')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失败：$e')),
      );
    }
  }

  // ------------------------------------------------------------ 分类
  List<String> _categories() {
    final cats = <String>[];
    for (final b in _badges) {
      final c = b['category'] as String? ?? '';
      if (c.isNotEmpty && !cats.contains(c)) cats.add(c);
    }
    return cats;
  }

  IconData _iconFor(String iconKey) => BadgeGiftOpen.iconFor(iconKey);

  // ------------------------------------------------------------ 汇总卡
  Widget _buildSummary() {
    final earned = (_summary['earned'] as num?)?.toInt() ?? 0;
    final total = (_summary['total'] as num?)?.toInt() ?? 0;
    final unearned = (_summary['unearned'] as num?)?.toInt() ?? 0;
    final pct = total > 0 ? (earned / total * 100).clamp(0.0, 100.0).round() : 0;
    return GradientCard(
      gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [AppColors.gold, AppColors.goldSoft]),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(Icons.emoji_events_rounded,
                  color: AppColors.gold, size: 28),
              Text('$earned / $total',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.ink900)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: total > 0 ? earned / total : 0,
            color: AppColors.gold,
            backgroundColor: AppColors.goldSoft,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _statTile('已获得', '$earned', AppColors.brand),
              _statTile('未获得', '$unearned', AppColors.ink400),
              _statTile('完成度', '$pct%', AppColors.gold),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color)),
        const SizedBox(height: 2),
        Text(label,
            style:
                const TextStyle(fontSize: 12, color: AppColors.ink500)),
      ],
    );
  }

  // ------------------------------------------------------------ 指标快照
  Widget _buildMetrics() {
    final items = _metrics.entries.map((e) {
      final key = e.key;
      final val = (e.value as num).toInt();
      final label = _metricLabel(key);
      return (label, val);
    }).toList();
    return Card(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.line)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('学习指标',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.ink700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: items
                  .map((e) => _metricChip(e.$1, e.$2))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricChip(String label, int val) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$val',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand,
                  fontSize: 14)),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.ink500)),
        ],
      ),
    );
  }

  String _metricLabel(String key) {
    const map = <String, String>{
      'mastered_count': '掌握',
      'journey_count': '贯通',
      'milestones_achieved': '里程碑',
      'quiz_correct_total': '答对',
      'quiz_attempt_total': '作答',
      'routes_completed': '路线',
      'streak_days': '连击',
      'dialogues_completed': '对话',
    };
    return map[key] ?? key;
  }

  // ------------------------------------------------------------ 分类分组
  Widget _buildCategory(String cat) {
    final list = _badges
        .where((b) => b['category'] == cat)
        .toList()
      ..sort((a, b) => (a['sort_order'] as int)
              .compareTo(b['sort_order'] as int));
    final iconKey =
        list.isNotEmpty ? '${list.first['icon_key'] ?? ''}' : 'star';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_iconFor(iconKey), color: AppColors.brand, size: 22),
            const SizedBox(width: 6),
            Text(cat,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.ink900)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.brandSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${list.length}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brand)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final b in list) AnimatedEntrance(
            delayMs: 30, child: _BadgeCard(badge: b, icon: _iconFor('${b['icon_key'] ?? 'star'}'))),
      ],
    );
  }
}

// ------------------------------------------------------------ 单枚勋章卡
class _BadgeCard extends StatelessWidget {
  const _BadgeCard({required this.badge, required this.icon});

  final Map<String, dynamic> badge;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final earned = badge['earned'] == true;
    final disabled = badge['disabled'] == true;
    final progress = (badge['progress'] as Map?)?.cast<String, dynamic>() ?? const {};
    final display = progress['display'] as String? ?? '';
    final target = (progress['target'] as num?)?.toInt();
    final current = (progress['current'] as num?)?.toInt();
    final pct =
        (target != null && target > 0 && current != null) ? (current / target).clamp(0.0, 1.0) : 0.0;

    return Card(
      color: earned ? AppColors.goldSoft : AppColors.surface,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: earned ? AppColors.gold : AppColors.line,
              width: earned ? 1.5 : 1)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 勋章图标
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: earned
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.gold, AppColors.goldSoft, AppColors.gold])
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.ink400,
                          AppColors.surface,
                          AppColors.ink400,
                        ]),
              ),
              alignment: Alignment.center,
              child: Icon(icon,
                  size: 30,
                  color: earned ? AppColors.brandDeep : AppColors.ink400),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(badge['name'] as String,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: earned
                                    ? AppColors.brandDeep
                                    : AppColors.ink700)),
                      ),
                      if (earned)
                        const Icon(Icons.check_circle,
                            color: AppColors.success, size: 18),
                      if (disabled)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: AppColors.ink400.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8)),
                            child: const Text('停用',
                                style: TextStyle(
                                    fontSize: 10, color: AppColors.ink500)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(badge['description'] as String,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.ink500)),
                  const SizedBox(height: 6),
                  // 进度条
                  if (display.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: LinearProgressIndicator(
                                value: pct,
                                color: earned ? AppColors.gold : AppColors.brand,
                                backgroundColor: AppColors.line,
                                minHeight: 5,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 90,
                              child: Text(display,
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.ink500)),
                            ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
