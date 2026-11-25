// 逐题解析卡门禁（D166）：用户实报「测试结果里的逐题解析只有解析，没有题目、我的答案、
// 正确答案」。本文件守住四条：
//  ① 客观题答错：题干 / 我的答案（选项正文）/ 正确答案（选项正文）/ 解析 四件都在；
//  ② 客观题没选：明确写「未作答」，不显示空白行；
//  ③ 主观题：给「我的作答」全文 + 「参考答案」（不是笼统的「解析」）；
//  ④ 申诉按钮只在外层给了回调时出现（豁免页/历史页不误显）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/widgets/quiz_review_card.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 400, child: SingleChildScrollView(child: child)),
        ),
      ),
    );

Map<String, dynamic> _choice({
  bool correct = false,
  String chosen = '唯心主义先验论',
}) =>
    {
      'item_id': 'q_choice',
      'stem': '“实践是检验真理的唯一标准”这一命题属于哪一哲学立场',
      'type': 'concept_discrimination',
      'options': ['唯心主义先验论', '辩证唯物主义认识论', '机械唯物主义'],
      'is_correct': correct,
      'answer': 'B',
      'answer_key': 'B',
      'chosen': chosen,
      'explanation': '实践的观点是马克思主义认识论首要的和基本的观点。',
      'source_chunk_id': '',
      'error_label': '概念混淆',
      'error_reason': '把认识论的首要观点误当成唯心主义先验论。',
    };

void main() {
  testWidgets('① 客观题答错：题干 / 我的答案 / 正确答案 / 解析 齐全', (t) async {
    await t.pumpWidget(_host(QuizReviewCard(index: 1, typeLabel: '概念辨析', review: _choice())));
    expect(find.textContaining('“实践是检验真理的唯一标准”'), findsOneWidget);
    expect(find.text('我的答案：'), findsOneWidget);
    expect(find.text('唯心主义先验论'), findsOneWidget);
    expect(find.text('正确答案：'), findsOneWidget);
    expect(find.text('辩证唯物主义认识论'), findsOneWidget);
    expect(find.textContaining('解析：实践的观点'), findsOneWidget);
    // 题号与题型，便于和作答时的顺序对上
    expect(find.textContaining('1. 概念辨析'), findsOneWidget);
  });

  testWidgets('② 客观题没选：写「未作答」而不是空白', (t) async {
    await t.pumpWidget(_host(QuizReviewCard(review: _choice(chosen: ''))));
    expect(find.text('未作答'), findsOneWidget);
    expect(find.text('正确答案：'), findsOneWidget);
  });

  testWidgets('③ 主观题：我的作答全文 + 参考答案', (t) async {
    await t.pumpWidget(_host(QuizReviewCard(index: 3, typeLabel: '错误诊断', review: {
      'item_id': 'q_sub',
      'stem': '用自己的话复述「矛盾的普遍性与特殊性」。',
      'type': 'error_diagnosis',
      'is_correct': true,
      'answer': '矛盾无处不在，又各有各的特殊性。',
      'explanation': '普遍性寓于特殊性之中，特殊性中包含普遍性。',
      'source_chunk_id': '',
      'subjective_feedback': {'score': 0.8, 'suggestions': <String>[]},
    })));
    expect(find.text('我的答案：'), findsOneWidget);
    expect(find.text('矛盾无处不在，又各有各的特殊性。'), findsOneWidget);
    expect(find.textContaining('参考答案：'), findsOneWidget);
    // 主观题挂在「错误诊断」题型下，头部不能直接摆这个题型名
    expect(find.textContaining('主观复述'), findsOneWidget);
    expect(find.textContaining('错误诊断'), findsNothing);
    // 主观题没有选项，不应出现「正确答案」
    expect(find.text('正确答案：'), findsNothing);
    expect(find.text('需改进'), findsNothing);
  });

  testWidgets('④ 申诉按钮只在给了回调时出现（按钮已改名「申诉判分」，见 D167）', (t) async {
    var appealed = 0;
    await t.pumpWidget(_host(QuizReviewCard(
      review: {..._choice(), 'source_chunk_id': 'CH-ME-TH-06-1'},
      onAppeal: () => appealed++,
    )));
    await t.tap(find.text('申诉判分'));
    expect(appealed, 1);

    await t.pumpWidget(_host(QuizReviewCard(review: {
      ..._choice(),
      'source_chunk_id': 'CH-ME-TH-06-1',
    })));
    expect(find.text('申诉判分'), findsNothing);
  });
}
