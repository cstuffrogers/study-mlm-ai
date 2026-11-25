// 「该复习了」巩固条目点「去做巩固题」应当进**试题**（D162，用户实报）。
//
// 旧行为：`route_map._practice` 推的是 `ChapterGuideScreen`（深入学习导读页）——
// 用户点「去做练习」却落到一个只读介绍页，还得自己往下翻找「开始章节测试」的按钮。
// 现在直接推 `ChapterTestScreen`：章节测试本身就按知识点交错排题，
// 与「巩固 / 加强检索与迁移」的语义一致；做完返回则刷新到期队列。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

/// 取出源码里从 [start] 到与之配对的 `}` 的那一段。
String _braceSlice(String src, String start) {
  final i = src.indexOf(start);
  expect(i, greaterThan(0), reason: '找不到 $start');
  var depth = 0;
  for (var k = i; k < src.length; k++) {
    if (src[k] == '{') depth++;
    if (src[k] == '}') {
      depth--;
      if (depth == 0) return src.substring(i, k + 1);
    }
  }
  fail('$start 的大括号没有闭合');
}

void main() {
  test('① 巩固条目跳的是章节测试，不是深入学习导读页', () {
    final src = _read('lib/screens/route_map.dart');
    final body = _braceSlice(src, 'void _practice(ReviewItem it) {');
    expect(body, contains('ChapterTestScreen('),
        reason: '点「去做巩固题」要直接出题');
    expect(body, isNot(contains('ChapterGuideScreen(')),
        reason: '不能再落到只读的深入学习页');
    expect(body, contains('sectionId: it.sectionId'));
    expect(body, contains('routeId: widget.routeId'));
    // 返回后刷新队列，避免刚做完的条目还挂在「建议巩固」里
    expect(body, contains('_loadDue()'));
    expect(src, contains("import 'chapter_test.dart';"));
  });

  test('② 文案与行为对齐：按钮叫「去做巩固题」，说明写清进本章测试', () {
    final card = _read('lib/widgets/review_card.dart');
    expect(card, contains("'去做巩固题'"));
    expect(card, isNot(contains("'去做混合练习'")),
        reason: '已不是跨章节混合练习，文案不能继续误导');
    expect(card, contains('进本章测试做几道题巩固'));
    expect(card, contains('建议巩固 · 不到期，做几道巩固题即可'));
  });

  test('③ 使用说明同步', () {
    final guide = _read('lib/widgets/guide_dialog.dart');
    expect(guide, contains('去做巩固题'));
    expect(guide, isNot(contains('去做混合练习')));
  });
}
