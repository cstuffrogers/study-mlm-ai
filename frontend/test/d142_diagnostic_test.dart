// D142b 门禁：单机版「摸底测」不再点进去是空的。
//
// 症状：首页 → 路线卡 → 章节地图 →「重新摸底测」→ 页面只有一句「该路线题库建设中」，
// 或者干脆空着，因为 `LocalRouter` 对 `POST /api/routes/{rid}/diagnostic` 直接回
// `items: []`（注释写着「单机版跳过诊断题」）。可题库（`assets/offline/quiz.json`）
// 本来就随包发，32 章全有题——line 上只是没人实现。
//
// 本门禁锁三件事：
//   1. 出题与后端 `quiz_service.start_diagnostic()` 同口径：按章节顺序每章抽 3 题、
//      最多 12 题；题目**必须带溯源 chunk_id**（否则等于放行未溯源题）。
//   2. 判分与后端 `submit_diagnostic()` 同口径：逐章正确率 ≥ 解锁阈值（0.8）判「可跳过」，
//      否则「需从该章开始」；**没有作答数据的章也算需从该章开始**；起点 = 第一张不可跳过的章。
//   3. 结果页显示「阶段N · 标题」而不是 `sec_A_03` 这种内部 id。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_router.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'package:marxism_reader/screens/diagnostic_test.dart';
import 'package:marxism_reader/theme/app_theme.dart';

import 'helpers/offline_assets_guard.dart';

Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
  final r = await LocalRouter.post(path, {'user_id': 'demo_user', ...body});
  return (r as Map).cast<String, dynamic>();
}

List<String> _sectionIds(String routeId) =>
    OfflineContent.sectionsOf(routeId).map((s) => '${s['id']}').toList();

