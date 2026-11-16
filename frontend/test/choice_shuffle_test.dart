import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/services/choice_shuffle.dart';
import 'dart:math';

void main() {
  test('shuffledOptionOrder 是有效排列且包含全部索引', () {
    final rng = Random(42);
    for (var n = 2; n <= 6; n++) {
      for (var t = 0; t < 50; t++) {
        final order = shuffledOptionOrder(n, rng);
        expect(order.length, n);
        expect(order.toSet(), List<int>.generate(n, (i) => i).toSet());
      }
    }
  });

  test('n<=1 原样返回（不打乱）', () {
    final rng = Random(1);
    expect(shuffledOptionOrder(0, rng), <int>[]);
    expect(shuffledOptionOrder(1, rng), <int>[0]);
  });

  test('displayLetterToOrig 正确映射并覆盖所有原始字母', () {
    final rng = Random(7);
    const n = 4;
    final order = shuffledOptionOrder(n, rng);
    final letters = List<String>.generate(n, (pos) => displayLetterToOrig(pos, order));
    // 每个原始字母恰好出现一次
    expect(letters.toSet(), {'A', 'B', 'C', 'D'});
    // 展示字母 i 对应的原始选项内容 == order[i]
    for (var pos = 0; pos < n; pos++) {
      final origIndex = displayLetterToOrig(pos, order).codeUnitAt(0) - 65;
      expect(origIndex, order[pos]);
    }
  });

  test('整体打乱后答案不在固定位置（统计意义）', () {
    final rng = Random(3);
    final positions = <int>[];
    for (var t = 0; t < 200; t++) {
      final order = shuffledOptionOrder(4, rng);
      // 原始答案 'A'(索引0) 现在落在哪个展示位置
      positions.add(order.indexOf(0));
    }
    // 4 个位置都应出现，说明不再是『答案永远第一项』
    expect(positions.toSet(), {0, 1, 2, 3});
  });
}
