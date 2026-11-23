// 动机/挫折调节横幅（P3 D14）— 分级鼓励 + 里程碑（三类三行）+ 最小下一步
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

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
          // 里程碑：三类三行，每类不同图标；已达成逐个显示，末尾显示下个目标
          if (milestones.isNotEmpty) ...[
            const SizedBox(height: 10),
            _milestoneSection(
              category: '贯通',
              icon: Icons.verified,
              color: AppColors.success,
              ms: milestones.where((e) => (e as Map)['category'] == '贯通').toList(),
            ),
            _milestoneSection(
              category: '连续学习',
              icon: Icons.local_fire_department,
              color: AppColors.warning,
              ms: milestones.where((e) => (e as Map)['category'] == '连续学习').toList(),
            ),
            _milestoneSection(
              category: '累计作答',
              icon: Icons.assignment,
              color: AppColors.brand,
              ms: milestones.where((e) => (e as Map)['category'] == '累计作答').toList(),
            ),
          ],
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

  // 里程碑类别行：左侧图标+类别名，右侧已达成chips + 下个目标chip
  Widget _milestoneSection({
    required String category,
    required IconData icon,
    required Color color,
    required List ms,
  }) {
    final achieved = ms.where((e) => (e as Map)['achieved'] == true).toList();
    final pending = ms.where((e) => (e as Map)['achieved'] != true).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 76,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(category,
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: color)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                // 每完成一个里程碑就多一个已达成chip
                ...achieved.map((e) => _msChip(e, done: true, color: color)),
                // 末尾显示下个目标
                if (pending.isNotEmpty) _msChip(pending.first, done: false, color: color),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 里程碑chip：已达成打勾 / 下个目标箭头
  Widget _msChip(Map m, {required bool done, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: done ? color.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: done ? color.withValues(alpha: 0.5) : AppColors.line),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
            done ? Icons.check_circle_outline : Icons.arrow_forward,
            size: 12,
            color: done ? color : AppColors.ink400),
        const SizedBox(width: 4),
        Flexible(
            child: Text('${m['label']}',
                style: TextStyle(
                    fontSize: 11,
                    color: done ? color : AppColors.ink500,
                    fontWeight: done ? FontWeight.w600 : FontWeight.w400))),
      ]),
    );
  }
}
