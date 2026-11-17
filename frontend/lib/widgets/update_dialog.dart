// 应用内更新提示框：显示新版本号 + 更新内容 + 「下载并安装 / 稍后 / 去网页下载」。
//
// 设计口径：
//  · 只在安卓弹（其他平台没有自装这回事，见 app_update.dart 的 checkUpdate）；
//  · 下载过程显示真实进度条，**不假装很快**（73MB 在移动网下要几十秒）；
//  · 下载失败要说人话（「网络中断，可改用浏览器下载」），不能只转圈；
//  · 「稍后」不是永不再提示 —— 同一版本当天不再打扰，隔天再问一次。
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/app_update.dart';
import '../theme/app_theme.dart';

/// 显示「发现新版本」提示。用户点「稍后」返回，不做任何动作。
Future<void> showUpdateDialog(BuildContext context, ReleaseInfo info) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(info: info),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info});
  final ReleaseInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double? _progress;
  String? _error;

  Future<void> _downloadAndInstall() async {
    setState(() {
      _downloading = true;
      _progress = null;
      _error = null;
    });
    final file = await downloadApk(
      widget.info,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    if (file == null) {
      setState(() {
        _downloading = false;
        _error = '下载没成功（网络中断或文件不完整）。可以改用浏览器下载。';
      });
      return;
    }
    final ok = await installApk(file);
    if (!mounted) return;
    setState(() => _downloading = false);
    if (!ok) {
      setState(() => _error = '没能唤起安装器。可能是系统里没允许本应用「安装未知应用」，'
          '去「设置 → 应用 → 唯物·马哲精读 → 安装未知应用」打开后重试。');
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// 打开下载页并关掉本框。
  ///
  /// 先把 NavigatorState 取出来再 await：await 之后再用 `context` 属于
  /// use_build_context_synchronously，而这里已经确定要关的是这个对话框。
  Future<void> _openPageAndClose() async {
    final nav = Navigator.of(context);
    await openDownloadPage();
    if (!mounted) return;
    nav.pop();
  }

  String get _sizeText {
    final b = widget.info.apkSize;
    if (b <= 0) return '';
    return ' · ${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.info.notes.trim();
    return AlertDialog(
      title: Text('发现新版本 ${widget.info.version}'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                // 说清「装的是什么」：用户有权知道这是从 GitHub 直接下的包
                '从 GitHub 下载最新安装包$_sizeText，下完交给系统安装器，'
                '你确认后才会装。应用会覆盖升级，学习记录不受影响。',
                style: const TextStyle(fontSize: 13, height: 1.55),
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    // Release 说明是 Markdown，这里不渲染、只截断展示前几行
                    notes.length > 600 ? '${notes.substring(0, 600)}…' : notes,
                    style: const TextStyle(
                        fontSize: 11.5, height: 1.5, color: AppColors.ink700),
                  ),
                ),
              ],
              if (_downloading) ...[
                const SizedBox(height: 14),
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 6),
                Text(
                  _progress == null
                      ? '正在下载…'
                      : '正在下载 ${(_progress! * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.ink400),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                      fontSize: 11.5, height: 1.5, color: AppColors.danger),
                ),
              ],
            ],
          ),
        ),
      ),
      actionsOverflowButtonSpacing: 6,
      actions: [
        TextButton(
          onPressed: _downloading ? null : _openPageAndClose,
          child: const Text('去网页下载'),
        ),
        TextButton(
          onPressed: _downloading ? null : () => Navigator.of(context).pop(),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: _downloading || !widget.info.hasApk
              ? null
              : _downloadAndInstall,
          child: Text(_downloading ? '下载中' : '下载并安装'),
        ),
      ],
    );
  }
}

/// 供测试与调用方判断：这台上是否可能自装更新。
/// 单机版只在安卓生效，其他平台一律 false（避免在桌面上弹一个装不了的框）。
bool canSelfUpdate() => Platform.isAndroid;
