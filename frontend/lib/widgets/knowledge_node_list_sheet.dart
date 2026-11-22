// 知识点列表弹层（进度平稳卡片点击展开）：按书籍分组，点击知识点跳转到该章节深入学习界面。
import 'package:flutter/material.dart';

import '../screens/chapter_guide_screen.dart';
import '../theme/app_theme.dart';

/// 弹出知识点列表。kind = 'mastered' 已掌握 / 'weak' 薄弱。
/// nodes 由 `LocalInsight.motivation()` 的 `mastered_nodes` / `weak_nodes` 提供。
void showKnowledgeNodeList(
  BuildContext context, {
  required List<Map<String, dynamic>> nodes,
  required String routeId,
  required String kind,
}) {
  if (nodes.isEmpty) {
    showDialog(
      context: context,
      builder: (_) => const AlertDialog(
        title: Text('暂无记录'),
        content: Text('还没有可查看的知识点，继续学习后这里会显示。'),
      ),
    );
    return;
  }
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => KnowledgeNodeListSheet(
      nodes: nodes,
      routeId: routeId,
      kind: kind,
    ),
  );
}

class KnowledgeNodeListSheet extends StatelessWidget {
  final List<Map<String, dynamic>> nodes;
  final String routeId;
  final String kind; // 'mastered' | 'weak'

  const KnowledgeNodeListSheet({
    super.key,
    required this.nodes,
    required this.routeId,
    required this.kind,
  });

  bool get _isMastered => kind == 'mastered';

  @override
  Widget build(BuildContext context) {
    // 按书籍分组，保持出现顺序
    final groups = <Map<String, dynamic>>[];
    final groupMap = <String, Map<String, dynamic>>{};
    for (final node in nodes) {
      final work =
          node['work'] as String? ?? node['work_short'] as String? ?? '';
      final key = work.isEmpty ? '其他' : work;
      if (groupMap.containsKey(key)) {
        groupMap[key]!['nodes'].add(node);
      } else {
        groupMap[key] = <String, dynamic>{'work': key, 'nodes': [node]};
        groups.add(groupMap[key]!);
      }
    }

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.78),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.line, width: 0.6),
                ),
              ),
              child: Row(children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _isMastered
                        ? AppColors.success.withValues(alpha: 0.12)
                        : AppColors.warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isMastered ? Icons.check_circle : Icons.warning_amber_outlined,
                    color: _isMastered
                        ? AppColors.success
                        : AppColors.warning,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _isMastered ? '已掌握知识点' : '薄弱知识点',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800,
                      color: AppColors.ink900),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _isMastered
                        ? AppColors.success.withValues(alpha: 0.1)
                        : AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '共 ${nodes.length} 个',
                    style: TextStyle(
                        fontSize: 11,
                        color: _isMastered
                            ? AppColors.success
                            : AppColors.warning,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
            // 列表
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: groups.map((group) {
                  final work = group['work'] as String;
                  final groupNodes =
                      (group['nodes'] as List).cast<Map<String, dynamic>>();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                        child: Text(
                          work,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700,
                              color: AppColors.ink400),
                        ),
                      ),
                      ...groupNodes.map((node) => _nodeRow(context, node)),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nodeRow(BuildContext context, Map<String, dynamic> node) {
    final nodeId = node['node_id'] as String;
    final name = node['name'] as String? ?? nodeId;
    final sectionId = node['section_id'] as String? ?? '';
    final sectionTitle = node['title'] as String? ?? sectionId;
    final level = node['level'] as String? ?? 'unseen';
    final score = (node['score'] as num?)?.toDouble() ?? 0.0;

    return ListTile(
      onTap: () {
        // 关闭弹层后跳转到该章节深入学习界面
        Navigator.of(context, rootNavigator: true).pop();
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => ChapterGuideScreen(
              routeId: routeId,
              sectionId: sectionId,
              sectionTitle: sectionTitle,
            ),
          ),
        );
      },
      contentPadding: const EdgeInsets.symmetric(
          horizontal: 20, vertical: 8),
      leading: Container(
        width: 6,
        height: 36,
        decoration: BoxDecoration(
          color: _levelColor(level).withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      title: Text(name,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600,
              color: AppColors.ink900)),
      subtitle: Text(
        '${_levelLabel(level)} · 掌握度 ${(score * 100).round()}%',
        style: const TextStyle(fontSize: 11, color: AppColors.ink400),
      ),
      trailing: Icon(Icons.chevron_right,
          size: 20, color: AppColors.ink400),
    );
  }

  Color _levelColor(String level) {
    if (level == 'mastered') return AppColors.success;
    if (level == 'beginner') return AppColors.warning;
    return AppColors.ink400;
  }

  String _levelLabel(String level) {
    if (level == 'mastered') return '已掌握';
    if (level == 'beginner') return '入门';
    if (level == 'familiar') return '熟悉';
    if (level == 'proficient') return '精通';
    return '未接触';
  }
}
