// 摸底测页（T015）— 渐变头图 + 动画进度 + 单题卡 + 跳过 + 结果页推荐起点
import 'package:flutter/material.dart';
import 'dart:math';
import '../services/routes_service.dart';
import '../models/learning_models.dart';
import '../services/choice_shuffle.dart';
import '../widgets/anim.dart';
import '../theme/app_theme.dart';

class DiagnosticTestScreen extends StatefulWidget {
  final String routeId;
  final String routeName;
  const DiagnosticTestScreen({
    super.key,
    required this.routeId,
    required this.routeName,
  });

  @override
  State<DiagnosticTestScreen> createState() => _DiagnosticTestScreenState();
}

class _DiagnosticTestScreenState extends State<DiagnosticTestScreen> {
  final _svc = RoutesService();
  String? _diagId;
  List<QuizItem> _items = [];
  final Map<String, String> _answers = {};
  final Random _rng = Random();
  final Map<String, List<int>> _optOrder = {}; // itemId -> 展示顺序（origAt）
  int _index = 0;
  bool _loading = true;
  Map<String, dynamic>? _result;

  /// section_id → 「阶段N · 标题」。结果里只有 id，直接显示就成了 `sec_A_03`。
  final Map<String, String> _secLabels = {};

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    // 标题表取不到也不影响做题：失败就退回显示 id（不编造标题）。
    try {
      for (final s in await _svc.sections(widget.routeId)) {
        final t = s.title.trim();
        _secLabels[s.id] = t.isEmpty ? s.id : '阶段 ${s.stageNo} · $t';
      }
    } catch (_) {}
    final j = await _svc.startDiagnostic(widget.routeId);
    final items = ((j['items'] as List?) ?? const [])
        .map((e) => QuizItem.fromJson(e as Map<String, dynamic>))
        .toList();
    setState(() {
      _diagId = j['diag_id'] as String?;
      _items = items;
      _optOrder.clear();
      for (final it in _items) {
        if (it.options.length > 1) {
          _optOrder[it.id] = shuffledOptionOrder(it.options.length, _rng);
        }
      }
      _loading = false;
    });
  }

  Future<void> _submit() async {
    if (_diagId == null) {
      setState(
        () => _result = {'recommended_start': null, 'note': '该路线题库建设中，可跳过摸底'},
      );
      return;
    }
    final payload = _items
        .map((it) => {'item_id': it.id, 'answer': _origAnswer(it)})
        .toList();
    final res = await _svc.submitDiagnostic(_diagId!, payload);
    setState(() => _result = res);
  }

  /// 把展示字母映回原始选项字母（后续判分/统计基于原始顺序）。
  String _origAnswer(QuizItem it) {
    final raw = _answers[it.id] ?? '';
    final order = _optOrder[it.id];
    if (order == null || raw.isEmpty) return raw;
    final pos = raw.codeUnitAt(0) - 65;
    if (pos < 0 || pos >= order.length) return raw;
    return displayLetterToOrig(pos, order);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_result != null) return _buildResult();
    if (_items.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('摸底测')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.construction,
                  size: 54,
                  color: AppColors.ink400,
                ),
                const SizedBox(height: 12),
                const Text('该路线题库建设中，可跳过摸底直接选起点。', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('跳过'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final it = _items[_index];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          GradientHeader(
            leading: Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.maybePop(ctx),
              ),
            ),
            title: widget.routeName,
            subtitle: '摸底测 · 定位你的起点',
            height: 110,
            actions: [
              TextButton(
                onPressed: _submit,
                child: const Text('跳过', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          Expanded(
            child: AuroraBackground(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '第 ${_index + 1} / ${_items.length} 题',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.ink500,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${((_index + 1) / _items.length * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.brand,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AnimatedBar(value: (_index + 1) / _items.length, height: 8),
                    const SizedBox(height: 22),
                    AnimatedEntrance(
                      key: ValueKey(_index),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          border: Border.all(color: AppColors.line),
                          boxShadow: AppShadows.soft,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              it.stem,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            // 选项卡外层是带背景色的 Container：RadioListTile 的水波纹只能画在
                            // 最近的 Material 上，不垫这一层点击就没反馈（Debug 下还会 assert）。
                            Material(
                              type: MaterialType.transparency,
                              child: RadioGroup<String>(
                                groupValue: _answers[it.id],
                                onChanged: (v) =>
                                    setState(() => _answers[it.id] = v!),
                                child: Column(
                                  children: List.generate(it.options.length, (
                                    pos,
                                  ) {
                                    final letter = String.fromCharCode(
                                      65 + pos,
                                    );
                                    final order = _optOrder[it.id];
                                    final optIdx =
                                        (order != null && pos < order.length)
                                        ? order[pos]
                                        : pos;
                                    final opt = it.options[optIdx].toString();
                                    final selected = _answers[it.id] == letter;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () => setState(
                                          () => _answers[it.id] = letter,
                                        ),
                                        // 选中态的底色必须由 Material 画：如果放在 RadioListTile
                                        // 上层的带色 Container/DecoratedBox 里，水波纹与点击反馈
                                        // 会被盖住（Debug 下 Flutter 直接 assert）。
                                        child: Material(
                                          color: selected
                                              ? AppColors.brandSoft.withValues(
                                                  alpha: 0.5,
                                                )
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: selected
                                                    ? AppColors.brand
                                                          .withValues(
                                                            alpha: 0.5,
                                                          )
                                                    : Colors.transparent,
                                              ),
                                            ),
                                            child: RadioListTile<String>(
                                              dense: true,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                  ),
                                              activeColor: AppColors.brand,
                                              value: letter,
                                              title: Text(
                                                '$letter. $opt',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        if (_index > 0)
                          OutlinedButton.icon(
                            onPressed: () => setState(() => _index--),
                            icon: const Icon(Icons.chevron_left, size: 18),
                            label: const Text('上一题'),
                          ),
                        const Spacer(),
                        SizedBox(
                          height: 46,
                          child: _index < _items.length - 1
                              ? FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.brand,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () => setState(() => _index++),
                                  icon: const Icon(
                                    Icons.chevron_right,
                                    size: 18,
                                  ),
                                  label: const Text('下一题'),
                                )
                              : FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.brand,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _submit,
                                  icon: const Icon(Icons.check, size: 18),
                                  label: const Text('提交'),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _label(Object? id) {
    final k = '${id ?? ''}';
    return _secLabels[k] ?? k;
  }

  Widget _buildResult() {
    final start = _label(_result!['recommended_start']);
    final skip = (_result!['skippable'] as List?) ?? const [];
    final reinforce = (_result!['to_reinforce'] as List?) ?? const [];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          GradientHeader(
            leading: Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.maybePop(ctx),
              ),
            ),
            title: '摸底结果',
            subtitle: '已为你定位起点',
            height: 110,
          ),
          Expanded(
            child: AuroraBackground(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  AnimatedEntrance(
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFDF1EF), Color(0xFFFBF1DA)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.hero),
                        border: Border.all(color: const Color(0xFFF3C9C6)),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: AppColors.brandGradient,
                              shape: BoxShape.circle,
                              boxShadow: AppShadows.lift,
                            ),
                            child: const Icon(
                              Icons.flag,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '建议起点',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.ink500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            start,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (skip.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    AnimatedEntrance(
                      delayMs: 80,
                      child: _resultSection(
                        '可跳过章节',
                        Icons.fast_forward,
                        skip.map((e) => _resultRow(_label(e))).toList(),
                      ),
                    ),
                  ],
                  if (reinforce.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    AnimatedEntrance(
                      delayMs: 140,
                      child: _resultSection(
                        '需补强',
                        Icons.error_outline,
                        reinforce
                            .map(
                              (e) => _resultRow(
                                '${e['name']}',
                                subtitle: '${e['reason'] ?? ''}',
                              ),
                            )
                            .toList(),
                        danger: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        '开始学习',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultSection(
    String title,
    IconData icon,
    List<Widget> rows, {
    bool danger = false,
  }) {
    final color = danger ? AppColors.danger : AppColors.brand;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w800, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...rows,
        ],
      ),
    );
  }

  Widget _resultRow(String text, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, size: 6, color: AppColors.ink400),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: const TextStyle(fontSize: 13.5)),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.ink400,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
