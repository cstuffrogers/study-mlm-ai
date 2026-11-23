// 薄弱点卡（T042）— 深入学习按钮（替代阻塞后续标签）+ 补学按钮（测试）
import 'package:flutter/material.dart';
import '../models/learning_models.dart';
import 'mastery_badge.dart';
import '../theme/app_theme.dart';

class WeakPointCard extends StatelessWidget {
  final WeakPoint item;
  final VoidCallback? onReinforce;
  final VoidCallback? onDeepLearn;

  const WeakPointCard({super.key, required this.item, this.onReinforce, this.onDeepLearn});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.report_gmailerrorred, color: AppColors.danger, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(item.name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                    const SizedBox(width: 8),
                    MasteryBadge(level: item.level, score: item.score, dense: true),
                  ],
                ),
                if (onDeepLearn != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        minimumSize: Size.zero,
                      ),
                      onPressed: onDeepLearn,
                      icon: const Icon(Icons.menu_book_outlined, size: 14, color: AppColors.brand),
                      label: const Text('深入学习',
                          style: TextStyle(fontSize: 11.5, color: AppColors.brand)),
                    ),
                  ),
              ],
            ),
          ),
          if (onReinforce != null)
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
              ),
              onPressed: onReinforce,
              child: const Text('补学', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
