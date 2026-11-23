// 勋章收藏卡 → PNG 渲染工具（spec 001 勋章系统 · US5 分享）
//
// 平台无关：把任意 Widget 通过 RepaintBoundary 渲染为 PNG 字节。
// 原生与 Web 的分享实现共用此工具，差异仅在「拿到 PNG 后如何分享」。
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as image_pkg;

/// 将 widget 渲染为 PNG 字节。
///
/// 通过临时插入 OverlayEntry，等首帧构建完成后用 RenderRepaintBoundary
/// 截图，最后移除 overlay。返回 null 表示渲染失败。
Future<Uint8List?> renderWidgetToPng(
  BuildContext context,
  Widget widget, {
  double maxPixelRatio = 3.0,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final boundaryKey = GlobalKey<State>();
  final completer = Completer<Uint8List?>();

  final pixelRatio =
      MediaQuery.of(context).devicePixelRatio.clamp(1.0, maxPixelRatio);

  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final render =
              boundaryKey.currentContext?.findRenderObject()
                  as RenderRepaintBoundary?;
          if (render != null) {
            final ui.Image image =
                await render.toImage(pixelRatio: pixelRatio);
            final rawData =
                await image.toByteData(format: ui.ImageByteFormat.rawRgba);
            image.dispose();
            if (rawData == null) {
              completer.complete(null);
              return;
            }
            // 用 image 包将原始 RGBA 数据编码为 PNG。
            final img = image_pkg.Image.fromBytes(
              width: image.width,
              height: image.height,
              bytes: rawData.buffer,
              numChannels: 4,
            );
            completer.complete(image_pkg.encodePng(img));
          } else {
            completer.complete(null);
          }
        } catch (e) {
          if (!completer.isCompleted) completer.completeError(e);
        }
      });
      return RepaintBoundary(key: boundaryKey, child: widget);
    },
  );
  overlay.insert(entry);

  try {
    return await completer.future.timeout(timeout);
  } on TimeoutException {
    return null;
  } catch (_) {
    return null;
  } finally {
    entry.remove();
  }
}
