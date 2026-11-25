// 逐题解析卡（D166）—— 用户实报「逐题解析只有解析，看不到题目、我的答案、正确答案」。
//
// 原先章节测试结果页的解析卡只渲染：对/错 + 评分反馈 + `explanation` + 错因 + 溯源，
// 题干、选项、本人所选、标准答案全部丢失 → 学生无法把「我选了什么」和「正确是什么」
// 对上，解析看得一头雾水。
//
// 本卡片按「题目 → 我的答案 → 正确答案 → 解析 → 错因 → 溯源」的顺序把一次作答
// 完整摊开，目前由章节测试结果页（chapter_test）逐题渲染；错题本（test_history）
// 自己那套展开行已包含同类字段，未合并。
//
// 注意：客观题的选项字母被展示层乱序过（choice_shuffle），所以这里只报**选项正文**、
// 不报字母，避免学生看到「我选了 A，怎么显示 C」。
//
// 数据来源（后端 `quiz_service.submit` / 单机 `LocalQuiz.submit`，两端同构）：
//   stem          题干
//   type          题型（外层传中文 label）
//   options       客观题选项数组（主观/应用题缺省）
//   answer_key    客观题标准答案字母（旧数据可能只有 `answer`）
//   chosen        本人所选选项的**文本**（并非字母：客观题字母受展示乱序影响）
//   answer        客观题为标准答案字母；主观/应用题为**本人作答全文**
//   explanation   解析（主观题即评分参考答案）
import 'package:flutter/material.dart';
import '../offline/local_quiz.dart';
import '../offline/offline_content.dart';
import '../theme/app_theme.dart';
import 'chunk_tag.dart';

class QuizReviewCard extends StatelessWidget {
  /// 1 起算的题号；0 表示不显示题号。
  final int index;
  final Map<String, dynamic> review;

  /// 中文题型名（概念辨析 / 原文定位 / …）；空则不显示。
  /// 主观/应用题不看这里：这两类在题库里挂在 `error_diagnosis` 题型下，
  /// 直接摆题型名会变成「错误诊断 · 主观复述题」这种错位标签。
  final String typeLabel;

  /// 申诉回调；为空则不出「申诉」按钮（只在错题上出现）。
  final VoidCallback? onAppeal;

  /// 本题是否已提交过申诉（提交后按钮换成「已申诉 · 待复核」）。
  final bool appealed;

  const QuizReviewCard({
    super.key,
    required this.review,
    this.index = 0,
    this.typeLabel = '',
    this.onAppeal,
    this.appealed = false,
  });

  Map<String, dynamic> get r => review;

  bool get _correct => r['is_correct'] == true;

  List<String> get _options {
    final raw = r['options'];
    if (raw is! List) return const [];
    return raw.map((e) => '$e').toList();
  }

  bool get _isChoice => _options.isNotEmpty;

  /// 头部题型标签：主观/应用凭反馈体判定，其余用外层传进来的题型名。
  String get _headerType {
    if (r['subjective_feedback'] != null) return '主观复述';
    if (r['application_feedback'] != null) return '应用论证';
    return typeLabel.trim();
  }

  /// 标准答案原文。客观题把字母换成选项正文；主观题直接是本人作答（无标准文本）。
  String get _standardText {
    if (!_isChoice) return '';
    final key = '${r['answer_key'] ?? r['answer'] ?? ''}'.trim().toUpperCase();
    if (key.isEmpty) return '';
    final idx = key.codeUnitAt(0) - 65;
    if (idx < 0 || idx >= _options.length) return '';
    return _options[idx].trim();
  }

  /// 本人所选原文（客观题取 `chosen` 文本；主观题取 `answer` 全文）。
  String get _mineText {
    if (_isChoice) return '${r['chosen'] ?? ''}'.trim();
    return '${r['answer'] ?? ''}'.trim();
  }

