// 掌握度徽章（五级统一色阶，T033）— 带小圆点与柔和底色的胶囊
import 'package:flutter/material.dart';

class MasteryStyle {
  final String label;
  final Color color;
  const MasteryStyle(this.label, this.color);

  static MasteryStyle of(String level) {
    switch (level) {
      case 'mastered':
        return const MasteryStyle('贯通', Color(0xFF16A34A));
      case 'proficient':
        return const MasteryStyle('精通', Color(0xFFD4A017));
      case 'familiar':
        return const MasteryStyle('熟悉', Color(0xFFD97706));
      case 'beginner':
        return const MasteryStyle('初学', Color(0xFFEA580C));
      case 'unseen':
      default:
        return const MasteryStyle('未接触', Color(0xFF94A3B8));
    }
  }
}

class MasteryBadge extends StatelessWidget {
  final String level;
  final double? score;
  final bool dense;

  const MasteryBadge({super.key, required this.level, this.score, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final s = MasteryStyle.of(level);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 9, vertical: dense ? 3 : 4),
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: s.color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dense ? 5 : 6,
            height: dense ? 5 : 6,
            decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
          ),
          SizedBox(width: dense ? 4 : 5),
          Text(
            score != null ? '${s.label} ${(score! * 100).toStringAsFixed(0)}%' : s.label,
            style: TextStyle(
                color: s.color, fontSize: dense ? 10 : 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
