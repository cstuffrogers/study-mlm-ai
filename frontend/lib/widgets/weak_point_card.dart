// 薄弱点卡（T042）— 含"阻塞后续N章"标签 + 深入学习
import 'package:flutter/material.dart';
import '../models/learning_models.dart';
import 'mastery_badge.dart';
import '../theme/app_theme.dart';

class WeakPointCard extends StatelessWidget {
  final WeakPoint item;
  final VoidCallback? onReinforce;

  const WeakPointCard({super.key, required this.item, this.onReinforce});

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
                if (item.blockingSections > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.link, size: 11, color: Color(0xFFB91C1C)),
                        const SizedBox(width: 4),
                        Text('阻塞后续 ${item.blockingSections} 章',
                            style: const TextStyle(fontSize: 11, color: Color(0xFFB91C1C))),
                      ]),
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
              child: const Text('深入学习', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
