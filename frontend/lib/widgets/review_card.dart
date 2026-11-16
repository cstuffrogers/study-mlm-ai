// 复习卡（P1-① D8）— 到期复习提醒 + 快速自评回写（暖色渐变 + 卡片化）
import 'package:flutter/material.dart';
import '../models/learning_models.dart';
import '../theme/app_theme.dart';

class ReviewCard extends StatelessWidget {
  final List<ReviewItem> items;
  // onReview(nodeId, correctRatio)
  final void Function(String nodeId, double correctRatio)? onReview;

  const ReviewCard({super.key, required this.items, this.onReview});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFBEB), Color(0xFFFFF7ED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: const Color(0xFFFDE68A)),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFFD97706).withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                  color: const Color(0xFFD97706).withValues(alpha: 0.15), shape: BoxShape.circle),
              child: const Icon(Icons.refresh, size: 18, color: Color(0xFFD97706)),
            ),
            const SizedBox(width: 8),
            const Text('该复习了 · 抗遗忘',
                style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFB45309), fontSize: 14)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('到期 ${items.length} 项',
                  style: const TextStyle(fontSize: 11, color: Color(0xFFB45309), fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 6),
          Text('有 ${items.length} 个知识点可快速巩固，花 1 分钟回忆或混合练习可显著延长记忆。',
              style: const TextStyle(fontSize: 12, color: Color(0xFF78350F), height: 1.5)),
          const SizedBox(height: 6),
          ...items.take(6).map((it) => Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  if (it.kind == 'interleave')
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('交错巩固',
                          style: TextStyle(fontSize: 10, color: Color(0xFF0369A1), fontWeight: FontWeight.w600)),
                    ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(it.name,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      Text(
                          it.kind == 'interleave'
                              ? '跨知识点混合练习，加强检索与迁移'
                              : '已隔 ${it.elapsedDays.toStringAsFixed(0)} 天 · 保持率 ${(it.retention * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF92400E))),
                    ]),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.success,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                    ),
                    onPressed: onReview == null ? null : () => onReview!(it.nodeId, 1.0),
                    child: const Text('还记得', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                    ),
                    onPressed: onReview == null ? null : () => onReview!(it.nodeId, 0.2),
                    child: const Text('忘了', style: TextStyle(fontSize: 12)),
                  ),
                ]),
              )),
        ],
      ),
    );
  }
}
