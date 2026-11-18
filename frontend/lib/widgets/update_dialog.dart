// 应用内更新提示框：显示新版本号 + 更新内容 + 「下载更新 / 稍后 / 去网页下载」。
//
// 设计口径：
//  · 只在安卓弹（其他平台没有自装这回事，见 app_update.dart 的 checkUpdate）；
//  · 点「下载更新」→ 框立刻关掉，**下载转到后台**（services/update_download.dart），
//    用户可以继续读书；进度条挂在底部提示条上，不挡内容；
//  · 下完再单独弹一次「现在装吗」——装机这一步必须用户自己点，
//    既不自动唤起安装器，也不静默安装；
//  · 下载失败要说人话（「网络中断，可改用浏览器下载」），不能只转圈；
//  · 「稍后」不是永不再提示 —— 同一版本当天不再打扰，隔天再问一次（见 update_host）。
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/app_update.dart';
import '../services/update_download.dart';
import '../theme/app_theme.dart';

/// 显示「发现新版本」提示。返回的 Future 在框关闭后完成。
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
  /// 点「下载更新」：关框 + 起后台下载。进度与结果由 update_host 负责提示。
  ///
  /// 先取 NavigatorState 再动：pop 之后再用 `context` 属于
  /// use_build_context_synchronously，而这里已确定要关的就是这个框。
  void _startBackgroundDownload() {
    final nav = Navigator.of(context);
    nav.pop();
    startUpdateDownload(widget.info);
  }

  /// 打开下载页并关掉本框。
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
                '从 GitHub 下载最新安装包$_sizeText。点「下载更新」会在**后台下载**，'
                '期间可以继续用；下完再问你装不装。覆盖升级，学习记录不受影响。',
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
            ],
          ),
        ),
      ),
      actionsOverflowButtonSpacing: 6,
      actions: [
        TextButton(
          onPressed: _openPageAndClose,
          child: const Text('去网页下载'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('稍后'),
        ),
        if (widget.info.hasApk)
          FilledButton(
            onPressed: _startBackgroundDownload,
            child: const Text('下载更新'),
          ),
      ],
    );
  }
}

/// 下载完成后的「装不装」确认框 —— 下载是后台的，装这一步必须用户亲手点。
Future<void> showInstallReadyDialog(BuildContext context, UpdateState state) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _InstallReadyDialog(state: state),
  );
}

class _InstallReadyDialog extends StatefulWidget {
  const _InstallReadyDialog({required this.state});
  final UpdateState state;

  @override
  State<_InstallReadyDialog> createState() => _InstallReadyDialogState();
}

class _InstallReadyDialogState extends State<_InstallReadyDialog> {
  bool _installing = false;
  String? _error;

  Future<void> _install() async {
    final file = widget.state.file;
    if (file == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _installing = true;
      _error = null;
    });
    final ok = await installApk(file);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _installing = false;
        _error = '没能唤起安装器。可能是系统里没允许本应用「安装未知应用」，'
            '去「设置 → 应用 → 唯物·马哲精读 → 安装未知应用」打开后重试。';
      });
      return;
    }
    resetUpdateDownload();
    if (mounted) Navigator.of(context).pop();
  }

  String? get _sizeLabel {
    final b = widget.state.info?.apkSize ?? 0;
    return b <= 0 ? null : '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final size = _sizeLabel;
    return AlertDialog(
      title: const Text('更新已下载完成'),
      content: SizedBox(
        width: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '版本 ${widget.state.version}${size == null ? '' : '（$size）'}已经下好。'
              '现在安装会覆盖旧版，学习记录不受影响；安装过程由系统接管。',
              style: const TextStyle(fontSize: 13, height: 1.55),
            ),
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
      actions: [
        TextButton(
          onPressed: _installing
              ? null
              : () {
                  // 稍后：包先留着（下次启动会被清理），下次还能从「关于」重查
                  resetUpdateDownload();
                  Navigator.of(context).pop();
                },
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: _installing ? null : _install,
          child: Text(_installing ? '正在唤起安装器…' : '立即安装'),
        ),
      ],
    );
  }
}

/// 供测试与调用方判断：这台上是否可能自装更新。
/// 单机版只在安卓生效，其他平台一律 false（避免在桌面上弹一个装不了的框）。
bool canSelfUpdate() => Platform.isAndroid;
