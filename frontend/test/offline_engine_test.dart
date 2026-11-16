// 单机版引擎冒烟测试：直接用打包进去的 assets/offline 数据跑通
// 路线 → 测验 → 判分 → 掌握度/推荐/复习 → 对话 的闭环。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_dialogue.dart';
import 'package:marxism_reader/offline/local_insight.dart';
import 'package:marxism_reader/offline/local_mastery.dart';
import 'package:marxism_reader/offline/local_quiz.dart';
import 'package:marxism_reader/offline/offline_content.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await OfflineContent.ensureMeta();
    await LocalDb.resetAll();
    LocalDb.routeId = 'route_A';
  });

  test('离线资产可加载：路线/章节/知识点', () async {
    expect(OfflineContent.routes, isNotEmpty);
    expect(OfflineContent.allSections, isNotEmpty);
    expect(OfflineContent.allNodes, isNotEmpty);
    final j = await LocalMastery.routesSections('route_A');
    final secs = (j['sections'] as List).cast<Map<String, dynamic>>();
    expect(secs, isNotEmpty);
    expect(secs.first['status'], 'unlocked');
    expect(secs.first['title'], isNotEmpty);
  });

  test('章节导读包与原文分片可读', () async {
    final secId = OfflineContent.sectionsOf('route_A').first['id'] as String;
    final g = await LocalMastery.guide('route_A', secId);
    expect(g['section_id'], secId);
    expect(g['guide'], isA<Map>());
    await OfflineContent.ensureChunks();
    final chunks = OfflineContent.chunksOfWork('关于费尔巴哈的提纲');
    expect(chunks, isNotEmpty);
    final id = chunks.first['id'] as String;
    expect(OfflineContent.chunk(id)?['text'], isNotEmpty);
  });

  test('测验闭环：出题 → 判分 → 掌握度 → 推荐 → 复习', () async {
    final sec = OfflineContent.sectionsOf('route_A')
        .firstWhere((s) => s['has_bank'] == true);
    final secId = sec['id'] as String;
    final started = await LocalQuiz.start(secId, 'route_A');
    final items = (started['items'] as List).cast<Map<String, dynamic>>();
    expect(items, isNotEmpty);
    // 全部按正确选项作答
    final answers = <Map<String, dynamic>>[];
    await OfflineContent.ensureQuiz();
    final full = {for (final q in OfflineContent.quizItems(secId)) '${q['id']}': q};
    for (final it in items) {
      final q = full['${it['id']}'];
      answers.add({
        'item_id': it['id'],
        'answer': '${q?['answer'] ?? 'A'}',
        'confidence': 'high',
      });
    }
    final res = await LocalQuiz.submit('${started['test_id']}', answers);
    expect(res['test_id'], started['test_id']);
    expect((res['review'] as List), isNotEmpty);
    final mastery = LocalMastery.masteryMap('route_A');
    expect(mastery, isNotEmpty);
    final rec = mastery.values.first as Map<String, dynamic>;
    expect((rec['score'] as num).toDouble(), greaterThan(0));
    expect(rec['level'], isNot('unseen'));
    // 复习与推荐都既能算出来，也不崩
    final status = LocalMastery.reviewStatus('route_A');
    expect(status['items'], isA<List>());
    final rec2 = LocalInsight.nextRecommendation('route_A');
    expect(rec2['rec_type'], isNotNull);
    final prof = LocalInsight.profile('route_A');
    expect(prof['mastery_distribution'], isA<Map>());
  });

  test('普通题答错 → 判错并归类，主观题按三维 rubric 给建议', () async {
    final sec = OfflineContent.sectionsOf('route_A')
        .firstWhere((s) => s['has_bank'] == true);
    final secId = sec['id'] as String;
    await OfflineContent.ensureQuiz();
    final quiz = OfflineContent.quizItems(secId);
    expect(quiz, isNotEmpty);
    final objective = quiz.firstWhere((q) => q['options'] != null &&
        (q['options'] as List).isNotEmpty &&
        q['subjective'] != true);
    final fb = LocalQuiz.gradeApplication(
      {'node_id': objective['node_id'], 'exempt_marked': false},
      '因为实践是对象性活动，例如工人改造自然界，所以这一命题成立。',
    );
    expect(fb['score'], isA<double>());
    expect(fb['suggestions'], isNotEmpty);
    final subj = LocalQuiz.gradeSubjective(
      {'node_id': objective['node_id']},
      '实践是人改造世界的对象性活动，因此认识来源于实践。',
    );
    expect(subj['score'], isA<double>());
    expect(subj['stance'], 'pass');
  });

  test('答错的客观题 → 逐题解析可显示：题面/正确答案/解析/错因 全部回填', () async {
    final sec = OfflineContent.sectionsOf('route_A')
        .firstWhere((s) => s['has_bank'] == true);
    final secId = sec['id'] as String;
    await OfflineContent.ensureQuiz();
    final started = await LocalQuiz.start(secId, 'route_A');
    final items = (started['items'] as List).cast<Map<String, dynamic>>();
    final full = {for (final q in OfflineContent.quizItems(secId)) '${q['id']}': q};

    // 客观题全部选一个必然错的选项
    final answers = <Map<String, dynamic>>[];
    for (final it in items) {
      final q = full['${it['id']}'];
      final opts = (q?['options'] as List?) ?? const [];
      var choice = 'Z';
      if (opts.length >= 2) {
        final right = '${q?['answer'] ?? 'A'}'.trim().toUpperCase();
        choice = right == 'A' ? 'B' : 'A';
      }
      answers.add({'item_id': it['id'], 'answer': choice, 'confidence': 'low'});
    }
    final res = await LocalQuiz.submit('${started['test_id']}', answers);
    final review = (res['review'] as List).cast<Map<String, dynamic>>();
    final wrongObjective = review.where((r) =>
        r['is_correct'] == false &&
        r['subjective'] != true &&
        r['application_feedback'] == null &&
        r['subjective_feedback'] == null);
    expect(wrongObjective, isNotEmpty, reason: '应至少有一道客观题答错');
    for (final r in wrongObjective) {
      expect('${r['stem'] ?? ''}'.trim(), isNotEmpty, reason: '结果页要显示题面');
      expect('${r['answer_key'] ?? ''}'.trim(), isNotEmpty, reason: '要显示正确答案');
      expect('${r['explanation'] ?? ''}'.trim(), isNotEmpty, reason: '要显示解析');
      final label = '${r['error_label'] ?? ''}'.trim();
      expect(label, isNotEmpty, reason: '错因标签不能为空（否则错因不显示）');
      expect(label.contains('_'), isFalse, reason: '错因不能显示内部编码：$label');
      expect('${r['error_reason'] ?? ''}'.trim(), isNotEmpty, reason: '要有错因诊断句');
    }

    // 错题本（历史）也必须能回填题面与解析
    final hist = LocalQuiz.history(onlyWrong: true);
    final rows = (hist['items'] as List).cast<Map<String, dynamic>>();
    expect(rows, isNotEmpty);
    final row = rows.first;
    expect('${row['stem'] ?? ''}'.trim(), isNotEmpty);
    expect('${row['error_label'] ?? ''}'.trim().contains('_'), isFalse);
  });

  test('本机对话：检索原文并给结构化相关原文，不泄露编码', () async {
    final r = await LocalDialogue.respond(
      dialogueId: 'unit',
      content: '什么是实践？为什么说旧唯物主义不懂实践？',
      paragraphId: 'th1',
      mode: 'explain',
    );
    expect(r['type'], 'ai_message');
    // 未配置在线大模型时，明确标记为本机引擎
    expect(r['engine'], 'local');
    final content = '${r['content']}';
    expect(content.contains('CH-'), false);
    expect(content.contains('原文摘录'), true);
    final src = (r['source_chunks'] as List).cast<Map<String, dynamic>>();
    expect(src, isNotEmpty);
    expect(src.first['chunk_id'], startsWith('CH-'));
    expect(src.first['kind'], 'related');
    // 历史可回放
    final msgs = LocalDialogue.listDialogues();
    expect(msgs.any((d) => d['id'] == 'unit'), true);
  });

  test('偏离表述在非批判模式下被拦截，批判模式下放行', () async {
    final blocked = await LocalDialogue.respond(
      dialogueId: 'u2',
      content: '我觉得意识决定物质，这是不是也行？',
      mode: 'explain',
    );
    expect(blocked['type'], 'blocked');
    expect(blocked['allow_critical_reading'], true);
    final allowed = await LocalDialogue.respond(
      dialogueId: 'u3',
      content: '我觉得意识决定物质，这是不是也行？',
      mode: 'explain',
      criticalReading: true,
    );
    expect(allowed['type'], 'ai_message');
  });
}
