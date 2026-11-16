// 知识点详情页 — 掌握分/等级/证据/前置与后继节点（可点跳转）
// 数据来自 GET /api/mastery/node/{node_id}
import 'package:flutter/material.dart';
import '../services/mastery_service_api.dart';
import '../widgets/mastery_badge.dart';
import '../widgets/chunk_tag.dart';
import '../widgets/anim.dart';
import '../theme/app_theme.dart';

const _levelLabels = {
  'unseen': '未接触', 'beginner': '初学', 'familiar': '熟悉',
  'proficient': '精通', 'mastered': '贯通',
};

class KnowledgeNodeScreen extends StatefulWidget {
  final String nodeId;
  final String routeId;
  const KnowledgeNodeScreen({super.key, required this.nodeId, this.routeId = 'route_A'});

  @override
  State<KnowledgeNodeScreen> createState() => _KnowledgeNodeScreenState();
}

class _KnowledgeNodeScreenState extends State<KnowledgeNodeScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final j = await MasteryApi().node(widget.nodeId, routeId: widget.routeId);
      setState(() { _data = j; _loading = false; });
    } catch (e) {
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF7F5),
      appBar: AppBar(title: Text(_data?['name']?.toString() ?? '知识点详情')),
      body: AuroraBackground(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('加载失败：$_error', style: const TextStyle(color: AppColors.ink500)),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _load, child: const Text('重试')),
        ]),
      );
    }
    final d = _data ?? {};
    final level = d['level']?.toString() ?? 'unseen';
    final score = (d['score'] as num?)?.toDouble() ?? 0.0;
    final basis = (d['basis'] as Map?)?.cast<String, dynamic>() ?? const {};
    final prereqs = (d['prerequisites'] as List?) ?? const [];
    final dependents = (d['dependents'] as List?) ?? const [];
    final sourceChunkId = (d['source_chunk_id'] ?? '').toString();

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        _scoreCard(d, level, score),
        const SizedBox(height: 14),
        if ((d['definition'] ?? '').toString().isNotEmpty) ...[
          _title('定义'),
          _card(Text(d['definition'].toString(),
              style: const TextStyle(fontSize: 14, height: 1.7, color: AppColors.ink700))),
          const SizedBox(height: 14),
        ],
        if (sourceChunkId.isNotEmpty) ...[
          _title('原文出处'),
          _card(Row(children: [
            const Icon(Icons.menu_book_outlined, size: 16, color: AppColors.brand),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ChunkTag(
                  chunkId: sourceChunkId,
                  fallbackText: d['definition']?.toString(),
                ),
              ),
            ),
          ])),
          const SizedBox(height: 14),
        ],
        if (basis.isNotEmpty) ...[
          _title('掌握依据（五信号）'),
          _card(Column(
            children: basis.entries.map((e) {
              final v = (e.value as num?)?.toDouble() ?? 0.0;
              final label = _basisLabel(e.key);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(width: 96, child: Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.ink500))),
                  Expanded(child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: v.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: AppColors.line,
                      valueColor: const AlwaysStoppedAnimation(AppColors.brand),
                    ),
                  )),
                  const SizedBox(width: 8),
                  SizedBox(width: 40, child: Text(v.toStringAsFixed(2),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12, color: AppColors.ink500))),
                ]),
              );
            }).toList(),
          )),
          const SizedBox(height: 14),
        ],
        if (prereqs.isNotEmpty) ...[
          _title('前置知识点（需先掌握）'),
          ...prereqs.map((n) => _nodeRow((n as Map).cast<String, dynamic>())),
          const SizedBox(height: 14),
        ],
        if (dependents.isNotEmpty) ...[
          _title('后续知识点（掌握本点可解锁）'),
          ...dependents.map((n) => _nodeRow((n as Map).cast<String, dynamic>())),
        ],
      ],
    );
  }

  String _basisLabel(String k) {
    switch (k) {
      case 'accuracy': return '正确率';
      case 'difficulty': return '难度';
      case 'review_stability': return '复习稳定';
      case 'dialogue': return '对话信号';
      case 'feynman': return '费曼';
      case 'stability': return '记忆稳定';
      default: return k;
    }
  }

  Widget _scoreCard(Map<String, dynamic> d, String level, double score) {
    return AnimatedEntrance(
      child: GradientCard(
        radius: AppRadius.hero,
        gradient: AppColors.heroGradient,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.hub, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(d['section_id']?.toString() ?? '',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5)),
            ),
            if ((d['ability_dim'] ?? '').toString().isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                child: Text(_dimLabel(d['ability_dim'].toString()),
                    style: const TextStyle(color: Colors.white, fontSize: 11)),
              ),
          ]),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(score.toStringAsFixed(2),
                style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, height: 1)),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text('掌握分 · ${_levelLabels[level] ?? level}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
            ),
            const Spacer(),
            if ((d['exam_weight'] as num?) != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('考纲权重 ${(d['exam_weight'] as num).toStringAsFixed(2)}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
              ),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: score.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        ]),
      ),
    );
  }

  String _dimLabel(String d) {
    switch (d) {
      case 'materialism': return '唯物主义';
      case 'dialectics': return '辩证法';
      case 'epistemology': return '认识论';
      case 'historical_materialism': return '唯物史观';
      case 'political_economy': return '政治经济学';
      default: return d;
    }
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Container(width: 3, height: 14, color: AppColors.brand, margin: const EdgeInsets.only(right: 8)),
          Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink700)),
        ]),
      );

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.line),
        ),
        child: child,
      );

  Widget _nodeRow(Map<String, dynamic> n) {
    final lv = n['level']?.toString() ?? 'unseen';
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => KnowledgeNodeScreen(nodeId: n['node_id'].toString(), routeId: widget.routeId))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(children: [
          Expanded(child: Text(n['name']?.toString() ?? '',
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink700))),
          MasteryBadge(level: lv, dense: true),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, size: 18, color: AppColors.ink400),
        ]),
      ),
    );
  }
}
