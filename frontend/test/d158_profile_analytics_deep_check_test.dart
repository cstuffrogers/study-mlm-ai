// D158 学情档案 / 学习分析数据深度检查测试
//
// 五个维度全量验证：
//  1. 边界情况：零作答、单题、全错、全对、分数临界 0.85/0.45/0.0、长时间未复习、跨路线
//  2. 多路线数据隔离：overview/profile/summary/calibration/motivation/wrongBook、
//     attemptsForRoute 四级归属、ApiClient 缓存键含 route_id
//  3. 图表渲染与数据一致性：雷达五维、掌握度分布计数、健康度四子项权重与缺数据归一、
//     错因分布、错题本去重、档案页雷达补 0 渲染契约
//  4. FSRS 复习参数合理性：间隔钳制、半衰期、保持率、到期判定、review 回写、
//     fitParameters 与后端同口径
//  5. 数据持久化与一致性：flushKey 只写单键（无空穿透）、写入→重启读回、
//     signals 与 attempts 冗余一致性
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_insight.dart';
import 'package:marxism_reader/offline/local_mastery.dart';
import 'package:marxism_reader/offline/local_router.dart';
import 'package:marxism_reader/offline/local_store_keys.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'package:marxism_reader/services/api_client.dart';
import 'package:marxism_reader/screens/profile_dashboard.dart';
import 'package:marxism_reader/widgets/radar_chart.dart';

import 'helpers/offline_assets_guard.dart';

