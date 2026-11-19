// D159 学情档案 / 学习分析数据更深层检查（第二轮）
//
// 五个维度全量验证：
//  1. 大数据量性能：节点索引 O(1)、500+ 作答规模下 LocalDb 扫描与 LocalInsight
//     全链分析的耗时预算与计数正确性；
//  2. 备份恢复完整性：大批量导出→清空→导入的字段级比对、data_schema 闸门、
//     空备份边界；
//  3. 并发写入安全：同测试并发双提交、同节点并发提交的稳定性增量、并发复习
//     回写、LocalDb.write 串行队列 FIFO；
//  4. 数据版本迁移：损坏文档隔离可恢复、模型反序列化容错、DataCompat.run 幂等、
//     旧 schema 备份兼容导入；
//  5. 可视化精度：混合时间格式按时刻排序、周/月窗口边界、雷达与健康度取值精度。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marxism_reader/models/learning_models.dart';
import 'package:marxism_reader/offline/data_compat.dart';
import 'package:marxism_reader/offline/local_api_exception.dart';
import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_insight.dart';
import 'package:marxism_reader/offline/local_mastery.dart';
import 'package:marxism_reader/offline/local_quiz.dart';
import 'package:marxism_reader/offline/local_store_keys.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'package:marxism_reader/services/api_client.dart';

import 'helpers/offline_assets_guard.dart';

