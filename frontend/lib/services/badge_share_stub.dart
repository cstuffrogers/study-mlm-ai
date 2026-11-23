// 勋章分享 · 空实现（spec 001 勋章系统 · US5）
//
// 无 io 也无 js_interop 的环境（如纯 Dart VM）落到此文件。
// 返回 false 表示分享不可用，UI 层据此给出提示。
import 'package:flutter/material.dart';

import '../widgets/badge_share_card.dart';

Future<bool> shareBadgeCard({
  required BuildContext context,
  required String appName,
  required int earnedCount,
  required int totalCount,
  required List<BadgeShareItem> badges,
}) async {
  return false;
}
