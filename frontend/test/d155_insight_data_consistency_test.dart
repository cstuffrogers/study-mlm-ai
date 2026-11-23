// 学情数据深度校验测试（D155）：边界用户、跨页一致性、周期筛选、键名契约与缓存失效。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_insight.dart';
import 'package:marxism_reader/offline/local_mastery.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'package:marxism_reader/models/learning_models.dart';
import 'package:marxism_reader/services/api_client.dart';
import 'helpers/offline_assets_guard.dart';

void main() {
  if (skipWithoutOfflineAssets()) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  const route = 'route_A';

  setUp(() async {
    await OfflineContent.ensureMeta();
    await LocalDb.resetAll();
    LocalDb.routeId = route;
  });

  List<Map<String, dynamic>> nodesOfDim(String dim) =>
      OfflineContent.allNodes.where((n) => n['ability_dim'] == dim).toList();

  /// 播种掌握记录；`updatedAt` 非空时改写记录时间（模拟历史作答）。
  Future<Map<String, dynamic>> seed(
    String nodeId, {
    double accuracy = 1.0,
    double stability = 1.0,
    double feynman = 0.9,
    DateTime? updatedAt,
  }) async {
    final rec = await LocalMastery.upsert(
        route,
        nodeId,
        {'accuracy': accuracy, 'stability': stability, 'feynman': feynman},
        'quiz');
    if (updatedAt != null) {
      LocalDb.putMastery(route, nodeId,
          {...rec, 'updated_at': updatedAt.toIso8601String()});
    }
    return rec;
  }

  test('全新用户（无作答/无评估）：雷达为空、薄弱点覆盖全部、空态判据成立', () {
    final prof = LocalInsight.profile(route);
    // 恒定五维（与后端 build_profile 同形状，golden parity 要求）；未评估维度补 0.0
    final profRadar = (prof['ability_radar'] as Map).cast<String, double>();
    expect(profRadar.length, 5);
    expect(profRadar.values.every((v) => v == 0.0), isTrue);
    expect(prof['assessed_nodes'], 0);
    // 未评估节点仍算薄弱点（与后端 build_profile 同口径）
    expect((prof['weak_points'] as List).length, OfflineContent.allNodes.length);

    final ov = LocalInsight.overview(route);
    expect(ov['has_data'], false);
    expect(ov['health_score'], 0);
    // 分析页雷达保持五维形状（供画布渲染），但无数据维度补 0
    expect((ov['ability_radar'] as Map).length, 5);
    final weakest = (ov['weakest_dim'] as Map);
    expect(weakest['dim'], isNull);
    expect(weakest['score'], isNull);

    final summary = LocalInsight.summary(route);
    expect((summary['mastered'] as List), isEmpty);
    expect((summary['to_reinforce'] as List), isEmpty);

    // 档案页空态判据（Profile.assessedNodes == 0）应触发空态
    expect(Profile.fromJson(prof).assessedNodes, 0);
  });

  test('部分评估用户：雷达只算已评估维度且两页同值，已掌握门槛 0.85', () async {
    final mats = nodesOfDim('materialism').take(2).toList();
    final epis = nodesOfDim('epistemology').take(1).toList();
    expect(mats.length + epis.length, greaterThan(0));

    final recA = await seed(mats.first['id']);
    final recB = await seed(
        mats.last['id'], accuracy: 0.75, stability: 0.75, feynman: 0.75);
    await seed(epis.first['id'], accuracy: 0.75, stability: 0.75, feynman: 0.75);

    final prof = LocalInsight.profile(route);
    final radar = (prof['ability_radar'] as Map).cast<String, dynamic>();
    // 恒定五维（与后端 build_profile 同形状）；未评估维度补 0.0
    expect(radar.length, 5);
    expect(radar.containsKey('materialism'), isTrue);
    expect(radar.containsKey('epistemology'), isTrue);
    expect(dnum(radar['dialectics']), 0.0);
    expect(dnum(radar['historical_materialism']), 0.0);
    expect(dnum(radar['political_economy']), 0.0);
    // 雷达值 = 该维度已评估节点 score 均值（未评估节点不再按 0 分拉低）
    final expectMat = (dnum(recA['score']) + dnum(recB['score'])) / 2;
    expect(dnum(radar['materialism']), closeTo(expectMat, 1e-3));
    expect(dnum(radar['materialism']), greaterThan(dnum(recB['score'])));

    // 跨页一致：分析页同一维度同值
    final ov = LocalInsight.overview(route);
    expect(dnum((ov['ability_radar'] as Map)['materialism']),
        closeTo(dnum(radar['materialism']), 1e-6));
    // 最弱维度只在已评估维度里选：epistemology 0.75 < materialism 均值
    expect((ov['weakest_dim'] as Map)['dim'], 'epistemology');

    // 「已掌握」门槛与 levelFromScore 的 mastered（0.85）一致：
    // 0.75 的 proficient 节点不算「已掌握」
    final mastered =
        (LocalInsight.summary(route)['mastered'] as List).cast<String>();
    expect(mastered.contains(mats.first['name']), true);
    expect(mastered.contains(mats.last['name']), false);
    expect(mastered.contains(epis.first['name']), false);
  });

  test('全部掌握用户：雷达满分、健康度满分、分布全部 mastered', () async {
    final ids = OfflineContent.allNodes.map((n) => '${n['id']}').toList();
    for (final id in ids) {
      await seed(id);
    }

    final prof = LocalInsight.profile(route);
    final radar = (prof['ability_radar'] as Map).cast<String, dynamic>();
    expect(radar.length, 5);
    for (final v in radar.values) {
      // 每个维度全部节点 score≈0.9933 → 均值同值
      expect(dnum(v), closeTo(0.9933, 1e-3));
    }
    expect(prof['assessed_nodes'], ids.length);
    expect(Profile.fromJson(prof).assessedNodes, ids.length);

    final ov = LocalInsight.overview(route);
    final dist = (ov['mastery_distribution'] as Map).cast<String, int>();
    expect(dist['mastered'], ids.length);
    expect(dist.values.where((v) => v > 0).length, 1);
    expect(ov['health_score'], 100);
    expect(ov['weakest_dim'], isNotNull);

    final mastered =
        (LocalInsight.summary(route)['mastered'] as List).cast<String>();
    expect(mastered.length, ids.length);
  });

  test('单维用户：雷达只算已评估的单个维度', () async {
    final mats = nodesOfDim('materialism');
    expect(mats, isNotEmpty);
    await seed(mats.first['id']);

    final radar = (LocalInsight.profile(route)['ability_radar'] as Map)
        .cast<String, dynamic>();
    // 恒定五维（与后端 build_profile 同形状）；未评估维度补 0.0
    expect(radar.length, 5);
    expect(dnum(radar['materialism']), greaterThan(0.0));
    expect(dnum(radar['dialectics']), 0.0);
  });

  test('周期筛选：week/month/all 按作答时间过滤，切换筛选数据有变化', () async {
    final now = DateTime.now().toUtc();
    final recent = nodesOfDim('materialism').first;
    final old = nodesOfDim('epistemology').first;
    await seed(recent['id'], updatedAt: now);
    await seed(old['id'], updatedAt: now.subtract(const Duration(days: 20)));

    final week = LocalInsight.summary(route, period: 'week');
    final month = LocalInsight.summary(route, period: 'month');
    final all = LocalInsight.summary(route, period: 'all');

    final wm = (week['mastered'] as List).cast<String>();
    final mm = (month['mastered'] as List).cast<String>();
    final am = (all['mastered'] as List).cast<String>();
    expect(wm.contains(recent['name']), true);
    expect(wm.contains(old['name']), false);
    expect(mm.contains(old['name']), true);
    expect(am.contains(old['name']), true);
    // 近一周与全部的结果不同 → period 筛选真实生效（原先恒等）
    expect(wm, isNot(am));
  });

  test('dueReviews 带 next_review_at 键，复习页可直接展示', () async {
    final mat = nodesOfDim('materialism').first;
    final rec = await LocalMastery.upsert(
        route,
        mat['id'],
        {'accuracy': 0.9, 'stability': 0.9, 'feynman': 0.9},
        'quiz',
        scheduleReview: true);
    final past = DateTime.now().toUtc().subtract(const Duration(days: 20));
    LocalDb.putMastery(route, mat['id'], {
      ...rec,
      'last_reviewed_at': past.toIso8601String(),
      'next_review_at': past.toIso8601String(),
    });

    final due = LocalMastery.dueReviews(route);
    expect(due, isNotEmpty);
    expect(due.first.containsKey('next_review_at'), true);
    expect(due.first['next_review_at'], past.toIso8601String());
  });

  test('review_status 每项带 section_id/level/next_review_at 契约键', () async {
    final mat = nodesOfDim('materialism').first;
    await LocalMastery.upsert(
        route,
        mat['id'],
        {'accuracy': 0.9, 'stability': 0.9, 'feynman': 0.9},
        'quiz',
        scheduleReview: true);

    final status = LocalMastery.reviewStatus(route);
    final items = (status['items'] as List).cast<Map<String, dynamic>>();
    expect(items, isNotEmpty);
    expect(items.first.containsKey('section_id'), true);
    expect(items.first.containsKey('level'), true);
    expect(items.first.containsKey('next_review_at'), true);
  });

  test('测验提交后档案/分析 GET 缓存失效，返回页面读到新数据', () async {
    final overviewUrl =
        '/api/analytics/overview?route_id=$route&user_id=cache-user';
    // 全新用户：第一次 GET 写入缓存（has_data=false）
    final before = await ApiClient.get(overviewUrl);
    expect(before['has_data'], false);
    final cached = await ApiClient.get(overviewUrl);
    expect(cached['has_data'], false);

    // 走完整测验判分（写 attempts + mastery，POST 应失效 /api/ 缓存）
    final sec = OfflineContent.sectionsOf(route)
        .firstWhere((s) => s['has_bank'] == true);
    final sid = sec['id'];
    final started =
        await ApiClient.post('/api/quiz/section/$sid/start',
            {'user_id': 'cache-user'});
    final items = (started['items'] as List).cast<Map<String, dynamic>>();
    expect(items, isNotEmpty);
    final answers = items
        .map((e) =>
            {'item_id': e['id'], 'answer': 'A', 'confidence': 'high'})
        .toList();
    final res = await ApiClient.post(
        '/api/quiz/${started['test_id']}/submit',
        {'user_id': 'cache-user', 'answers': answers});
    expect(res['test_id'], started['test_id']);

    // 提交后：overview 缓存已失效，重新计算 → has_data=true
    final after = await ApiClient.get(overviewUrl);
    expect(after['has_data'], true);

    // profile 缓存同样失效：assessed_nodes 更新
    final profUrl = '/api/mastery/profile?route_id=$route&user_id=cache-user';
    final pAfter = await ApiClient.get(profUrl);
    expect(pAfter['assessed_nodes'], greaterThan(0));
  });
}

double dnum(Object? v) => (v as num).toDouble();
