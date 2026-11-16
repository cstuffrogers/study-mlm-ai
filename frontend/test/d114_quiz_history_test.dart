// D114 门禁：错题本 / 测试历史的数据契约。
//
// 背景：离线版错题本（TestHistoryScreen）读的是后端 /api/quiz/history 的形状
// `{total, wrong, rows: [...]}`，而 LocalQuiz.history 早先只回 `{items, count}`，
// 于是答完题打开错题本永远是「0 / 0 / — / 暂无作答记录」。
// 这个测试守住：本地历史必须与后端同构，且行内带题面、章节标题、得分、错因。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_quiz.dart';
import 'package:marxism_reader/offline/offline_content.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await OfflineContent.ensureMeta();
    await OfflineContent.ensureQuiz();
  });

  setUp(() {
    LocalDb.attempts = [];
    LocalDb.tests = {};
  });

  void seed() {
    LocalDb.tests = {
      'local_1': {
        'id': 'local_1',
        'section_id': 'sec_A_03',
        'route_id': 'route_A',
        'status': 'submitted',
        'created_at': '2026-11-14T10:00:00.000Z',
      },
    };
    final quiz = OfflineContent.quizItems('sec_A_03').first;
    final quizId = '${quiz['id']}';
    LocalDb.attempts = [
      {
        'node_id': '${quiz['node_id'] ?? ''}',
        'quiz_id': quizId,
        'test_id': 'local_1',
        'answer': 'B',
        'reference': '测试用解析',
        'source_chunk_id': 'GUIDE-sec_A_03-1',
        'is_correct': false,
        'score': 0.0,
        'error_category': 'concept_layer_confusion',
        'confidence': 'general',
        'created_at': '2026-11-14T10:01:00.000Z',
      },
    ];
  }

  test('历史返回后端同构字段，错题本能显示出来', () {
    seed();
    final j = LocalQuiz.history(limit: 200);
    expect(j['total'], 1, reason: 'TestHistoryScreen 读 total，不是 count');
    expect(j['wrong'], 1);
    final rows = (j['rows'] as List).cast<Map<String, dynamic>>();
    expect(rows, hasLength(1));
    final r = rows.first;
    for (final k in ['stem', 'options', 'answer', 'answer_key', 'section_id',
                     'section_title', 'score', 'error_category', 'created_at',
                     'source_chunk_id']) {
      expect(r.containsKey(k), isTrue, reason: '错题本要用 $k 字段');
    }
    expect('${r['stem']}', isNotEmpty);
    expect((r['options'] as List), isNotEmpty);
    expect('${r['section_title']}', '实践的辩证法：从《实践论》到《矛盾论》');
    expect('${r['answer_key']}', isNotEmpty);
  });

  test('只看错题：答对的记录被过滤掉', () {
    seed();
    LocalDb.attempts = [
      ...LocalDb.attempts,
      {
        'node_id': '',
        'quiz_id': '${OfflineContent.quizItems('sec_A_03').first['id']}',
        'test_id': 'local_1',
        'answer': 'A',
        'is_correct': true,
        'score': 1.0,
        'error_category': '',
        'created_at': '2026-11-14T10:02:00.000Z',
      },
    ];
    final all = LocalQuiz.history(limit: 200);
    expect(all['total'], 2);
    expect(all['wrong'], 1);
    final onlyWrong = LocalQuiz.history(onlyWrong: true, limit: 200);
    expect(onlyWrong['total'], 1);
    expect((onlyWrong['rows'] as List).single['is_correct'], isFalse);
  });

  test('空记录：返回 0 而不是抛异常', () {
    final j = LocalQuiz.history();
    expect(j['total'], 0);
    expect(j['wrong'], 0);
    expect(j['rows'], isEmpty);
  });
}
