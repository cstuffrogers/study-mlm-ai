// D162 数据深检：学习路径推进与状态联动
//
// 四个维度：
//  1. 路线推进 / 解锁状态联动：章节完成→门控→下一章节解锁；路线切换时地基章节
//     状态正确联动；guide() 不得降级已完成状态（本轮核心修复）。
//  2. 掌握度→复习→推荐联动：掌握度记录影响复习到期；复习结果影响推荐；推荐
//     不重复已掌握章节；掌握度不足时推荐巩固。
//  3. 完成 / 重置状态变更联动：标记完成影响路线状态；重置清空所有状态；
//     重新打开已完成章节不丢失状态。
//  4. 状态联动时序与竞态：连续提交不产生竞态；guide() 与 markProgress 串行安全。
//
// 离线层测试：LocalRouter 走本地 API，不依赖后端。

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_insight.dart';
import 'package:marxism_reader/offline/local_mastery.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'package:marxism_reader/services/api_client.dart';

import 'helpers/offline_assets_guard.dart';

void main() {
  if (skipWithoutOfflineAssets()) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  const routeA = 'route_A';
  const routeB = 'route_B';

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

  // ------------------------------------------------------------ 辅助

  String firstNodeSectionId() {
    for (final sec in OfflineContent.sectionsOf(routeA)) {
      final sid = '${sec['id'] ?? ''}';
      if (sid.isNotEmpty && OfflineContent.nodesOf(sid).isNotEmpty) {
        return sid;
      }
    }
    throw StateError('路线 A 无带节点的章节');
  }

  Future<(String, List<Map<String, dynamic>>)> firstChoiceSection() async {
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

  Map<String, dynamic> masteryRec(
      String nodeId, double score, DateTime updatedAt) => {
        'node_id': nodeId,
        'score': score,
        'level': score >= 0.85 ? 'mastered' : score >= 0.7 ? 'proficient' : 'learning',
        'stability': 1.0,
        'next_review_at':
            updatedAt.add(const Duration(days: 7)).toUtc().toIso8601String(),
        'last_reviewed_at': updatedAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'dialogue': null,
        'source': 'quiz',
        'attempts': 1,
        'calibration': 'unknown',
        'late': false,
        'late_rate': 0.0,
        'suc_rate': 1.0,
        'lapse_rate': 0.0,
        'visits': 1,
      };

  // ============================================================ 维度一 路线推进/解锁联动

  test('路线推进·章节完成后门控解锁下一章节', () async {
    final sid = firstNodeSectionId();
    await submitSectionQuiz(allCorrect: true);
    final gating =
        LocalMastery.computeGating(LocalMastery.masteryMap(routeA), routeA, sid);
    expect(gating['unlocked'], isTrue,
        reason: '全对提交后章节应解锁下一章');
  });

  test('路线推进·未提交测验时门控不解锁', () async {
    final sid = firstNodeSectionId();
    // 空 mastery → 不解锁
    final gating =
        LocalMastery.computeGating(LocalMastery.masteryMap(routeA), routeA, sid);
    expect(gating['unlocked'], isFalse,
        reason: '无掌握度记录时章节不应解锁');
  });

  test('路线推进·guide 不降级已完成状态（D162 核心修复）', () async {
    final sid = firstNodeSectionId();
    // 先标记章节为 completed
    LocalMastery.markProgress(routeA, sid, status: 'completed', lastPosition: 1);
    final before = LocalMastery.progressOf(routeA, sid);
    expect(before['status'], 'completed', reason: '初始状态应为 completed');

    // 打开导读 → guide() 不应把状态降级回 in_progress
    await LocalMastery.guide(routeA, sid);
    final after = LocalMastery.progressOf(routeA, sid);
    expect(after['status'], 'completed',
        reason: 'guide() 不得降级已完成状态，应保持 completed');
  });

  test('路线推进·guide 不降级 done 状态', () async {
    final sid = firstNodeSectionId();
    LocalMastery.markProgress(routeA, sid, status: 'done', lastPosition: 5);
    await LocalMastery.guide(routeA, sid);
    final after = LocalMastery.progressOf(routeA, sid);
    expect(after['status'], 'done',
        reason: 'guide() 不得降级 done 状态');
  });

  test('路线推进·guide 对未开始章节仍标记 in_progress', () async {
    final sid = firstNodeSectionId();
    // 清空进度
    LocalDb.progress[routeA] = {};
    // 打开导读 → 应标记为 in_progress
    await LocalMastery.guide(routeA, sid);
    final after = LocalMastery.progressOf(routeA, sid);
    expect(after['status'], 'in_progress',
        reason: '未开始的章节打开导读应标记 in_progress');
  });

  test('路线推进·路线切换时地基章节状态联动', () async {
    // 路线 A 第一个章节标记完成
    final aFirst = OfflineContent.sectionsOf(routeA).first['id'] as String;
    LocalMastery.markProgress(routeA, aFirst, status: 'completed', lastPosition: 1);
    // 提交测验建立 mastery
    await submitSectionQuiz(allCorrect: true);

    // 切换到路线 B
    LocalDb.routeId = routeB;
    final result = await LocalMastery.routesSections(routeB);
    final sections = result['sections'] as List<Map<String, dynamic>>;
    // 地基章节（route A 的章节在 B 路线中作为地基出现）状态应正确联动
    for (final sec in sections) {
      final sid = '${sec['id']}';
      // 地基章节的进度应来自路线 A
      if (sec['is_foundation'] == true && sid == aFirst) {
        expect(sec['status'], 'completed',
            reason: '路线 B 的地基章节应继承路线 A 的完成状态');
      }
    }
  });

  // ============================================================ 维度二 掌握度→复习→推荐联动

  test('掌握度→复习·掌握度记录产生复习到期项', () async {
    final sid = firstNodeSectionId();
    final nodes = OfflineContent.nodesOf(sid);
    final nodeId = nodes.first['id'] as String;
    final now = DateTime.now().toUtc();
    // 注入一个已过期需要复习的掌握度记录
    LocalDb.mastery[routeA] = {
      nodeId: masteryRec(nodeId, 0.9, now.subtract(const Duration(days: 10))),
    };
    final due = LocalMastery.dueReviews(routeA);
    expect(due.isNotEmpty, isTrue,
        reason: '过期掌握度记录应产生复习到期项');
    expect(due.first['node_id'], nodeId,
        reason: '复习到期项应指向该节点');
  });

  test('掌握度→复习·未到期记录不产生复习项', () async {
    final sid = firstNodeSectionId();
    final nodes = OfflineContent.nodesOf(sid);
    final nodeId = nodes.first['id'] as String;
    final now = DateTime.now().toUtc();
    // 注入一个未到期的掌握度记录（下次复习在 7 天后）
    LocalDb.mastery[routeA] = {
      nodeId: masteryRec(nodeId, 0.9, now),
    };
    final due = LocalMastery.dueReviews(routeA);
    expect(due, isEmpty,
        reason: '未到期的掌握度记录不应产生复习到期项');
  });

  test('掌握度→推荐·已掌握章节不出现在推荐中', () async {
    final sid = firstNodeSectionId();
    final nodes = OfflineContent.nodesOf(sid);
    // 对所有节点注入高分掌握度记录
    final now = DateTime.now().toUtc();
    final mastery = <String, Map<String, dynamic>>{};
    for (final n in nodes) {
      final nid = '${n['id']}';
      mastery[nid] = masteryRec(nid, 0.95, now);
    }
    LocalDb.mastery[routeA] = mastery;
    // 该章节应标记完成
    LocalMastery.markProgress(routeA, sid, status: 'completed', lastPosition: 1);

    final rec = LocalInsight.nextRecommendation(routeA, currentSectionId: sid);
    expect(rec['target_section_id'], isNot(sid),
        reason: '已掌握且已完成的章节不应被推荐');
  });

  test('掌握度→推荐·掌握度不足时推荐巩固', () async {
    final sid = firstNodeSectionId();
    final nodes = OfflineContent.nodesOf(sid);
    final now = DateTime.now().toUtc();
    // 注入低分掌握度记录（score 0.3，未达标）
    final mastery = <String, Map<String, dynamic>>{};
    for (final n in nodes) {
      final nid = '${n['id']}';
      mastery[nid] = masteryRec(nid, 0.3, now);
    }
    LocalDb.mastery[routeA] = mastery;
    // 进度标记为 in_progress（有评估但未达标）
    LocalMastery.markProgress(routeA, sid, status: 'in_progress', lastPosition: 1);

    final rec = LocalInsight.nextRecommendation(routeA, currentSectionId: null);
    // 应推荐巩固该章节（rec_type = reinforce）
    expect(rec['rec_type'], 'reinforce',
        reason: '有评估但未达标的章节应推荐巩固');
    expect(rec['target_section_id'], sid,
        reason: '巩固推荐应指向该未达标章节');
  });

  test('掌握度→推荐·有到期复习时优先推荐复习', () async {
    final sid = firstNodeSectionId();
    final nodes = OfflineContent.nodesOf(sid);
    final nodeId = nodes.first['id'] as String;
    final now = DateTime.now().toUtc();
    // 注入过期复习记录
    LocalDb.mastery[routeA] = {
      nodeId: masteryRec(nodeId, 0.9, now.subtract(const Duration(days: 10))),
    };
    final rec = LocalInsight.nextRecommendation(routeA, currentSectionId: null);
    expect(rec['rec_type'], 'review',
        reason: '有到期复习时推荐应优先返回 review');
    expect(rec['target_node_id'], nodeId,
        reason: '复习推荐应指向到期的节点');
  });

  // ============================================================ 维度三 完成/重置状态变更联动

  test('完成状态·提交测验后标记完成路线状态更新为 completed', () async {
    final sid = firstNodeSectionId();
    // 先提交全对测验（建立 mastery），再标记进度完成
    await submitSectionQuiz(allCorrect: true);
    LocalMastery.markProgress(routeA, sid, status: 'completed', lastPosition: 1);
    final result = await LocalMastery.routesSections(routeA);
    final sections = result['sections'] as List<Map<String, dynamic>>;
    final sec = sections.where((s) => '${s['id']}' == sid).first;
    expect(sec['status'], 'completed',
        reason: '提交测验+标记完成后路线状态应更新为 completed');
  });

  test('完成状态·标记 in_progress 后路线状态更新为 in_progress', () async {
    final sid = firstNodeSectionId();
    LocalMastery.markProgress(routeA, sid, status: 'in_progress', lastPosition: 1);
    final result = await LocalMastery.routesSections(routeA);
    final sections = result['sections'] as List<Map<String, dynamic>>;
    final sec = sections.where((s) => '${s['id']}' == sid).first;
    expect(sec['status'], 'in_progress',
        reason: '标记 in_progress 后路线状态应更新为 in_progress');
  });

  test('重置状态·resetAll 清空全部进度与掌握度', () async {
    final sid = firstNodeSectionId();
    LocalMastery.markProgress(routeA, sid, status: 'completed', lastPosition: 1);
    LocalDb.mastery[routeA] = {
      'node_1': masteryRec('node_1', 0.9, DateTime.now().toUtc()),
    };

    await LocalDb.resetAll();
    final progress = LocalDb.progressFor(routeA);
    expect(progress, isEmpty, reason: '重置后进度应清空');
    expect(LocalDb.mastery.isEmpty, isTrue, reason: '重置后掌握度应清空');
    expect(LocalDb.attemptsForRoute(routeA), isEmpty,
        reason: '重置后答题记录应清空');
  });

  test('完成状态·重新打开已完成章节的导读不丢失完成状态', () async {
    final sid = firstNodeSectionId();
    // 标记完成
    LocalMastery.markProgress(routeA, sid, status: 'completed', lastPosition: 1);
    // 模拟用户重新打开导读
    await LocalMastery.guide(routeA, sid);
    // 验证进度状态不被降级（核心修复）
    final prog = LocalMastery.progressOf(routeA, sid);
    expect(prog['status'], 'completed',
        reason: '重新打开导读后进度状态应保持 completed，不被降级');
  });

  // ============================================================ 维度四 时序与竞态

  test('时序竞态·连续提交两次测验不产生状态错乱', () async {
    // 第一次提交全对
    await submitSectionQuiz(allCorrect: true);
    final mastery1 = LocalDb.mastery[routeA];
    expect(mastery1, isNotEmpty, reason: '第一次提交应产生掌握度记录');

    // 第二次提交全对（同一章节）
    await submitSectionQuiz(allCorrect: true);
    final mastery2 = LocalDb.mastery[routeA];
    // 掌握度记录不应被清空
    expect(mastery2, isNotEmpty, reason: '第二次提交后掌握度记录应保留');
    for (final nid in mastery1.keys) {
      expect(mastery2.containsKey(nid), isTrue,
          reason: '节点 $nid 的掌握度记录在二次提交后应保留');
    }
  });

  test('时序竞态·guide 与 markProgress 串行不丢失状态', () async {
    final sid = firstNodeSectionId();
    // 标记完成
    LocalMastery.markProgress(routeA, sid, status: 'completed', lastPosition: 1);
    // guide() 不应降级
    await LocalMastery.guide(routeA, sid);
    final prog = LocalMastery.progressOf(routeA, sid);
    expect(prog['status'], 'completed',
        reason: 'guide() 与 markProgress 串行执行后，完成状态应保持');
  });

  test('时序竞态·guide 标记 in_progress 后再次标记 completed 不回退', () async {
    final sid = firstNodeSectionId();
    // 打开导读 → in_progress
    await LocalMastery.guide(routeA, sid);
    expect(LocalMastery.progressOf(routeA, sid)['status'], 'in_progress',
        reason: '首次打开导读应标记 in_progress');
    // 用户完成学习 → 标记 completed
    LocalMastery.markProgress(routeA, sid, status: 'completed', lastPosition: 1);
    // 再次打开导读 → 不应降级
    await LocalMastery.guide(routeA, sid);
    expect(LocalMastery.progressOf(routeA, sid)['status'], 'completed',
        reason: '完成后再打开导读不应降级回 in_progress');
  });

  test('时序竞态·提交测验后打开导读不丢失 mastery 记录', () async {
    await submitSectionQuiz(allCorrect: true);
    final sid = firstNodeSectionId();
    // 打开导读
    await LocalMastery.guide(routeA, sid);
    // 掌握度记录不应丢失
    expect(LocalDb.mastery[routeA], isNotEmpty,
        reason: 'guide() 不应影响掌握度记录');
    // 进度状态应保持（非 completed 时标记 in_progress）
    final prog = LocalMastery.progressOf(routeA, sid);
    expect(prog.isNotEmpty, isTrue, reason: '打开导读后应有进度记录');
  });
}
