// 推荐卡（T048）— 一句话理由 + 一键进入，跨页复用（渐变底 + 微光）
import 'package:flutter/material.dart';
import '../models/learning_models.dart';
import '../theme/app_theme.dart';

class RecommendationCard extends StatelessWidget {
  final Recommendation rec;
  final VoidCallback? onEnter;
  final bool compact;

  const RecommendationCard({super.key, required this.rec, this.onEnter, this.compact = false});

  IconData get _icon {
    switch (rec.recType) {
      case 'reinforce':
        return Icons.build_circle_outlined;
      case 'next_section':
      case 'start':
        return Icons.play_circle_outline;
      case 'review':
        return Icons.refresh;
      default:
        return Icons.lightbulb_outline;
    }
  }

  String get _tag {
    switch (rec.recType) {
      case 'reinforce':
        return '专项回补';
      case 'next_section':
        return '下一章';
      case 'start':
        return '起步';
      case 'review':
        return '复习';
      default:
        return '推荐';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFDF1EF), Color(0xFFFBF1DA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: const Color(0xFFF3C9C6)),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 40 : 48,
            height: compact ? 40 : 48,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: AppColors.brand.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 5)),
              ],
            ),
            child: Icon(_icon, color: Colors.white, size: compact ? 22 : 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.auto_awesome, size: 12, color: AppColors.brand),
                  const SizedBox(width: 4),
                  Text('今日推荐 · $_tag',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.brand, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 4),
                Text(rec.reason,
                    style: const TextStyle(fontSize: 14, color: AppColors.ink900, height: 1.4)),
              ],
            ),
          ),
          if (onEnter != null) ...[
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onPressed: onEnter,
              child: const Text('一键进入'),
            ),
          ],
        ],
      ),
    );
  }
}
