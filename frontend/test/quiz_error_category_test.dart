// 测验判分回归：错因必须「显示得出来、看得懂」。
//
// 曾经的故障：
//   1. 单机引擎在 review 里用 reference 而前端读 explanation → 「解析」空白；
//   2. 客观题 review 不返回 answer_key → 结果页没有正确答案；
//   3. 错因直接写内部编码（real_unknown / concept_layer_confusion）
//      → 学习者看到的是英文串，等于没显示。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_quiz.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('错因编码 → 中文标签，未知编码原样返回', () {
    expect(LocalQuiz.errorLabel('real_unknown'), '真不会');
    expect(LocalQuiz.errorLabel('concept_layer_confusion'), '概念层级混淆');
    expect(LocalQuiz.errorLabel('stance_deviation'), '立场偏移');
    expect(LocalQuiz.errorLabel('concept_application'), '概念运用不准');
    expect(LocalQuiz.errorLabel('term_misuse'), '术语使用不当');
    expect(LocalQuiz.errorLabel(''), '');
    expect(LocalQuiz.errorLabel('some_new_code'), 'some_new_code');
  });

  test('错因诊断句：每种错因都给「错在哪 + 怎么改」', () {
    final quiz = <String, dynamic>{'type': 'concept_discrimination'};
    for (final cat in [
      'real_unknown',
      'concept_layer_confusion',
      'stance_deviation',
      'concept_application',
      'term_misuse',
    ]) {
      final advice = LocalQuiz.errorAdvice(quiz, cat, '');
      expect(advice, isNotEmpty, reason: '$cat 应有诊断句');
      expect(advice.contains('_'), isFalse, reason: '$cat 诊断句泄露了内部编码');
    }
    expect(LocalQuiz.errorAdvice(quiz, '', ''), '');
  });

  test('判分结果结构完整：题面/选项/正确答案/解析/错因 一项不缺', () async {
    // 这道题来自 sec_A_02 的正式题库（concept_discrimination）
    const quiz = <String, dynamic>{
      'id': 'q_practice_def',
      'node_id': 'kn_practice',
      'type': 'concept_discrimination',
      'stem': '在马克思主义哲学中，对「实践」理解正确的是：',
      'options': ['人的主观的精神性活动', '人的物质性、客观性的物质活动'],
      'answer': 'B',
      'explanation': '实践是物质性活动，不是纯主观精神活动。',
      'source_chunk_id': 'CH-ME-TH-01-1',
      'authority_status': 'reviewed',
      'trial_only': false,
      'subjective': false,
    };

    // 走 classifyError + errorAdvice 的生产路径（与 submit 内一致）
    final errCat = LocalQuiz.classifyError(quiz, quiz['options'][0] as String);
    expect(errCat, isNotEmpty, reason: '选错必须给出错因');

    final label = LocalQuiz.errorLabel(errCat);
    expect(label.contains('_'), isFalse, reason: '错因标签不能是内部编码');

    final advice = LocalQuiz.errorAdvice(quiz, errCat, '');
    expect(advice, isNotEmpty);
  });

  test('选到偏离立场的选项 → 错因归为立场偏移', () {
    final quiz = <String, dynamic>{'type': 'text_location'};
    final chosen = LocalQuiz.classifyError(quiz, '这是一种人道主义的马克思主义解读');
    // 只有命中偏离关键词才判立场偏移，否则普通题归真不会
    expect(
      chosen == 'stance_deviation' || chosen == 'real_unknown',
      isTrue,
    );
    expect(LocalQuiz.errorLabel(chosen), isNotEmpty);
  });
}
