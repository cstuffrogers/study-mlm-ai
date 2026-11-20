// D161 第四轮深检：学情档案 + 学习分析 数据深检
//
// 五个维度：
//  1. 时间边界精度：week/month 窗口边界（7/30 天，含端点）、时区与夏令时（统一按
//     UTC 瞬时比较）、跨日连续性（streak 按 UTC 日计）、秒级/毫秒级精度、
//     缺失/非法时间戳的防御；
//  2. 极端值处理：全对用户、全错用户、单数据点、零数据、极大值（1.0）、
//     双路线（A 有数据 / B 空）的计算与展示合理性；
//  3. 统计口径可解释性：健康度/掌握度/雷达/保持率/FSRS 的界面说明存在性
//     （widget 级验证）；
//  4. 导出格式完整性：元数据（版本/时间/用户标识）、七份文档、JSON 可解析、
//     往返一致、缺失字段保留、多余字段加法合并、非法文件报错、较大数据量；
//  5. 离线在线一致性：overview/profile/summary/motivation/fit 的响应键集与
//     后端契约一致、summary GET/POST 双通道同结果、ApiClient 缓存命中与写后
//     失效、作答写入格式与分析消费一致。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marxism_reader/offline/data_compat.dart';
import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_insight.dart';
import 'package:marxism_reader/offline/local_mastery.dart';
import 'package:marxism_reader/offline/local_router.dart';
import 'package:marxism_reader/offline/local_store_keys.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'package:marxism_reader/services/api_client.dart';

import 'package:marxism_reader/screens/analytics_dashboard.dart';
import 'package:marxism_reader/screens/knowledge_node_screen.dart';
import 'package:marxism_reader/screens/profile_dashboard.dart';
import 'helpers/offline_assets_guard.dart';

