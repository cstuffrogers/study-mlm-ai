// 测试历史 / 错题本 — 逐题作答记录，可按错题过滤，展开看题面/答案/解析/溯源
import 'package:flutter/material.dart';
import '../offline/local_quiz.dart';
import '../services/content_service_api.dart';
import '../widgets/chunk_tag.dart';
import '../widgets/anim.dart';
import '../theme/app_theme.dart';

class TestHistoryScreen extends StatefulWidget {
  final String routeId;
  const TestHistoryScreen({super.key, this.routeId = 'route_A'});

  @override
  State<TestHistoryScreen> createState() => _TestHistoryScreenState();
}

class _TestHistoryScreenState extends State<TestHistoryScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _onlyWrong = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final j = await QuizHistoryApi().history(onlyWrong: _onlyWrong, limit: 200);
      setState(() { _data = j; _loading = false; });
    } catch (e) {
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _data?['total'] ?? 0;
    final wrong = _data?['wrong'] ?? 0;
    return Scaffold(
      backgroundColor: const Color(0xFFFBF7F5),
      appBar: AppBar(
        title: const Text('测试历史 / 错题本'),
        actions: [
          IconButton(
            tooltip: _onlyWrong ? '显示全部' : '只看错题',
            icon: Icon(_onlyWrong ? Icons.filter_alt : Icons.filter_alt_outlined),
            color: _onlyWrong ? AppColors.brand : null,
            onPressed: () { setState(() => _onlyWrong = !_onlyWrong); _load(); },
          ),
        ],
      ),
      body: AuroraBackground(child: _buildBody(total, wrong)),
    );
  }

  Widget _buildBody(int total, int wrong) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('加载失败：$_error', style: const TextStyle(color: AppColors.ink500)),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: _load, child: const Text('重试')),
      ]));
    }
    final rows = (_data?['rows'] as List?) ?? const [];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Row(children: [
          _stat('作答记录', '$total', AppColors.brand),
          const SizedBox(width: 10),
          _stat('错题', '$wrong', AppColors.danger),
          const SizedBox(width: 10),
          _stat('正确率', total == 0 ? '—' : '${((total - wrong) / total * 100).toStringAsFixed(0)}%', AppColors.success),
        ]),
      ),
      Expanded(
        child: rows.isEmpty
            ? Center(child: Text(_onlyWrong ? '暂无错题，继续保持！' : '暂无作答记录',
                style: const TextStyle(color: AppColors.ink400)))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                itemCount: rows.length,
                itemBuilder: (c, i) => _row((rows[i] as Map).cast<String, dynamic>()),
              ),
      ),
    ]);
  }

  Widget _stat(String label, String value, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.ink400)),
          ]),
        ),
      );

  Widget _row(Map<String, dynamic> r) {
    final correct = r['is_correct'] == true;
    final color = correct ? AppColors.success : AppColors.danger;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(correct ? Icons.check : Icons.close, color: color, size: 18),
          ),
          title: Text(r['stem']?.toString() ?? '',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink700)),
          subtitle: Text(
              '${r['section_title'] ?? r['section_id']} · ${_typeLabel(r['type']?.toString() ?? '')} · 得分 ${(r['score'] as num?)?.toStringAsFixed(2) ?? '0'}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.ink400)),
          children: [
            _kv('你的作答', _answerText(r), correct ? AppColors.success : AppColors.danger),
            if (!correct && (r['answer_key'] ?? '').toString().isNotEmpty)
              _kv('正确答案', _answerText({'answer': r['answer_key'], 'options': r['options']}),
                  AppColors.success),
            if ((r['explanation'] ?? '').toString().isNotEmpty)
              _kv('解析', r['explanation'].toString(), AppColors.ink700),
            if ((r['error_category'] ?? '').toString().isNotEmpty)
              _kv('错因', _errLabel(r['error_category'].toString()), AppColors.warning),
            if ((r['error_reason'] ?? '').toString().isNotEmpty)
              _kv('诊断', r['error_reason'].toString(), AppColors.ink500),
            if ((r['created_at'] ?? '').toString().isNotEmpty)
              _kv('时间', r['created_at'].toString().split('.').first, AppColors.ink400),
            if ((r['source_chunk_id'] ?? '').toString().isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: ChunkTag(
                    chunkId: r['source_chunk_id'].toString(),
                    label: '溯源 原文分片',
                    fallbackText: r['explanation']?.toString(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, Color color) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(fontSize: 11.5, color: AppColors.ink400, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(v, style: TextStyle(fontSize: 13.5, height: 1.6, color: color)),
        ]),
      );

  String _answerText(Map<String, dynamic> r) {
    final a = '${r['answer'] ?? ''}'.trim();
    if (a.isEmpty) return '（未作答 / 主观题）';
    // 客观题：答案存的是选项字母，展示成「B. 选项原文」而不是孤立的字母
    final opts = (r['options'] as List?) ?? const [];
    final head = a.split(RegExp(r'[\s，,。；;]')).first.toUpperCase();
    if (opts.isNotEmpty && head.length == 1) {
      final idx = head.codeUnitAt(0) - 65;
      if (idx >= 0 && idx < opts.length) {
        final text = '${opts[idx]}';
        return '$head. ${text.length > 100 ? '${text.substring(0, 100)}…' : text}';
      }
    }
    return a.length > 120 ? '${a.substring(0, 120)}…' : a;
  }

  String _typeLabel(String t) {
    const m = {
      'concept_discrimination': '概念辨析', 'text_location': '原文定位',
      'logical_deduction': '逻辑推演', 'error_diagnosis': '错误诊断',
      'application': '应用案例',
    };
    return m[t] ?? t;
  }

  String _errLabel(String e) => LocalQuiz.errorLabel(e);
}
