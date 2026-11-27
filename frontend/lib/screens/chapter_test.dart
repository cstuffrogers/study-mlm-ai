// 章节测试页（T032）— 四类题型混合 + 主观题 + 判分结果 + 错题解析 + 溯源 + 申诉
import 'package:flutter/material.dart';
import 'dart:math';
import '../models/learning_models.dart';
import '../services/quiz_service_api.dart';
import '../services/sync_controller.dart';
import '../services/choice_shuffle.dart';
import '../widgets/mastery_badge.dart';
import '../widgets/chunk_tag.dart';
import '../widgets/quiz_review_card.dart';
import '../widgets/quiz_appeal_dialog.dart';
import '../widgets/anim.dart';
import '../theme/app_theme.dart';
import 'package:provider/provider.dart';

class ChapterTestScreen extends StatefulWidget {
  final String routeId;
  final String sectionId;
  final String sectionTitle;
  const ChapterTestScreen({
    super.key,
    required this.routeId,
    required this.sectionId,
    required this.sectionTitle,
  });

  @override
  State<ChapterTestScreen> createState() => _ChapterTestScreenState();
}

class _ChapterTestScreenState extends State<ChapterTestScreen> {
  final _api = QuizApi();
  String _testId = '';
  List<QuizItem> _items = [];
  final Map<String, String> _answers = {};
  final Map<String, String> _confidence = {}; // P2-④ 元认知自评：low/mid/high
  final Random _rng = Random();
  final Map<String, List<int>> _optOrder = {}; // itemId -> 展示顺序（origAt）
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _result;
  bool _submitting = false;
  /// 本次结果页里已经提交过申诉的题（item_id）：按钮换成「已申诉 · 待复核」
  final Set<String> _appealed = {};

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final r = await _api.start(widget.sectionId, routeId: widget.routeId);
      setState(() {
        _testId = r.testId;
        _items = r.items;
        // 为每道客观题生成一次选项展示顺序（避免正确答案固定在 A）
        _optOrder.clear();
        for (final it in _items) {
          if (!(it.subjective || it.application) && it.options.length > 1) {
            _optOrder[it.id] = shuffledOptionOrder(it.options.length, _rng);
          }
        }
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final payload = _items
        .map((it) => {
              'item_id': it.id,
              'answer': _origAnswer(it),
              'confidence': _confidence[it.id] ?? '',
            })
        .toList();
    try {
      final res = await _api.submit(_testId, payload);
      setState(() => _result = res);
      // 章节完成 → 上报进度（服务端权威；离线自动暂存）
      final passed = (res['gating']?['next_section_unlocked'] ?? false) == true;
      if (mounted) {
        context.read<SyncController>().reportProgress(
              widget.sectionId,
              _items.length,
              routeId: widget.routeId,
              status: passed ? 'completed' : 'in_progress',
            );
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 把用户在「打乱展示」中选的展示字母，映回原始选项字母（后端 answer 基于原始顺序）。
  String _origAnswer(QuizItem it) {
    final raw = _answers[it.id] ?? '';
    final order = _optOrder[it.id];
    if (order == null || raw.isEmpty) return raw;
    final pos = raw.codeUnitAt(0) - 65;
    if (pos < 0 || pos >= order.length) return raw;
    return displayLetterToOrig(pos, order);
  }

  String _typeLabel(String t) {
    switch (t) {
      case 'concept_discrimination':
        return '概念辨析';
      case 'text_location':
        return '原文定位';
      case 'logical_deduction':
        return '逻辑推演';
      case 'error_diagnosis':
        return '错误诊断';
      case 'application':
        return '应用论证';
      default:
        return t;
    }
  }

  // 卷首说明（D176）：不再分「易/中/难」——同一知识点的各档只是换种问法，
  // 一章才 3 个知识点却被问成 12 道题。现在一个知识点只出一道，
  // 卷首直说这卷覆盖哪些知识点，不再列出没有信息量的「易/中/难」构成。
  Widget _buildScopeHeader() {
    final challenge = _items.where((it) => it.subjective || it.application).length;
    final objective = _items.length - challenge;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('本套 ${_items.length} 题 · 每个知识点一道',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
              '覆盖本章 ${_items.length} 个知识点'
              '${challenge > 0 ? '（$objective 道选择题 + $challenge 道自己写）' : ''}，'
              '重考会换同知识点的另一道题，不会原样重复。',
              style: TextStyle(fontSize: 11, color: AppColors.ink400, height: 1.5)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.sectionTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('无法开始测试：$_error', textAlign: TextAlign.center),
          ),
        ),
      );
    }
    if (_result != null) return _buildResult();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text('测试 · ${widget.sectionTitle}')),
      body: AuroraBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_items.isNotEmpty) AnimatedEntrance(child: _buildScopeHeader()),
            for (var i = 0; i < _items.length; i++)
              AnimatedEntrance(delayMs: i * 45, child: _buildQuestion(i, _items[i])),
            const SizedBox(height: 8),
            SizedBox(
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('提交测试', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion(int i, QuizItem it) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.brandSoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${i + 1}. ${_typeLabel(it.type)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.brandDeep, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 6),
            const Spacer(),
            if (it.trialOnly)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Text('练习(未审)', style: TextStyle(fontSize: 10, color: Color(0xFFB45309))),
              ),
            if (it.exemptMarked)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Text('豁免', style: TextStyle(fontSize: 10, color: AppColors.success)),
              ),
          ]),
          const SizedBox(height: 10),
          Text(it.stem, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.5)),
          // 溯源入口：作答前就能核对原著出处，不必等提交后看解析
          if (it.sourceChunkId.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ChunkTag(
                  chunkId: it.sourceChunkId,
                  label: '溯源 原文分片',
                  compact: true,
                  tooltip: it.sourceChunkId.startsWith('GUIDE-')
                      ? '本章导读未逐字引用原著，溯源停在本章导读层'
                      : '本题所依据的原著原文片段，点开可核对',
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (it.subjective || it.application)
            TextField(
              maxLines: 5,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surface,
                hintText: it.application
                    ? '结合具体案例论述：指出问题 → 运用概念 → 举现实例证 → 得出结论…'
                    : '用自己的话作答（费曼式复述）…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.line),
                ),
              ),
              onChanged: (v) => _answers[it.id] = v,
            )
          else
            RadioGroup<String>(
              groupValue: _answers[it.id],
              onChanged: (v) => setState(() => _answers[it.id] = v!),
              child: Column(
                children: List.generate(it.options.length, (pos) {
                  final letter = String.fromCharCode(65 + pos);
                  final order = _optOrder[it.id];
                  final optIdx = (order != null && pos < order.length) ? order[pos] : pos;
                  final optText = it.options[optIdx].toString();
                  final selected = _answers[it.id] == letter;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _answers[it.id] = letter),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.brandSoft.withValues(alpha: 0.5) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: selected ? AppColors.brand.withValues(alpha: 0.5) : Colors.transparent),
                        ),
                        child: RadioListTile<String>(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          activeColor: AppColors.brand,
                          value: letter,
                          title: Text('$letter. $optText', style: const TextStyle(fontSize: 14)),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          const SizedBox(height: 8),
          _buildConfidence(it),
        ],
      ),
    );
  }

  Widget _buildConfidence(QuizItem it) {
    final cur = _confidence[it.id] ?? '';
    Widget chip(String val, String label, Color color) {
      final sel = cur == val;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label, style: TextStyle(fontSize: 11, color: sel ? Colors.white : color)),
          selected: sel,
          selectedColor: color,
          onSelected: (_) => setState(() => _confidence[it.id] = val),
        ),
      );
    }

    return Row(children: [
      const Text('把握度：', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
      chip('low', '没把握', const Color(0xFFDC2626)),
      chip('mid', '一般', const Color(0xFFD97706)),
      chip('high', '有把握', const Color(0xFF16A34A)),
    ]);
  }

  Widget _buildResult() {
    final total = (_result!['total_score'] ?? 0).toDouble();
    final mastery = (_result!['mastery'] as List?) ?? const [];
    final review = (_result!['review'] as List?) ?? const [];
    final gating = (_result!['gating'] as Map?)?.cast<String, dynamic>() ?? {};
    final calibration = (_result!['calibration'] as Map?)?.cast<String, dynamic>() ?? {};
    final unlocked = gating['next_section_unlocked'] == true;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AuroraBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                const Text('测试结果', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context, true),
                ),
              ]),
              AnimatedEntrance(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                  decoration: BoxDecoration(
                    gradient: unlocked
                        ? const LinearGradient(colors: [Color(0xFFF0FDF4), Color(0xFFECFDF5)])
                        : const LinearGradient(colors: [Color(0xFFFEF2F2), Color(0xFFFFF1F2)]),
                    borderRadius: BorderRadius.circular(AppRadius.hero),
                    border: Border.all(
                        color: (unlocked ? AppColors.success : AppColors.danger).withValues(alpha: 0.3)),
                    boxShadow: AppShadows.soft,
                  ),
                  child: Column(children: [
                    AnimatedProgressRing(
                      value: total,
                      size: 118,
                      strokeWidth: 12,
                      color: unlocked ? AppColors.success : AppColors.danger,
                      center: Column(mainAxisSize: MainAxisSize.min, children: [
                        CountUp(
                          value: (total * 100),
                          suffix: '%',
                          style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: unlocked ? AppColors.success : AppColors.danger),
                        ),
                        const Text('总分', style: TextStyle(fontSize: 11, color: AppColors.ink400)),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(unlocked ? Icons.lock_open : Icons.lock_outline,
                          size: 16, color: unlocked ? AppColors.success : AppColors.danger),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          unlocked
                              ? '已达标，本章掌握良好'
                              : '未达 ${((gating['threshold'] ?? 0.8) * 100).toStringAsFixed(0)}% 达标线，建议回补薄弱点（仍可继续往后学）',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: unlocked ? AppColors.success : AppColors.danger,
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              if (calibration['available'] == true) _buildCalibrationCard(calibration),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text('知识点掌握度', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: mastery
                    .map((m) => MasteryBadge(level: m['level'], score: (m['score'] ?? 0).toDouble()))
                    .toList(),
              ),
              const SizedBox(height: 18),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 4),
                child: Text('逐题解析', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              // D166：逐题解析必须带上题目 / 我的答案 / 正确答案，不能只甩一段解析
              ...review.asMap().entries.map((e) {
                final item = (e.value as Map).cast<String, dynamic>();
                final itemId = '${item['item_id'] ?? ''}';
                return AnimatedEntrance(
                  delayMs: 60 + e.key * 40,
                  child: QuizReviewCard(
                    index: e.key + 1,
                    review: item,
                    typeLabel: _typeLabel('${item['type'] ?? ''}'),
                    appealed: _appealed.contains(itemId),
                    onAppeal: itemId.isEmpty || item['is_correct'] == true
                        ? null
                        : () => _appeal(itemId, e.key + 1, item),
                  ),
                );
              }),
              const SizedBox(height: 24),
              SizedBox(
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('返回', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// 申诉判分（D167）：先弹框说清「不会自动改分」并收一句理由，再记一笔。
  /// 原先直接调接口、既无输入也无回执 —— 用户点了完全没反应。
  Future<void> _appeal(String itemId, int no, Map<String, dynamic> item) async {
    final messenger = ScaffoldMessenger.of(context);
    final type = _typeLabel('${item['type'] ?? ''}');
    final res = await showQuizAppealDialog(
      context,
      title: type.isEmpty ? '第 $no 题' : '第 $no 题 · $type',
      stem: '${item['stem'] ?? ''}',
      onSubmit: (reason) => _api.appeal(_testId, itemId, reason: reason),
    );
    if (res == null || !mounted) return;
    setState(() => _appealed.add(itemId));
    messenger.showSnackBar(SnackBar(
      content: Text('${res['message'] ?? '申诉已记录（待复核），不会自动改分。'}'),
      duration: const Duration(seconds: 4),
    ));
  }

  Widget _buildCalibrationCard(Map<String, dynamic> cal) {
    final verdict = cal['verdict'] ?? 'calibrated';
    final color = verdict == 'overconfident'
        ? AppColors.danger
        : verdict == 'underconfident'
            ? AppColors.warning
            : AppColors.success;
    final label = verdict == 'overconfident'
        ? '元认知：偏高估'
        : verdict == 'underconfident'
            ? '元认知：偏低估'
            : '元认知：校准良好';
    return Card(
      color: const Color(0xFFFBF7F5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text('自评预期正确率 ${((cal['expected'] ?? 0) * 100).toStringAsFixed(0)}% · '
              '实测 ${((cal['actual'] ?? 0) * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
          const SizedBox(height: 6),
          Text('${cal['tip'] ?? ''}', style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }
}
