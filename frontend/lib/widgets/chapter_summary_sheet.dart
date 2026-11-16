// 章节小结 + 待巩固清单卡（T024）— 附"去测试"按钮
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ChapterSummarySheet extends StatelessWidget {
  final List<String> keyPoints;
  final List<String> toReinforce;
  final VoidCallback? onGoTest;

  const ChapterSummarySheet({
    super.key,
    required this.keyPoints,
    required this.toReinforce,
    this.onGoTest,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.receipt_long, color: Colors.white, size: 19),
            ),
            const SizedBox(width: 10),
            const Text('本章小结', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 16),
          Row(children: const [
            Icon(Icons.check_circle, size: 15, color: AppColors.success),
            SizedBox(width: 6),
            Text('要点', style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          ...keyPoints.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_circle_outline, size: 16, color: AppColors.success),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(e, style: const TextStyle(fontSize: 13, height: 1.5))),
                ]),
              )),
          if (toReinforce.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(children: const [
              Icon(Icons.error_outline, size: 15, color: AppColors.danger),
              SizedBox(width: 6),
              Text('待巩固', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger)),
            ]),
            const SizedBox(height: 8),
            ...toReinforce.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.error_outline, size: 16, color: Color(0xFFEF4444)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(e, style: const TextStyle(fontSize: 13, height: 1.5))),
                  ]),
                )),
          ],
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: onGoTest,
              icon: const Icon(Icons.edit_note),
              label: const Text('去测试', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