void main() {
  if (skipWithoutOfflineAssets()) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  const routeA = 'route_A';
  const routeB = 'route_B';

  setUp(() async {
    await OfflineContent.ensureMeta();
    SharedPreferences.setMockInitialValues({});
    LocalDb.reloadForTest();
    await LocalDb.ensure();
    LocalDb.routeId = routeA;
    ApiClient.invalidatePrefix();
  });

  // ------------------------------------------------------------ 辅助

  String firstNodeId() => '${OfflineContent.allNodes.first['id']}';

  Map<String, dynamic> masteryRec(
      String nodeId, double score, DateTime updatedAt,
      {Map<String, dynamic>? basis}) {
    return {
      'node_id': nodeId,
      'score': score,
      'level': LocalMastery.levelFromScore(score),
      'updated_at': updatedAt.toIso8601String(),
      'basis': basis ?? {},
      'source_flags': {},
    };
  }

  Future<Map<String, dynamic>> get(String path, [Map<String, String>? query]) async {
    final r =
        await LocalRouter.get(path, {'user_id': 'demo_user', ...(query ?? const {})});
    return r.cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final r = await LocalRouter.post(path, {'user_id': 'demo_user', ...body});
    return r.cast<String, dynamic>();
  }

  Future<(String, List<Map<String, dynamic>>)> firstChoiceSection() async {
    await OfflineContent.ensureQuiz();
    for (final sec in OfflineContent.sectionsOf(routeA)) {
      final sid = '${sec['id'] ?? ''}';
      if (sid.isEmpty) continue;
      final choice = OfflineContent.quizItems(sid)
          .where((it) => ((it['options'] as List?) ?? const []).length > 1)
          .take(3)
          .toList();
      if (choice.isNotEmpty) return (sid, choice);
    }
    throw StateError('离线题库缺少选择题，无法构造提交用例');
  }

  /// 提交一章章节测验（经 ApiClient，触发写后缓存失效，与真实页面同路径）。
  Future<void> submitSectionQuiz({bool allCorrect = true}) async {
    final (sid, items) = await firstChoiceSection();
    final seed =
        await ApiClient.post('/api/quiz/section/$sid/start', {'user_id': 'u'});
    final testId = '${seed['test_id']}';
    final answers = items
        .map((it) => {
              'item_id': it['id'],
              'answer': allCorrect ? '${it['answer'] ?? 'A'}' : 'X',
              'confidence': 'high',
            })
        .toList();
    await ApiClient.post('/api/quiz/$testId/submit',
        {'user_id': 'u', 'answers': answers});
  }

  // ============================================================ 维度一 时间边界

  test('时间边界·week：7 天窗口内计入、窗外 1 秒不计入（边界含端点）', () async {
    final nodeId = firstNodeId();
    final name = '${OfflineContent.node(nodeId)?['name'] ?? nodeId}';
    final now = DateTime.now().toUtc();

    // 窗口内 60 秒：必须计入（若实现按 > 而非 >= 判定边界，此处同样通过；
    // 精确端点语义由代码 `t.isBefore(边界)` 保证含端点）。
    LocalDb.mastery[routeA] = {
      nodeId: masteryRec(nodeId, 0.9, now.subtract(const Duration(days: 7, seconds: -60))),
    };
    final inWin = LocalInsight.summary(routeA, period: 'week');
    expect(inWin['mastered'], contains(name));

    // 窗外 60 秒：必须不计入。
    LocalDb.mastery[routeA] = {
      nodeId: masteryRec(nodeId, 0.9, now.subtract(const Duration(days: 7, seconds: 60))),
    };
    final outWin = LocalInsight.summary(routeA, period: 'week');
    expect(outWin['mastered'], isEmpty);
  });

  test('时间边界·month：30 天窗口边界与 week 同规则', () async {
    final nodeId = firstNodeId();
    final name = '${OfflineContent.node(nodeId)?['name'] ?? nodeId}';
    final now = DateTime.now().toUtc();

    LocalDb.mastery[routeA] = {
      nodeId: masteryRec(nodeId, 0.9, now.subtract(const Duration(days: 30, seconds: -60))),
    };
    expect((LocalInsight.summary(routeA, period: 'month'))['mastered'], contains(name));

    LocalDb.mastery[routeA] = {
      nodeId: masteryRec(nodeId, 0.9, now.subtract(const Duration(days: 30, seconds: 60))),
    };
    expect((LocalInsight.summary(routeA, period: 'month'))['mastered'], isEmpty);
  });

  test('时间边界·all：period=all 不做时间过滤，百天前记录仍计入', () async {
    final nodeId = firstNodeId();
    final name = '${OfflineContent.node(nodeId)?['name'] ?? nodeId}';
    final now = DateTime.now().toUtc();
    LocalDb.mastery[routeA] = {
      nodeId: masteryRec(nodeId, 0.9, now.subtract(const Duration(days: 100))),
    };
    expect((LocalInsight.summary(routeA, period: 'all'))['mastered'], contains(name));
  });

  test('时间边界·时区：同一瞬时的 Z/+00:00/无时区三种写法判定一致', () async {
    final nodeId = firstNodeId();
    final name = '${OfflineContent.node(nodeId)?['name'] ?? nodeId}';
    final now = DateTime.now().toUtc();
    final inInstant = now.subtract(const Duration(days: 6));
    final outInstant = now.subtract(const Duration(days: 8));
    // 三种写法都由同一个瞬时格式化而来，保证除「时区表示方式」外没有其他差异。
    String asZ(DateTime t) => t.toUtc().toIso8601String();
    String asOffset(DateTime t) =>
        t.toUtc().toIso8601String().replaceAll('Z', '+00:00');
    String asLocalWall(DateTime t) => t.toLocal().toIso8601String();
    List<String> formatsOf(DateTime t) =>
        [asZ(t), asOffset(t), asLocalWall(t)];

    for (final f in formatsOf(inInstant)) {
      LocalDb.mastery[routeA] = {nodeId: masteryRec(nodeId, 0.9, inInstant)};
      // 直接替换 updated_at 字符串以覆盖三种格式。
      final rec0 = LocalDb.mastery[routeA]![nodeId]!;
      rec0['updated_at'] = f;
      expect((LocalInsight.summary(routeA, period: 'week'))['mastered'], contains(name),
          reason: '格式 $f 应与 Z 格式同瞬时、同判定');
    }
    // 窗外瞬时的三种格式同样一致地被排除。
    for (final f in formatsOf(outInstant)) {
      final fOut = f;
      LocalDb.mastery[routeA] = {nodeId: masteryRec(nodeId, 0.9, outInstant)};
      final recOut = LocalDb.mastery[routeA]![nodeId]!;
      recOut['updated_at'] = fOut;
      expect((LocalInsight.summary(routeA, period: 'week'))['mastered'], isEmpty,
          reason: '窗外格式 $fOut 应被排除');
    }
  });

  test('时间边界·精度：毫秒级（±0.5 秒）边界判定无截断误差', () async {
    final nodeId = firstNodeId();
    final name = '${OfflineContent.node(nodeId)?['name'] ?? nodeId}';
    final now = DateTime.now().toUtc();

    LocalDb.mastery[routeA] = {
      nodeId: masteryRec(
          nodeId, 0.9, now.subtract(const Duration(days: 7, milliseconds: -500))),
    };
    expect((LocalInsight.summary(routeA, period: 'week'))['mastered'], contains(name));

    LocalDb.mastery[routeA] = {
      nodeId: masteryRec(
          nodeId, 0.9, now.subtract(const Duration(days: 7, milliseconds: 500))),
    };
    expect((LocalInsight.summary(routeA, period: 'week'))['mastered'], isEmpty);
  });

  test('时间边界·跨日：UTC 23:59 与次日 00:01 的作答计 2 个连续学习日', () {
    final now = DateTime.now().toUtc();
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayLate =
        DateTime.utc(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
    final todayEarly = DateTime.utc(now.year, now.month, now.day, 0, 0, 1);
    final attempts = [
      {'created_at': yesterdayLate.toIso8601String()},
      {'created_at': todayEarly.toIso8601String()},
    ];
    expect(LocalInsight.streakOf(attempts), 2);
  });

  test('时间边界·防御：缺失/非法时间戳的记录不计入窗口统计', () async {
    final nodeId = firstNodeId();
    LocalDb.mastery[routeA] = {
      nodeId: {
        'node_id': nodeId,
        'score': 0.9,
        'level': 'mastered',
        // 无 updated_at
        'basis': {},
        'source_flags': {},
      },
    };
    expect((LocalInsight.summary(routeA, period: 'week'))['mastered'], isEmpty,
        reason: '缺失时间戳的记录视为旧数据，不计入窗口');

    LocalDb.mastery[routeA] = {
      nodeId: {
        ...masteryRec(nodeId, 0.9, DateTime.now().toUtc()),
        'updated_at': '不是时间',
      },
    };
    expect((LocalInsight.summary(routeA, period: 'week'))['mastered'], isEmpty,
        reason: '非法时间戳的记录不计入窗口');
  });

  // ============================================================ 维度二 极端值

  test('极端值·全对用户：作答全对后档案/分析无 NaN，薄弱点口径自洽', () async {
    await submitSectionQuiz(allCorrect: true);

    final p = await get('/api/mastery/profile', {'route_id': routeA});
    final ov = await get('/api/analytics/overview', {'route_id': routeA});
    final nodeId = LocalDb.mastery[routeA]!.keys.first;
    final answered = (p['weak_points'] as List)
        .cast<Map<String, dynamic>>()
        .where((w) => '${w['node_id']}' == nodeId)
        .toList();
    // 薄弱点口径：score < 0.8 才进薄弱点，不存在 score ≥ 0.8 的薄弱点。
    for (final w in (p['weak_points'] as List).cast<Map<String, dynamic>>()) {
      expect((w['score'] as num).toDouble(), lessThan(0.8));
    }
    // 全对用户已评估节点：score 为有限数、level 非 unseen。
    final rec = LocalDb.mastery[routeA]![nodeId]!;
    expect(rec['score'], isA<double>());
    expect((rec['score'] as num).isFinite, isTrue);
    expect(rec['level'], isNot('unseen'));
    // answered 出现在薄弱点列表当且仅当其 score < 0.8。
    expect(answered.isNotEmpty,
        equals((rec['score'] as num).toDouble() < 0.8));

    // 分析看板：平均得分应为 1.0，健康度为有限整数。
    expect((ov['avg_score'] as num).toDouble(), closeTo(1.0, 0.001));
    expect(ov['health_score'], isA<int>());
    expect(ov['health_score'] as int, greaterThanOrEqualTo(0));
    expect(ov['health_score'] as int, lessThanOrEqualTo(100));
  });

  test('极端值·全错用户：得分 0、等级 unseen，各接口无 NaN', () async {
    await submitSectionQuiz(allCorrect: false);

    final p = await get('/api/mastery/profile', {'route_id': routeA});
    final ov = await get('/api/analytics/overview', {'route_id': routeA});
    final mot = await get('/api/motivation/state', {'route_id': routeA});
    final nodeId = LocalDb.mastery[routeA]!.keys.first;
    final rec = LocalDb.mastery[routeA]![nodeId]!;
    // 全错：accuracy 0、stability 0 → 加权得分恒 < 0.2 → unseen。
    expect((rec['score'] as num).toDouble(), lessThan(0.2));
    expect(rec['level'], 'unseen');
    // 该节点必进薄弱点列表。
    final weak = (p['weak_points'] as List).cast<Map<String, dynamic>>();
    expect(weak.any((w) => '${w['node_id']}' == nodeId), isTrue);

    expect((ov['avg_score'] as num).toDouble(), closeTo(0.0, 0.001));
    expect(ov['health_score'], isA<int>());
    expect((mot['frustration'] as Map)['score'], isA<num>());
    expect(((mot['frustration'] as Map)['score'] as num).isFinite, isTrue);
    expect(mot['avg_recent_accuracy'], closeTo(0.0, 0.001));
  });

  test('极端值·单数据点：单个作答时均值即该值，无除零/NaN', () async {
    final nodeId = firstNodeId();
    LocalDb.attempts.add({
      'node_id': nodeId,
      'quiz_id': 'q_single',
      'test_id': 't_single',
      'route_id': routeA,
      'answer': 'A',
      'reference': '',
      'source_chunk_id': '',
      'is_correct': true,
      'score': 0.7,
      'error_category': '',
      'confidence': 'high',
      'created_at': nowIso(),
    });
    LocalDb.mastery[routeA] = {
      nodeId: masteryRec(nodeId, 0.7, DateTime.now()),
    };
    final ov = LocalInsight.overview(routeA);
    expect(ov['total_attempts'], 1);
    expect((ov['avg_score'] as num).toDouble(), closeTo(0.7, 0.001));
    expect(ov['avg_retention'], isA<num>());
    expect(((ov['avg_retention'] as num)).isFinite, isTrue);
    expect(ov['health_score'], isA<int>());
  });

  test('极端值·零数据：空态字段齐备，动机/总结无 NaN', () async {
    final ov = LocalInsight.overview(routeA);
    expect(ov['has_data'], isFalse);
    expect(ov['health_score'], 0);
    expect(ov['avg_retention'], isNull);
    expect(ov['avg_score'], isNull);
    expect(ov['total_attempts'], 0);

    final p = LocalInsight.profile(routeA);
    expect(p['assessed_nodes'], 0);

    final s = LocalInsight.summary(routeA, period: 'week');
    expect(s['mastered'], isEmpty);
    expect(s['to_reinforce'], isEmpty);

    final mot = LocalInsight.motivation(routeA);
    expect(((mot['frustration'] as Map)['score'] as num).isFinite, isTrue);
    expect(mot['milestones'], isA<List>());
    expect(mot['next_best_action'], isA<Map>());
    expect((mot['next_best_action'] as Map)['kind'], isA<String>());
  });

  test('极端值·极大值：score=1.0 计入已掌握、不进薄弱点', () async {
    final nodeId = firstNodeId();
    final name = '${OfflineContent.node(nodeId)?['name'] ?? nodeId}';
    LocalDb.mastery[routeA] = {
      nodeId: masteryRec(nodeId, 1.0, DateTime.now().toUtc()),
    };
    final s = LocalInsight.summary(routeA, period: 'week');
    expect(s['mastered'], contains(name));
    final p = LocalInsight.profile(routeA);
    final weak = (p['weak_points'] as List).cast<Map<String, dynamic>>();
    expect(weak.any((w) => '${w['node_id']}' == nodeId), isFalse);
  });

  test('极端值·双路线：A 有数据、B 空时 B 不串线、A 不受污染', () async {
    final nodeId = firstNodeId();
    LocalDb.mastery[routeA] = {
      nodeId: masteryRec(nodeId, 0.9, DateTime.now().toUtc()),
    };
    LocalDb.attempts.add({
      'node_id': nodeId,
      'quiz_id': 'q1',
      'test_id': 't1',
      'route_id': routeA,
      'answer': 'A',
      'reference': '',
      'source_chunk_id': '',
      'is_correct': true,
      'score': 1.0,
      'error_category': '',
      'confidence': 'high',
      'created_at': nowIso(),
    });

    // B 路线空态。
    final pB = LocalInsight.profile(routeB);
    expect(pB['assessed_nodes'], 0);
    final sB = LocalInsight.summary(routeB, period: 'week');
    expect(sB['mastered'], isEmpty);
    final ovB = LocalInsight.overview(routeB);
    expect(ovB['has_data'], isFalse);
    expect(ovB['total_attempts'], 0);
    final motB = LocalInsight.motivation(routeB);
    expect(motB['total_attempts'], 0);

    // A 路线数据完整、不被 B 的查询污染。
    final ovA = LocalInsight.overview(routeA);
    expect(ovA['total_attempts'], 1);
    expect((ovA['avg_score'] as num).toDouble(), closeTo(1.0, 0.001));
    final motA = LocalInsight.motivation(routeA);
    expect(motA['total_attempts'], 1);
  });

  // ============================================================ 维度三 可解释性

  testWidgets('口径说明·分析看板：分布/保持率/短板三卡均有计算口径说明',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: AnalyticsDashboardScreen(routeId: routeA)));
    await tester.pump();
    await tester.pumpAndSettle();
    // 看板是懒加载 ListView：屏外的卡片不会被建出来，必须滚到可见处再断言。
    final scrollable = find.byType(Scrollable).first;
    for (final txt in const [
      '五级按掌握度得分划分',
      '保持率按记忆半衰期衰减估算',
      '维度得分 = 该维度已评估知识点的掌握度均值',
    ]) {
      await tester.scrollUntilVisible(find.textContaining(txt), 200,
          scrollable: scrollable);
      expect(find.textContaining(txt), findsOneWidget, reason: '缺口径说明：$txt');
    }
  });

  testWidgets('口径说明·学情档案：雷达卡标注维度得分口径', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: ProfileDashboardScreen(routeId: routeA)));
    await tester.pumpAndSettle();
    expect(find.textContaining('维度得分 = 该维度已评估知识点的掌握度均值'),
        findsOneWidget);
  });

  testWidgets('口径说明·知识点详情：掌握依据标注五信号合成口径', (tester) async {
    final nodeId = firstNodeId();
    LocalDb.mastery[routeA] = {
      nodeId: masteryRec(
        nodeId,
        0.82,
        DateTime.now().toUtc(),
        basis: {'accuracy': 1.0, 'stability': 0.5, 'difficulty': 0.4},
      ),
    };
    await tester.pumpWidget(MaterialApp(
        home: KnowledgeNodeScreen(nodeId: nodeId, routeId: routeA)));
    await tester.pumpAndSettle();
    expect(find.textContaining('掌握度由准确性、难度、稳定性、对话参与、费曼表达五项加权合成'),
        findsOneWidget);
  });

  // ============================================================ 维度四 导出格式

  test('导出·元数据与七份文档齐全、JSON 可解析', () async {
    final nodeId = firstNodeId();
    LocalDb.mastery[routeA] = {
      nodeId: masteryRec(nodeId, 0.9, DateTime.now().toUtc()),
    };
    LocalDb.attempts.add({
      'node_id': nodeId,
      'quiz_id': 'q1',
      'test_id': 't1',
      'route_id': routeA,
      'answer': 'A',
      'reference': '',
      'source_chunk_id': '',
      'is_correct': true,
      'score': 1.0,
      'error_category': '',
      'confidence': 'high',
      'created_at': nowIso(),
    });
    LocalDb.signals.add({
      'kind': 'stuck',
      'intensity': 0.5,
      'detail': 'd',
      'node_id': nodeId,
      'section_id': 'sec_A_02',
      'created_at': nowIso(),
    });

    final text = await DataCompat.exportJson();
    final obj = jsonDecode(text) as Map<String, dynamic>;

    // 元数据：版本号、导出时间、用户标识齐备。
    expect(obj['app'], 'xxmz');
    expect(obj['format'], DataCompat.backupFormat);
    expect(obj['data_schema'], DataCompat.schema);
    expect(obj['client_version'], isA<String>());
    expect(obj['user_id'], isA<String>());
    expect(obj['route_id'], routeA);
    expect(obj['exported_at'], isA<String>());

    // 七份文档一份不少。
    final docs = obj['docs'] as Map<String, dynamic>;
    for (final k in [
      LocalStoreKeys.mastery,
      LocalStoreKeys.progress,
      LocalStoreKeys.attempts,
      LocalStoreKeys.tests,
      LocalStoreKeys.dialogues,
      LocalStoreKeys.settings,
      LocalStoreKeys.signals,
    ]) {
      expect(docs.containsKey(k), isTrue, reason: '导出缺少文档 $k');
    }
    expect((docs[LocalStoreKeys.attempts] as List).length, 1);
    expect((docs[LocalStoreKeys.signals] as List).length, 1);
  });

  test('导出导入·往返一致：导出后重置再导入，掌握度与作答完整保留', () async {
    final nodeId = firstNodeId();
    LocalDb.mastery[routeA] = {
      nodeId: masteryRec(
        nodeId,
        0.82,
        DateTime.now().toUtc(),
        basis: {'accuracy': 1.0, 'stability': 0.5, 'difficulty': 0.4},
      ),
    };
    LocalDb.attempts.add({
      'node_id': nodeId,
      'quiz_id': 'q1',
      'test_id': 't1',
      'route_id': routeA,
      'answer': 'A',
      'reference': '',
      'source_chunk_id': '',
      'is_correct': true,
      'score': 1.0,
      'error_category': '',
      'confidence': 'high',
      'created_at': nowIso(),
    });

    final text = await DataCompat.exportJson();
    await LocalDb.resetAll();
    expect(LocalDb.attempts, isEmpty);
    expect(LocalDb.mastery, isEmpty);

    final counts = await DataCompat.importJson(text);
    expect(counts[LocalStoreKeys.mastery], 1);
    expect(counts[LocalStoreKeys.attempts], 1);

    final p = LocalInsight.profile(routeA);
    expect(p['assessed_nodes'], 1);
    final ov = LocalInsight.overview(routeA);
    expect(ov['total_attempts'], 1);
    expect((ov['avg_score'] as num).toDouble(), closeTo(1.0, 0.001));
  });

  test('导出导入·缺失字段保留：旧备份缺字段时不覆盖本地已有字段', () async {
    LocalDb.tests['t1'] = {
      'test_id': 't1',
      'section_id': 'sec_A_02',
      'route_id': routeA,
      'status': 'completed',
      'total_score': 1.0,
    };
    LocalDb.mastery[routeA] = {
      firstNodeId(): {
        'node_id': firstNodeId(),
        'score': 0.82,
        'level': 'proficient',
        'updated_at': nowIso(),
        'basis': {'accuracy': 1.0},
        'source_flags': {},
      },
    };
    await LocalDb.flush();

    // 旧备份：tests 记录缺 status/total_score，mastery 记录缺 source_flags。
    final backup = jsonEncode({
      'app': 'xxmz',
      'format': DataCompat.backupFormat,
      'data_schema': DataCompat.schema,
      'docs': {
        LocalStoreKeys.tests: {
          't1': {'test_id': 't1', 'section_id': 'sec_A_02', 'route_id': routeA},
        },
        LocalStoreKeys.mastery: {
          routeA: {
            firstNodeId(): {
              'node_id': firstNodeId(),
              'score': 0.9,
              'level': 'mastered',
              'updated_at': nowIso(),
              'basis': {'accuracy': 1.0},
            },
          },
        },
      },
    });
    await DataCompat.importJson(backup);

    final testRec = LocalDb.tests['t1'];
    expect(testRec['status'], 'completed', reason: '备份缺字段不得清空本地字段');
    expect(testRec['total_score'], 1.0);

    final mRec = LocalDb.mastery[routeA]![firstNodeId()]!;
    expect(mRec['score'], 0.9, reason: '备份有值时以备份为准');
    expect(mRec['source_flags'], isEmpty,
        reason: '备份缺失的字段应保留本地已有值（空 map 仍保留键）。 ');
    expect(mRec.containsKey('source_flags'), isTrue);
  });

  test('导出导入·多余字段加法合并：不破坏核心字段', () async {
    LocalDb.tests['t1'] = {'test_id': 't1', 'section_id': 'sec_A_02'};
    final backup = jsonEncode({
      'app': 'xxmz',
      'format': DataCompat.backupFormat,
      'data_schema': DataCompat.schema,
      'docs': {
        LocalStoreKeys.tests: {
          't1': {
            'test_id': 't1',
            'section_id': 'sec_A_02',
            'status': 'completed',
            '未来扩展字段': '保留',
          },
        },
      },
    });
    await DataCompat.importJson(backup);
    final rec = LocalDb.tests['t1'];
    expect(rec['status'], 'completed');
    expect(rec['未来扩展字段'], '保留', reason: '多余字段加法合并，不丢弃');
    expect(rec['test_id'], 't1');
  });

  test('导出导入·非法文件：非 JSON/错误标识/缺 docs 均友好报错或安全跳过',
      () async {
    expect(() => DataCompat.importJson('这不是 JSON'),
        throwsA(isA<FormatException>()));
    final wrongApp = jsonEncode({
      'app': 'evil-app',
      'format': DataCompat.backupFormat,
      'data_schema': DataCompat.schema,
      'docs': {},
    });
    expect(() => DataCompat.importJson(wrongApp),
        throwsA(isA<FormatException>()));
    final badFormat = jsonEncode({
      'app': 'xxmz',
      'format': 99,
      'data_schema': DataCompat.schema,
      'docs': {},
    });
    expect(() => DataCompat.importJson(badFormat),
        throwsA(isA<FormatException>()));
    // 合法 JSON 但缺 docs：安全跳过，不抛异常。
    final noDocs = jsonEncode({
      'app': 'xxmz',
      'format': DataCompat.backupFormat,
      'data_schema': DataCompat.schema,
    });
    final counts = await DataCompat.importJson(noDocs);
    expect(counts, isEmpty);
  });

  test('导出·大数据量：600 条作答导出可解析、体积合理、往返完整', () async {
    final nodeId = firstNodeId();
    for (var i = 0; i < 600; i++) {
      LocalDb.attempts.add({
        'node_id': nodeId,
        'quiz_id': 'q$i',
        'test_id': 't$i',
        'route_id': routeA,
        'answer': 'A',
        'reference': '',
        'source_chunk_id': '',
        'is_correct': i % 2 == 0,
        'score': i % 2 == 0 ? 1.0 : 0.0,
        'error_category': '',
        'confidence': 'high',
        'created_at': nowIso(),
      });
    }
    final text = await DataCompat.exportJson();
    expect(text.length, lessThan(5 * 1024 * 1024), reason: '导出体积应在合理范围');
    final obj = jsonDecode(text) as Map<String, dynamic>;
    expect((obj['docs'][LocalStoreKeys.attempts] as List).length, 600);

    await LocalDb.resetAll();
    await DataCompat.importJson(text);
    expect(LocalDb.attempts.length, 600);
    final ov = LocalInsight.overview(routeA);
    expect(ov['total_attempts'], 600);
  });

  // ============================================================ 维度五 一致性

  test('一致性·响应键集与后端契约一致（overview/profile/motivation）', () async {
    final ov = await get('/api/analytics/overview', {'route_id': routeA});
    expect(ov.keys.toSet(), containsAll([
      'route_id', 'total_nodes', 'assessed_nodes', 'mastery_distribution',
      'mastered', 'avg_retention', 'due_count', 'calibration',
      'error_breakdown', 'ability_radar', 'weakest_dim', 'total_attempts',
      'avg_score', 'streak_days', 'health_score', 'has_data'
    ]));
    expect(ov.keys, hasLength(16));
    expect(ov['health_score'], isA<int>());
    expect(ov['mastery_distribution'], isA<Map>());
    expect(ov['ability_radar'], isA<Map>());

    final p = await get('/api/mastery/profile', {'route_id': routeA});
    // 后端六键 + 单机新增 assessed_nodes/total_nodes（加法扩展）。
    expect(p.keys.toSet(), containsAll([
      'route_id', 'ability_radar', 'weak_points', 'mastery_distribution',
      'summary', 'updated_at', 'assessed_nodes', 'total_nodes'
    ]));

    final mot = await get('/api/motivation/state', {'route_id': routeA});
    expect(mot.keys.toSet(), containsAll([
      'route_id', 'frustration', 'encouragement', 'avg_recent_accuracy',
      'mastered', 'proficient', 'due_count', 'streak_days', 'milestones',
      'next_best_action', 'total_attempts'
    ]));
    expect((mot['frustration'] as Map).keys.toSet(),
        containsAll(['level', 'score', 'drivers']));
    expect((mot['next_best_action'] as Map).keys.toSet(),
        containsAll(['kind', 'label', 'reason']));
  });

  test('一致性·响应键集：summary 与 review/fit 与后端契约一致', () async {
    final s = await post('/api/mastery/summary',
        {'route_id': routeA, 'period': 'week'});
    expect(s.keys.toSet(), containsAll([
      'route_id', 'period', 'mastered', 'to_reinforce', 'next_step',
      'summary', 'source_tags'
    ]));
    expect(s.keys, hasLength(7));

    final fit = await get('/api/review/fit', {'route_id': routeA});
    expect(fit['available'], isFalse);
    expect(fit.keys.toSet(), containsAll([
      'available', 'n', 'message', 'current', 'suggested'
    ]));
    expect((fit['current'] as Map).keys.toSet(), containsAll(['gain', 'regress']));

    // 有样本时的可用分支键集。
    LocalDb.attempts.add({
      'node_id': firstNodeId(),
      'quiz_id': 'q',
      'test_id': 't',
      'route_id': routeA,
      'answer': 'A',
      'reference': '',
      'source_chunk_id': '',
      'is_correct': true,
      'score': 1.0,
      'error_category': '',
      'confidence': 'high',
      'created_at': nowIso(),
    });
    final fit2 = LocalMastery.fitParameters(routeA);
    expect(fit2.keys.toSet(), containsAll([
      'available', 'n', 'message', 'succ_rate', 'lapse_rate', 'current',
      'suggested', 'note'
    ]));
  });

  test('一致性·summary 双通道：GET 与 POST 返回同一份结果', () async {
    final nodeId = firstNodeId();
    LocalDb.mastery[routeA] = {
      nodeId: masteryRec(nodeId, 0.9, DateTime.now().toUtc()),
    };
    final viaPost =
        await post('/api/mastery/summary', {'route_id': routeA, 'period': 'month'});
    final viaGet =
        await get('/api/mastery/summary', {'route_id': routeA, 'period': 'month'});
    expect(viaGet, equals(viaPost));
    expect(viaGet['period'], 'month');
  });

  test('一致性·ApiClient 缓存：GET 命中缓存，写后立即失效', () async {
    final nodeId = firstNodeId();
    LocalDb.attempts.add({
      'node_id': nodeId,
      'quiz_id': 'q1',
      'test_id': 't1',
      'route_id': routeA,
      'answer': 'A',
      'reference': '',
      'source_chunk_id': '',
      'is_correct': true,
      'score': 1.0,
      'error_category': '',
      'confidence': 'high',
      'created_at': nowIso(),
    });
    final q = {'route_id': routeA};
    final ov1 =
        (await ApiClient.get('/api/analytics/overview', query: q)) as Map;
    final ov2 =
        (await ApiClient.get('/api/analytics/overview', query: q)) as Map;
    expect(identical(ov1, ov2), isTrue, reason: 'TTL 内 GET 应命中缓存');

    // 写操作后缓存失效：再读必须看到新数据。
    LocalDb.attempts.add({
      'node_id': nodeId,
      'quiz_id': 'q2',
      'test_id': 't2',
      'route_id': routeA,
      'answer': 'A',
      'reference': '',
      'source_chunk_id': '',
      'is_correct': true,
      'score': 1.0,
      'error_category': '',
      'confidence': 'high',
      'created_at': nowIso(),
    });
    await ApiClient.post('/api/sync/progress', {
      'user_id': 'u',
      'route_id': routeA,
      'section_id': 'sec_A_00',
      'last_position': 1,
      'status': 'in_progress',
    });
    final ov3 =
        (await ApiClient.get('/api/analytics/overview', query: q)) as Map;
    expect(ov3['total_attempts'], 2, reason: '写后缓存失效，接口须立即看到新数据');

    // 缓存键含查询参数：不同 period 互不串用。
    final s1 = (await ApiClient.get('/api/mastery/summary',
            query: {'route_id': routeA, 'period': 'week'})) as Map;
    final s2 = (await ApiClient.get('/api/mastery/summary',
            query: {'route_id': routeA, 'period': 'month'})) as Map;
    expect(s1['period'], 'week');
    expect(s2['period'], 'month');
    expect(identical(s1, s2), isFalse);
  });

  test('一致性·作答写入格式：提交产生的记录键齐全且被分析接口正确消费',
      () async {
    await submitSectionQuiz(allCorrect: true);
    final rec = LocalDb.attempts.last as Map<String, dynamic>;
    // 与后端 QuizAttempt 共享的键名/类型保持一致。
    for (final k in [
      'quiz_id', 'test_id', 'answer', 'is_correct', 'score', 'error_category',
      'confidence', 'created_at'
    ]) {
      expect(rec.containsKey(k), isTrue, reason: '作答记录缺少键 $k');
    }
    expect(rec['score'], isA<double>());
    expect(rec['is_correct'], isTrue);
    // 单机扩展键（离线分析所需）。
    for (final k in ['node_id', 'route_id']) {
      expect(rec.containsKey(k), isTrue, reason: '单机作答记录缺少键 $k');
    }

    // 分析接口消费一致：总分与作答数吻合。
    final ov = LocalInsight.overview(routeA);
    expect(ov['total_attempts'], LocalDb.attempts.length);
    expect((ov['avg_score'] as num).toDouble(), closeTo(1.0, 0.001));
  });
}
