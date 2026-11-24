// D164 门禁：勋章图标键必须「每枚唯一」，且离线目录与后端目录一致。
//
// 背景（实测缺陷）：后端 content/badges.py 在 v1.4.18 已把 29 枚勋章的
// icon_key 各自改成唯一值（seed/sprout/book/…/chat/forum），但前端离线目录
// offline/local_badge.dart 的 iconKey 仍留成「分类键」（knowledge/journey/
// milestone/quiz/route/streak/dialogue）。单机版（默认）走 LocalBadge，
// 于是 6 枚知识徽章共用同一个图标、界面看不出勋章差异。
//
// 本测试锁三件事：
//   1. 离线目录每枚勋章 iconKey 互不相同；
//   2. 每个 iconKey 映射到的 IconData 也互不相同（不是只改了字符串）；
//   3. 离线目录与后端 badges.py 的 badge_id / icon_key 完全对齐。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_badge.dart';
import 'package:marxism_reader/widgets/badge_gift_open.dart';

/// 旧的「分类色调键」——曾经被误当作勋章图标键使用，现在不允许再出现。
///
/// 注意：`quiz` 不在此列。它既是旧的分类色调键，也是后端为 quiz_10
/// 指定的专属图标键（两者同名是历史遗留，不算漂移）。
const _legacyCategoryKeys = <String>{
  'knowledge',
  'journey',
  'milestone',
  'route',
  'streak',
  'dialogue',
};

/// 解析后端 badges.py：返回 {badge_id: icon_key}。
Map<String, String> _parseBackendBadges() {
  final f = File('../backend/content/badges.py');
  expect(f.existsSync(), isTrue, reason: '未找到后端勋章目录 ${f.path}');
  final src = f.readAsStringSync();
  final out = <String, String>{};
  for (final chunk in src.split('BadgeDef(').skip(1)) {
    // 每个 BadgeDef(...) 里的字符串按位次是：
    // 0=badge_id 1=name 2=description 3=category 4=icon_key ...
    final quoted = RegExp(r'"([^"]*)"')
        .allMatches(chunk)
        .map((m) => m.group(1)!)
        .toList();
    if (quoted.length < 5) continue;
    out[quoted[0]] = quoted[4];
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('离线勋章目录：iconKey 每枚唯一', () {
    final badges = allBadges(enabledOnly: false);
    expect(badges.length, greaterThanOrEqualTo(29));

    final byKey = <String, List<String>>{};
    for (final b in badges) {
      byKey.putIfAbsent(b.iconKey, () => []).add(b.badgeId);
    }
    final dup = byKey.entries.where((e) => e.value.length > 1).toList();
    expect(
      dup,
      isEmpty,
      reason: '以下勋章共用同一 iconKey（应为每枚唯一）：\n'
          '${dup.map((e) => '  ${e.key} → ${e.value.join(", ")}').join("\n")}',
    );
  });

  test('离线勋章目录：iconKey 不能再用分类色调键', () {
    for (final b in allBadges(enabledOnly: false)) {
      expect(_legacyCategoryKeys.contains(b.iconKey), isFalse,
          reason: '${b.badgeId} 的 iconKey 仍是分类键 "${b.iconKey}"，'
              '应改成该勋章专属图标键');
    }
  });

  test('离线勋章目录：iconKey 映射到互不相同的 IconData', () {
    final icons = <int, List<String>>{};
    for (final b in allBadges(enabledOnly: false)) {
      final icon = BadgeGiftOpen.iconFor(b.iconKey);
      icons.putIfAbsent(icon.codePoint, () => []).add(b.iconKey);
    }
    final dup = icons.entries.where((e) => e.value.length > 1).toList();
    expect(dup, isEmpty,
        reason: '以下 iconKey 映射到同一个 IconData（界面显示一致，'
            '等于没区分）：\n'
            '${dup.map((e) => '  codePoint=${e.key} → ${e.value.join(", ")}').join("\n")}');
  });

  test('离线目录与后端 badges.py 完全对齐（badge_id + icon_key）', () {
    final backend = _parseBackendBadges();
    expect(backend.length, greaterThanOrEqualTo(29));

    final local = {
      for (final b in allBadges(enabledOnly: false)) b.badgeId: b.iconKey,
    };

    final missingLocal = backend.keys.where((k) => !local.containsKey(k)).toList();
    expect(missingLocal, isEmpty,
        reason: '后端有、离线目录没有的勋章：$missingLocal');

    final missingBackend =
        local.keys.where((k) => !backend.containsKey(k)).toList();
    expect(missingBackend, isEmpty,
        reason: '离线目录有、后端没有的勋章：$missingBackend');

    final drift = <String>[];
    for (final e in backend.entries) {
      if (local[e.key] != e.value) {
        drift.add('  ${e.key}: 后端="${e.value}" 离线="${local[e.key]}"');
      }
    }
    expect(drift, isEmpty,
        reason: '离线目录 iconKey 与后端不一致（单机版会显示成旧图标）：\n'
            '${drift.join("\n")}');
  });
}
