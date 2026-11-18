// 朗读音频这类**派生产物**一律不留盘 —— 启动扫一遍 + 设置页可手动清。
//
// 为什么需要（用户口径）：「tts 生成的音频不是永久保存的吧，要及时清理」。
//
// 现状先说清楚，别建成第二个攒垃圾的地方：
//  · 安卓原生朗读走系统 TextToSpeech 的 `speak()`，音频直接进混音器，
//    **本 App 一个字节都不写盘**（MainActivity 里没有 synthesizeToFile）；
//  · Web 端由后端合成 MP3 流式播放，响应头是 no-store，浏览器不许落盘。
// 这一层是**兜底**：部分 OEM 语音引擎（讯飞 / 小艺一类）会把合成结果写进
// 「调用方」的缓存目录，将来若加「离线语音包」也会落地文件。这类文件纯派生，
// 留着没有任何价值，占的却是用户手机的存储。
//
// 安全性：只扫**本 App 自己的缓存目录**，只删音频后缀、且只删「一小时没动过」的，
// 正在播放/正在写的不会被误删；删不掉（被占用）就跳过，绝不抛给界面。
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 清理结果：删了几个文件、腾了多少字节。
@immutable
class SweepResult {
  const SweepResult(this.files, this.bytes);

  static const SweepResult none = SweepResult(0, 0);

  final int files;
  final int bytes;

  bool get isEmpty => files == 0;

  /// 给人看的大小（<1MB 显示 KB，否则一位小数的 MB）。
  String get sizeLabel {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes B';
  }
}

/// 会被当成本 App 朗读产物的后缀（只认音频，其它文件一律不碰）。
const Set<String> kAudioExts = <String>{
  '.mp3',
  '.wav',
  '.m4a',
  '.aac',
  '.ogg',
  '.opus',
  '.amr',
  '.flac',
};

/// 清掉应用缓存目录里的**残留朗读音频**。
///
/// [olderThan] 是安全阀：只删「这么久没被改过」的文件，默认 1 小时，
/// 避免误删正在播放/正在写入的那一个。[dir] 仅供测试注入。
Future<SweepResult> cleanTempAudio({
  Directory? dir,
  Duration olderThan = const Duration(hours: 1),
  DateTime? now,
}) async {
  // 显式传目录（测试）不做平台判断；Web 端没有可扫的缓存目录，直接报 0。
  if (dir == null && !Platform.isAndroid) return SweepResult.none;
  var files = 0;
  var bytes = 0;
  try {
    final d = dir ?? await getTemporaryDirectory();
    if (!await d.exists()) return SweepResult.none;
    final cutoff = (now ?? DateTime.now()).subtract(olderThan);
    await for (final e in d.list(followLinks: false)) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last.toLowerCase();
      final dot = name.lastIndexOf('.');
      if (dot < 0 || !kAudioExts.contains(name.substring(dot))) continue;
      try {
        final st = await e.stat();
        if (st.modified.isAfter(cutoff)) continue; // 可能正在用，别动
        final size = st.size;
        await e.delete();
        files++;
        bytes += size;
      } catch (err) {
        debugPrint('删朗读缓存文件失败：$err');
      }
    }
  } catch (e) {
    debugPrint('清理朗读缓存失败：$e');
  }
  return SweepResult(files, bytes);
}
