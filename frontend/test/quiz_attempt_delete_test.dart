// 错题本删除链路门禁（D163）
//
// 用户口径：「错题本只收录错题」，条目右下角可删除；点删除先问「是否已掌握」，
// 确认后调 DELETE /api/quiz/attempt/{attempt_id} 并刷新列表。
//
// 这里走单机路径（ApiClient → LocalRouter → LocalQuiz），验证：
//   1. 错题记录能被删除，且只删这一条（其余记录、掌握度都不动）；
//   2. 重复删除 / 不存在的 id → 404（前端据错误码提示）；
//   3. 删除后错题本统计同步下降（列表即 only_wrong 视图）。

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_router.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'package:marxism_reader/services/api_client.dart';

import 'helpers/offline_assets_guard.dart';

void main() {
  if (skipWithoutOfflineAssets()) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  const routeA = 'route_A';

  setUp(() async {
    await OfflineContent.ensureMeta();
    await OfflineContent.ensureQuiz();
    SharedPreferences.setMockInitialValues({});
    LocalDb.reloadForTest();
    await LocalDb.ensure();
    LocalDb.routeId = routeA;
    ApiClient.invalidatePrefix();
  });

  tearDown(() {
    LocalDb.reloadForTest();
  });

  String firstNodeSectionId() {
    for (final sec in OfflineContent.sectionsOf(routeA)) {
      final sid = '${sec['id'] ?? ''}';
      if (sid.isNotEmpty && OfflineContent.nodesOf(sid).isNotEmpty) return sid;
    }
    throw StateError('路线 A 无带节点的章节');
  }

  /// 交一份全错的测验，制造错题记录。
  Future<void> submitWrongQuiz() async {
    final sid = firstNodeSectionId();
    final seed =
        await ApiClient.post('/api/quiz/section/$sid/start', {'user_id': 'u'});
    final items = ((seed['items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map((it) => {'item_id': it['id'], 'answer': 'ZZZ', 'confidence': 'low'})
        .toList();
    await ApiClient.post(
        '/api/quiz/${seed['test_id']}/submit', {'user_id': 'u', 'answers': items});
  }

  test('删除错题：只删一条，其余记录与掌握度不受影响', () async {
    await submitWrongQuiz();
    final before = await ApiClient.get('/api/quiz/history',
        query: {'user_id': 'u', 'only_wrong': 'true'});
    final rows = ((before['rows'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    expect(rows.length, greaterThan(1), reason: '全错提交应产生多条错题记录');
    final target = '${rows.first['attempt_id']}';
    expect(target.trim(), isNotEmpty);

    final attemptsBefore = LocalDb.attempts.length;
    final masteryBefore = LocalDb.mastery[routeA]?.length ?? 0;

    final res =
        await ApiClient.delete('/api/quiz/attempt/${Uri.encodeComponent(target)}');
    expect(res['deleted'], target);

    expect(LocalDb.attempts.length, attemptsBefore - 1);
    expect(LocalDb.mastery[routeA]?.length ?? 0, masteryBefore,
        reason: '删除作答记录不回滚已写入的掌握度');

    final after = await ApiClient.get('/api/quiz/history',
        query: {'user_id': 'u', 'only_wrong': 'true'});
    final ids = ((after['rows'] as List?) ?? const [])
        .map((r) => '${(r as Map)['attempt_id']}')
        .toList();
    expect(ids, isNot(contains(target)), reason: '删除后错题本不应再出现该条');
    expect((after['wrong'] as num).toInt(), rows.length - 1);
  });

  test('删除不存在的记录 → 404', () async {
    await expectLater(
      ApiClient.delete('/api/quiz/attempt/not_exist/not_exist'),
      throwsA(predicate((e) => '$e'.contains('404'))),
    );
  });

  test('重复删除同一条 → 第二次 404', () async {
    await submitWrongQuiz();
    final hist = await ApiClient.get('/api/quiz/history',
        query: {'user_id': 'u', 'only_wrong': 'true'});
    final id = '${(((hist['rows'] as List?) ?? const []).first as Map)['attempt_id']}';
    await ApiClient.delete('/api/quiz/attempt/${Uri.encodeComponent(id)}');
    await expectLater(
      ApiClient.delete('/api/quiz/attempt/${Uri.encodeComponent(id)}'),
      throwsA(predicate((e) => '$e'.contains('404'))),
    );
  });

  test('未知 quiz 子路径仍 404（删除分支不吞掉正常路由）', () async {
    await expectLater(
      LocalRouter.delete('/api/quiz/whatever', const {}),
      throwsA(predicate((e) => e is LocalApiException && e.status == 404)),
    );
  });
}
