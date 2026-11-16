// 即时小结卡（T023）— 折叠不打断，复用 reader/chat 形态
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'chat_markdown.dart';

class InstantSummaryCard extends StatelessWidget {
  final String oneLine;
  final String checkQuestion;

  const InstantSummaryCard({super.key, required this.oneLine, required this.checkQuestion});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFBF7F5), Color(0xFFFDF1EF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.summarize_outlined, size: 18, color: AppColors.brand),
        ),
        title: const Text('即时小结', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        subtitle: Text(ChatMarkdown.plainPreview(oneLine),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.ink500)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ChatMarkdown(text: oneLine, baseColor: AppColors.ink700),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              children: [
                const Icon(Icons.help_outline, size: 16, color: Color(0xFFD97706)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('检验：${ChatMarkdown.plainPreview(checkQuestion)}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF92400E))),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
