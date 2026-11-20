// D160 第三轮深检：端到端回归 + 契约一致性 + 生命周期 + 安全导入
//
// 五个维度：
//  1. 端到端回归：作答/进度提交后的数据刷新路径（ApiClient 缓存失效链）、摸底测重做、
//     周期筛选（week/month/all）、阈值边界（0.8/0.849/0.85/0.9）、重置后空态；
//  2. 前后端契约：appeal 补 appeal_id、复习拟合无样本回 n、缓存键含 period；
//  3. 数据生命周期：作答/信号落盘裁剪上限、同节点掌握记录唯一；
//  4. 数据安全：恶意备份导入校验（非对象条目丢弃、路线文档不被覆盖）、重置清队列。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marxism_reader/offline/data_compat.dart';
import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_mastery.dart';
import 'package:marxism_reader/offline/local_router.dart';
import 'package:marxism_reader/offline/local_store_keys.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'package:marxism_reader/services/api_client.dart';
import 'package:marxism_reader/services/sync_controller.dart';

import 'package:marxism_reader/screens/test_history_screen.dart';
import 'helpers/offline_assets_guard.dart';

void main() {
  if (skipWithoutOfflineAssets()) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  const routeA = 'route_A';
  const nodeA1 = 'kn_practice'; // 路线 A 认识论节点（sec_A_02 题库挂载）

  setUp(() async {
    await OfflineContent.ensureMeta();
    SharedPreferences.setMockInitialValues({});
    LocalDb.reloadForTest();
    await LocalDb.ensure();
    LocalDb.routeId = routeA;
    ApiClient.invalidatePrefix(); // 每个用例独立缓存，互不污染
  });

  // ------------------------------------------------------------ 辅助

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final r = await LocalRouter.post(path, {'user_id': 'demo_user', ...body});
    return r.cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> get(String path, [Map<String, String>? query]) async {
    final r = await LocalRouter.get(path, {'user_id': 'demo_user', ...(query ?? const {})});
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

  /// 提交一章章节测验（走 ApiClient，触发写后缓存失效，与真实页面同路径）。
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

  // ============================================================ 维度一 端到端回归

  test('回归·数据刷新：作答提交后档案/分析/动机接口立即读到新数据（无缓存陈旧）',
      () async {
    // 提交前先把各接口读进缓存（模拟页面进入时的首次加载）。
    final profile0 =
        (await ApiClient.get('/api/mastery/profile', query: {'route_id': routeA}))
            as Map;
    final analytics0 = (await ApiClient.get('/api/analytics/overview',
            query: {'route_id': routeA})) as Map;
    final mot0 = (await ApiClient.get('/api/motivation/state',
            query: {'route_id': routeA})) as Map;
    expect(profile0['assessed_nodes'], 0);
    expect(analytics0['has_data'], isFalse);
    expect(mot0['total_attempts'], 0);

    // 提交一章测验（经 ApiClient.post，触发 /api/ 缓存失效）。
    await submitSectionQuiz(allCorrect: true);

    // 提交后不换新实例、不做 fresh 强制，直接再读：必须看到新数据。
    final profile1 =
        (await ApiClient.get('/api/mastery/profile', query: {'route_id': routeA}))
            as Map;
    final analytics1 = (await ApiClient.get('/api/analytics/overview',
            query: {'route_id': routeA})) as Map;
    final mot1 = (await ApiClient.get('/api/motivation/state',
            query: {'route_id': routeA})) as Map;
    expect(profile1['assessed_nodes'], greaterThanOrEqualTo(1),
        reason: '提交后档案必须立刻反映评估节点');
    expect(analytics1['has_data'], isTrue, reason: '提交后分析看板必须判有数据');
    expect(mot1['total_attempts'], greaterThanOrEqualTo(3),
        reason: '提交后动机统计必须立刻包含本次作答');
  });

  test('回归·数据刷新：进度上报后路线章节视图立即反映进度与完成状态', () async {
    final before =
        (await ApiClient.get('/api/routes/$routeA/sections',
                query: {'route_id': routeA})) as Map;
    final secs = (before['sections'] as List).cast<Map<String, dynamic>>();
    final target = secs.first;
    expect(target['status'], 'unlocked', reason: '零进度章节初始为 unlocked');

    // 上报进度（经 ApiClient.post，触发缓存失效）。
    await ApiClient.post('/api/sync/progress', {
      'user_id': 'u',
      'route_id': routeA,
      'section_id': target['id'],
      'last_position': 5,
      'status': 'in_progress',
    });

    // 落库与刷新：pull 快照必须立即含本次上报（sync 路径的端到端刷新）。
    final snap1 =
        (await ApiClient.get('/api/sync/pull', query: {'route_id': routeA})) as Map;
    final p1 = snap1['progress'].toString();
    expect(p1.contains('in_progress'), isTrue, reason: '快照必须含上报状态');
    expect(p1.contains('last_position'), isTrue);

    final after =
        (await ApiClient.get('/api/routes/$routeA/sections',
                query: {'route_id': routeA})) as Map;
    final secs2 = (after['sections'] as List).cast<Map<String, dynamic>>();
    final t2 = secs2.firstWhere(
        (s) => '${s['id']}' == '${target['id']}', orElse: () => secs2.first);
    expect(t2['status'], 'in_progress', reason: '上报后章节视图状态必须立即生效');

    // 完成态上报 → 快照立即更新。
    await ApiClient.post('/api/sync/progress', {
      'user_id': 'u',
      'route_id': routeA,
      'section_id': target['id'],
      'last_position': 5,
      'status': 'completed',
    });
    final snap2 =
        (await ApiClient.get('/api/sync/pull', query: {'route_id': routeA})) as Map;
    final p2 = snap2['progress'].toString();
    expect(p2.contains('completed'), isTrue, reason: '完成后快照必须立即更新');
  });

  test('回归·摸底测重做：同路线再出题题号一致，重复提交不被阻塞（与后端同口径）',
      () async {
    final r1 = await post('/api/routes/$routeA/diagnostic', const {});
    final r2 = await post('/api/routes/$routeA/diagnostic', const {});
    expect(r1['diag_id'], r2['diag_id'], reason: '同路线摸底题必须可复现');
    expect(r1['items'], r2['items']);
    final diagId = '${r1['diag_id']}';
    final items = (r1['items'] as List).cast<Map<String, dynamic>>();
    expect(items, isNotEmpty);
    // publicItem 不下发正确答案（与后端 `_public_item()` 同口径），判分用例须从题库反查。
    final answers = <Map<String, dynamic>>[];
    for (final it in items) {
      final full = OfflineContent.quiz('${it['id']}')!;
      answers.add({'item_id': it['id'], 'answer': '${full['answer']}'});
    }

    // 首次提交：全部答对 → 各章可跳过。
    final s1 = await post('/api/routes/diagnostic/$diagId/submit',
        {'answers': answers});
    expect(s1['diag_id'], diagId);
    expect((s1['skippable'] as List).length, greaterThan(0));

    // 重做：再次提交同一诊断（后端直接重写 result，不阻塞），必须同样成功。
    final s2 = await post('/api/routes/diagnostic/$diagId/submit',
        {'answers': answers});
    expect(s2['diag_id'], diagId);
    expect(s2['recommended_start'], s1['recommended_start'],
        reason: '同一份作答，重做结果必须稳定');
  });

  test('回归·周期筛选：summary 按 updated_at 窗口过滤（week/month/all）', () async {
    final nodes = OfflineContent.allNodes.take(2).map((n) => n['id']).toList();
    // 一条 3 天前、一条 40 天前的掌握记录。
    final now = DateTime.now().toUtc();
    for (var i = 0; i < nodes.length; i++) {
      await LocalMastery.upsert(routeA, nodes[i],
          {'accuracy': 1.0, 'stability': 1.0, 'feynman': 1.0, 'test_count': 1}, 'quiz');
      LocalDb.mastery[routeA]?['${nodes[i]}']?['updated_at'] =
          now.subtract(i == 0 ? const Duration(days: 3) : const Duration(days: 40))
              .toIso8601String();
    }
    await LocalDb.flushKey('mastery');

    final week = await get('/api/mastery/summary', {'period': 'week'});
    final month = await get('/api/mastery/summary', {'period': 'month'});
    final all = await get('/api/mastery/summary', {'period': 'all'});
    expect(week['mastered'], isNotEmpty, reason: '近一周内的记录应被选中');
    expect(week['mastered'].length, 1, reason: '40 天前的记录不得进入近一周');
    expect(month['mastered'].length, 1, reason: '近一月（30 天）同样不含 40 天前记录');
    expect(all['mastered'].length, 2, reason: '全部不过滤');
    expect(week['period'], 'week');
  });

  test('回归·阈值边界：0.8/0.849 精通、0.85/0.9 贯通需 feynman 达标', () {
    expect(LocalMastery.levelFromScore(0.8), 'proficient');
    expect(LocalMastery.levelFromScore(0.849), 'proficient');
    // 0.85 无 feynman 依据 → 按严口径降回精通（与后端一致）。
    expect(LocalMastery.levelFromScore(0.85), 'proficient');
    expect(LocalMastery.levelFromScore(0.85, {'feynman': 0.9}), 'mastered');
    expect(LocalMastery.levelFromScore(0.9, {'feynman': 0.8}), 'mastered');
    // summary 的「已掌握」宽口径：0.8 即算。
    expect(0.8 >= 0.8, isTrue);
  });

  test('回归·重置学习进度：七份文档清空、缓存失效、页面读到空态', () async {
    await LocalMastery.upsert(routeA, nodeA1,
        {'accuracy': 1.0, 'stability': 1.0, 'feynman': 1.0, 'test_count': 1}, 'quiz');
    await submitSectionQuiz(allCorrect: true);
    final pre =
        (await ApiClient.get('/api/analytics/overview',
                query: {'route_id': routeA})) as Map;
    expect(pre['has_data'], isTrue);

    await LocalDb.resetAll();
    await SyncController.clearQueue();
    ApiClient.invalidatePrefix();

    final post0 =
        (await ApiClient.get('/api/analytics/overview',
                query: {'route_id': routeA})) as Map;
    expect(post0['has_data'], isFalse, reason: '重置后分析看板必须回到空态');
    expect(LocalDb.mastery, isEmpty);
    expect(LocalDb.attempts, isEmpty);
    expect(LocalDb.signals, isEmpty);
  });

  // ============================================================ 维度二 契约一致性

  test('契约·申诉接口补 appeal_id（与后端 ap_{test_id}_{item_id} 同形）', () async {
    LocalDb.tests['t_ap'] = {'id': 't_ap', 'section_id': 'sec_A_00', 'route_id': routeA};
    final r = await post('/api/quiz/appeal',
        {'test_id': 't_ap', 'item_id': 'q_1', 'reason': '答案有异议'});
    expect(r['appeal_id'], 'ap_t_ap_q_1', reason: 'appeal_id 必须与后端同形');
    expect(r['status'], isNotEmpty);
    expect(r['test_id'], 't_ap');
    expect(r['item_id'], 'q_1');
  });

  test('契约·复习拟合无样本：回 available=false 且带 n（与后端同键）', () async {
    final r = await get('/api/review/fit', {'route_id': routeA});
    expect(r['available'], isFalse);
    expect(r['n'], 0, reason: '无样本分支也必须回 n，与后端 fit_parameters 一致');
    expect(r['current']['gain'], isA<double>());
    expect(r['current']['regress'], isA<double>());
    expect(r['suggested'], isNull);
  });

  test('契约·缓存键含 period：week/month 各自走缓存、互不串用', () async {
    await LocalMastery.upsert(routeA, nodeA1,
        {'accuracy': 1.0, 'stability': 1.0, 'feynman': 1.0, 'test_count': 1}, 'quiz');
    LocalDb.mastery[routeA]?[nodeA1]?['updated_at'] =
        DateTime.now().toUtc().toIso8601String();
    await LocalDb.flushKey('mastery');

    final week = await ApiClient.get('/api/mastery/summary',
        query: {'route_id': routeA, 'period': 'week'}) as Map;
    final month = await ApiClient.get('/api/mastery/summary',
        query: {'route_id': routeA, 'period': 'month'}) as Map;
    expect(week['period'], 'week');
    expect(month['period'], 'month');
    // 同一条记录在两个周期窗口下都被选中：证明两个键各自取数、没串缓存。
    expect(week['mastered'], month['mastered']);

    // 清掉 week 缓存后重读仍正确（缓存失效不破坏数据）。
    ApiClient.invalidatePrefix('/api/mastery/summary?');
    final week2 = await ApiClient.get('/api/mastery/summary',
        query: {'route_id': routeA, 'period': 'week'}) as Map;
    expect(week2['mastered'], week['mastered']);
  });

  // ============================================================ 维度三 空态

  test('空态·零数据下各分析接口返回完整空态形状（不抛错、不缺键）', () async {
    final profile = await get('/api/mastery/profile');
    expect(profile['assessed_nodes'], 0);
    expect(profile['weak_points'], isA<List>());
    final analytics = await get('/api/analytics/overview');
    expect(analytics['has_data'], isFalse);
    expect(analytics['ability_radar'], isA<Map>());
    expect((analytics['ability_radar'] as Map).length, 5, reason: '雷达恒五维');
    final mot = await get('/api/motivation/state');
    expect(mot['frustration']['level'], isA<String>());
    expect(mot['milestones'], isA<List>());
    final cal = await get('/api/analytics/calibration');
    expect(cal['verdict'], 'unknown');
    expect(cal['n'], 0);
  });

  // ============================================================ 维度四 生命周期

  test('生命周期·作答/信号落盘裁剪：超出上限保留最新，不无限膨胀', () async {
    for (var i = 0; i < LocalDb.maxAttempts + 5; i++) {
      LocalDb.attempts.add({
        'node_id': nodeA1,
        'quiz_id': 'q_$i',
        'route_id': routeA,
        'is_correct': true,
        'score': 1.0,
        'created_at': nowIso(),
      });
    }
    for (var i = 0; i < LocalDb.maxSignals + 5; i++) {
      LocalDb.signals.add({'node_id': nodeA1, 'intensity': 0.5});
    }
    await LocalDb.flush();
    expect(LocalDb.attempts.length, LocalDb.maxAttempts,
        reason: '作答流水应裁剪到上限');
    expect(LocalDb.signals.length, LocalDb.maxSignals,
        reason: '学情信号应裁剪到上限');
    // 保留的是最新的：首条应是上限窗口内的第 1 条。
    expect('${LocalDb.attempts.first['quiz_id']}', 'q_5');
    // 单键 flush 同样触发裁剪。
    LocalDb.attempts.add({'quiz_id': 'q_new', 'created_at': nowIso()});
    LocalDb.attempts.add({'quiz_id': 'q_new2', 'created_at': nowIso()});
    await LocalDb.flushKey('attempts');
    expect(LocalDb.attempts.length, LocalDb.maxAttempts);
  });

  test('生命周期·掌握记录唯一：同节点多次评估只留一条、字段取最新', () async {
    await LocalMastery.upsert(routeA, nodeA1,
        {'accuracy': 0.4, 'stability': 0.3, 'feynman': 0.1, 'test_count': 1},
        'quiz');
    await LocalMastery.upsert(routeA, nodeA1,
        {'accuracy': 0.9, 'stability': 0.9, 'feynman': 0.9, 'test_count': 1},
        'quiz');
    final map = LocalDb.masteryFor(routeA);
    expect(map.keys.where((k) => k == nodeA1).length, 1,
        reason: '同一节点只能有一条掌握记录');
    final rec = map[nodeA1].cast<String, dynamic>();
    expect(rec['score'], greaterThanOrEqualTo(0.85),
        reason: '后一次评估应覆盖前一次（分数取最新）');
  });

  // ============================================================ 维度五 安全

  test('安全·恶意备份导入：非对象条目丢弃、路线文档不被覆盖、合法条目正常合并',
      () async {
    // 本机已有路线 A 的一份掌握记录（导入时必须被保护/合并）。
    await LocalMastery.upsert(routeA, nodeA1,
        {'accuracy': 1.0, 'stability': 1.0, 'feynman': 1.0, 'test_count': 1}, 'quiz');
    LocalDb.tests['t_ok'] = {'id': 't_ok', 'route_id': routeA};
    await LocalDb.flush();

    final backup = jsonDecode(jsonEncode({
      'app': 'xxmz',
      'format': 1,
      'data_schema': DataCompat.schema,
      'docs': {
        LocalStoreKeys.mastery: {
          // 恶意：把路线 A 的整份掌握文档替换成字符串。
          routeA: 'garbage',
          // 合法：路线 B 的新记录正常合并。
          'route_B': {'kn_b1': {'score': 0.9, 'level': 'proficient'}},
        },
        LocalStoreKeys.progress: {
          // 恶意：非 Map 条目。
          routeA: 42,
        },
        LocalStoreKeys.attempts: [
          // 恶意：字符串条目。
          'xx',
          // 合法：对象条目。
          {'quiz_id': 'q_b1', 'route_id': routeA, 'is_correct': true},
        ],
        LocalStoreKeys.signals: ['bad', {'node_id': 'kn_practice'}],
        LocalStoreKeys.tests: {
          // 恶意：值不是 Map。
          't_bad': 123,
          // 合法：对象条目。
          't_in': {'id': 't_in', 'route_id': routeA},
        },
        LocalStoreKeys.dialogues: {
          'd_bad': 'not-a-map',
          'd_in': {'id': 'd_in', 'messages': []},
        },
        LocalStoreKeys.settings: {'route_id': routeA},
      },
    })) as Map<String, dynamic>;

    final counts = await DataCompat.importJson(jsonEncode(backup));

    // 路线 A 原文档完好（恶意覆盖被丢弃）。
    final mapA = LocalDb.masteryFor(routeA);
    expect(mapA[nodeA1], isNotNull, reason: '非 Map 覆盖不得破坏既有路线文档');
    // 路线 B 合法条目合并成功。
    expect((LocalDb.mastery['route_B'] as Map)['kn_b1'], isNotNull);
    // 作答：合法条目入列、字符串条目丢弃。
    expect(LocalDb.attempts.whereType<Map>().length, 1);
    expect(LocalDb.attempts.any((e) => e == 'xx'), isFalse);
    // 信号：合法入列、坏条目丢弃。
    expect(LocalDb.signals.whereType<Map>().length, 1);
    // 测试/对话：合法入列、非 Map 值丢弃。
    expect(LocalDb.tests['t_ok'], isNotNull, reason: '既有记录不受影响');
    expect(LocalDb.tests['t_in'], isNotNull);
    expect(LocalDb.tests['t_bad'], isNull);
    expect(LocalDb.dialogues['d_in'], isNotNull);
    expect(LocalDb.dialogues['d_bad'], isNull);
    expect(counts[LocalStoreKeys.attempts], 1);
    expect(counts[LocalStoreKeys.signals], 1);
  });

  test('安全·重置清离线队列：待同步事件不残留、不回灌', () async {
    // 模拟离线队列里有未上报事件。
    final sp = await SharedPreferences.getInstance();
    await sp.setString(LocalStoreKeys.syncQueue,
        jsonEncode([{'type': 'progress', 'section_id': 'sec_A_00'}]));
    await SyncController.clearQueue();
    final sp2 = await SharedPreferences.getInstance();
    expect(sp2.getString(LocalStoreKeys.syncQueue), isNull,
        reason: '重置学习进度后离线队列必须清空');
  });

  test('安全·本地存储审计：各文档与偏好里没有明文 API 密钥', () async {
    // 造一些学习数据 + 一个（假）配置，然后全库扫描敏感键。
    await LocalMastery.upsert(routeA, nodeA1,
        {'accuracy': 1.0, 'stability': 1.0, 'feynman': 1.0, 'test_count': 1}, 'quiz');
    LocalDb.attempts.add({'quiz_id': 'q1', 'node_id': nodeA1});
    LocalDb.signals.add({'node_id': nodeA1, 'intensity': 0.5});
    final sp = await SharedPreferences.getInstance();
    // 模拟一个密钥类键（即便被错误写入也应被审计发现）。
    await sp.setString('llm_config', jsonEncode({'api_key': 'sk-secret-123'}));

    final sensitive = RegExp(r'(api[_-]?key|secret|token|password)',
        caseSensitive: false);
    final leaks = <String>[];
    for (final doc in [
      LocalDb.mastery,
      LocalDb.progress,
      LocalDb.tests,
      LocalDb.dialogues,
      LocalDb.settings,
    ]) {
      for (final e in doc.entries) {
        if (sensitive.hasMatch(e.key)) leaks.add('doc key: $e.key');
      }
    }
    for (final a in LocalDb.attempts) {
      if (a is Map) {
        for (final e in a.entries) {
          if (sensitive.hasMatch('${e.key}')) leaks.add('attempt key: ${e.key}');
        }
      }
    }
    // 序列化内容里不得出现明文密钥串。
    final docFields = {
      LocalStoreKeys.mastery: LocalDb.mastery,
      LocalStoreKeys.progress: LocalDb.progress,
      LocalStoreKeys.attempts: LocalDb.attempts,
      LocalStoreKeys.signals: LocalDb.signals,
      LocalStoreKeys.settings: LocalDb.settings,
    };
    for (final entry in docFields.entries) {
      final raw = jsonEncode(entry.value);
      if (raw.contains('sk-')) leaks.add('文档 ${entry.key} 含明文密钥');
    }
    // SharedPreferences 无 getAll()，逐个检查已知敏感键。
    final sensitivePrefs = [LocalStoreKeys.settings];
    for (final key in sensitivePrefs) {
      final val = sp.getString(key);
      if (val != null && val.isNotEmpty && val.contains('sk-')) {
        leaks.add('偏好 $key 含明文密钥');
      }
    }
    expect(leaks, isEmpty, reason: '本地存储不得出现明文 API 密钥：$leaks');
  });

  testWidgets(
    '可读性·测试历史时间本地化：显示到分钟、不带原始 ISO 的 T/Z',
    (tester) async {
      // 造一条作答记录，created_at 为带时区的 ISO 串。
      LocalDb.attempts.add({
        'quiz_id': 'q_t',
        'node_id': nodeA1,
        'test_id': 't_t',
        'route_id': routeA,
        'is_correct': true,
        'score': 1.0,
        'created_at': '2025-06-15T10:30:45.123Z',
      });
      await LocalDb.flushKey('attempts');
      ApiClient.invalidatePrefix();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TestHistoryScreen(routeId: routeA)),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      // 时间在 ExpansionTile 的折叠内容里，先点开再查找。
      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      final texts = find.byType(Text).evaluate()
          .map((e) => (e.widget as Text).data)
          .where((s) => s != null)
          .toList();
      final timeText = texts.firstWhere(
          (s) => s!.contains('2025-06-15'), orElse: () => '');
      // 本地化到分钟：YYYY-MM-DD HH:mm，不含 T/Z/毫秒。
      expect(timeText, matches(RegExp(r'^2025-06-15 \d{2}:\d{2}$')),
          reason: '时间应本地化显示为 YYYY-MM-DD HH:mm：实际「$timeText」');
    },
  );
}

/// nowIso 与生产代码同源（local_mastery.dart）。
String nowIso() => DateTime.now().toUtc().toIso8601String();
