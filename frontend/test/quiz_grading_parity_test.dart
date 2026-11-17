// D131 门禁：客观题判分口径必须与后端 `_norm_choice` 一致。
//
// 后端：strip → upper → 取第一个字符。
// 单机版曾把「空白 + . 、 。」全删再整串比，于是「A．」（全角点）在联网版算对、
// 单机版算错。这类差异只在真机上才暴露，用这条测试钉住口径。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_quiz.dart';

void main() {
  test('选项归一化与后端同口径（取首字符，不整串比）', () {
    // 后端 _norm_choice 对这几种输入都是 'A'
    for (final raw in ['A', 'a', ' A ', 'A.', 'A．', 'A、', 'A 因为生产关系']) {
      expect(LocalQuiz.normChoice(raw), 'A', reason: 'raw=<$raw>');
    }
    expect(LocalQuiz.normChoice(''), '');
    expect(LocalQuiz.normChoice('   '), '');
    expect(LocalQuiz.normChoice('B'), 'B');
    expect(LocalQuiz.normChoice('d'), 'D');
  });
}
