// 申诉判分门禁（D167）：用户实报「测试结果里点申诉没反应，这按钮有什么用」。
//
// 根因：`chapter_test` 直接 `_api.appeal(testId, itemId)` —— 不收理由、不看回执、不提示；
// 本机侧也只是往 `LocalDb.tests[testId]['appeals']` 记一笔，既不改分也没有人工复核台，
// 于是用户视角就是「点了没反应」。本文件守住：
//  ① 弹窗必须当面说清「不会自动改分」，并把理由原样传给接口；
//  ② 提交成功关框带回执，失败留在框里显式报错（不能静默关掉）；
//  ③ 卡片：错题才有「申诉判分」，答对不给；没有溯源分片也要能申诉；申诉后换状态；
//  ④ 本机记录：同题重复申诉只留最新一条，回执带 status/message，错题本能看到「已申诉」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_insight.dart';
import 'package:marxism_reader/offline/local_quiz.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'package:marxism_reader/widgets/quiz_appeal_dialog.dart';
import 'package:marxism_reader/widgets/quiz_review_card.dart';
import 'helpers/offline_assets_guard.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: SizedBox(width: 400, child: SingleChildScrollView(child: child)))),
    );

Map<String, dynamic> _review({bool correct = false, String chunk = ''}) => {
      'item_id': 'q_1',
      'stem': '“实践是检验真理的唯一标准”属于哪一哲学立场',
      'type': 'concept_discrimination',
      'options': ['唯心主义先验论', '辩证唯物主义认识论'],
      'is_correct': correct,
      'answer': 'B',
      'answer_key': 'B',
      'chosen': correct ? '辩证唯物主义认识论' : '唯心主义先验论',
      'explanation': '实践的观点是马克思主义认识论首要的和基本的观点。',
      'source_chunk_id': chunk,
      'error_label': '概念混淆',
      'error_reason': '把认识论的首要观点误当成唯心主义先验论。',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------- ③ 卡片
  testWidgets('③ 卡片：错题没有溯源分片也有「申诉判分」，答对不给', (t) async {
    await t.pumpWidget(_host(QuizReviewCard(review: _review(), onAppeal: () {})));
    expect(find.text('申诉判分'), findsOneWidget);

    await t.pumpWidget(_host(QuizReviewCard(review: _review(correct: true), onAppeal: () {})));
    expect(find.text('申诉判分'), findsNothing);
    expect(find.textContaining('已申诉'), findsNothing);
  });

  testWidgets('③ 卡片：申诉后按钮换成「已申诉 · 待复核」', (t) async {
    await t.pumpWidget(_host(QuizReviewCard(review: _review(), onAppeal: () {}, appealed: true)));
    expect(find.text('申诉判分'), findsNothing);
    expect(find.textContaining('已申诉 · 待复核'), findsOneWidget);
    expect(find.textContaining('不会自动改分'), findsOneWidget);
  });

  // ---------------------------------------------------------------- ①② 弹窗
  testWidgets('①② 弹窗：写明不会自动改分，理由原样提交、成功后关框带回执', (t) async {
    Map<String, dynamic>? got;
    String? sent;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              got = await showQuizAppealDialog(
                ctx,
                title: '第 2 题 · 概念辨析',
                stem: '“实践是检验真理的唯一标准”属于哪一哲学立场',
                onSubmit: (reason) async {
                  sent = reason;
                  return {
                    'status': 'pending_review',
                    'message': '申诉已记录（待复核）：不会自动改分，请对照原文分片再核一遍。',
                  };
                },
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('打开'));
    await t.pumpAndSettle();
    expect(find.textContaining('不会自动改分'), findsWidgets, reason: '必须当面说清不会自动改分');
    expect(find.textContaining('溯源'), findsOneWidget, reason: '要引导用户先核对原文');
    expect(find.textContaining('第 2 题 · 概念辨析'), findsOneWidget);

    await t.enterText(find.byType(TextField), '  原文第 3 段不是这个意思  ');
    await t.tap(find.text('提交申诉'));
    await t.pumpAndSettle();
    expect(sent, '原文第 3 段不是这个意思', reason: '理由要去掉首尾空白再提交');
    expect(got?['status'], 'pending_review');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('② 弹窗：提交失败不关框，就地报错', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showQuizAppealDialog(
              ctx,
              title: '第 1 题',
              onSubmit: (_) async => throw StateError('boom'),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('打开'));
    await t.pumpAndSettle();
    await t.tap(find.text('提交申诉'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('提交失败'), findsOneWidget);
  });

  // ---------------------------------------------------------------- ④ 本机记录
  if (!hasOfflineAssets) {
    test('（跳过）申诉本机记录需要 assets/offline 离线数据', () {},
        skip: '未发现 assets/offline/，运行 python scripts/export_offline_assets.py');
    return;
  }

  group('④ 本机申诉记录', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await OfflineContent.ensureMeta();
      await OfflineContent.ensureQuiz();
    });

    setUp(() {
      LocalDb.attempts = [];
      LocalDb.tests = {
        'local_1': {'id': 'local_1', 'section_id': 'sec_A_03', 'route_id': 'route_A', 'status': 'submitted'},
      };
    });

    test('同题重复申诉只留最新一条，回执带 status/message', () {
      final a = LocalInsight.appeal('local_1', 'q_x', '第一次的理由');
      expect(a['status'], 'pending_review');
      expect('${a['message']}', contains('不会自动改分'));
      expect(a['appeal_id'], 'ap_local_1_q_x');
      expect(a['count'], 1);

      final b = LocalInsight.appeal('local_1', 'q_x', '第二次的理由');
      expect(b['count'], 1, reason: '同一题重复申诉不叠加（后端 appeal_id 一题一条）');
      final stored = (LocalDb.tests['local_1']!['appeals'] as List).cast<Map>();
      expect(stored.length, 1);
      expect('${stored.single['reason']}', '第二次的理由');

      final c = LocalInsight.appeal('local_1', 'q_y', '');
      expect(c['count'], 2);
      expect(LocalDb.tests['local_1']!['appeals'], isA<List>());
    });

    test('错题本行带 appealed 标记与申诉理由', () {
      final quiz = OfflineContent.quizItems('sec_A_03').first;
      final quizId = '${quiz['id']}';
      LocalDb.attempts = [
        {
          'node_id': '${quiz['node_id'] ?? ''}',
          'quiz_id': quizId,
          'test_id': 'local_1',
          'answer': 'A',
          'reference': '测试用解析',
          'is_correct': false,
          'created_at': '2026-11-25T10:00:00.000Z',
        },
      ];
      expect(LocalQuiz.history(onlyWrong: true)['rows'].first['appealed'], isFalse);
      LocalInsight.appeal('local_1', quizId, '觉得解析写错了');
      final row = Map<String, dynamic>.from(LocalQuiz.history(onlyWrong: true)['rows'].first as Map);
      expect(row['appealed'], isTrue);
      expect(row['appeal_reason'], '觉得解析写错了');
    });
  });
}
