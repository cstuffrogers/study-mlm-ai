// 勋章分享 · Web 实现（spec 001 勋章系统 · US5）
//
// 流程：收藏卡 widget → PNG 字节 → 优先 Web Share API（携带图片文件）；
// 浏览器不支持时回退为复制分享文案到剪贴板并提示手动粘贴。
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:web/web.dart' as web;

import '../widgets/badge_share_card.dart';
import 'badge_share_render.dart';

Future<bool> shareBadgeCard({
  required BuildContext context,
  required String appName,
  required int earnedCount,
  required int totalCount,
  required List<BadgeShareItem> badges,
}) async {
  final text = shareText(appName, earnedCount);

  final png = await renderWidgetToPng(
    context,
    BadgeShareCard(
      appName: appName,
      earnedCount: earnedCount,
      totalCount: totalCount,
      badges: badges,
      shareText: text,
    ),
  );
  if (png == null) return false;

  // 优先 Web Share API（携带图片文件）。
  try {
    final result = await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(png, mimeType: 'image/png', name: 'badge_card.png'),
      ],
      text: text,
    ));
    if (result.status == ShareResultStatus.success) return true;
  } catch (_) {
    // Web Share API 不可用或调用失败，回退到剪贴板。
  }

  // 回退：复制分享文案到剪贴板，提示用户手动粘贴。
  await web.window.navigator.clipboard.writeText(text).toDart;
  return true;
}

/// 默认分享文案。
String shareText(String appName, int earnedCount) {
  return '我在「$appName」已获得 $earnedCount 枚学习勋章，继续加油！';
}
