// 复习卡（P1-① D8，D160 重构）— 到期自评 + 巩固建议（暖色渐变 + 卡片化）
//
// 为什么分成两组、两种按钮（用户实报：点「还记得」没反应、点「忘了」卡片被吞）：
//  · 队列里混着两类条目 —— `kind='due'`（真到期）与 `kind='interleave'`（交错巩固，
//    引擎不看 `next_review_at`，只要 `score>=0.6` 就补进池）。交错条目**不会因为自评
//    而离开队列**，所以给它「还记得」永远像是点了没反应；
//  · 到期条目自评后 `next_review_at` 立刻推到下次到期，条目本来就该消失，
//    原先没有任何提示 → 像被卡片吃掉了。
// 现在：到期组问「还记得/忘了」并明确告知「下次复习 X」；巩固组只给「去做巩固题」
// （直接进该章章节测试 —— 原先跳「深入学习」导读页，点了练习却落到只读页，用户实报），
// 不再对没被提问的知识点要自评；标题的「到期 N 项」也只数真正到期的条目。
import 'package:flutter/material.dart';
import '../models/learning_models.dart';
import '../theme/app_theme.dart';

class ReviewCard extends StatefulWidget {
  final List<ReviewItem> items;

  /// 到期条目的自评回写：`(nodeId, correctRatio)`。
  ///
  /// 返回值用于给用户一句明确反馈（`next_review_at` / `applied` / `reason`）；
  /// 抛异常即视为失败，卡片会提示「记录失败」而不是静默吞掉。
  final Future<Map<String, dynamic>?> Function(String nodeId, double correctRatio)? onReview;

  /// 「去做巩固题」：跳到该知识点所在章节的试题。为空则不显示该按钮。
  final void Function(ReviewItem item)? onPractice;

  const ReviewCard({
    super.key,
    required this.items,
    this.onReview,
    this.onPractice,
  });

  @override
  State<ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<ReviewCard> {
  /// 正在提交的节点（按钮转圈 + 防重复点击）。
  final Set<String> _pending = <String>{};

  /// 本轮已经处理过的节点：立刻移出列表，不等接口刷新。
  final Set<String> _done = <String>{};

  List<ReviewItem> get _due => widget.items
      .where((e) => e.kind != 'interleave' && !_done.contains(e.nodeId))
      .toList();

  List<ReviewItem> get _consolidate => widget.items
      .where((e) => e.kind == 'interleave' && !_done.contains(e.nodeId))
      .toList();

  String _whenText(dynamic raw) {
    final t = raw is String && raw.isNotEmpty ? DateTime.tryParse(raw)?.toLocal() : null;
    if (t == null) return '';
    final now = DateTime.now();
    final days = DateTime(t.year, t.month, t.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (days <= 0) return '今天稍后';
    if (days == 1) return '明天';
    if (days < 7) return '$days 天后';
    return '${t.month} 月 ${t.day} 日';
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(text, style: const TextStyle(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        backgroundColor: error ? AppColors.danger : const Color(0xFFB45309),
      ));
  }

  /// 到期条目自评。成功 → 本地移出 + 告知下次复习时间；失败/未生效 → 原地保留并说明原因。
  Future<void> _review(ReviewItem it, double ratio) async {
    final cb = widget.onReview;
    if (cb == null || _pending.contains(it.nodeId)) return;
    setState(() => _pending.add(it.nodeId));
    try {
      final r = await cb(it.nodeId, ratio);
      if (!mounted) return;
      final applied = r?['applied'] != false;
      if (applied) {
        setState(() => _done.add(it.nodeId));
        final when = _whenText(r?['next_review_at']);
        _toast(when.isEmpty ? '已记录 · ${it.name}' : '已记录 · ${it.name} 下次复习：$when');
      } else {
        final why = '${r?['reason'] ?? ''}'.trim();
        _toast(why.isEmpty ? '这次自评没生效，请先完成一次章节测验' : why, error: true);
      }
    } catch (_) {
      _toast('记录失败，请稍后重试', error: true);
    } finally {
      if (mounted) setState(() => _pending.remove(it.nodeId));
    }
  }

  void _practice(ReviewItem it) {
    final cb = widget.onPractice;
    if (cb == null) return;
    cb(it);
    setState(() => _done.add(it.nodeId));
  }

  @override
  Widget build(BuildContext context) {
    final due = _due;
    final consol = _consolidate;
    if (due.isEmpty && consol.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFBEB), Color(0xFFFFF7ED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: const Color(0xFFFDE68A)),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFFD97706).withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                  color: const Color(0xFFD97706).withValues(alpha: 0.15), shape: BoxShape.circle),
              child: const Icon(Icons.refresh, size: 18, color: Color(0xFFD97706)),
            ),
            const SizedBox(width: 8),
            const Text('该复习了 · 抗遗忘',
                style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFB45309), fontSize: 14)),
            const Spacer(),
            // 「到期」只数真到期的条目（原先把交错巩固也算进去，数字对不上）
            if (due.isNotEmpty) _badge('到期 ${due.length} 项', const Color(0xFFB45309)),
            if (consol.isNotEmpty) ...[
              const SizedBox(width: 6),
              _badge('建议巩固 ${consol.length} 项', const Color(0xFF0369A1)),
            ],
          ]),
          const SizedBox(height: 6),
          Text(
            due.isNotEmpty
                ? '到期 ${due.length} 个知识点：点「还记得 / 忘了」做一次自评，系统据此排下次复习时间。'
                : '这些知识点已掌握，做几道跨章混合题能显著延长记忆。',
            style: const TextStyle(fontSize: 12, color: Color(0xFF78350F), height: 1.5),
          ),
          if (due.isNotEmpty) ...[
            _groupTitle('到期复习 · 自评后立刻排下次时间'),
            ...due.map((it) => _dueRow(it)),
          ],
          if (consol.isNotEmpty) ...[
            _groupTitle('建议巩固 · 不到期，做几道巩固题即可'),
            ...consol.map((it) => _consolRow(it)),
          ],
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      );

  Widget _groupTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 2),
        child: Text(text,
            style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2)),
      );

  Widget _row(ReviewItem it, {required Widget trailing, Widget? tag}) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          if (tag != null) ...[
            tag,
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF7C2D12))),
              const SizedBox(height: 2),
              Text(
                it.kind == 'interleave'
                    ? '已掌握、不到期；进本章测试做几道题巩固'
                    : '已隔 ${it.elapsedDays.toStringAsFixed(0)} 天 · 保持率 ${(it.retention * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 11, color: Color(0xFF9A3412)),
              ),
            ]),
          ),
          trailing,
        ]),
      );

  Widget _dueRow(ReviewItem it) {
    final busy = _pending.contains(it.nodeId);
    final disabled = widget.onReview == null || busy;
    return _row(
      it,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (busy)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFB45309)),
            ),
          ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.success,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
          ),
          onPressed: disabled ? null : () => _review(it, 1.0),
          child: const Text('还记得', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.danger,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
          ),
          onPressed: disabled ? null : () => _review(it, 0.2),
          child: const Text('忘了', style: TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }

  Widget _consolRow(ReviewItem it) => _row(
        it,
        tag: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFE0F2FE),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text('交错巩固',
              style: TextStyle(fontSize: 10, color: Color(0xFF0369A1), fontWeight: FontWeight.w600)),
        ),
        trailing: TextButton(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF0369A1),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
          ),
          onPressed: widget.onPractice == null ? null : () => _practice(it),
          child: const Text('去做巩固题', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      );
}
