// 立场待核标注（D171）
//
// 为什么要单独做成一个 widget、而不是直接改拦截卡片：
// 拦截卡（blocked）讲的是「这段不能展示」；这里讲的是相反的事 ——
// **回答照常展示**，只是里面出现了批判对象术语的中性使用（「物化劳动指…」）
// 或者被引述的反面例子，规则层只召回、不下定论。
// 把这两件事混在一个 UI 里，用户又会以为「是不是又要拦我了」。
//
// 交互：默认一行摘要（不打扰阅读），点开才展开每处的理由与流派归属。
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class StanceNoteChip extends StatefulWidget {
  /// 每项：{term, school, reason}
  final List<Map<String, String>> notes;

  const StanceNoteChip({super.key, required this.notes});

  @override
  State<StanceNoteChip> createState() => _StanceNoteChipState();
}

class _StanceNoteChipState extends State<StanceNoteChip> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (widget.notes.isEmpty) return const SizedBox.shrink();
    final terms = widget.notes
        .map((n) => (n['term'] ?? '').trim())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Row(children: [
              const Icon(Icons.rule_rounded, size: 13, color: AppColors.warning),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '立场待核 ${widget.notes.length} 处'
                  '${terms.isEmpty ? '' : ' · ${terms.take(3).join('、')}'}',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.warning,
                      fontWeight: FontWeight.w600),
                ),
              ),
              Icon(_open ? Icons.expand_less : Icons.expand_more,
                  size: 15, color: AppColors.warning),
            ]),
          ),
          if (_open) ...[
            const SizedBox(height: 5),
            for (final n in widget.notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '· ${n['reason'] ?? ''}',
                  style: const TextStyle(
                      fontSize: 11, height: 1.45, color: AppColors.ink500),
                ),
              ),
            const SizedBox(height: 2),
            const Text(
              '这只是提示，回答已正常展示。若你要的正是批判它，把该说法写进引号或'
              '「有人说……」即可，不算你的立场。',
              style: TextStyle(fontSize: 10.5, height: 1.4, color: AppColors.ink400),
            ),
          ],
        ],
      ),
    );
  }
}
