// 勋章收藏卡组件（spec 001 勋章系统 · US5 分享）
//
// 平台无关：纯展示组件，由 `badge_share_native.dart` / `badge_share_web.dart`
// 渲染为 PNG 后分享。包含应用名、已获得勋章数量、分类勋章墙与分享文案。
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/badge_gift_open.dart';

/// 收藏卡上单枚勋章的精简数据。
class BadgeShareItem {
  const BadgeShareItem({
    required this.badgeId,
    required this.name,
    required this.category,
    required this.iconKey,
  });

  final String badgeId;
  final String name;
  final String category;
  final String iconKey;
}

/// 勋章收藏卡：标题 → 数量概览 → 分类勋章墙 → 分享文案。
///
/// 外层须用 `RepaintBoundary` 包裹（分享服务负责），以便截图时只重绘自身。
class BadgeShareCard extends StatelessWidget {
  const BadgeShareCard({
    super.key,
    required this.appName,
    required this.earnedCount,
    required this.totalCount,
    required this.badges,
    required this.shareText,
  });

  final String appName;
  final int earnedCount;
  final int totalCount;
  final List<BadgeShareItem> badges;
  final String shareText;

  // 分类显示名
  static const _categoryLabels = <String, String>{
    'knowledge': '知识掌握',
    'journey': '贯通学习',
    'milestone': '里程碑',
    'quiz': '答题达人',
    'route': '路线完成',
    'streak': '连续学习',
    'dialogue': '经典对话',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.brand,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // —— 标题 ——
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(Icons.emoji_events_rounded,
                  color: AppColors.gold, size: 28),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                ),
                child: Text(
                  appName,
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '勋章收藏卡',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // —— 数量概览 ——
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.verified_rounded,
                    color: AppColors.gold, size: 32),
                const SizedBox(width: 10),
                Text(
                  '$earnedCount / $totalCount',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.emoji_events_rounded,
                    color: AppColors.gold, size: 28),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // —— 勋章墙（按分类排列）——
          _buildBadgeWall(),
          const SizedBox(height: 20),

          // —— 分享文案 ——
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              shareText,
              style: TextStyle(
                color: AppColors.ink700.withValues(alpha: 0.85),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeWall() {
    if (badges.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text(
          '暂未获得勋章，继续加油！',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
      );
    }
    // 按分类分组
    final groups = <String, List<BadgeShareItem>>{};
    for (final b in badges) {
      final key = b.category;
      groups.putIfAbsent(key, () => []).add(b);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '勋章墙',
          style: TextStyle(
            color: AppColors.gold,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        for (final entry in groups.entries) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _categoryLabels[entry.key] ?? entry.key,
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${entry.value.length} 枚',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final b in entry.value)
                _BadgeTile(badge: b),
            ],
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

/// 收藏卡上的单枚勋章图标 + 名称。
class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge});

  final BadgeShareItem badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.gold.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            BadgeGiftOpen.iconFor(badge.iconKey),
            size: 20,
            color: AppColors.gold,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              badge.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