void main() {
  if (skipWithoutOfflineAssets()) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  const routeA = 'route_A';
  const routeB = 'route_B';
  const routeC = 'route_C';

  // 路线 A / B 的真实节点（meta.json 产物，sectionsOf(route) 可解析）。
  const nodeA1 = 'kn_practice'; // 认识论
  const nodeA2 = 'kn_object_activity';
  const nodeB1 = 'kn_b00_practice';

  setUp(() async {
    await OfflineContent.ensureMeta();
    await LocalDb.resetAll();
    LocalDb.routeId = routeA;
    ApiClient.invalidatePrefix(); // 每个用例独立缓存，互不污染
  });

  // ------------------------------------------------------------ 辅助

  Future<Map<String, dynamic>> seed(
    String routeId,
    String nodeId, {
    double? accuracy,
    double? stability,
    double? feynman,
    bool scheduleReview = false,
  }) async {
    final rec = await LocalMastery.upsert(
      routeId,
      nodeId,
      {
        'accuracy': accuracy,
        'stability': stability,
        'feynman': feynman,
        'test_count': 1,
        'review_count': 0,
      },
      'quiz',
      scheduleReview: scheduleReview,
    );
    return rec;
  }

  void addAttempt({
    String routeId = routeA,
    String nodeId = '',
    String quizId = '',
    String testId = '',
    bool isCorrect = false,
    double score = 0.0,
    String errorCategory = '',
    String confidence = 'mid',
    String createdAt = '',
  }) {
    LocalDb.attempts.add({
      'node_id': nodeId,
      'quiz_id': quizId,
      'test_id': testId,
      'route_id': routeId,
      'answer': 'A',
      'is_correct': isCorrect,
      'score': score,
      'error_category': errorCategory,
      'confidence': confidence,
      'created_at': createdAt.isEmpty ? nowIso() : createdAt,
    });
  }

  // ============================================================ 维度一 边界情况

  test('边界·零作答：档案/分析空态、分布全未接触、健康度 0、无作答统计', () {
    final profile = LocalInsight.profile(routeA);
    expect(profile['ability_radar'], isEmpty, reason: '无评估节点不进雷达');
    expect(profile['assessed_nodes'], 0);
    expect(profile['weak_points'].length, OfflineContent.allNodes.length,
        reason: '未评估节点也算薄弱点（后端同口径）');

    final ov = LocalInsight.overview(routeA);
    expect(ov['has_data'], isFalse);
    expect(ov['health_score'], 0);
    expect(ov['mastery_distribution']['unseen'],
        OfflineContent.allNodes.length);
    expect(ov['total_attempts'], 0);
    expect(ov['avg_score'], isNull);
    expect(ov['error_breakdown'], isEmpty);
    // 雷达恒定五维，没测过的维度给 0.0，保证图能画出来。
    final radar = ov['ability_radar'] as Map;
    expect(radar.length, 5);
    expect(radar.values.every((v) => v == 0.0), isTrue);
    expect(ov['weakest_dim']['dim'], isNull);

    final summary = LocalInsight.summary(routeA);
    expect(summary['mastered'], isEmpty);
    // summary 只统计已评估节点（后端同口径：未评估节点不进总结，仅档案薄弱点全量）。
    expect(summary['to_reinforce'], isEmpty);

    final cal = LocalInsight.calibration(routeA);
    expect(cal['n'], 0);
    expect(cal['verdict'], 'unknown');

    final mot = LocalInsight.motivation(routeA);
    expect(mot['total_attempts'], 0);
    expect(mot['avg_recent_accuracy'], isNull);
    expect(mot['mastered'], 0);
    expect(mot['streak_days'], 0);

    expect(LocalInsight.wrongBook(routeA)['items'], isEmpty);
  });

  test('边界·单题：雷达只含已评估维度、分析页五维补 0、分布/健康度正确', () async {
    await seed(routeA, nodeA1, accuracy: 1.0, stability: 1.0, feynman: 0.9);

    final profile = LocalInsight.profile(routeA);
    final pRadar = profile['ability_radar'] as Map;
    expect(pRadar.length, 1, reason: '档案页只列已评估维度');
    final dim = OfflineContent.node(nodeA1)!['ability_dim'] as String;
    // 0.6*1 + 0.1*1 + 0.05*0.9 = 0.745，权重和 0.75 → 0.9933
    expect(pRadar[dim], closeTo(0.9933, 4));

    final ov = LocalInsight.overview(routeA);
    final oRadar = ov['ability_radar'] as Map;
    expect(oRadar.length, 5);
    expect(oRadar[dim], closeTo(0.9933, 4));
    expect(oRadar.values.whereType<double>().where((v) => v != 0.0).length, 1);
    expect(ov['mastery_distribution']['mastered'], 1);
    expect(ov['assessed_nodes'], 1);
    expect(ov['total_nodes'], OfflineContent.allNodes.length);
    // 掌握面 masteryRatio = 1/N；已评估节点的保持率锚定评估时间（updated_at）→
    // 未复习即满值 1.0，保留维度在权重内。权重 40+25 归一。
    final r1 = 1.0 / OfflineContent.allNodes.length;
    expect(ov['health_score'],
        (100 * (0.40 * r1 + 0.25 * 1.0) / 0.65).round());
    expect(ov['has_data'], isTrue);
  });

  test('边界·全错：得分 0 记 unseen、错因计数、健康度为 0 但不假报有数据之外', () async {
    await seed(routeA, nodeA1, accuracy: 0.0, stability: 0.1);
    addAttempt(
      nodeId: nodeA1,
      quizId: 'q_wrong_1',
      isCorrect: false,
      score: 0.0,
      errorCategory: 'logic_error',
      confidence: '',
    );
    addAttempt(
      nodeId: nodeA1,
      quizId: 'q_wrong_2',
      isCorrect: false,
      score: 0.0,
      errorCategory: 'logic_error',
      confidence: '',
    );

    final ov = LocalInsight.overview(routeA);
    expect(ov['avg_score'], 0.0);
    expect(ov['error_breakdown'], {'logic_error': 2});
    expect(ov['mastery_distribution']['unseen'],
        OfflineContent.allNodes.length,
        reason: '105 个未评估 + 1 个已评估但 score 0 均为 unseen');
    expect(ov['total_attempts'], 2);
    expect(ov['has_data'], isTrue, reason: '有作答记录即有数据');
    // 掌握面 0、平均分 0；作答无把握度 → 校准缺数据剔除。保持率锚定评估时间
    // （未复习即满值 1.0）→ 健康度 = 100*(0.25*1.0)/(0.40+0.25+0.20)。
    expect(ov['health_score'], (100 * 0.25 / 0.85).round());

    final wb = LocalInsight.wrongBook(routeA) as Map;
    expect(wb['count'], 2);
    expect(wb['items'].length, 2);
  });

  test('边界·全对：仅客观题不达「贯通」（feynman 门槛），补自评后贯通', () async {
    // 第一次：无 feynman 自评 → score 1.0 但等级降 proficient。
    await seed(routeA, nodeA1, accuracy: 1.0, stability: 1.0);
    final rec1 = LocalMastery.masteryMap(routeA)[nodeA1] as Map;
    expect(rec1['score'], closeTo(1.0, 4), reason: '0.7/0.7=1.0');
    expect(rec1['level'], 'proficient');
    // 总结的「已掌握」是宽口径 score>=0.8（与后端 generate_summary 同），
    // score 1.0 即入选，不与 levelFromScore 的严口径混用。
    expect(LocalInsight.summary(routeA)['mastered'],
        contains(OfflineContent.node(nodeA1)!['name'] as String));

    // 第二次：补自评 0.9 → score 0.9933、level mastered。
    await seed(routeA, nodeA1, accuracy: 1.0, stability: 1.0, feynman: 0.9);
    final rec2 = LocalMastery.masteryMap(routeA)[nodeA1] as Map;
    expect(rec2['score'], closeTo(0.9933, 4));
    expect(rec2['level'], 'mastered');
    final summary = LocalInsight.summary(routeA);
    expect(summary['mastered'], contains(
        OfflineContent.node(nodeA1)!['name'] as String));
  });

  test('边界·分数临界：0.2/0.45/0.7/0.85 四档阈值逐点正确', () {
    expect(LocalMastery.levelFromScore(0.1999), 'unseen');
    expect(LocalMastery.levelFromScore(0.2), 'beginner');
    expect(LocalMastery.levelFromScore(0.4499), 'beginner');
    expect(LocalMastery.levelFromScore(0.45), 'familiar');
    expect(LocalMastery.levelFromScore(0.6999), 'familiar');
    expect(LocalMastery.levelFromScore(0.7), 'proficient');
    expect(LocalMastery.levelFromScore(0.8499), 'proficient');
    expect(LocalMastery.levelFromScore(0.85, {'feynman': 0.9}), 'mastered');
    expect(LocalMastery.levelFromScore(0.85, {'feynman': 0.79}), 'proficient',
        reason: 'feynman 未达 0.8 降档');
    expect(LocalMastery.levelFromScore(0.85), 'proficient',
        reason: '无自评不判 mastered');

    // summary 的已掌握是宽口径 score>=0.8（与后端 generate_summary 同口径），
    // 与 levelFromScore 的 0.85 严口径并存、互不混用。
  });

  test('边界·分数临界：summary 已掌握门槛 0.8（后端口径）、掌握度分布 0.85 严口径', () async {
    // (0.6*0.85 + 0.05*0.9)/0.65 = 0.8538 → levelFromScore mastered（0.85 + feynman 严口径）
    await seed(routeA, nodeA1, accuracy: 0.85, feynman: 0.9);
    // (0.6*0.84 + 0.05*0.9)/0.65 = 0.8446 → proficient（严口径），
    // 但 summary 宽口径 0.8 判已掌握。
    await seed(routeA, nodeA2, accuracy: 0.84, feynman: 0.9);

    final ov = LocalInsight.overview(routeA);
    expect(ov['mastery_distribution']['mastered'], 1);
    expect(ov['mastery_distribution']['proficient'], 1);

    final summary = LocalInsight.summary(routeA);
    expect(summary['mastered'].length, 2);
    expect(summary['mastered'].contains(
        OfflineContent.node(nodeA1)!['name'] as String), isTrue);
    expect(summary['mastered'].contains(
        OfflineContent.node(nodeA2)!['name'] as String), isTrue);
  });

  test('边界·长时间未复习：到期进队列、保持率按半衰期衰减、健康度同步', () async {
    await seed(routeA, nodeA1, accuracy: 0.9, feynman: 0.9,
        scheduleReview: true);
    // 把复习时间拨回 60 天前：stability=1 → 半衰期 15 天 → 保持率 0.5^4。
    final now = DateTime.now().toUtc();
    final past = now.subtract(const Duration(days: 60));
    final rec = LocalDb.masteryFor(routeA).values
        .firstWhere((m) => m['node_id'] == nodeA1) as Map;
    rec['last_reviewed_at'] = past.toIso8601String();
    rec['next_review_at'] = past.toIso8601String();

    final due = LocalMastery.dueReviews(routeA);
    expect(due.any((d) => d['node_id'] == nodeA1), isTrue);
    final item = due.firstWhere((d) => d['node_id'] == nodeA1);
    expect(item['retention'], closeTo(0.0625, 4), reason: '0.5^(60/15)');

    final status = LocalMastery.reviewStatus(routeA);
    expect(status['due_count'], 1);
    expect(status['items'].first['retention'], closeTo(0.0625, 4));

    final ov = LocalInsight.overview(routeA);
    expect(ov['avg_retention'], closeTo(0.0625, 4));
    expect(ov['due_count'], 1);
    // 保持率 0.0625 → retentionPart 0；保留掌握面维度（masteryRatio = 1/N），
    // 权重 40+25 归一。
    expect(ov['health_score'],
        (100 * (0.40 * (1.0 / OfflineContent.allNodes.length) + 0.25 * 0.0)
            / 0.65)
            .round());

    // 时间为负（数据异常/时钟回拨）保持率钳为 1，不出现 >1 的假值。
    expect(LocalMastery.retention(-1.0, 0.5), 1.0);
  });

  test('边界·跨路线：A 有数据、B 无数据时两页互不串扰', () async {
    await seed(routeA, nodeA1, accuracy: 0.9, feynman: 0.9);
    addAttempt(nodeId: nodeA1, quizId: 'q1', isCorrect: true, score: 1.0);

    final pA = LocalInsight.profile(routeA);
    final pB = LocalInsight.profile(routeB);
    expect(pA['assessed_nodes'], 1);
    expect(pB['assessed_nodes'], 0);
    expect(pB['ability_radar'], isEmpty);
    expect(pB['weak_points'].length, OfflineContent.allNodes.length,
        reason: 'B 路线零数据时薄弱点仍是全量（未评估节点算薄弱点）');

    final oA = LocalInsight.overview(routeA);
    final oB = LocalInsight.overview(routeB);
    expect(oA['has_data'], isTrue);
    expect(oB['has_data'], isFalse);
    expect(oB['total_attempts'], 0);
    expect(oB['avg_score'], isNull);
    expect(oB['error_breakdown'], isEmpty);
    expect(oB['mastery_distribution']['unseen'],
        OfflineContent.allNodes.length);
    expect(oB['ability_radar'].values.every((v) => v == 0.0), isTrue);

    expect(LocalInsight.summary(routeB)['mastered'], isEmpty);
    expect(LocalInsight.calibration(routeB)['verdict'], 'unknown');
    expect(LocalInsight.motivation(routeB)['total_attempts'], 0);
    expect(LocalInsight.wrongBook(routeB)['count'], 0);
  });

  // ============================================================ 维度二 多路线隔离

  test('路线归属：带 route_id 精确匹配；无 route_id 按测试归属、再按节点解析', () {
    LocalDb.tests['test_b'] = {
      'id': 'test_b',
      'route_id': routeB,
      'status': 'submitted',
    };
    LocalDb.attempts.add({
      'node_id': nodeA1,
      'quiz_id': 'q_explicit',
      'test_id': '',
      'route_id': routeA,
      'is_correct': true,
      'score': 1.0,
      'created_at': nowIso(),
    });
    LocalDb.attempts.add({
      'node_id': '',
      'quiz_id': 'q_via_test',
      'test_id': 'test_b',
      'is_correct': false,
      'score': 0.0,
      'created_at': nowIso(),
    });
    LocalDb.attempts.add({
      'node_id': nodeA1, // 无 route_id、无 test_id → 节点所在章节属 route_A
      'quiz_id': 'q_via_node_a',
      'test_id': '',
      'is_correct': true,
      'score': 1.0,
      'created_at': nowIso(),
    });
    LocalDb.attempts.add({
      'node_id': nodeB1, // route_B 的节点
      'quiz_id': 'q_via_node_b',
      'test_id': '',
      'is_correct': false,
      'score': 0.0,
      'created_at': nowIso(),
    });

    final forA = LocalDb.attemptsForRoute(routeA).map((e) => e['quiz_id']);
    expect(forA.toSet(), {'q_explicit', 'q_via_node_a'});
    final forB = LocalDb.attemptsForRoute(routeB).map((e) => e['quiz_id']);
    expect(forB.toSet(), {'q_via_test', 'q_via_node_b'});
    expect(LocalDb.attemptsForRoute(routeC), isEmpty);
    // 全部原始记录都在，归属只影响取数，不删数据。
    expect(LocalDb.attempts.length, 4);
  });

  test('路线隔离：档案/分析各接口按 routeId 取数，同机两路线结果不同', () async {
    await seed(routeA, nodeA1, accuracy: 0.9, feynman: 0.9);
    addAttempt(nodeId: nodeA1, quizId: 'q1', isCorrect: true, score: 1.0,
        errorCategory: '');
    addAttempt(nodeId: nodeA1, quizId: 'q2', isCorrect: false, score: 0.0,
        errorCategory: 'terminology');

    // 掌握记录：A 有、B 无。
    final mA = LocalMastery.masteryMap(routeA);
    final mB = LocalMastery.masteryMap(routeB);
    expect(mA.length, 1);
    expect(mB, isEmpty);

    // attempts 带路线过滤后两页分析口径分离。
    final oA = LocalInsight.overview(routeA);
    final oB = LocalInsight.overview(routeB);
    expect(oA['total_attempts'], 2);
    expect(oB['total_attempts'], 0);
    expect(oA['error_breakdown'], {'terminology': 1});
    expect(oB['error_breakdown'], isEmpty);

    final pA = LocalInsight.profile(routeA);
    final pB = LocalInsight.profile(routeB);
    expect(pA['assessed_nodes'], 1);
    expect(pB['assessed_nodes'], 0);

    final wA = LocalInsight.wrongBook(routeA) as Map;
    final wB = LocalInsight.wrongBook(routeB) as Map;
    expect(wA['count'], 1);
    expect(wB['count'], 0);

    final motA = LocalInsight.motivation(routeA);
    final motB = LocalInsight.motivation(routeB);
    expect(motA['total_attempts'], 2);
    expect(motB['total_attempts'], 0);
    expect(motA['avg_recent_accuracy'], 0.5);
    expect(motB['avg_recent_accuracy'], isNull);
  });

  test('路线隔离：ApiClient 缓存键含 route_id，A 的缓存不串给 B', () async {
    await seed(routeA, nodeA1, accuracy: 1.0, stability: 1.0, feynman: 0.9);
    // 先缓存路线 A 的 overview（有数据）。
    final a = await ApiClient.get('/api/analytics/overview',
        query: {'route_id': routeA, 'user_id': 'u'}) as Map;
    expect(a['has_data'], isTrue);
    // 路线 B 零数据：若缓存键不含 route_id，这里会命中 A 的缓存错误返回 true。
    final b = await ApiClient.get('/api/analytics/overview',
        query: {'route_id': routeB, 'user_id': 'u'}) as Map;
    expect(b['has_data'], isFalse, reason: '不同路线必须走各自缓存键');
    // A 的缓存仍在：改数据前返回原值。
    final a2 = await ApiClient.get('/api/analytics/overview',
        query: {'route_id': routeA, 'user_id': 'u'}) as Map;
    expect(a2['has_data'], isTrue, reason: '同路线命中缓存');
  });

  // ============================================================ 维度三 图表与数据一致性

  test('雷达一致性：五维 0-1、维度均值=该维度已评估节点均值、两页同源', () async {
    // 认识论（nodeA1）与另一维度各建一个节点，其余维度未评估。
    final dim2 = OfflineContent.node(nodeA2)!['ability_dim'] as String;
    await seed(routeA, nodeA1, accuracy: 0.9, feynman: 0.9);
    await seed(routeA, nodeA2, accuracy: 0.7, feynman: 0.9);

    final ov = LocalInsight.overview(routeA);
    final radar = ov['ability_radar'] as Map;
    expect(radar.length, 5, reason: '分析页恒定五维');
    // 0.6*0.9+0.05*0.9=0.615，/0.65=0.9462；0.6*0.7+0.05*0.9=0.465，/0.65=0.7154
    final dim1 = OfflineContent.node(nodeA1)!['ability_dim'] as String;
    expect(radar[dim1], closeTo(0.9462, 4));
    expect(radar[dim2], closeTo(0.7154, 4));
    expect(radar.values.every((v) => v >= 0.0 && v <= 1.0), isTrue);
    for (final v in radar.values) {
      expect(v, isA<num>(), reason: '雷达值为数值，供 0-1 轴渲染');
    }

    final profile = LocalInsight.profile(routeA);
    final pRadar = profile['ability_radar'] as Map;
    expect(pRadar[dim1], closeTo(radar[dim1], 6));
    expect(pRadar[dim2], closeTo(radar[dim2], 6));
    expect(pRadar.length, 2, reason: '档案页只含已评估维度');
  });

  testWidgets('雷达渲染契约：档案页仅 1 个已评估维度时补 0 成五边形（n≥3 可渲染）',
      (tester) async {
    await seed(routeA, nodeA1, accuracy: 0.9, feynman: 0.9);
    await tester.pumpWidget(const MaterialApp(
      home: ProfileDashboardScreen(routeId: 'route_A'),
    ));
    await tester.pumpAndSettle();

    final radar = tester.widget<RadarChart>(find.byType(RadarChart));
    expect(radar.values.length, 5, reason: '未评估维度补 0，雷达形状稳定');
    expect(radar.labels!.length, 5);
    expect(radar.values.values.every((v) => v >= 0.0 && v <= 1.0), isTrue);
  }, skip: false);

  testWidgets('雷达渲染契约：零数据时仍渲染五维空网格，不隐藏图表',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ProfileDashboardScreen(routeId: 'route_A'),
    ));
    await tester.pumpAndSettle();

    final radar = tester.widget<RadarChart>(find.byType(RadarChart));
    expect(radar.values.length, 5);
    expect(radar.values.values.every((v) => v == 0.0), isTrue);
  }, skip: false);

  test('掌握度分布：四档计数之和=总节点数，且与掌握记录逐节点一致', () async {
    await seed(routeA, nodeA1, accuracy: 1.0, stability: 1.0, feynman: 0.9);
    await seed(routeA, nodeA2, accuracy: 0.9); // proficient（无自评降档）
    await seed(routeA, nodeB1, accuracy: 0.7); // proficient（0.7 恰达 proficient 阈值

    final ov = LocalInsight.overview(routeA);
    final dist = ov['mastery_distribution'] as Map;
    // 掌握记录以「路线」为键，节点可跨路线评估：nodeB1（B 路线节点）在本路线
    // A 上的评估同样计入本路线分布。
    var sum = 0;
    for (final v in dist.values) {
      sum += v as int;
    }
    expect(sum, OfflineContent.allNodes.length);
    expect(dist['mastered'], 1);
    expect(dist['proficient'], 2);
    expect(dist['familiar'], 0);
    expect(dist['beginner'], 0);
    expect(dist['unseen'], OfflineContent.allNodes.length - 3);

    // 与掌握记录逐节点核对。
    final mastery = LocalMastery.masteryMap(routeA);
    var expectUnseen = 0;
    for (final n in OfflineContent.allNodes) {
      final rec = mastery['${n['id']}'];
      if (rec == null) expectUnseen++;
    }
    expect(dist['unseen'], expectUnseen);
  });

  test('健康度：四子项 40/25/15/20，缺数据维度剔除后按剩余权重归一', () async {
    final totalNodes = OfflineContent.allNodes.length;

    // 只有掌握面：1 个 mastered、1 个 beginner（score 0.2）→ masteryRatio = 1/N。
    await seed(routeA, nodeA1, accuracy: 1.0, stability: 1.0, feynman: 0.9);
    await seed(routeA, nodeA2, accuracy: 0.2);
    final ov1 = LocalInsight.overview(routeA);
    // 已评估节点的保持率锚定评估时间（updated_at），未复习即满值 1.0。
    expect(ov1['avg_retention'], 1.0);
    expect(ov1['avg_score'], isNull);
    expect(ov1['calibration']['verdict'], 'unknown');
    final r1 = 1.0 / totalNodes;
    expect(ov1['health_score'],
        (100 * (0.40 * r1 + 0.25 * 1.0) / 0.65).round(),
        reason: '掌握面 + 保持率两维度在权重，其余缺数据剔除后归一');

    // 掌握面 + 全对作答（带把握度 → 校准 calibrated）：权重 40+15+20。
    addAttempt(nodeId: nodeA1, quizId: 'q1', isCorrect: true, score: 1.0,
        confidence: 'high');
    final ov2 = LocalInsight.overview(routeA);
    expect(ov2['avg_score'], 1.0);
    expect(ov2['calibration']['verdict'], 'calibrated');
    expect(ov2['health_score'],
        (100 * (0.40 * r1 + 0.25 * 1.0 + 0.15 * 1.0 + 0.20 * 1.0)).round());

    // 再补复习记录与作答 → 四维度齐全，权重 40+25+15+20。
    await seed(routeA, nodeA2, accuracy: 1.0, stability: 1.0, feynman: 0.9,
        scheduleReview: true);
    addAttempt(nodeId: nodeA2, quizId: 'q2', isCorrect: true, score: 1.0,
        confidence: 'high');
    final ov3 = LocalInsight.overview(routeA);
    expect(ov3['avg_retention'], 1.0);
    expect(ov3['health_score'],
        (100 * (0.40 * (2.0 / totalNodes) + 0.25 * 1.0 + 0.15 * 1.0 +
            0.20 * 1.0)).round());

    // 全维度但数值明确：保持率拨回精确 0.5（半衰期 15 天）、到期 2 项
    // → retentionPart = 0.5 - min(0.5, 2*0.05) = 0.4；正确率 0.5；
    // 作答不带把握度 → 校准 unknown 不进权重。权重 40+25+20 归一。
    final now = DateTime.now().toUtc();
    await seed(routeA, nodeA1, accuracy: 1.0, stability: 1.0, feynman: 0.9,
        scheduleReview: true);
    await seed(routeA, nodeA2, accuracy: 1.0, stability: 1.0, feynman: 0.9,
        scheduleReview: true);
    final past = now.subtract(const Duration(days: 15));
    for (final rec0 in LocalDb.masteryFor(routeA).values) {
      final rec = rec0 as Map;
      if (rec['next_review_at'] != '') {
        rec['last_reviewed_at'] = past.toIso8601String();
        rec['next_review_at'] = past.toIso8601String();
      }
    }
    LocalDb.attempts
      ..clear()
      ..add({
        'node_id': nodeA1,
        'quiz_id': 'q3',
        'route_id': routeA,
        'is_correct': true,
        'score': 1.0,
        'error_category': '',
        'confidence': '',
        'created_at': nowIso(),
      })
      ..add({
        'node_id': nodeA1,
        'quiz_id': 'q4',
        'route_id': routeA,
        'is_correct': false,
        'score': 0.0,
        'error_category': '',
        'confidence': '',
        'created_at': nowIso(),
      });
    final ov4 = LocalInsight.overview(routeA);
    expect(ov4['avg_score'], 0.5);
    expect(ov4['avg_retention'], 0.5);
    expect(ov4['due_count'], 2);
    expect(ov4['calibration']['verdict'], 'unknown');
    expect(ov4['health_score'],
        (100 * (0.40 * (2.0 / totalNodes) + 0.25 * 0.4 + 0.20 * 0.5) / 0.85)
            .round());
  });

  test('错因分布与错题本：计数逐条一致、同题只留最新一条', () {
    final now = DateTime.now().toUtc();
    LocalDb.attempts
      ..add({
        'node_id': nodeA1,
        'quiz_id': 'q1',
        'route_id': routeA,
        'is_correct': false,
        'score': 0.0,
        'error_category': 'terminology',
        'created_at': now.subtract(const Duration(days: 2)).toIso8601String(),
      })
      ..add({
        'node_id': nodeA1,
        'quiz_id': 'q1', // 同题重做
        'route_id': routeA,
        'is_correct': false,
        'score': 0.0,
        'error_category': 'logic_error',
        'created_at': now.toIso8601String(),
      })
      ..add({
        'node_id': nodeA2,
        'quiz_id': 'q2',
        'route_id': routeA,
        'is_correct': false,
        'score': 0.0,
        'error_category': 'terminology',
        'created_at': now.toIso8601String(),
      })
      ..add({
        'node_id': nodeA2,
        'quiz_id': 'q3',
        'route_id': routeA,
        'is_correct': true,
        'score': 1.0,
        'error_category': '',
        'created_at': now.toIso8601String(),
      });

    final ov = LocalInsight.overview(routeA);
    expect(ov['error_breakdown'], {'terminology': 2, 'logic_error': 1});

    final wb = LocalInsight.wrongBook(routeA) as Map;
    expect(wb['count'], 2, reason: 'q1 只留最新错误记录，q3 正确不入错题本');
    final q1 = wb['items']
        .where((i) => i['quiz_id'] == 'q1')
        .first as Map;
    expect(q1['error_category'], 'logic_error', reason: '保留最新一条');
    expect(q1['node_name'], isNotEmpty);
  });

  // ============================================================ 维度四 FSRS 参数

  test('FSRS·间隔合理性：stability 0→1 天起、增长式、封顶 60 天、下限 0.5 天', () {
    expect(LocalMastery.intervalDays(0.0), 1.0, reason: '基础间隔 1 天');
    expect(LocalMastery.intervalDays(0.3), 2.0, reason: '1.0*2^(3*0.3)');
    expect(LocalMastery.intervalDays(0.6), 4.0);
    expect(LocalMastery.intervalDays(1.0) > 10.0, isTrue, reason: '2^3.33≈10');
    final big = LocalMastery.intervalDays(50.0);
    expect(big, 60.0, reason: '封顶 max_interval_days=60（≤365）');
    expect(LocalMastery.intervalDays(-1.0), 1.0, reason: '负稳定性钳到基础间隔');
    for (final s in List.generate(21, (i) => i / 10.0)) {
      final d = LocalMastery.intervalDays(s);
      expect(d, greaterThanOrEqualTo(0.5), reason: '间隔下限 0.5 天');
      expect(d, lessThanOrEqualTo(60.0));
    }
  });

  test('FSRS·半衰期与保持率：3~15 天线性、0.5^(t/hl)、时间为负钳为 0', () {
    expect(LocalMastery.halfLife(0.0), 3.0);
    expect(LocalMastery.halfLife(1.0), 15.0);
    expect(LocalMastery.halfLife(0.5), 9.0);
    expect(LocalMastery.halfLife(2.0), 15.0, reason: '上限钳 15');
    expect(LocalMastery.retention(0.0, 0.5), 1.0);
    expect(LocalMastery.retention(3.0, 0.5), closeTo(0.5, 4),
        reason: 'elapsed=half_life → 0.5');
    expect(LocalMastery.retention(6.0, 0.5), closeTo(0.25, 4));
    expect(LocalMastery.retention(-2.0, 1.0), 1.0,
        reason: '负时间（时钟回拨）不产生 >1 的假保持率');
  });

  test('FSRS·到期判定：score<0.2 不进队列、风险降序、到期时间口径', () async {
    await seed(routeA, nodeA1, accuracy: 0.1, stability: 0.5,
        scheduleReview: true); // score 0.1 → 跳过
    await seed(routeA, nodeA2, accuracy: 0.9, feynman: 0.9,
        scheduleReview: true); // 到期、risk 0
    await seed(routeA, nodeB1, accuracy: 0.9, feynman: 0.9,
        scheduleReview: true); // 到期、risk 0

    final now = DateTime.now().toUtc();
    final past = now.subtract(const Duration(days: 5));
    for (final rec0 in LocalDb.masteryFor(routeA).values) {
      final rec = rec0 as Map;
      if (rec['next_review_at'] != '') {
        rec['last_reviewed_at'] = past.toIso8601String();
        rec['next_review_at'] = past.toIso8601String();
      }
    }

    final due = LocalMastery.dueReviews(routeA);
    expect(due.length, 2, reason: 'score<0.2 不进到期队列');
    expect(due.map((d) => d['node_id']).toSet(), {nodeA2, nodeB1});

    // 依赖者多的节点风险更高、排在前面。
    final nodeWithDependents =
        OfflineContent.allNodes.firstWhere((n) =>
            (n['dependents'] as List?)?.isNotEmpty == true)['id'] as String;
    await seed(routeA, nodeWithDependents, accuracy: 0.9, feynman: 0.9,
        scheduleReview: true);
    final rec3 = LocalDb.masteryFor(routeA).values
        .firstWhere((m) => m['node_id'] == nodeWithDependents) as Map;
    rec3['last_reviewed_at'] = past.toIso8601String();
    rec3['next_review_at'] = past.toIso8601String();
    // 风险降序：到期项中依赖者最多的排最前（keep 相同时按 1+依赖者数比较）。
    final due2 = LocalMastery.dueReviews(routeA);
    final maxDeps = due2
        .map((d) => LocalMastery.dependentsCount('${d['node_id']}'))
        .reduce((a, b) => a > b ? a : b);
    expect(
        LocalMastery.dependentsCount('${due2.first['node_id']}'), maxDeps,
        reason: '风险（依赖者数）降序排列');
  });

  test('FSRS·review 回写：gain/regress 门槛 0.8、stability 钳制、计数与到期时间', () async {
    await seed(routeA, nodeA1, accuracy: 0.9, feynman: 0.9, stability: 0.5,
        scheduleReview: true);
    // 注意：masteryMap 返回的是实时记录引用，applyReview 会就地合并，
    // 需在调用前先取一次基准值，否则比较对象已被改写。
    double stab(Map rec) => dnum((rec['basis'] as Map)['stability']);
    final before = LocalMastery.masteryMap(routeA)[nodeA1] as Map;
    final beforeStability = stab(before);
    final beforeReviewCount = inum(before['review_count']);

    // 0.8 → gain；0.7 → regress。stability 存于 basis。
    final g = await LocalMastery.applyReview(routeA, nodeA1, 0.8);
    expect(g['applied'], isTrue);
    final rec1 = LocalMastery.masteryMap(routeA)[nodeA1] as Map;
    expect(stab(rec1), greaterThan(beforeStability),
        reason: 'gain 提升稳定性');
    expect(rec1['review_count'], beforeReviewCount + 1,
        reason: '本次复习使复习计数 +1');
    expect(parseTime(rec1['next_review_at']), isNotNull);

    final stabAfterGain = stab(rec1);
    final r = await LocalMastery.applyReview(routeA, nodeA1, 0.7);
    expect(r['applied'], isTrue);
    final rec2 = LocalMastery.masteryMap(routeA)[nodeA1] as Map;
    expect(stab(rec2), lessThan(stabAfterGain), reason: 'regress 回落稳定性');

    // 不存在的节点不建档。
    final miss = await LocalMastery.applyReview(routeA, 'no_such_node', 1.0);
    expect(miss['applied'], isFalse);
    expect(LocalMastery.masteryMap(routeA).containsKey('no_such_node'), isFalse);

    // stability 钳在 [0, 1]。
    final clampTest = await LocalMastery.applyReview(routeA, nodeA1, 1.0);
    expect(clampTest['applied'], isTrue);
    final rec3 = LocalMastery.masteryMap(routeA)[nodeA1] as Map;
    expect(stab(rec3), lessThanOrEqualTo(1.0));
  });

  test('FSRS·参数拟合：样本门槛 6、建议公式与后端一致、只算本路线', () {
    // 5 条 → 不足。
    for (var i = 0; i < 5; i++) {
      addAttempt(
        nodeId: nodeA1,
        quizId: 'q$i',
        isCorrect: i < 3,
        score: i < 3 ? 1.0 : 0.0,
      );
    }
    final few = LocalMastery.fitParameters(routeA);
    expect(few['available'], isFalse);
    expect('${few['message']}', contains('5/6'));

    // 6 条：4 对 2 错 → succ 0.667；gain=0.15*(0.5+0.667)=0.175；
    // regress=0.2*(1.5-0.667)=0.167。
    addAttempt(nodeId: nodeA1, quizId: 'q5', isCorrect: true, score: 1.0);
    final fit = LocalMastery.fitParameters(routeA);
    expect(fit['available'], isTrue);
    expect(fit['n'], 6);
    expect(fit['succ_rate'], closeTo(0.667, 3));
    final sug = fit['suggested'] as Map;
    expect(sug['gain'], closeTo(0.175, 3));
    expect(sug['regress'], closeTo(0.167, 3));
    expect(fit['current'], {'gain': 0.15, 'regress': 0.2});

    // 路线过滤：这些作答都属路线 A，路线 B 拟合应不足。
    final fitB = LocalMastery.fitParameters(routeB);
    expect(fitB['available'], isFalse);
  });

  // ============================================================ 维度五 持久化

  test('持久化·flushKey 只写指定文档（不发生全库空穿透）', () async {
    SharedPreferences.setMockInitialValues({
      LocalStoreKeys.attempts: '[]',
      LocalStoreKeys.progress: '{}',
      LocalStoreKeys.mastery: '[]',
    });
    LocalDb.reloadForTest();
    await LocalDb.ensure();

    LocalDb.mastery = {routeA: [{'node_id': nodeA1, 'score': 0.9}]};
    LocalDb.attempts = [{'quiz_id': 'q1'}];
    LocalDb.progress = {routeA: {'node_id': nodeA1, 'status': 'done'}};

    // 只 flush mastery：attempts/progress 不得被重写。
    await LocalDb.flushKey('mastery');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LocalStoreKeys.mastery), contains('kn_practice'));
    expect(prefs.getString(LocalStoreKeys.attempts), '[]',
        reason: 'flushKey(mastery) 不得连带写 attempts');
    expect(prefs.getString(LocalStoreKeys.progress), '{}',
        reason: 'flushKey(mastery) 不得连带写 progress');

    // 只 flush attempts：mastery/progress 保持原样。
    await LocalDb.flushKey('attempts');
    final prefs2 = await SharedPreferences.getInstance();
    expect(prefs2.getString(LocalStoreKeys.attempts), contains('q1'));
    expect(prefs2.getString(LocalStoreKeys.mastery), contains('kn_practice'));
    expect(prefs2.getString(LocalStoreKeys.progress), '{}');

    // 七个键逐个 flush：每个键写自己、不误写其他键。
    LocalDb.signals = [{'node_id': 'n'}];
    LocalDb.tests = {'t1': {'id': 't1', 'route_id': routeA}};
    LocalDb.dialogues = {'1': {'round': 1}};
    LocalDb.settings = {'theme': 'light'};
    for (final k in ['signals', 'tests', 'dialogues', 'settings']) {
      await LocalDb.flushKey(k);
    }
    final prefs3 = await SharedPreferences.getInstance();
    expect(prefs3.getString(LocalStoreKeys.signals), contains('n'));
    expect(prefs3.getString(LocalStoreKeys.tests), contains('t1'));
    expect(prefs3.getString(LocalStoreKeys.dialogues), contains('round'));
    expect(prefs3.getString(LocalStoreKeys.settings), contains('theme'));
    expect(prefs3.getString(LocalStoreKeys.attempts), contains('q1'),
        reason: 'flush 其他键不得清掉 attempts');
  });

  test('持久化·写入→重启读回：掌握/作答/测试/信号完整恢复', () async {
    await seed(routeA, nodeA1, accuracy: 0.9, feynman: 0.9);
    addAttempt(nodeId: nodeA1, quizId: 'q1', isCorrect: false, score: 0.0,
        errorCategory: 'logic_error');
    LocalDb.tests['test_p'] = {'id': 'test_p', 'route_id': routeA};
    LocalDb.signals.add({'node_id': nodeA1, 'intensity': 0.6});
    await LocalDb.flushKey('mastery');
    await LocalDb.flushKey('attempts');
    await LocalDb.flushKey('tests');
    await LocalDb.flushKey('signals');

    // 模拟重启：清内存、重新从 SharedPreferences 加载。
    LocalDb.reloadForTest();
    await LocalDb.ensure();

    final mastery = LocalMastery.masteryMap(routeA);
    expect(mastery.length, 1);
    expect(mastery[nodeA1]['score'], closeTo(0.9462, 4));
    expect(LocalDb.attemptsForRoute(routeA).length, 1);
    expect(LocalDb.tests['test_p']['route_id'], routeA);
    expect(LocalDb.signals.length, 1);
  });

  test('持久化·signals 与 attempts 冗余一致：同步事件两类都落库、归属不串线',
      () async {
    final r = await LocalRouter.post('/api/sync/push', {
      'events': [
        {
          'type': 'quiz_attempt',
          'quiz_id': 'q1',
          'node_id': nodeA1,
          'answer': 'A',
          'is_correct': false,
          'score': 0.0,
          'duration_ms': 1000,
          'error_category': 'logic_error',
          'confidence': 'mid',
          'route_id': routeA,
        },
        {
          'type': 'struggle_signal',
          'node_id': nodeA1,
          'intensity': 0.8,
          'source': 'dialogue',
          'route_id': routeA,
        },
        {
          'type': 'progress',
          'node_id': nodeA1,
          'status': 'completed',
          'route_id': routeA,
        },
        {
          'type': 'section_complete',
          'section_id': 'sec_A_02',
          'score': 0.8,
          'route_id': routeA,
        },
        {'type': 'unknown_event', 'route_id': routeA},
      ],
    });
    expect(r['applied'], 4);
    expect(r['skipped'], 1);

    // 作答与信号双写，归属路线正确。
    final attempts = LocalDb.attemptsForRoute(routeA);
    expect(attempts.length, 1);
    expect(attempts.first['error_category'], 'logic_error');
    expect(attempts.first['confidence'], 'mid');
    expect(LocalDb.signals.length, 1);
    expect(LocalDb.signals.first['intensity'], 0.8);
    final prog = LocalDb.progressFor(routeA);
    expect(prog['sec_A_02'] is Map, isTrue,
        reason: 'section_complete 写进度完成态');
    expect((prog['sec_A_02'] as Map)['status'], 'completed');

    // 事件路线为 B 时归入 B，不串入 A。
    await LocalRouter.post('/api/sync/push', {
      'events': [
        {
          'type': 'quiz_attempt',
          'quiz_id': 'q2',
          'node_id': nodeB1,
          'answer': 'A',
          'is_correct': true,
          'score': 1.0,
          'duration_ms': 1000,
          'route_id': routeB,
        },
      ],
    });
    expect(LocalDb.attemptsForRoute(routeA).length, 1);
    expect(LocalDb.attemptsForRoute(routeB).length, 1);
  });
}