/// 题面不下发 section_id（与后端 `_public_item()` 一致），按题库反查题号所属章。
String _secOf(String routeId, Object? itemId) {
  for (final sid in _sectionIds(routeId)) {
    if (OfflineContent.quizItems(sid)
        .any((it) => '${it['id']}' == '$itemId')) {
      return sid;
    }
  }
  return '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (skipWithoutOfflineAssets()) return;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.ensure();
    await OfflineContent.ensureMeta();
    await OfflineContent.ensureQuiz();
  });

  group('出题', () {
    test('三个路线都真的出题，最多 12 道，每题有选项与溯源自片', () async {
      for (final rid in ['route_A', 'route_B', 'route_C']) {
        final j = await _post('/api/routes/$rid/diagnostic', const {});
        final items = (j['items'] as List).cast<Map<String, dynamic>>();
        expect(items, isNotEmpty, reason: '$rid 摸底测不该是空的');
        expect(items.length, lessThanOrEqualTo(12));
        expect(j['diag_id'], isNotNull);
        for (final it in items) {
          expect('${it['stem']}'.trim(), isNotEmpty);
          expect((it['options'] as List).length, greaterThan(1),
              reason: '选择题至少两个选项');
          // 锚点两种：CH-*（原著分片）与 GUIDE-sec_*（章节导读块，D140 已确认不是 chunk id）。
          final anchor = '${it['source_chunk_id']}';
          expect(anchor.startsWith('CH-') || anchor.startsWith('GUIDE-'), isTrue,
              reason: '题目必须可溯源，否则等于放行未溯源题（$anchor）');
        }
      }
    });

    test('按章节顺序每章取 3 题（与后端 start_diagnostic 同口径）', () async {
      final j = await _post('/api/routes/route_A/diagnostic', const {});
      final items = (j['items'] as List).cast<Map<String, dynamic>>();
      final order = _sectionIds('route_A');
      // 题面不下发 section_id（与后端一致），按题库反查
      String secOf(Object? id) {
        for (final sid in order) {
          if (OfflineContent.quizItems(sid).any((it) => '${it['id']}' == '$id')) {
            return sid;
          }
        }
        return '';
      }

      expect(secOf(items.first['id']), order.first, reason: '第一卷第一章要先出题');

      // 12 题上限按章节顺序吃满：每章最多 3 题（有的章选择题不足 3 道，就少出）
      final bySec = <String, int>{};
      for (final it in items) {
        bySec.update(secOf(it['id']), (v) => v + 1, ifAbsent: () => 1);
      }
      for (final e in bySec.entries) {
        expect(e.value, lessThanOrEqualTo(3), reason: '每章最多 3 题：${e.key}');
      }
      // 章节顺序必须与路线一致（不能乱序跳章）
      final seq = items.map((e) => secOf(e['id'])).toList();
      final uniq = <String>[];
      for (final s in seq) {
        if (uniq.isEmpty || uniq.last != s) uniq.add(s);
      }
      expect(uniq, order.take(uniq.length).toList());
      expect(bySec.length, uniq.length, reason: '一章只应出现一段连续区间');
    });

    test('同一份数据两次出题题号完全一致（可复现）', () async {
      final a = await _post('/api/routes/route_B/diagnostic', const {});
      final b = await _post('/api/routes/route_B/diagnostic', const {});
      expect(a['diag_id'], b['diag_id']);
      expect(
          (a['items'] as List).map((e) => '${e['id']}').toList(),
          (b['items'] as List).map((e) => '${e['id']}').toList());
    });
  });

  group('判分', () {
    test('全答对：有作答数据的章全部可跳过，起点落到第一章', () async {
      final start = await _post('/api/routes/route_A/diagnostic', const {});
      final items = (start['items'] as List).cast<Map<String, dynamic>>();
      final answers = <Map<String, dynamic>>[];
      for (final it in items) {
        final full = OfflineContent.quiz('${it['id']}')!;
        answers.add({'item_id': it['id'], 'answer': '${full['answer']}'});
      }
      final res = await _post(
          '/api/routes/diagnostic/${start['diag_id']}/submit', {'answers': answers});
      final order = _sectionIds('route_A');
      final answered =
          items.map((e) => _secOf('route_A', e['id'])).toSet().toList();
      expect((res['skippable'] as List).toSet(), answered.toSet(),
          reason: '全对就该全标「可跳过」');
      // 后端口径：起点 = 第一张「没有作答数据 / 没达标」的章 → 这里就是第一个没出题的章
      final firstNoData = order.firstWhere((s) => !answered.contains(s),
          orElse: () => order.first);
      expect(res['recommended_start'], firstNoData,
          reason: '全部可跳过时，起点落到第一个没作答数据的章');
      expect(res['to_reinforce'], isEmpty);
      // 没作答数据的章不能凭空判「可跳过」
      final skippable = (res['skippable'] as List).cast<String>().toSet();
      for (final sid in order) {
        if (!answered.contains(sid)) {
          expect(skippable.contains(sid), isFalse,
              reason: '$sid 没有作答数据，不能判为可跳过');
        }
      }
    });

    test('全答错：起点=第一章，可跳过为空，需补强非空且用人话名字', () async {
      final start = await _post('/api/routes/route_A/diagnostic', const {});
      final items = (start['items'] as List).cast<Map<String, dynamic>>();
      final answers = items
          .map((it) => {'item_id': it['id'], 'answer': 'Z'}) // 不在选项里的答案=错
          .toList();
      final res = await _post(
          '/api/routes/diagnostic/${start['diag_id']}/submit', {'answers': answers});
      final order = _sectionIds('route_A');
      expect(res['recommended_start'], order.first);
      expect(res['skippable'], isEmpty);
      expect((res['order'] as List).map((e) => '$e').toList(), order,
          reason: '全错 = 每章都要学，顺序即路线顺序');
      final reinforce = (res['to_reinforce'] as List).cast<Map<String, dynamic>>();
      expect(reinforce, isNotEmpty);
      for (final r in reinforce) {
        expect('${r['node_id']}'.startsWith('kn_'), isTrue);
        expect('${r['name']}', isNot('${r['node_id']}'),
            reason: '需补强要显示知识点名字，不能直接甩 id');
        expect('${r['reason']}', isNotEmpty);
      }
    });

    test('只答对前两章：后两章进「要学」，起点=第三章；未作答的章也算要学', () async {
      final start = await _post('/api/routes/route_A/diagnostic', const {});
      final items = (start['items'] as List).cast<Map<String, dynamic>>();
      final order = _sectionIds('route_A');
      final goodSecs = order.take(2).toSet();
      final answers = <Map<String, dynamic>>[];
      for (final it in items) {
        final full = OfflineContent.quiz('${it['id']}')!;
        final sid = _secOf('route_A', it['id']);
        answers.add({
          'item_id': it['id'],
          'answer': goodSecs.contains(sid) ? '${full['answer']}' : 'Z',
        });
      }
      final res = await _post(
          '/api/routes/diagnostic/${start['diag_id']}/submit', {'answers': answers});
      expect((res['skippable'] as List).cast<String>().toSet(), goodSecs);
      expect(res['recommended_start'], order[2],
          reason: '第一张没达标的章（含没作答数据的章）就是起点');
      expect((res['order'] as List).map((e) => '$e').toList(),
          order.sublist(2));
    });

    test('伪造诊断 id 报 404（不再静默返回成功）', () async {
      await expectLater(
        _post('/api/routes/diagnostic/local_diag_bogus/submit',
            {'answers': const <Map<String, dynamic>>[]}),
        throwsA(isA<LocalApiException>()
            .having((e) => e.status, 'status', 404)),
      );
    });
  });

  group('界面', () {
    testWidgets('点进去就出题，答完给出「阶段N · 标题」的起点', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(),
        home: const DiagnosticTestScreen(routeId: 'route_A', routeName: '路线 A'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('该路线题库建设中，可跳过摸底直接选起点。'), findsNothing,
          reason: '题库随包发，不该出现「建设中」');
      expect(find.textContaining('第 1 / 12 题'), findsOneWidget);

      // 12 题：每题点第一个选项，然后「下一题」/最后「提交」
      for (var i = 0; i < 12; i++) {
        await tester.tap(find.byType(RadioListTile<String>).first);
        await tester.pump();
        await tester.tap(find.text(i == 11 ? '提交' : '下一题'));
        await tester.pumpAndSettle();
      }

      expect(find.text('建议起点'), findsOneWidget);
      expect(find.textContaining('sec_'), findsNothing,
          reason: '结果页要显示章节标题，不能甩内部 id');
      expect(find.textContaining('阶段 '), findsWidgets,
          reason: '起点/可跳过用「阶段N · 标题」');
    });

    testWidgets('解析文案与选项在窄屏不溢出', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920); // 360dp
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(),
        home: const DiagnosticTestScreen(routeId: 'route_C', routeName: '路线 C'),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
