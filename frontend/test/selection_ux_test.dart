// 「选中文字」与「深入学习」两处界面回归。
//
// 用户报的三个问题，逐条钉死：
//   ① 选中导读/原文文字时，除本站自己的释义浮框外还会弹出系统的「copy / share」工具条，
//      两套浮窗互相遮挡 —— 本站浮框已自带复制/朗读/五种模式，系统工具条必须屏蔽；
//   ② 释义浮框原先出现在屏幕中部，正好盖住刚选中的那句话 —— 现在贴顶出现；
//   ③ 深入学习页正文字号偏小，正文与要点统一放大到 15。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _guide = 'lib/screens/chapter_guide_screen.dart';
const _reader = 'lib/screens/work_reader_screen.dart';

String _read(String p) => File(p).readAsStringSync();

/// 取出某个浮动面板 `initialOffset` 的纵向初值（最后一个整数即 dy）。
int _topOf(String path, String anchor, String offsetAnchor) {
  final src = _read(path);
  final a = src.indexOf(anchor);
  expect(a, greaterThan(0), reason: '找不到 $anchor');
  final i = src.lastIndexOf(offsetAnchor, a);
  expect(i, greaterThan(0), reason: '找不到 $offsetAnchor');
  final open = src.indexOf('(', i);
  var depth = 0;
  var end = -1;
  for (var k = open; k < src.length; k++) {
    final c = src[k];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) {
        end = k;
        break;
      }
    }
  }
  expect(end, greaterThan(open));
  final body = src.substring(open + 1, end);
  final ints = RegExp(r'\d+')
      .allMatches(body)
      .map((m) => int.parse(m.group(0)!))
      .toList();
  expect(ints, isNotEmpty);
  return ints.last;
}

void main() {
  test('选中文字不再弹系统 copy/share 工具条（导读 + 原文阅读器）', () {
    for (final p in [_guide, _reader]) {
      final src = _read(p);
      final i = src.indexOf('SelectionArea(');
      expect(i, greaterThan(0), reason: '$p 没有 SelectionArea');
      final block = src.substring(i, i + 400);
      expect(block.contains('contextMenuBuilder'), isTrue,
          reason: '$p 没屏蔽系统工具条，选中会同时冒出 copy/share 浮框');
      expect(block.contains('SizedBox.shrink()'), isTrue,
          reason: '$p 的 contextMenuBuilder 必须返回空组件');
    }
  });

  test('释义浮框贴顶出现，不压在选中的文字上', () {
    // 导读页：MovableBox → SelectionAskPanel
    expect(_topOf(_guide, 'SelectionAskPanel(', 'initialOffset: Offset('),
        lessThanOrEqualTo(24));
    // 阅读器：MovableBox → _selectionFab()
    expect(_topOf(_reader, '_selectionFab()', 'initialOffset: Offset('),
        lessThanOrEqualTo(24));
    // 旧写法（离屏底 280~300）不许回来
    expect(_read(_guide).contains('bodySize.height - 300'), isFalse);
    expect(_read(_reader).contains('size.height - 280'), isFalse);
  });

  test('深入学习页：正文与要点字号不小于 15', () {
    final src = _read(_guide);
    // 正文段（_prose）：height 1.75
    final prose = RegExp(r'fontSize: (\d+(?:\.\d+)?),\s*\n\s*height: 1\.75')
        .firstMatch(src);
    expect(prose, isNotNull, reason: '找不到 _prose 的正文样式');
    expect(double.parse(prose!.group(1)!), greaterThanOrEqualTo(15),
        reason: '深入学习正文字号被改小了');
    // 要点段：height 1.8
    final body = RegExp(r'fontSize: (\d+(?:\.\d+)?),\s*\n\s*height: 1\.8,')
        .firstMatch(src);
    expect(body, isNotNull, reason: '找不到要点段的正文样式');
    expect(double.parse(body!.group(1)!), greaterThanOrEqualTo(15),
        reason: '深入学习要点字号被改小了');
  });
}