void main() {
  if (skipWithoutOfflineAssets()) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  const routeA = 'route_A';
  const routeB = 'route_B';
  const nodeA1 = 'kn_practice'; // 路线 A 认识论节点（sec_A_02 题库挂载）
  const nodeA2 = 'kn_object_activity';

  setUp(() async {
    await OfflineContent.ensureMeta();
    // 先起 prefs 再 reload+ensure：既有清空语义（空内存起步），又保证后续
    // flush 有落点、ensure 不再回读覆盖内存（_ready=true）。
    SharedPreferences.setMockInitialValues({});
    LocalDb.reloadForTest();
    await LocalDb.ensure();
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

  /// 无时区信息的墙钟时间（data_compat._nowIso 同风格，本地时区）。
  String naiveLocal(DateTime utc) =>
      utc.toLocal().toIso8601String().substring(0, 19);

  /// 取路线 A 第一个有选择题的章节及其前 3 道选择题（与摸底测同取法）。
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

  // ============================================================ 维度一 性能

  test('性能·节点索引：全部节点可 O(1) 命中，与原全表扫描结果一致、未知 id 为空',
      () {
    expect(OfflineContent.allNodes.length, greaterThan(100),
        reason: '离线知识库应为 100+ 节点规模');
    for (final n in OfflineContent.allNodes) {
      // 索引返回的是同一节点内容的 Map（_list 每次 cast 为副本，按内容比对），
      // 与原全表扫描结果等价且 O(1)。
      expect(OfflineContent.node('${n['id']}'), equals(n));
    }
    expect(OfflineContent.node('no_such_node_xyz'), isNull);
    // 索引随 meta 就绪，未就绪时与原实现一致返回空。
    expect(OfflineContent.node('kn_practice'), isNotNull);
  });

  test('性能·大数据量：500 作答下全链分析在耗时预算内且计数精确', () async {
    await OfflineContent.ensureQuiz();
    final nodes = OfflineContent.allNodes;

    // 500 条作答：跨节点、跨路线（每 4 条一条归 B），全部带显式 route_id。
    const total = 500;
    for (var i = 0; i < total; i++) {
      final n = nodes[i % nodes.length];
      addAttempt(
        routeId: i % 4 == 0 ? routeB : routeA,
        nodeId: '${n['id']}',
        quizId: 'q_big_$i',
        isCorrect: i % 2 == 0,
        score: i % 2 == 0 ? 1.0 : 0.0,
        errorCategory: i % 2 == 1 ? 'logic_error' : '',
      );
    }
    final expectedForA =
        total - (total / 4).toInt(); // i%4==0 的 125 条归 B
    // 20 个掌握记录。
    for (var i = 0; i < 20; i++) {
      await seed(routeA, '${nodes[i]['id']}', accuracy: 0.9, feynman: 0.9);
    }

    // 单次路线扫描。
    final swScan = Stopwatch()..start();
    final forA = LocalDb.attemptsForRoute(routeA);
    swScan.stop();
    expect(swScan.elapsedMilliseconds, lessThan(1000),
        reason: '500 条作答的路线扫描应为线性量级');
    expect(forA.length, expectedForA);

    // 全链分析（overview/profile/summary/motivation/wrongBook/复习状态）。
    final sw = Stopwatch()..start();
    final ov = LocalInsight.overview(routeA);
    final prof = LocalInsight.profile(routeA);
    final sum = LocalInsight.summary(routeA);
    final mot = LocalInsight.motivation(routeA);
    final wb = LocalInsight.wrongBook(routeA);
    final status = LocalMastery.reviewStatus(routeA);
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(3000),
        reason: '500 作答 + 20 掌握记录的全链分析必须在线性耗时预算内');

    // 计数精确性（性能优化不得改变口径）。
    expect(ov['total_attempts'], expectedForA);
    expect(ov['assessed_nodes'], 20);
    expect(prof['assessed_nodes'], 20);
    expect(sum['mastered'].length, 20, reason: 'score>=0.8 全部入已掌握');
    expect(mot['total_attempts'], expectedForA);
    // 错题本：250 道不同错题按题去重后，受 60 条上限钳制。
    expect(wb['count'], 60, reason: '错题上限 60 生效（去重后按上限截断）');
    expect((wb['items'] as List).every((e) => e['is_correct'] != true), isTrue,
        reason: '错题本只收错题');
    expect(status['items'].length, 20, reason: '20 条掌握记录全部入复习状态表');

    // 历史接口同样扫全表，验证耗时与限额钳制。
    final swH = Stopwatch()..start();
    final hist = LocalQuiz.history(limit: 100);
    swH.stop();
    expect(swH.elapsedMilliseconds, lessThan(1000));
    expect(hist['items'].length, 100, reason: 'limit 钳制生效');
  });

  // ============================================================ 维度二 备份恢复

  test('备份·大批量往返：作答/掌握/测试/对话/信号/进度/原文导出→清空→导入逐字段一致',
      () async {
    final nodes = OfflineContent.allNodes;
    // 120 条作答。
    for (var i = 0; i < 120; i++) {
      addAttempt(
        nodeId: '${nodes[i % nodes.length]['id']}',
        quizId: 'q_bk_$i',
        isCorrect: i % 3 != 0,
        score: i % 3 == 0 ? 0.0 : 1.0,
        errorCategory: i % 3 == 0 ? 'terminology' : '',
        confidence: i % 2 == 0 ? 'high' : 'mid',
      );
    }
    // 10 条掌握记录（含 basis 子结构）。
    for (var i = 0; i < 10; i++) {
      await seed(routeA, '${nodes[i]['id']}',
          accuracy: 0.9, stability: 0.7, feynman: 0.9);
    }
    LocalDb.tests['t_bk'] = {
      'id': 't_bk',
      'section_id': 'sec_A_00',
      'route_id': routeA,
      'item_ids': ['q_a00_1'],
      'status': 'passed',
      'total_score': 1.0,
    };
    LocalDb.dialogues['d_bk'] = {
      'id': 'd_bk',
      'title': '备份对话',
      'current_mode': 'explain',
      'created_at': '2026-01-01T09:00:00',
      'messages': [
        {'role': 'user', 'content': '问', 'mode': 'explain', 'created_at': '2026-01-01T09:00:00'},
      ],
    };
    LocalDb.signals.add({'node_id': nodeA1, 'signal_type': 'struggle', 'intensity': 0.8});
    LocalDb.putProgress(routeA, 'sec_A_00', {
      'status': 'done',
      'anchor': 'kn_a00_basic',
      'updated_at': nowIso(),
    });
    LocalDb.settings['route_id'] = routeA;
    LocalDb.settings['font_scale'] = 1.1;
    await LocalDb.flush();

    // 原文阅读器数据（独立于七份文档的 reader_* 键）。
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        LocalStoreKeys.reader('《国家与革命》', LocalStoreKeys.readerNotes),
        jsonEncode([{'para': 3, 'text': '笔记'}]));
    await prefs.setInt(
        LocalStoreKeys.reader('《国家与革命》', LocalStoreKeys.readerLastPage), 8);

    final backup = await DataCompat.exportJson();
    final parsed = jsonDecode(backup) as Map<String, dynamic>;
    expect(parsed['data_schema'], DataCompat.schema);
    final docs = parsed['docs'] as Map<String, dynamic>;
    for (final k in LocalStoreKeys.docs) {
      expect(docs.containsKey(k), isTrue, reason: '备份缺文档 $k');
    }
    final reader = parsed['reader'] as Map<String, dynamic>;
    expect(reader.isNotEmpty, isTrue, reason: '原文阅读器数据要进备份');
    final beforeStats = await DataCompat.stats();

    // 换机：清空本机后导入。
    SharedPreferences.setMockInitialValues({});
    LocalDb.reloadForTest();
    await LocalDb.ensure();
    expect((await DataCompat.stats())['attempts'], 0);

    final counts = await DataCompat.importJson(backup);
    expect(counts[LocalStoreKeys.attempts], 120);
    expect(counts[LocalStoreKeys.signals], 1);

    final afterStats = await DataCompat.stats();
    for (final k in beforeStats.keys) {
      expect(afterStats[k], beforeStats[k], reason: '恢复后 $k 应与备份时一致');
    }
    // 字段级深比对。
    expect(jsonEncode(LocalDb.attempts),
        jsonEncode(docs[LocalStoreKeys.attempts]),
        reason: '作答流水逐条一致');
    expect(jsonEncode(LocalDb.signals), jsonEncode(docs[LocalStoreKeys.signals]));
    expect(jsonEncode(LocalDb.masteryFor(routeA)),
        jsonEncode((docs[LocalStoreKeys.mastery] as Map)[routeA]),
        reason: '掌握记录逐节点一致（含 basis）');
    expect(jsonEncode(LocalDb.tests['t_bk']), jsonEncode(docs[LocalStoreKeys.tests]['t_bk']));
    expect(jsonEncode(LocalDb.dialogues['d_bk']),
        jsonEncode(docs[LocalStoreKeys.dialogues]['d_bk']));
    expect(jsonEncode(LocalDb.progressFor(routeA)['sec_A_00']),
        jsonEncode(docs[LocalStoreKeys.progress][routeA]['sec_A_00']),
        reason: '章节进度含锚点完整恢复');
    // 原文数据恢复。
    final prefsAfter = await SharedPreferences.getInstance();
    expect(prefsAfter.getString(
            LocalStoreKeys.reader('《国家与革命》', LocalStoreKeys.readerNotes)),
        contains('笔记'));
    expect(prefsAfter.getInt(
            LocalStoreKeys.reader('《国家与革命》', LocalStoreKeys.readerLastPage)),
        8);
  });

  test('备份·data_schema 闸门：高于本版的备份拒绝恢复，同版/旧版/缺字段放行',
      () async {
    addAttempt(nodeId: nodeA1, quizId: 'q1', isCorrect: true, score: 1.0);
    await LocalDb.flushKey('attempts');
    final backup = await DataCompat.exportJson();
    final parsed = jsonDecode(backup) as Map<String, dynamic>;

    // 更高数据结构版本：拒绝，且不动本机数据。
    parsed['data_schema'] = DataCompat.schema + 1;
    final guarded = jsonEncode(LocalDb.attempts);
    await expectLater(
        DataCompat.importJson(jsonEncode(parsed)),
        throwsA(isA<FormatException>()));
    expect(jsonEncode(LocalDb.attempts), guarded, reason: '拒绝导入不得改动本机数据');

    // 同版本 / 旧版本 / 缺字段 / 字符串版本号（非 int 不参与比较）：放行。
    for (final v in [DataCompat.schema, 1, null, '${DataCompat.schema}']) {
      parsed['data_schema'] = v;
      LocalDb.attempts.clear();
      await DataCompat.importJson(jsonEncode(parsed));
      expect(LocalDb.attempts.length, 1, reason: 'data_schema=$v 应放行导入');
    }
  });

  test('备份·空备份：空设备导出→空设备导入不报错，统计保持零', () async {
    SharedPreferences.setMockInitialValues({});
    LocalDb.reloadForTest();
    await LocalDb.ensure();
    final backup = await DataCompat.exportJson();
    final parsed = jsonDecode(backup) as Map<String, dynamic>;
    expect(parsed['data_schema'], DataCompat.schema);
    // 空设备：文档容器形状正确（列表文档为 []、映射文档为 {}）。
    for (final k in LocalStoreKeys.docs) {
      final v = (parsed['docs'] as Map)[k];
      final isMapDoc = k == LocalStoreKeys.settings || k == LocalStoreKeys.mastery ||
          k == LocalStoreKeys.progress || k == LocalStoreKeys.dialogues ||
          k == LocalStoreKeys.tests;
      expect(isMapDoc ? v is Map : v is List, isTrue, reason: '$k 容器类型不符');
      expect(v.isEmpty, isTrue, reason: '$k 应为空容器');
    }

    await DataCompat.importJson(backup);
    final stats = await DataCompat.stats();
    expect(stats['attempts'], 0);
    expect(stats['dialogues'], 0);
    expect(stats['mastery_nodes'], 0);
    expect(stats['notes'], 0);
  });

  // ============================================================ 维度三 并发安全

  test('并发·同测试双提交：仅一次成功、作答不重复、掌握回写一次', () async {
    final (sid, items) = await firstChoiceSection();
    LocalDb.tests['t_dup'] = {
      'id': 't_dup',
      'section_id': sid,
      'route_id': routeA,
      'item_ids': items.map((e) => '${e['id']}').toList(),
      'status': 'open',
    };
    final answers = items
        .map((e) => {'item_id': e['id'], 'answer': e['answer'], 'confidence': 'high'})
        .toList();

    Map<String, dynamic>? ok;
    LocalApiException? err;
    Future<Map<String, dynamic>?> trySubmit(String id) async {
      try {
        final r = await LocalQuiz.submit(id, answers);
        ok = r;
        return r;
      } catch (e) {
        if (e is LocalApiException) err = e;
        return null;
      }
    }

    final results = await Future.wait([trySubmit('t_dup'), trySubmit('t_dup')]);
    expect(results.length, 2);
    expect(ok, isNotNull, reason: '两次提交应有一次成功');
    expect(err, isNotNull, reason: '另一次应被 409 拒绝');
    expect(err!.status, 409);
    expect(LocalDb.attempts.length, items.length,
        reason: '作答流水不得因并发重复写入');
    expect(LocalDb.tests['t_dup']['status'], 'submitted');
    // 掌握回写只发生一次：accuracy 全对、basis 只被写一次。
    final rec = LocalDb.masteryFor(routeA).values.first as Map;
    expect(dnum((rec['basis'] as Map)['accuracy']), 1.0, reason: '全对时回写准确率为 1');
  });

  test('并发·同节点并发提交：稳定性增量不互相覆盖、累计完整', () async {
    final (sid, items) = await firstChoiceSection();
    final item = items.first;
    final nodeId = '${item['node_id']}';
    // 两份不同测试、同一节点、全对。
    for (final tid in ['t_c1', 't_c2']) {
      LocalDb.tests[tid] = {
        'id': tid,
        'section_id': sid,
        'route_id': routeA,
        'item_ids': [item['id']],
        'status': 'open',
      };
    }
    final answers =
        [{'item_id': item['id'], 'answer': item['answer'], 'confidence': 'high'}];

    final results = await Future.wait([
      LocalQuiz.submit('t_c1', answers),
      LocalQuiz.submit('t_c2', answers),
    ]);
    expect(results.every((r) => r.containsKey('test_id')), isTrue,
        reason: '两份测试都应提交成功');
    expect(LocalDb.attempts.length, 2);

    // 无先验记录时首交 stability 0→0.3，串行下第二交读到 0.3 → 0.6。
    final rec = LocalDb.masteryFor(routeA)[nodeId] as Map;
    expect(dnum((rec['basis'] as Map)['stability']), closeTo(0.6, 4),
        reason: '串行写入下两次 +0.3 增量完整累计，不互相覆盖');
    expect(dnum((rec['basis'] as Map)['accuracy']), 1.0);
  });

  test('并发·并行复习回写：计数正确累加、无记录节点不重复建档', () async {
    await seed(routeA, nodeA1, accuracy: 0.9, stability: 0.5, feynman: 0.9);
    final before = LocalMastery.masteryMap(routeA)[nodeA1] as Map;
    final beforeCount = inum(before['review_count']);

    final done = await Future.wait([
      LocalMastery.applyReview(routeA, nodeA1, 0.9),
      LocalMastery.applyReview(routeA, nodeA1, 0.9),
    ]);
    expect(done.every((m) => m['applied'] == true), isTrue);
    final rec = LocalMastery.masteryMap(routeA)[nodeA1] as Map;
    expect(inum(rec['review_count']), beforeCount + 2,
        reason: '两次并发复习各计一次');
    // gain 0.15 × 2，从 0.5 累加到 0.8。
    expect(dnum((rec['basis'] as Map)['stability']), closeTo(0.8, 4),
        reason: '稳定性增益不互相覆盖');

    // 无记录节点：并发两次都应判定「尚无掌握记录」，且不凭空建档。
    final misses = await Future.wait([
      LocalMastery.applyReview(routeA, 'no_such_node_c', 1.0),
      LocalMastery.applyReview(routeA, 'no_such_node_c', 1.0),
    ]);
    expect(misses.every((m) => m['applied'] == false), isTrue);
    expect(LocalMastery.masteryMap(routeA).containsKey('no_such_node_c'), isFalse);
  });

  test('并发·LocalDb.write 串行队列：任务 FIFO、异常不切断队列', () async {
    final order = <String>[];
    await Future.wait([
      LocalDb.write(() async {
        await Future.delayed(const Duration(milliseconds: 30));
        order.add('a');
        return 1;
      }),
      LocalDb.write(() async {
        order.add('b');
        return 2;
      }),
      LocalDb.write(() async {
        order.add('c');
        return 3;
      }),
    ]);
    expect(order, ['a', 'b', 'c'], reason: '串行队列 FIFO，快任务不得插队');

    // 前一个任务抛错，队列不因此断掉，后续任务照常执行。
    order.clear();
    await Future.wait([
      LocalDb.write(() async {
        order.add('x');
        throw StateError('boom');
      }).then((_) {}, onError: (_) {}),
      LocalDb.write(() async {
        order.add('y');
        return 1;
      }),
    ]);
    expect(order, ['x', 'y'], reason: '异常只影响本任务，队列继续');
  });

  // ============================================================ 维度四 版本迁移

  test('迁移·损坏文档隔离：解析失败按空数据运行、原文存隔离键可找回', () async {
    SharedPreferences.setMockInitialValues({
      LocalStoreKeys.mastery: '{坏掉的 json',
      LocalStoreKeys.attempts: jsonEncode([{'quiz_id': 'q1'}]),
    });
    LocalDb.reloadForTest();
    await LocalDb.ensure();

    // 内存按空数据继续，应用不崩。
    expect(LocalDb.mastery, isEmpty);
    expect(LocalDb.attempts.length, 1, reason: '正常文档不受影响');
    final ov = LocalInsight.overview(routeA);
    expect(ov['has_data'], isTrue, reason: '有作答记录即有数据，分析页可正常出数');

    // 原文隔离保存，可手动找回。
    final prefs = await SharedPreferences.getInstance();
    final quarantined =
        prefs.getString(LocalStoreKeys.corruptKey(LocalStoreKeys.mastery));
    expect(quarantined, '{坏掉的 json', reason: '损坏原文不得静默丢弃');
    // 隔离键不进备份（备份只含七份文档与 reader_* 键）。
    final raw = await DataCompat.exportJson();
    expect(raw.contains('坏掉的 json'), isFalse);

    // 修复盘上的文档 → 重启读回，数据恢复。
    await prefs.setString(
        LocalStoreKeys.mastery,
        jsonEncode({routeA: {nodeA1: {'score': 0.9, 'accuracy': 0.9}}}));
    await prefs.remove(LocalStoreKeys.corruptKey(LocalStoreKeys.mastery));
    LocalDb.reloadForTest();
    await LocalDb.ensure();
    expect(LocalDb.masteryFor(routeA)[nodeA1]['score'], 0.9);
  });

  test('迁移·模型反序列化容错：缺字段补默认、空对象不抛错', () {
    final entry = MasteryEntry.fromJson({'node_id': 'n1'});
    expect(entry.nodeId, 'n1');
    expect(entry.level, 'unseen');
    expect(entry.score, 0.0);

    final prof = Profile.fromJson({});
    expect(prof.routeId, '');
    expect(prof.abilityRadar, isEmpty);
    expect(prof.weakPoints, isEmpty);
    expect(prof.masteryDistribution, isEmpty);
    expect(prof.summary, '');
    expect(prof.assessedNodes, 0);
    expect(prof.totalNodes, 0);

    final sec = RouteSection.fromJson({'id': 's1'});
    expect(sec.status, 'locked');
    expect(sec.masteryScore, 0.0);
    expect(sec.unlockThreshold, 0.8);
    expect(sec.hasBank, isTrue);
    expect(sec.prevCompleted, isTrue);
    expect(sec.inRoute, isTrue);
    expect(sec.routeId, isNull);

    final route = LearningRoute.fromJson({});
    expect(route.id, '');
    expect(route.sharesFoundation, isFalse);

    final q = QuizItem.fromJson({'id': 'q1'});
    expect(q.difficulty, 0.5);
    expect(q.options, isEmpty);
    expect(q.subjective, isFalse);
    expect(q.authorityStatus, 'reviewed');

    final w = WeakPoint.fromJson({'node_id': 'x'});
    expect(w.score, 0.0);
    expect(w.blockingSections, 0);
    expect(w.sectionId, '');

    final rv = ReviewItem.fromJson({});
    expect(rv.nodeId, '');
    expect(rv.kind, '');
    expect(rv.elapsedDays, 0.0);
  });

  test('迁移·DataCompat.run 幂等：schema 登记一次，第二次运行不再改动',
      () async {
    SharedPreferences.setMockInitialValues({});
    LocalDb.reloadForTest();
    await LocalDb.ensure();
    LocalDb.settings['data_schema'] = 1;
    await LocalDb.flushKey('settings');

    await DataCompat.run();
    expect(LocalDb.settings['data_schema'], DataCompat.schema);
    final firstUpdated = LocalDb.settings['data_schema_updated_at'];
    expect(firstUpdated, isNotNull);

    await DataCompat.run();
    expect(LocalDb.settings['data_schema'], DataCompat.schema);
    expect(LocalDb.settings['data_schema_updated_at'], firstUpdated,
        reason: '第二遍幂等，不得重复登记或改写时间');
    // 已有数据不被迁移触碰。
    expect(LocalDb.mastery, isEmpty);
  });

  test('迁移·旧 schema 备份兼容导入：data_schema=1 的备份可正常恢复',
      () async {
    addAttempt(nodeId: nodeA1, quizId: 'q_old', isCorrect: true, score: 1.0);
    await LocalDb.flushKey('attempts');
    final backup = await DataCompat.exportJson();
    final parsed = jsonDecode(backup) as Map<String, dynamic>;
    parsed['data_schema'] = 1; // 老版本备份

    LocalDb.attempts.clear();
    await DataCompat.importJson(jsonEncode(parsed));
    expect(LocalDb.attempts.length, 1);
    expect(LocalDb.attempts.first['quiz_id'], 'q_old');
  });

  // ============================================================ 维度五 可视化精度

  test('精度·历史排序按时刻：混合 Z/毫秒/无时区格式不排错序', () async {
    await OfflineContent.ensureQuiz();
    // 同一时刻的三种写法 + 一个更晚时刻 + 一个更早时刻。
    final naiveSame = naiveLocal(DateTime.utc(2026, 3, 1, 9, 0, 0));
    addAttempt(nodeId: nodeA1, quizId: 'q_e',
        createdAt: '2026-02-28T23:59:59Z'); // 最早
    addAttempt(nodeId: nodeA1, quizId: 'q_b',
        createdAt: '2026-03-01T09:00:00Z'); // 并列（与 c/d 同时刻）
    addAttempt(nodeId: nodeA1, quizId: 'q_c',
        createdAt: '2026-03-01T09:00:00.000Z'); // 与 b 同时刻
    addAttempt(nodeId: nodeA1, quizId: 'q_d',
        createdAt: naiveSame); // 与 b/c 同时刻（本地墙钟写法）
    addAttempt(nodeId: nodeA1, quizId: 'q_a',
        createdAt: '2026-03-01T09:00:00.500Z'); // 最晚

    final items = LocalQuiz.history()['items'] as List;
    expect(items.map((e) => e['quiz_id']).toList(),
        ['q_a', 'q_b', 'q_c', 'q_d', 'q_e'],
        reason: '倒序按时刻；并列按 quiz_id 升序；无时区写法与 Z 写法归一比较');
  });

  test('精度·激励与错题本排序按时刻：混合格式下最近/最新选取不偏移', () {
    final now = DateTime.now().toUtc();
    // 12 条作答：最近 10 条全对、更早 2 条错误；一半用 Z 写法、一半用无时区写法。
    for (var i = 0; i < 12; i++) {
      final t = now.subtract(Duration(hours: i));
      final iso = i % 2 == 0
          ? t.toIso8601String()
          : naiveLocal(t);
      addAttempt(
        nodeId: nodeA1,
        quizId: 'm_$i',
        isCorrect: i < 10,
        score: i < 10 ? 1.0 : 0.0,
        createdAt: iso,
      );
    }
    final mot = LocalInsight.motivation(routeA);
    expect(mot['total_attempts'], 12);
    expect(mot['avg_recent_accuracy'], 1.0,
        reason: '最近 10 条应恰好是较新的 10 条（全对），格式差异不得影响选取');

    // 错题本：三条错误作答，最新一条用无时区写法，仍须排最前。
    LocalDb.attempts.clear();
    final t = DateTime.now().toUtc();
    addAttempt(nodeId: nodeA1, quizId: 'w_old', isCorrect: false,
        createdAt: t.subtract(const Duration(hours: 3)).toIso8601String());
    addAttempt(nodeId: nodeA2, quizId: 'w_mid', isCorrect: false,
        createdAt: naiveLocal(t.subtract(const Duration(hours: 2))));
    addAttempt(nodeId: nodeA1, quizId: 'w_new', isCorrect: false,
        createdAt: t.subtract(const Duration(hours: 1)).toIso8601String());
    final wb = LocalInsight.wrongBook(routeA) as Map;
    expect(wb['count'], 3);
    expect(wb['items'].first['quiz_id'], 'w_new',
        reason: '错题本按时刻倒序，混合格式不得排错');
    expect(wb['items'].last['quiz_id'], 'w_old');
  });

  test('精度·周/月窗口边界：恰在窗口外的记录剔除、窗口内的保留', () async {
    await seed(routeA, nodeA1, accuracy: 1.0, stability: 1.0, feynman: 0.9);
    await seed(routeA, nodeA2, accuracy: 1.0, stability: 1.0, feynman: 0.9);
    final now = DateTime.now().toUtc();
    final names = {
      nodeA1: OfflineContent.node(nodeA1)!['name'] as String,
      nodeA2: OfflineContent.node(nodeA2)!['name'] as String,
    };
    // nodeA1 更新于 7 天前 +1 秒（窗口内）；nodeA2 更新于 7 天前 -1 分钟（窗口外）。
    LocalDb.masteryFor(routeA)[nodeA1]['updated_at'] =
        (now.subtract(const Duration(days: 7)).add(const Duration(seconds: 1)))
            .toIso8601String();
    LocalDb.masteryFor(routeA)[nodeA2]['updated_at'] =
        (now.subtract(const Duration(days: 7)).subtract(const Duration(minutes: 1)))
            .toIso8601String();

    final week = LocalInsight.summary(routeA, period: 'week');
    expect(week['mastered'], [names[nodeA1]],
        reason: '恰好 7 天前的边界：严格早于窗口才剔除');

    final all = LocalInsight.summary(routeA, period: 'all');
    expect(all['mastered'].toSet(), names.values.toSet());

    // 月窗口：30 天前 +1 秒在窗内、30 天前 -1 分钟在窗外。
    LocalDb.masteryFor(routeA)[nodeA1]['updated_at'] =
        (now.subtract(const Duration(days: 30)).add(const Duration(seconds: 1)))
            .toIso8601String();
    LocalDb.masteryFor(routeA)[nodeA2]['updated_at'] =
        (now.subtract(const Duration(days: 30)).subtract(const Duration(minutes: 1)))
            .toIso8601String();
    final month = LocalInsight.summary(routeA, period: 'month');
    expect(month['mastered'], [names[nodeA1]]);
  });

  test('精度·雷达与健康度取值：0-1 区间、四位小数、健康度整数口径', () async {
    await seed(routeA, nodeA1, accuracy: 0.9, stability: 1.0, feynman: 0.9);
    await seed(routeA, nodeA2, accuracy: 0.7, feynman: 0.9);

    final ov = LocalInsight.overview(routeA);
    final radar = ov['ability_radar'] as Map;
    expect(radar.length, 5, reason: '分析页恒定五维');
    for (final v in radar.values) {
      expect(v, isA<num>(), reason: '雷达值必须是数值');
      expect(v, greaterThanOrEqualTo(0.0));
      expect(v, lessThanOrEqualTo(1.0), reason: '雷达值在 0-1 区间');
      final r4 = (v * 10000).round() / 10000;
      expect(r4 - v, lessThanOrEqualTo(1e-9),
          reason: '雷达值保留四位小数（round4 口径）');
    }

    final prof = LocalInsight.profile(routeA);
    for (final v in (prof['ability_radar'] as Map).values) {
      expect(v, isA<num>());
      expect(v, greaterThanOrEqualTo(0.0));
      expect(v, lessThanOrEqualTo(1.0));
    }

    final health = ov['health_score'];
    expect(health, isA<int>(), reason: '健康度为整数分值');
    expect(health, greaterThanOrEqualTo(0));
    expect(health, lessThanOrEqualTo(100));
  });
}
