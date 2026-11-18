// 更新下载的「眼皮底下」提示：进度条 + 下完后的「装不装」确认框。
//
// 为什么单独一个 host（挂在 MaterialApp.builder 里）：
//  · 下载是在后台跑的（services/update_download.dart），用户可能已经翻到别的页面了，
//    提示不能挂在某个具体页面上；
//  · 下载进度只占底部一条提示条，不挡内容 —— 用户点「下载更新」后可以继续读书；
//  · 下完弹一次确认框（装在系统安装器里点，不做静默安装）。
import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_nav.dart';
import '../services/app_update.dart';
import '../services/update_download.dart';
import '../theme/app_theme.dart';
import 'update_dialog.dart';

/// 把更新下载的进度与结果反馈包在整个 App 外面（见 main.dart 的 builder）。
class UpdateHost extends StatefulWidget {
  const UpdateHost({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateHost> createState() => _UpdateHostState();
}

class _UpdateHostState extends State<UpdateHost> {
  UpdatePhase _phase = UpdatePhase.idle;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _progress;
  bool _askedInstall = false;

  @override
  void initState() {
    super.initState();
    updateState.addListener(_onState);
    _phase = updateState.value.phase;
  }

  @override
  void dispose() {
    updateState.removeListener(_onState);
    _closeProgress();
    super.dispose();
  }

  void _onState() {
    final s = updateState.value;
    final was = _phase;
    _phase = s.phase;
    switch (s.phase) {
      case UpdatePhase.downloading:
        if (was != UpdatePhase.downloading) _showProgress();
        break;
      case UpdatePhase.ready:
        if (!_askedInstall) {
          _askedInstall = true;
          _closeProgress();
          _askInstall(s);
        }
        break;
      case UpdatePhase.failed:
        _askedInstall = false;
        _closeProgress();
        _toast(s.error ?? '下载失败，可以改用浏览器下载。', action: true);
        break;
      case UpdatePhase.idle:
        _askedInstall = false;
        _closeProgress();
        break;
    }
  }

  ScaffoldMessengerState? get _messenger {
    if (!mounted) return null;
    try {
      return ScaffoldMessenger.of(context);
    } catch (_) {
      return null;
    }
  }

  void _closeProgress() {
    final c = _progress;
    _progress = null;
    try {
      c?.close();
    } catch (_) {}
  }

  /// 底部进度条：不挡内容、不阻断操作，只有「隐藏」一个动作（真要停就直接不管它）。
  void _showProgress() {
    final m = _messenger;
    if (m == null) return;
    _progress = m.showSnackBar(SnackBar(
      duration: const Duration(hours: 1), // 由 ready/failed 主动关掉
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink900,
      content: ValueListenableBuilder<UpdateState>(
        valueListenable: updateState,
        builder: (context, s, _) {
          final p = s.progress;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '正在后台下载更新 ${s.version}'
                '${s.percentLabel == null ? '' : ' · ${s.percentLabel}'}',
                style: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: p,
                  minHeight: 4,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.gold),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '可以继续阅读，下完会问你要不要装',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          );
        },
      ),
    ));
  }

  void _toast(String msg, {bool action = false}) {
    final m = _messenger;
    if (m == null) return;
    m.showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: Text(msg),
      action: action
          ? SnackBarAction(label: '去网页下载', onPressed: openDownloadPage)
          : null,
    ));
  }

  Future<void> _askInstall(UpdateState s) async {
    final ctx = appRootContext;
    if (ctx == null) return;
    await showInstallReadyDialog(ctx, s);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
