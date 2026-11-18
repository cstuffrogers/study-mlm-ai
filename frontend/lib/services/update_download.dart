// 后台下载更新包：点「下载更新」后**不占着界面** —— 框关掉，人继续读书，
// 下载在后台跑；下完再单独问一句「现在装吗」。
//
// 口径（与 app_update.dart 一致，别越线）：
//  · 不静默安装：装不装由用户在系统安装器里点；
//  · 不重复下载：已经在下载 / 已下好同一个版本，再来一次直接忽略；
//  · 失败要说人话（网络中断 / 文件不完整），并给一条「去网页下载」的出路；
//  · 状态放全局 ValueNotifier，UI 层（widgets/update_host.dart）负责眼皮底下的提示，
//    这样下载逻辑不依赖任何页面，随手切页面也不会断。
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_update.dart';

/// 更新包下载所处的阶段。
enum UpdatePhase {
  /// 什么都没发生。
  idle,

  /// 正在后台下。
  downloading,

  /// 下好了，等用户决定装不装。
  ready,

  /// 下失败了。
  failed,
}

/// 下载状态快照（不可变，方便 UI 直接比对）。
@immutable
class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.info,
    this.progress,
    this.file,
    this.error,
  });

  static const UpdateState idle = UpdateState();

  final UpdatePhase phase;

  /// 目标版本（idle 时为 null）。
  final ReleaseInfo? info;

  /// 0~1；总大小未知时为 null（显示「正在下载…」而不是假的百分比）。
  final double? progress;

  /// 下好的安装包（[UpdatePhase.ready] 时非空）。
  final File? file;

  /// 失败原因（[UpdatePhase.failed] 时非空）。
  final String? error;

  bool get busy => phase == UpdatePhase.downloading;
  bool get ready => phase == UpdatePhase.ready;

  String get version => info?.version ?? '';

  /// 「42%」这种给人看的百分比；进度未知时是 null。
  String? get percentLabel =>
      progress == null ? null : '${(progress! * 100).clamp(0, 100).toStringAsFixed(0)}%';
}

/// 全局唯一的下载状态。UI 用 ValueListenableBuilder 或监听器跟它。
final ValueNotifier<UpdateState> updateState =
    ValueNotifier<UpdateState>(UpdateState.idle);

/// 下载器的可注入签名（测试用假实现，生产走 [downloadApk]）。
typedef ApkDownloader = Future<File?> Function(
  ReleaseInfo info,
  void Function(double? progress) onProgress,
);

/// 开始（或继续）后台下载。已有下载在进行 / 同版本已下好时直接返回，不重复拉 73MB。
Future<void> startUpdateDownload(
  ReleaseInfo info, {
  ApkDownloader? downloader,
}) async {
  final current = updateState.value;
  if (current.busy) return;
  if (current.ready && current.version == info.version) return;
  if (!info.hasApk) {
    updateState.value = UpdateState(
      phase: UpdatePhase.failed,
      info: info,
      error: '这个版本没有安装包附件，只能去网页下载。',
    );
    return;
  }

  updateState.value = UpdateState(phase: UpdatePhase.downloading, info: info);
  final download = downloader ?? _defaultDownloader;

  File? file;
  try {
    file = await download(info, (p) {
      // 期间被 cancelUpdateDownload 打断就不要再把状态写回去
      if (updateState.value.phase != UpdatePhase.downloading) return;
      updateState.value = UpdateState(
        phase: UpdatePhase.downloading,
        info: info,
        progress: p,
      );
    });
  } catch (e) {
    debugPrint('后台下载更新异常：$e');
    file = null;
  }
  if (updateState.value.phase != UpdatePhase.downloading) return; // 已被取消
  updateState.value = file == null
      ? UpdateState(
          phase: UpdatePhase.failed,
          info: info,
          error: '下载没成功（网络中断或文件不完整）。可以改用浏览器下载。',
        )
      : UpdateState(
          phase: UpdatePhase.ready,
          info: info,
          progress: 1,
          file: file,
        );
}

Future<File?> _defaultDownloader(
  ReleaseInfo info,
  void Function(double? progress) onProgress,
) =>
    downloadApk(info, onProgress: onProgress);

/// 归位到「什么都没发生」。已下好的包默认**保留**（下一次启动会被
/// `cleanDownloadedApks` 清掉，不占长期存储），[deleteFile] 为 true 才立刻删。
void resetUpdateDownload({bool deleteFile = false}) {
  final f = updateState.value.file;
  if (deleteFile && f != null) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (e) {
      debugPrint('删更新包失败：$e');
    }
  }
  updateState.value = UpdateState.idle;
}
