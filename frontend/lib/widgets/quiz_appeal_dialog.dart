// 「申诉判分」弹窗（D167）—— 用户实报「点在测试结果里点申诉没有反应，这按钮到底干啥用」。
//
// 根因：`chapter_test` 直接 `_api.appeal(...)` 就完事，既不让填理由、也不回任何提示；
// 而这条链路在本机（单机版）只是往 `LocalDb.tests[testId]['appeals']` 记一笔，
// 既不改分、也没有「人工复核台」，用户看到的就是「点了没反应」。
//
// 这里把话说清楚，并且真的收一笔东西：
//   · 弹窗首段必须写明「不会自动改分、本机没有人工复核台」——不许让用户以为点完就重判；
//   · 引导先点「溯源 原文分片」核对原句，很多异议是自己看错了；
//   · 理由可选填（写上依据更好复核），提交后回执由调用方用 SnackBar 告知。
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 弹出申诉框。提交成功返回接口回执（含 `message`），取消或失败返回 null。
Future<Map<String, dynamic>?> showQuizAppealDialog(
  BuildContext context, {
  required String title,
  String stem = '',
  required Future<Map<String, dynamic>> Function(String reason) onSubmit,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => _AppealDialog(title: title, stem: stem, onSubmit: onSubmit),
  );
}

class _AppealDialog extends StatefulWidget {
  final String title;
  final String stem;
  final Future<Map<String, dynamic>> Function(String reason) onSubmit;
  const _AppealDialog({required this.title, required this.stem, required this.onSubmit});

  @override
  State<_AppealDialog> createState() => _AppealDialogState();
}

class _AppealDialogState extends State<_AppealDialog> {
  final _reason = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await widget.onSubmit(_reason.text.trim());
      if (!mounted) return;
      Navigator.pop(context, res);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '提交失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.hero)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: const Text('申诉判分', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink400)),
              if (widget.stem.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(widget.stem.trim(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, height: 1.45, fontWeight: FontWeight.w600)),
                ),
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.goldSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '申诉只做一件事：把这道题、你的作答和下面这段说明记录在本机，'
                  '方便你事后对照。它不会自动改分，本机也没有人工复核台。'
                  '如果你觉得答案或解析有误，先在卡片下方点「溯源 原文分片」核对原句。',
                  style: TextStyle(fontSize: 12, height: 1.55, color: AppColors.ink700),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                maxLines: 3,
                maxLength: 300,
                enabled: !_submitting,
                decoration: InputDecoration(
                  hintText: '为什么觉得判错了？（选填）例如：原文这一段明确说…',
                  hintStyle: const TextStyle(fontSize: 12.5),
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_error!,
                      style: const TextStyle(fontSize: 12, color: AppColors.danger)),
                ),
            ]),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('提交申诉'),
        ),
      ],
    );
  }
}
