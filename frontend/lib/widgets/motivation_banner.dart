// 动机/挫折调节横幅（P3 D14）— 分级鼓励 + 里程碑 + 最小下一步
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'knowledge_node_list_sheet.dart';

class MotivationBanner extends StatelessWidget {
  final Map<String, dynamic> state;
  final VoidCallback? onAction;

  const MotivationBanner({super.key, required this.state, this.onAction});

  @override
  Widget build(BuildContext context) {
    final frust = (state['frustration'] as Map?)?.cast<String, dynamic>() ?? {};
    final level = frust['level'] ?? 'low';
    final drivers = (frust['drivers'] as List?) ?? const [];
    final milestones = (state['milestones'] as List?) ?? const [];
    final nextBest = (state['next_best_action'] as Map?)?.cast<String, dynamic>() ?? {};

    final color = level == 'high'
        ? AppColors.danger
        : level == 'mid'
            ? AppColors.warning
            : AppColors.success;
    final grad = level == 'high'
        ? const [Color(0xFFFEF2F2), Color(0xFFFFF1F2)]
        : level == 'mid'
            ? const [Color(0xFFFFFBEB), Color(0xFFFEF3C7)]
            : const [Color(0xFFF0FDF4), Color(0xFFECFDF5)];
    final icon = level == 'high'
        ? Icons.favorite
        : level == 'mid'
            ? Icons.trending_up
            : Icons.emoji_events_outlined;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 8),
            Text(level == 'high' ? '先喘口气' : level == 'mid' ? '稳步推进' : '进度平稳',
                style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 14)),
            const Spacer(),
            if ((state['mastered'] ?? 0) is int)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('贯通 ${state['mastered']} 点 · 连续 ${state['streak_days'] ?? 0} 天',
                    style: const TextStyle(fontSize: 11, color: AppColors.ink500)),
              ),
          ]),
          const SizedBox(height: 8),
          Text('${state['encouragement'] ?? ''}',
              style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.ink700)),
          if (drivers.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.info_outline, size: 13, color: Color(0xFFB45309)),
              const SizedBox(width: 4),
              Expanded(
                child: Text('注意：${drivers.join('；')}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFFB45309))),
              ),
            ]),
          ],
          if (milestones.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: milestones.map((m) {
                final mm = (m as Map).cast<String, dynamic>();
                final done = mm['achieved'] == true;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: done ? color.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: done ? color.withValues(alpha: 0.5) : AppColors.line),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 13, color: done ? color : AppColors.ink400),
                    const SizedBox(width: 4),
                    Text('${mm['label']}',
                        style: TextStyle(
                            fontSize: 11,
                            color: done ? color : AppColors.ink500,
                            fontWeight: done ? FontWeight.w600 : FontWeight.w400)),
                  ]),
                );
              }).toList(),
            ),
          ],
          // 知识点掌握统计（可点击展开知识点列表，按书籍分组，再点知识点进入深入学习）
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statTap(
                context: context,
                icon: Icons.check_circle,
                color: AppColors.success,
                label: '已掌握',
                count: state['mastered'] ?? 0,
                nodes: (state['mastered_nodes'] as List?)
                        ?.cast<Map<String, dynamic>>() ??
                    const [],
                kind: 'mastered',
                routeId: state['route_id'] as String? ?? '',
              ),
              _statTap(
                context: context,
                icon: Icons.warning_amber_outlined,
                color: AppColors.warning,
                label: '薄弱',
                count: state['weak'] ?? 0,
                nodes: (state['weak_nodes'] as List?)
                        ?.cast<Map<String, dynamic>>() ??
                    const [],
                kind: 'weak',
                routeId: state['route_id'] as String? ?? '',
              ),
            ],
          ),
          if (nextBest.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.brand),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${nextBest['label'] ?? ''}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.ink900, fontWeight: FontWeight.w600)),
                ),
                if (onAction != null)
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero),
                    onPressed: onAction,
                    child: const Text('开始', style: TextStyle(fontSize: 12)),
                  ),
              ]),
            ),
            if ('${nextBest['reason'] ?? ''}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: Text('${nextBest['reason']}',
                    style: const TextStyle(fontSize: 11, color: AppColors.ink400)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _statTap({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String label,
    required dynamic count,
    required List<Map<String, dynamic>> nodes,
    required String kind,
    required String routeId,
  }) {
    final n = count is int ? count : 0;
    return GestureDetector(
      onTap: () => showKnowledgeNodeList(
          context, nodes: nodes, routeId: routeId, kind: kind),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text('$label $n 个',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ]),
      ),
    );
  }
}
