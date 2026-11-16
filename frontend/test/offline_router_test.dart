// 单机版路由层契约测试：把界面实际会打的所有 /api/* 端点跑一遍，
// 确认返回形状与联网版一致（各 *Api 类无需改动即可用）。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/services/analytics_service_api.dart';
import 'package:marxism_reader/services/api_client.dart';
import 'package:marxism_reader/services/mastery_service_api.dart';
import 'package:marxism_reader/services/motivation_service_api.dart';
import 'package:marxism_reader/services/quiz_service_api.dart';
import 'package:marxism_reader/services/recommendation_service_api.dart';
import 'package:marxism_reader/services/review_service_api.dart';
import 'package:marxism_reader/services/routes_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('路线/章节/导读/原文 端点可用', () async {
    final routes = await RoutesService().listRoutes();
    expect(routes.length, greaterThanOrEqualTo(3));
    final sections = await RoutesService().sections('route_B');
    expect(sections, isNotEmpty);
    expect(sections.first.status, isNotEmpty);
    final sid = sections.first.id;

    final guide = await ApiClient.get('/api/routes/route_B/sections/$sid/guide');
    expect(guide['section_id'], sid);
    expect(guide['section_title'], isNotEmpty);

    final gate = await ApiClient.get(
        '/api/routes/route_B/sections/$sid/gating');
    expect(gate.containsKey('next_section_unlocked'), true);
    expect(gate['threshold'], isA<double>());

    final works = await ApiClient.get('/api/chunks/works');
    expect((works['works'] as List), isNotEmpty);
    // items 带作者（原著浏览页搜索用）；作者未登记的留空，不编造
    final items = (works['items'] as List).cast<Map>();
    expect(items.length, (works['works'] as List).length);
    expect(items.every((e) => e.containsKey('author')), true);
    expect(items.any((e) => '${e['author']}'.isNotEmpty), true);
    final work = (works['works'] as List).first as String;
    final chunks = await ApiClient.get(
        '/api/chunks/by_work/${Uri.encodeComponent(work)}');
    expect((chunks['items'] as List), isNotEmpty);
    final chunkId = ((chunks['items'] as List).first as Map)['id'] as String;
    final chunk = await ApiClient.get('/api/chunks/${Uri.encodeComponent(chunkId)}');
    expect(chunk['text'], isNotEmpty);
  });

  test('测验/复习/档案/推荐/激励/分析 端点可用', () async {
    final secs = await RoutesService().sections('route_A');
    final sec = secs.firstWhere((s) => s.hasBank);
    final quiz = QuizApi();
    final started = await quiz.start(sec.id, routeId: 'route_A');
    expect(started.items, isNotEmpty);
    final res = await quiz.submit(started.testId, [
      {'item_id': started.items.first.id, 'answer': 'A', 'confidence': 'mid'},
    ]);
    expect(res['test_id'], started.testId);

    final review = ReviewApi();
    expect(await review.due(), isA<List>());
    expect(await review.interleaved(), isA<List>());
    expect(await review.fit(), isA<Map>());

    final profile = await MasteryApi().profile();
    expect(profile.masteryDistribution, isA<Map>());
    expect(profile.summary, isNotEmpty);
    final summary = await MasteryApi().summary();
    expect(summary['summary'], isNotEmpty);

    final rec = await RecommendationApi().today();
    expect(rec.recType, isNotEmpty);
    expect((await RecommendationApi().weakTop()).length, lessThanOrEqualTo(5));

    final mot = await MotivationApi().state();
    expect(mot['frustration'], isA<Map>());
    expect(mot['milestones'], isA<List>());

    final an = AnalyticsApi();
    final ov = await an.overview();
    expect(ov['health_score'], isA<int>());
    expect(ov['mastery_distribution'], isA<Map>());
    final cal = await an.calibration();
    expect(cal['verdict'], isNotEmpty);
  });

  test('对话与历史端点可用（本机生成）', () async {
    final send = await ApiClient.post('/api/dialogue/send', {
      'dialogue_id': 'router-test',
      'content': '为什么说社会存在决定社会意识？',
      'mode': 'explain',
      'paragraph_id': 'th1',
    });
    expect(send['type'], 'ai_message');
    final list = await ApiClient.get('/api/dialogue/list/demo_user');
    expect((list['dialogues'] as List).isNotEmpty, true);
    final msgs = await ApiClient.get('/api/dialogue/router-test/messages');
    expect(msgs['messages'], isA<List>());
  });

  test('同步端点：进度本机落盘并回读', () async {
    final secs = await RoutesService().sections('route_A');
    final sid = secs.first.id;
    final pushed = await ApiClient.post('/api/sync/push', {
      'route_id': 'route_A',
      'user_id': 'demo_user',
      'events': [
        {'type': 'progress', 'section_id': sid, 'status': 'completed', 'last_position': 3},
      ],
    });
    expect(pushed['accepted'], 1);
    final pulled = await ApiClient.get(
        '/api/sync/pull?route_id=route_A&user_id=demo_user');
    expect(pulled['progress'], isA<List>());
    final after = await RoutesService().sections('route_A');
    final s = after.firstWhere((e) => e.id == sid);
    // 有序题库章是否「完成」由掌握分决定；这里只要求进度被记录并回读。
    expect(s.status, anyOf('completed', 'in_progress'));
    final rows = (pulled['progress'] as List).cast<Map>();
    final row = rows.firstWhere((r) => r['section_id'] == sid);
    expect(row['status'], 'completed');
    expect(row['last_position'], 3);
  });
}