  @override
  Widget build(BuildContext context) {
    final correct = _correct;
    final fb = (r['subjective_feedback'] as Map?)?.cast<String, dynamic>();
    final appFb = (r['application_feedback'] as Map?)?.cast<String, dynamic>();
    final explanation = '${r['explanation'] ?? ''}'.trim();
    final mine = _mineText;
    final standard = _standardText;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(correct ? Icons.check_circle : Icons.cancel,
                  color: correct ? AppColors.success : const Color(0xFFDC2626), size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  [
                    if (index > 0) '$index.',
                    if (_headerType.isNotEmpty) _headerType,
                    correct ? '正确' : '需改进',
                  ].join(' '),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (r['exempt_marked'] == true)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text('(错误诊断豁免)', style: TextStyle(fontSize: 11, color: AppColors.success)),
                ),
              if (r['trial_only'] == true)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text('练习(未审)', style: TextStyle(fontSize: 11, color: Color(0xFFB45309))),
                ),
            ]),
            // 题干：先让学生看清「在问什么」，再谈对错
            if ('${r['stem'] ?? ''}'.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('${r['stem']}'.trim(),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, height: 1.45)),
              ),
            const SizedBox(height: 6),
            // 我的答案 → 正确答案：客观题给选项正文（不报字母，展示时选项被乱序过）
            _answerLine(
              '我的答案',
              mine.isEmpty ? '未作答' : mine,
              correct ? AppColors.success : const Color(0xFFB91C1C),
            ),
            if (_isChoice)
              _answerLine(
                '正确答案',
                standard.isEmpty ? '（题面缺失标准答案）' : standard,
                AppColors.success,
              ),
            if (appFb != null) ...[
              const SizedBox(height: 6),
              Text('论证结构 ${((appFb['structure'] ?? 0) * 100).toStringAsFixed(0)}% · '
                  '概念运用 ${((appFb['concept_use'] ?? 0) * 100).toStringAsFixed(0)}% · '
                  '立场 ${((appFb['stance'] ?? 0) * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
              ...((appFb['suggestions'] as List?) ?? const []).map((s) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('· $s', style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
                  )),
            ],
            if (fb != null) ...[
              const SizedBox(height: 6),
              Text('术语正统性 ${((fb['terminology_orthodoxy'] ?? 0) * 100).toStringAsFixed(0)}% · '
                  '逻辑 ${((fb['logic_coherence'] ?? 0) * 100).toStringAsFixed(0)}% · '
                  '概念层次 ${((fb['concept_layer'] ?? 0) * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
              _GradingSourceTag(src: fb['grading_source']),
              ...((fb['suggestions'] as List?) ?? const []).map((s) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('· $s', style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
                  )),
            ],
            if (explanation.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                  _isChoice ? '解析：$explanation' : '参考答案：$explanation',
                  style: const TextStyle(fontSize: 13, height: 1.5)),
            ],
            if (!correct) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.error_outline, size: 14, color: Color(0xFFB91C1C)),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('错因：${quizReviewErrorLabelOrFallback(r, correct)}',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFFB91C1C), fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
              if (quizReviewErrorReason(r).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 18),
                  child: Text(quizReviewErrorReason(r),
                      style: const TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF7F1D1D))),
                ),
            ],
            if ('${r['source_chunk_id'] ?? ''}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ChunkTag(
                      chunkId: '${r['source_chunk_id']}',
                      label: '溯源 原文分片',
                      compact: true,
                      fallbackText: r['explanation']?.toString()),
                ),
              ),
            // 申诉只对错题给：不是判错，申诉没有意义（D167）
            if (!correct && onAppeal != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: appealed
                      ? const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.flag_outlined, size: 14, color: AppColors.warning),
                          SizedBox(width: 4),
                          Text('已申诉 · 待复核（不会自动改分）',
                              style: TextStyle(fontSize: 11.5, color: AppColors.warning)),
                        ])
                      : TextButton.icon(
                          onPressed: onAppeal,
                          icon: const Icon(Icons.flag_outlined, size: 14),
                          label: const Text('申诉判分', style: TextStyle(fontSize: 11.5)),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.ink500,
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _answerLine(String label, String value, Color color) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 62,
            child: Text('$label：',
                style: const TextStyle(fontSize: 12.5, color: AppColors.ink400)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 13, height: 1.45, color: color, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

/// 错因展示：优先用后端/本机引擎给出的中文标签，兼容旧数据的内部编码。
String quizReviewErrorLabel(Map<String, dynamic> r) {
  final label = '${r['error_label'] ?? ''}'.trim();
  if (label.isNotEmpty) return label;
  final code = '${r['error_category'] ?? ''}'.trim();
  return LocalQuiz.errorLabel(code);
}

/// 按题目 id 取回原始题目（含 answer/explanation），用于旧数据现推错因。
Map<String, dynamic>? _quizOf(Map<String, dynamic> r) {
  final qid = '${r['item_id'] ?? ''}'.trim();
  if (qid.isEmpty) return null;
  return OfflineContent.quiz(qid);
}

/// 错因标签；推不出来时给一个诚实的兜底（不返回空串）。
String quizReviewErrorLabelOrFallback(Map<String, dynamic> r, bool correct) {
  if (correct) return '';
  final label = quizReviewErrorLabel(r);
  if (label.isNotEmpty) return label;
  final quiz = _quizOf(r);
  if (quiz != null) {
    final chosen = '${r['chosen'] ?? ''}'.trim();
    final cat = LocalQuiz.classifyError(quiz, chosen);
    final l = LocalQuiz.errorLabel(cat);
    if (l.isNotEmpty) return l;
  }
  return '知识点尚未掌握';
}

/// 错因诊断句；旧数据没有 error_reason 时按标签现给一句。
String quizReviewErrorReason(Map<String, dynamic> r) {
  final reason = '${r['error_reason'] ?? ''}'.trim();
  if (reason.isNotEmpty) return reason;
  final quiz = _quizOf(r);
  if (quiz != null) {
    final chosen = '${r['chosen'] ?? ''}'.trim();
    final cat = LocalQuiz.classifyError(quiz, chosen);
    return LocalQuiz.errorAdvice(quiz, cat, chosen);
  }
  final code = '${r['error_category'] ?? ''}'.trim();
  if (code.isNotEmpty) {
    return LocalQuiz.errorAdvice(const {}, code, '');
  }
  return '这一知识点还没有真正掌握：对照上方解析回看原句，再用自己的话复述一遍原理。';
}

class _GradingSourceTag extends StatelessWidget {
  final dynamic src;
  const _GradingSourceTag({this.src});

  @override
  Widget build(BuildContext context) {
    final s = '${src ?? ''}';
    final label = switch (s) {
      'llm' => 'AI 语义精评',
      'llm_low_conf' => 'AI 语义精评（低置信）',
      'llm_stance_adjusted' => 'AI 语义精评（立场校正）',
      'heuristic' => '本地近似评分',
      _ => null,
    };
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              color: s.startsWith('llm') ? const Color(0xFF2563EB) : const Color(0xFF6B7280))),
    );
  }
}
