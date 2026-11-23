// 勋章分享 · 原生实现（spec 001 勋章系统 · US5）
//
// 流程：收藏卡 widget → PNG 字节 → 写临时文件 → share_plus 调系统分享面板。
// 用户可选择微信、朋友圈、QQ 等任意支持图片分享的渠道。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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

  // 写入临时文件后交给系统分享面板。
  final dir = await getTemporaryDirectory();
  final file = File(
      '${dir.path}/badge_card_${DateTime.now().millisecondsSinceEpoch}.png');
  await file.writeAsBytes(png);

  final result = await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path)],
    text: text,
  ));
  return result.status == ShareResultStatus.success;
}

/// 默认分享文案。
String shareText(String appName, int earnedCount) {
  return '我在「$appName」已获得 $earnedCount 枚学习勋章，继续加油！';
}
