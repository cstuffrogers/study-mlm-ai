// 测验（单机版）：对应 backend/services/quiz_service.py
// 语义一致点：只出带 source_chunk_id 的题（正统性门禁）；只有 official 题
// （authority_status == reviewed 且非 trial_only）计入正式掌握度；
// 主观题/应用题走三维 rubric 给建议不代写。
import 'dart:math' as math;

import '../offline/local_api_exception.dart';
import '../offline/local_guard.dart';
import '../offline/offline_content.dart';
import 'local_db.dart';
import 'local_mastery.dart';

class LocalQuiz {
  LocalQuiz._();

  static Map<String, dynamic> publicItem(Map<String, dynamic> it) => {
        'id': it['id'],
        'node_id': it['node_id'],
        'type': it['type'],
        'stem': it['stem'],
        'options': it['options'] ?? const [],
        'difficulty': it['difficulty'] ?? 0.5,
        'difficulty_band': bandOf(it),
        'subjective': it['subjective'] ?? false,
        'application': it['application'] ?? (it['type'] == 'application'),
        'source_chunk_id': it['source_chunk_id'] ?? '',
        'authority_status': it['authority_status'] ?? 'reviewed',
        'exempt_marked': it['exempt_marked'] ?? false,
        'trial_only': it['trial_only'] ?? false,
      };

  /// 错因内部编码 → 面向学习者的说法。
  static const Map<String, String> errorCategoryLabels = {
    'real_unknown': '真不会',
    'concept_layer_confusion': '概念层级混淆',
    'stance_deviation': '立场偏移',
    'careless': '粗心',
    'concept_application': '概念运用不准',
    'term_misuse': '术语使用不当',
  };

  static String errorLabel(String code) =>
      errorCategoryLabels[code.trim()] ?? code.trim();

  /// 错因诊断句：除了标签，还要告诉学习者「错在哪、怎么改」。
  static String errorAdvice(
      Map<String, dynamic> quiz, String errCat, String chosenText) {
    switch (errCat) {
      case 'stance_deviation':
        return '所选说法偏离经典立场（含非正统话语），作答时请使用正统术语与原著原意。';
      case 'concept_layer_confusion':
        return '本题考概念辨析，把不同层次或相邻概念混在了一起；先分清概念的定义边界，再判断哪一句符合原著。';
      case 'concept_application':
        return '原理本身说得过去，但扣错了现实对象或条件；先把材料里的关键条件与原理的适用范围对齐。';
      case 'term_misuse':
        return '术语用得不准：用词偏离经典表述，建议改用原著术语重述一遍论证。';
      case 'real_unknown':
        return '这一知识点还没有真正掌握：对照下方解析回看原句，再用自己的话复述一遍原理。';
      default:
        return '';
    }
  }

  static bool isOfficial(Map<String, dynamic> it) =>
      (it['authority_status'] ?? 'reviewed') == 'reviewed' &&
      it['trial_only'] != true;

  static bool isTrialOnly(Map<String, dynamic> it) =>
      it['trial_only'] == true ||
      (it['authority_status'] ?? 'reviewed') != 'reviewed';

  // ------------------------------------------------------------ 难度分档
  /// 易 / 中 / 难三档阈值（与 `backend/services/quiz_service.py`、
  /// `backend/content/expand_quiz_bank.py` 同口径）：<0.45 易，<0.65 中，其余难。
  static const double bandEasyMax = 0.45;
  static const double bandMedMax = 0.65;

  /// 难度档位标识（`difficulty_band` 字段值）。
  /// 主观题/应用题单列 `challenge`（「拓展」）：它们难度值也很高，但若混进
  /// 「难」档，一章 12 个知识点会全被论述题占满（旧版就是 4 道同模板论述题）。
  static String bandOf(Map<String, dynamic> it) {
    final type = '${it['type'] ?? ''}';
    if (type == 'application' || it['subjective'] == true) return 'challenge';
    final d = dnum(it['difficulty'], 0.5);
    if (d < bandEasyMax) return 'easy';
    if (d < bandMedMax) return 'medium';
    return 'hard';
  }

  static const List<String> bandOrder = ['easy', 'medium', 'hard', 'challenge'];

  static String bandLabel(String band) {
    switch (band) {
      case 'easy':
        return '易';
      case 'medium':
        return '中';
      case 'hard':
        return '难';
      case 'challenge':
        return '拓展';
      default:
        return '';
    }
  }

  /// 每档出题名额：cap=12 → 易 4 / 中 4 / 难 2 / 拓展 2；cap=8 → 3/3/1/1。
  ///
  /// 拓展档留两个名额：一个案例应用题（application）+ 一个费曼自述题
  /// （error_diagnosis / subjective），两者评分维度不同，不能互相顶替。
  static Map<String, int> bandQuota(int cap) {
    final challenge = cap >= 10 ? 2 : 1;
    final rest = math.max(3, cap - challenge);
    final easy = math.max(1, (rest * 0.36).round());
    final med = math.max(1, (rest * 0.36).round());
    final hard = math.max(1, rest - easy - med);
    return {'easy': easy, 'medium': med, 'hard': hard, 'challenge': challenge};
  }

  /// 题干归一化（去所有空白）：用于「同一道题重复登记」去重。
  static String _stemKey(Map<String, dynamic> it) =>
      '${it['stem'] ?? ''}'.replaceAll(RegExp(r'\s+'), '').trim();

  // ------------------------------------------------------------ 选题
  /// 按「易 / 中 / 难 / 拓展」三档出题（D169）。
  ///
  /// 旧版只按「每知识点保底一道 + 余量顺序补齐」，结果：不看难度、同一张卷子
  /// 反复重考一模一样、题库里重复登记的题会同一卷里出现两次。现在：
  ///   ① 题干重复的只留一条；
  ///   ② 每档按名额取题（不够由别的档补）；
  ///   ③ [excludeIds]（最近两次做过的题）优先避开，[seed] 打乱档内顺序，
  ///      所以重考同一章不会原样重复。
  static List<Map<String, dynamic>> selectItems(
    List<Map<String, dynamic>> items, {
    Set<String> excludeIds = const <String>{},
    int seed = 0,
  }) {
    final minSize = inum(OfflineContent.config['quiz_size_min'], 8);
    final maxSize = inum(OfflineContent.config['quiz_size_max'], 12);

    // ① 去重（同题干只留第一条）
    final uniq = <Map<String, dynamic>>[];
    final seenStem = <String>{};
    for (final it in items) {
      final key = _stemKey(it);
      if (key.isNotEmpty && !seenStem.add(key)) continue;
      uniq.add(it);
    }

    final cap = math.max(minSize, math.min(maxSize, uniq.length));
    final quota = bandQuota(cap);
    final buckets = <String, List<Map<String, dynamic>>>{
      for (final b in bandOrder) b: <Map<String, dynamic>>[],
    };
    for (final it in uniq) {
      (buckets[bandOf(it)] ?? buckets['hard']!).add(it);
    }

    // ③ 档内：没做过（fresh）在前，各自按种子打乱
    final rnd = math.Random(seed);
    // 拓展档内部顺序：案例应用题 0、费曼自述题 1、其它 2
    int priority(Map<String, dynamic> e) {
      if ('${e['type']}' == 'application' && e['subjective'] == true) return 0;
      if (e['subjective'] == true) return 1;
      return 2;
    }

    for (final b in bandOrder) {
      final list = buckets[b]!;
      final fresh = list.where((e) => !excludeIds.contains('${e['id']}')).toList()..shuffle(rnd);
      final used = list.where((e) => excludeIds.contains('${e['id']}')).toList()..shuffle(rnd);
      fresh.sort((x, y) => priority(x) - priority(y));
      used.sort((x, y) => priority(x) - priority(y));
      buckets[b] = [...fresh, ...used];
    }
    // 拓展档「应用—费曼」交替：两个名额一人一个，评分维度互补
    final ch = buckets['challenge']!;
    final apps = ch.where((e) => priority(e) == 0).toList();
    final feyns = ch.where((e) => priority(e) == 1).toList();
    final rest = ch.where((e) => priority(e) == 2).toList();
    final merged = <Map<String, dynamic>>[];
    for (var i = 0; i < math.max(apps.length, feyns.length); i++) {
      if (i < apps.length) merged.add(apps[i]);
      if (i < feyns.length) merged.add(feyns[i]);
    }
    buckets['challenge'] = [...merged, ...rest];

    // ② 按名额取
    final chosen = <Map<String, dynamic>>[];
    final ids = <String>{};
    void take(Map<String, dynamic> it) {
      if (chosen.length >= cap) return;
      if (ids.add('${it['id']}')) chosen.add(it);
    }

    for (final b in bandOrder) {
      var n = 0;
      for (final it in buckets[b]!) {
        if (n >= (quota[b] ?? 0)) break;
        final before = chosen.length;
        take(it);
        if (chosen.length > before) n++;
      }
    }
    // 某档题不够 → 按 易→中→难→拓展 补齐
    for (final b in bandOrder) {
      for (final it in buckets[b]!) {
        if (chosen.length >= cap) break;
        take(it);
      }
    }
    return chosen;
  }

  /// 排序：易 → 中 → 难 → 拓展，档内仍按知识点轮转（避免同知识点连坐）。
  static List<Map<String, dynamic>> orderByTier(List<Map<String, dynamic>> items) {
    final out = <Map<String, dynamic>>[];
    for (final b in bandOrder) {
      out.addAll(interleaveItems(items.where((it) => bandOf(it) == b).toList()));
    }
    return out;
  }

  /// 同一章最近两次做过的题号：重考时优先换一批，不再原样重复。
  static Set<String> recentItemIds(String sectionId, {int lastTests = 2}) {
    final tests = LocalDb.tests.values
        .where((t) => '${t['section_id'] ?? ''}' == sectionId)
        .toList()
      ..sort((a, b) =>
          '${b['created_at'] ?? ''}'.compareTo('${a['created_at'] ?? ''}'));
    final out = <String>{};
    for (final t in tests.take(lastTests)) {
      for (final id in (t['item_ids'] as List?) ?? const []) {
        out.add('$id');
      }
    }
    return out;
  }

  /// 出题随机种子：同一章的考次越多，种子越不同（重考换题）。
  static int seedForSection(String sectionId) {
    final n = LocalDb.tests.values
        .where((t) => '${t['section_id'] ?? ''}' == sectionId)
        .length;
    return (sectionId.hashCode ^ (0x9E3779B9 * (n + 1))) & 0x7fffffff;
  }

  static List<Map<String, dynamic>> interleaveItems(
      List<Map<String, dynamic>> items) {
    if (items.length <= 2) return List<Map<String, dynamic>>.from(items);
    final byNode = <String, List<Map<String, dynamic>>>{};
    for (final it in items) {
      (byNode['${it['node_id'] ?? ''}'] ??= []).add(it);
    }
    if (byNode.length <= 1) return List<Map<String, dynamic>>.from(items);
    final out = <Map<String, dynamic>>[];
    var idx = 0;
    while (out.length < items.length) {
      var progressed = false;
      for (final bucket in byNode.values) {
        if (idx < bucket.length) {
          out.add(bucket[idx]);
          progressed = true;
        }
      }
      if (!progressed) break;
      idx++;
    }
    if (out.length != items.length) return List<Map<String, dynamic>>.from(items);
    // 与后端 `_interleave_items()` 同口径：轮转后若仍有相邻同节点（某节点题多时
    // 会出现），做一次局部交换修正。早先缺这段，两端同题不同序。
    String nodeOf(Map<String, dynamic> it) => '${it['node_id'] ?? ''}';
    for (var i = 1; i < out.length; i++) {
      if (nodeOf(out[i]) != nodeOf(out[i - 1])) continue;
      for (var j = i + 1; j < out.length; j++) {
        final okLeft = nodeOf(out[j]) != nodeOf(out[i - 1]);
        final okRight = j + 1 >= out.length || nodeOf(out[j + 1]) != nodeOf(out[i]);
        if (okLeft && okRight) {
          final tmp = out[i];
          out[i] = out[j];
          out[j] = tmp;
          break;
        }
      }
    }
    return out;
  }

  static Future<Map<String, dynamic>> start(
      String sectionId, String routeId) async {
    await OfflineContent.ensureQuiz();
    await LocalDb.ensure();
    final raw = OfflineContent.quizItems(sectionId);
    // 与后端 `_public_item()` 同红线：无溯源 chunk_id 的题**拒绝出题**，
    // 不得静默过滤后照常开考（那等于悄悄放行未溯源题）。
    for (final it in raw) {
      if ('${it['source_chunk_id'] ?? ''}'.isEmpty) {
        throw LocalApiException(422,
            '题目 ${it['id']} 缺少溯源 chunk_id，拒绝出题');
      }
    }
    final items = List<Map<String, dynamic>>.from(raw);
    if (items.isEmpty) {
      // D135：无题库章在联网侧是 409（`OrthodoxyViolation` → HTTPException(409)），
      // 单机原先回 200 + 空 items，界面于是开出一张没有题的测验；对齐成抛 409。
      throw LocalApiException(
          409, '章节 $sectionId 暂无题库，降级为按段落学习 + 简化测试');
    }
    final selected = orderByTier(selectItems(
      items,
      excludeIds: recentItemIds(sectionId),
      seed: seedForSection(sectionId),
    ));
    final testId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    LocalDb.tests[testId] = {
      'id': testId,
      'section_id': sectionId,
      'route_id': routeId,
      'item_ids': selected.map((e) => '${e['id']}').toList(),
      'status': 'open',
      'created_at': nowIso(),
    };
    await LocalDb.flushKey('tests');
    return {
      'test_id': testId,
      'section_id': sectionId,
      'items': selected.map(publicItem).toList(),
    };
  }

  // ------------------------------------------------------------ 摸底测
  /// 摸底测出题 —— 与后端 `quiz_service.start_diagnostic()` 同口径：
  /// 按路线章节顺序，每章取题库前 3 题，累计最多 12 题。
  ///
  /// 单机版原先直接回 `items: []`，界面就成了「点进去空的」：用户看不到一道题，
  /// 只能跳过。题库（`assets/offline/quiz.json`）本来就随包发，没理由不出题。
  static Future<Map<String, dynamic>> startDiagnostic(String routeId) async {
    await OfflineContent.ensureMeta();
    await OfflineContent.ensureQuiz();
    final picked = <Map<String, dynamic>>[];
    for (final sec in OfflineContent.sectionsOf(routeId)) {
      final sid = '${sec['id'] ?? ''}';
      if (sid.isEmpty) continue;
      // 应用题/主观题没有选项（走三维 rubric），摸底测里点进去就答不了 —— 只出选择题。
      final choice = OfflineContent.quizItems(sid)
          .where((it) => ((it['options'] as List?) ?? const []).length > 1);
      picked.addAll(choice.take(3));
    }
    if (picked.isEmpty) {
      // 该路线确实没有题库：与后端一样返回空，由界面提示可跳过（不伪造题）。
      return {
        'diag_id': null,
        'items': <Map<String, dynamic>>[],
        'note': '该路线题库建设中，可跳过摸底直接选起点',
      };
    }
    final chosen = picked.take(12).toList();
    final ids = chosen.map((e) => '${e['id']}').toList();
    return {
      'diag_id': diagIdFor(routeId, ids),
      'items': chosen.map(publicItem).toList(),
    };
  }

  /// 单机版的「诊断测试记录」不落库，直接把路线与题号编进 id（同一台设备内自洽）。
  /// 分隔符用 `~`：题号只含字母数字下划线，不会撞。
  static String diagIdFor(String routeId, List<String> itemIds) =>
      'local_diag_$routeId~${itemIds.join('~')}';

  static (String, List<String>)? parseDiagId(String diagId) {
    if (!diagId.startsWith('local_diag_')) return null;
    final parts = diagId.substring('local_diag_'.length).split('~');
    if (parts.length < 2) return null;
    return (parts.first, parts.sublist(1));
  }

  /// 摸底判定 —— 与后端 `quiz_service.submit_diagnostic()` 同口径：
  /// 逐章正确率 ≥ 解锁阈值（默认 0.8）判「可跳过」，否则为「需从该章开始」；
  /// 无题数据的章视为需从该章开始；起点 = 第一张不可跳过的章。
  static Future<Map<String, dynamic>> submitDiagnostic(
      String diagId, List<Map<String, dynamic>> answers) async {
    await OfflineContent.ensureMeta();
    await OfflineContent.ensureQuiz();
    final parsed = parseDiagId(diagId);
    if (parsed == null) {
      throw LocalApiException(404, '诊断测试不存在或已过期: $diagId');
    }
    final (routeId, itemIds) = parsed;
    final ansById = {
      for (final a in answers) '${a['item_id'] ?? ''}': '${a['answer'] ?? ''}'
    };
    // 题面（publicItem）不下发 section_id（与后端 `_public_item()` 一致），
    // 所以按路线章节反查「题号 → 章号」。
    final itemSec = <String, String>{};
    for (final sec in OfflineContent.sectionsOf(routeId)) {
      final sid = '${sec['id'] ?? ''}';
      for (final it in OfflineContent.quizItems(sid)) {
        itemSec['${it['id']}'] = sid;
      }
    }
    final secCorrect = <String, List<int>>{};
    final nodeCorrect = <String, List<int>>{};
    for (final qid in itemIds) {
      final it = OfflineContent.quiz(qid);
      if (it == null) continue;
      final ok =
          normChoice(ansById[qid] ?? '') == normChoice('${it['answer'] ?? ''}')
              ? 1
              : 0;
      final sid = itemSec[qid] ?? '';
      if (sid.isNotEmpty) (secCorrect[sid] ??= <int>[]).add(ok);
      final nid = '${it['node_id'] ?? ''}';
      if (nid.isNotEmpty) (nodeCorrect[nid] ??= <int>[]).add(ok);
    }
    final threshold =
        double.tryParse('${OfflineContent.config['unlock_threshold'] ?? 0.8}') ??
            0.8;
    String? recommendedStart;
    final order = <String>[];
    final skippable = <String>[];
    final secs = OfflineContent.sectionsOf(routeId);
    for (final sec in secs) {
      final sid = '${sec['id'] ?? ''}';
      final vals = secCorrect[sid];
      if (vals == null) {
        recommendedStart ??= sid;
        order.add(sid);
        continue;
      }
      final avg = vals.reduce((a, b) => a + b) / vals.length;
      if (avg >= threshold) {
        skippable.add(sid);
      } else {
        recommendedStart ??= sid;
        order.add(sid);
      }
    }
    final toReinforce = <Map<String, dynamic>>[];
    nodeCorrect.forEach((nodeId, vals) {
      final avg = vals.reduce((a, b) => a + b) / vals.length;
      if (avg >= threshold) return;
      final n = OfflineContent.node(nodeId);
      toReinforce.add({
        'node_id': nodeId,
        'name': '${n?['name'] ?? nodeId}',
        'reason': '摸底正确率偏低',
      });
    });
    return {
      'diag_id': diagId,
      'recommended_start':
          recommendedStart ?? (secs.isEmpty ? null : '${secs.first['id']}'),
      'order': order,
      'skippable': skippable,
      'to_reinforce': toReinforce,
    };
  }

  // ------------------------------------------------------------ 判分
  /// 客观题选项归一化 —— **必须与后端 `quiz_service._norm_choice` 同口径**：
  /// 去掉首尾空白、转大写、取第一个字符。
  ///
  /// 曾经这里是把所有空白和「. 、 。」删干净再整串比：用户答「A．」（全角点）
  /// 或「A、因为…」时后端判对、单机版判错——同一道题两个结论。
  static String normChoice(String s) {
    final t = s.trim().toUpperCase();
    return t.isEmpty ? '' : t[0];
  }

  static List<String> termsFor(String nodeId) {
    final t = OfflineContent.nodeTerms(nodeId)['terms'];
    return ((t as List?) ?? const []).map((e) => '$e').toList();
  }

  static List<String> misconceptionsFor(String nodeId) {
    final t = OfflineContent.nodeTerms(nodeId)['misconceptions'];
    return ((t as List?) ?? const []).map((e) => '$e').toList();
  }

  static String classifyError(Map<String, dynamic> quiz, String chosenText) {
    if (OfflineGuard.deviationKeywords.any(chosenText.contains)) {
      return 'stance_deviation';
    }
    final type = '${quiz['type'] ?? ''}';
    if (type == 'concept_discrimination' || type == 'error_diagnosis') {
      return 'concept_layer_confusion';
    }
    return 'real_unknown';
  }

  static Map<String, dynamic> gradeSubjective(
      Map<String, dynamic> quiz, String answer) {
    final guard = OfflineGuard.check(answer);
    final hasDeviation = OfflineGuard.deviationKeywords.any(answer.contains);
    final terminology = guard.blocked || hasDeviation ? 0.35 : 1.0;
    var logic = answer.trim().length >= 20 ? 0.9 : 0.5;
    if (['因为', '所以', '因此', '只有', '才能'].any(answer.contains)) {
      logic = math.min(1.0, logic + 0.05);
    }
    var conceptLayer = guard.blocked || hasDeviation ? 0.3 : 1.0;
    // 与后端 `_grade_subjective()` 同口径：极短作答（几乎未答）不给分，
    // 否则一个 “X” 能靠「术语没写错」拿到 ≈0.83 而被当成答对。
    var term = terminology;
    if (answer.trim().length < 10) {
      term = math.min(term, 0.2);
      logic = math.min(logic, 0.1);
      conceptLayer = math.min(conceptLayer, 0.2);
    }
    final suggestions = <String>[];
    if (term < 0.6) suggestions.add('建议使用正统术语，避免西马/修正主义话语');
    if (logic < 0.7) suggestions.add('论证偏简，建议补充"原理—推理—结论"的完整链条');
    if (conceptLayer < 0.6) suggestions.add('存在概念层次混淆，注意区分"实践"与"理论活动"');
    return {
      'terminology_orthodoxy': round4(term),
      'logic_coherence': round4(logic),
      'concept_layer': round4(conceptLayer),
      'suggestions':
          suggestions.isEmpty ? ['表述基本符合要求，可补充一个原文例证'] : suggestions,
      'score': round4((term + logic + conceptLayer) / 3),
      'stance': guard.blocked || hasDeviation ? 'block' : 'pass',
      'grading_source': 'heuristic',  // 离线本地近似评分
    };
  }

  static Map<String, dynamic> gradeApplication(
      Map<String, dynamic> quiz, String answer) {
    final nodeId = '${quiz['node_id'] ?? ''}';
    var terms = termsFor(nodeId);
    final misconceptions = misconceptionsFor(nodeId);
    if (terms.isEmpty) {
      // 概念词典没覆盖到这条节点时，退回到题干里的「引号词」，
      // 否则 concept_use 恒为 0、应用题永远判不及格（D169 新题多为新节点）。
      final m = RegExp(r'「([^」]{2,20})」').firstMatch('${quiz['stem'] ?? ''}');
      final fallback = m?.group(1) ?? '';
      if (fallback.isNotEmpty) terms = [fallback];
    }
    final hits = terms.where(answer.contains).toList();
    final conceptUse = round4(
        math.min(1.0, hits.length / math.max(1, math.min(3, terms.length))));
    var structure = 0.5;
    if (answer.trim().length >= 30) structure += 0.2;
    if (['例如', '比如', '因为', '所以', '因此', '这体现', '这说明', '可见']
        .any(answer.contains)) {
      structure += 0.2;
    }
    structure = round4(math.min(1.0, structure));
    final misHit = misconceptions.where(answer.contains).toList();
    final exempt = quiz['exempt_marked'] == true;
    final hasDeviation = OfflineGuard.deviationKeywords.any(answer.contains);
    final guard = OfflineGuard.check(answer);
    final stance = exempt || (!guard.blocked && !hasDeviation && misHit.isEmpty)
        ? 1.0
        : 0.3;
    final suggestions = <String>[];
    if (conceptUse < 0.6) {
      suggestions.add('答题较少运用核心概念，建议显式引入：${terms.take(4).join('、')}');
    }
    if (structure < 0.7) {
      suggestions.add('论证结构偏弱，建议按『原理—结合具体案例—得出结论』展开');
    }
    if (stance < 0.6) {
      suggestions.add('存在概念误用或立场偏移，注意运用正统术语（避免：'
          '${misconceptions.take(3).join('、')}）');
    }
    return {
      'structure': structure,
      'concept_use': conceptUse,
      'stance': stance,
      'matched_terms': hits,
      'suggestions':
          suggestions.isEmpty ? ['论证完整、概念运用准确，可再举一个现实例证升华'] : suggestions,
      'score': round4(0.4 * structure + 0.4 * conceptUse + 0.2 * stance),
    };
  }

  static String dominantError(
      List<Map<String, dynamic>> review, String nodeId) {
    final counts = <String, int>{};
    for (final r in review) {
      if ('${r['node_id'] ?? ''}' != nodeId && r['node_id'] != null) continue;
      final cat = '${r['error_category'] ?? ''}'.trim();
      if (cat.isEmpty) continue;
      counts[cat] = (counts[cat] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';
    var best = '';
    var bestN = 0;
    counts.forEach((k, v) {
      if (v > bestN) {
        best = k;
        bestN = v;
      }
    });
    return best;
  }

  static Map<String, dynamic> computeCalibration(
    List<Map<String, dynamic>> answers,
    Map<String, Map<String, dynamic>> quizMap,
    List<Map<String, dynamic>> review,
  ) {
    final calCfg =
        ((OfflineContent.config['calibration']) as Map?)?.cast<String, dynamic>() ??
            const {};
    final confMap = ((calCfg['confidence_map'] as Map?) ?? const {
      'low': 0.3,
      'mid': 0.6,
      'high': 0.9,
    })
        .map((k, v) => MapEntry('$k', dnum(v)));
    final gapLimit = dnum(calCfg['overconfident_gap'], 0.25);
    final correct = <String, bool>{
      for (final r in review) '${r['item_id']}': r['is_correct'] == true
    };
    final expected = <double>[];
    final actual = <double>[];
    for (final a in answers) {
      final conf = '${a['confidence'] ?? ''}'.toLowerCase();
      if (!confMap.containsKey(conf)) continue;
      final qid = '${a['item_id'] ?? ''}';
      if (!correct.containsKey(qid)) continue;
      expected.add(confMap[conf]!);
      actual.add(correct[qid]! ? 1.0 : 0.0);
    }
    if (expected.isEmpty) {
      return {'n': 0, 'available': false, 'verdict': 'unknown', 'tip': ''};
    }
    final exp = expected.reduce((a, b) => a + b) / expected.length;
    final act = actual.reduce((a, b) => a + b) / actual.length;
    final gap = exp - act;
    String verdict;
    String tip;
    if (gap > gapLimit) {
      verdict = 'overconfident';
      tip = '你对自己的把握偏高，部分"觉得会"的题实际错了；建议对存疑点先自测再下结论。';
    } else if (gap < -gapLimit) {
      verdict = 'underconfident';
      tip = '你实际掌握得比自评好，可以更有信心；不必过度复核。';
    } else {
      verdict = 'calibrated';
      tip = '自评与实测大体一致，元认知较准确，保持这种"知之为知之"的判断。';
    }
    return {
      'n': expected.length,
      'available': true,
      'overall': {
        'expected': round4(exp),
        'actual': round4(act),
        'gap': round4(gap),
      },
      'verdict': verdict,
      'tip': tip,
    };
  }

  // ------------------------------------------------------------ 提交
  static Future<Map<String, dynamic>> submit(
      String testId, List<Map<String, dynamic>> answers) async {
    await OfflineContent.ensureQuiz();
    await LocalDb.ensure();
    // D159 并发安全：从「已提交」查重到掌握度回写跨越多个 await（flush×2、
    // 每个节点一次 upsert）。两个并发提交会在 await 间隙交错：同一份测试
    // 两次都通过查重 → 重复判分与重复作答流水；同节点的稳定性增量按旧快照
    // 计算互相覆盖。整个写阶段走 LocalDb.write 串行队列，后一个提交读到的
    // 状态必是前一个写完的终态。
    return LocalDb.write(() => _submitLocked(testId, answers));
  }

  /// submit 的写阶段（调用方已持 LocalDb.write 串行锁，内部不得再进锁）。
  static Future<Map<String, dynamic>> _submitLocked(
      String testId, List<Map<String, dynamic>> answers) async {
    final raw = LocalDb.tests[testId];
    // D135：这两处原来抛裸 `Exception`，界面上拿不到状态码，只能显示
    // 「Exception: …」；后端是 404（测试不存在）/ 409（重复提交），这里对齐。
    if (raw is! Map) {
      throw LocalApiException(404, '测试不存在');
    }
    final test = raw.cast<String, dynamic>();
    if (test['status'] == 'submitted') {
      throw LocalApiException(409, '该测试已提交，请勿重复提交');
    }
    final sectionId = '${test['section_id'] ?? ''}';
    final routeId = '${test['route_id'] ?? LocalDb.routeId}';
    final itemIds =
        ((test['item_ids'] as List?) ?? const []).map((e) => '$e').toList();
    final quizMap = <String, Map<String, dynamic>>{};
    for (final it in OfflineContent.quizItems(sectionId)) {
      if (itemIds.contains('${it['id']}')) quizMap['${it['id']}'] = it;
    }
    final ansById = {for (final a in answers) '${a['item_id']}': a};
    final review = <Map<String, dynamic>>[];
    final itemScores = <double>[];
    final nodeStats = <String, Map<String, dynamic>>{};
    final attempts = <Map<String, dynamic>>[];

    Map<String, dynamic> statsFor(String nodeId, bool official) =>
        nodeStats.putIfAbsent(
            nodeId,
            () => {
                  'correct': 0,
                  'total': 0,
                  'diff_sum': 0.0,
                  'feynman': null,
                  'official': official,
                });

    for (final qid in itemIds) {
      final quiz = quizMap[qid];
      if (quiz == null) continue;
      final a = (ansById[qid] ?? const <String, dynamic>{});
      final ansText = '${a['answer'] ?? ''}';
      final official = isOfficial(quiz);
      final nodeId = '${quiz['node_id'] ?? ''}';
      final difficulty = dnum(quiz['difficulty'], 0.5);
      final isApplication =
          quiz['application'] == true || '${quiz['type']}' == 'application';
      final isSubjective = quiz['subjective'] == true;
      final st = statsFor(nodeId, official);

      void account(double score, {double? feynman}) {
        itemScores.add(score);
        st['total'] = inum(st['total']) + 1;
        st['diff_sum'] = dnum(st['diff_sum']) + difficulty;
        if (score >= 0.6) st['correct'] = inum(st['correct']) + 1;
        if (feynman != null) st['feynman'] = feynman;
      }

      if (isApplication) {
        final fb = gradeApplication(quiz, ansText);
        final score = dnum(fb['score']);
        final errCat = score >= 0.6 ? '' : 'concept_application';
        account(score);
        review.add({
          'item_id': qid,
          'node_id': nodeId,
          'stem': quiz['stem'],
          'type': quiz['type'],
          'is_correct': score >= 0.6,
          'answer': ansText,
          'explanation': quiz['explanation'] ?? '',
          'source_chunk_id': quiz['source_chunk_id'],
          'application_feedback': fb,
          'error_category': errCat,
          'error_label': errorLabel(errCat),
          'error_reason': errorAdvice(quiz, errCat, ansText),
          'exempt_marked': quiz['exempt_marked'] == true,
        });
        attempts.add({
          'node_id': nodeId,
          'quiz_id': qid,
          'test_id': testId,
          'route_id': routeId,
          'answer': ansText,
          'reference': quiz['explanation'] ?? '',
          'source_chunk_id': quiz['source_chunk_id'],
          'is_correct': score >= 0.6,
          'score': score,
          'error_category': errCat,
          'confidence': '${a['confidence'] ?? ''}',
        });
      } else if (isSubjective) {
        final fb = gradeSubjective(quiz, ansText);
        final score = dnum(fb['score']);
        final errCat = score >= 0.6 ? '' : 'term_misuse';
        account(score, feynman: score);
        review.add({
          'item_id': qid,
          'node_id': nodeId,
          'stem': quiz['stem'],
          'type': quiz['type'],
          'is_correct': score >= 0.6,
          'answer': ansText,
          'explanation': quiz['explanation'] ?? '',
          'source_chunk_id': quiz['source_chunk_id'],
          'subjective_feedback': fb,
          'error_category': errCat,
          'error_label': errorLabel(errCat),
          'error_reason': errorAdvice(quiz, errCat, ansText),
          'exempt_marked': quiz['exempt_marked'] == true,
        });
        attempts.add({
          'node_id': nodeId,
          'quiz_id': qid,
          'test_id': testId,
          'route_id': routeId,
          'answer': ansText,
          'reference': quiz['explanation'] ?? '',
          'source_chunk_id': quiz['source_chunk_id'],
          'is_correct': score >= 0.6,
          'score': score,
          'error_category': errCat,
          'confidence': '${a['confidence'] ?? ''}',
        });
      } else {
        final correct = normChoice(ansText) == normChoice('${quiz['answer']}');
        var chosenText = '';
        final options = (quiz['options'] as List?) ?? const [];
        final norm = normChoice(ansText);
        if (options.isNotEmpty && norm.isNotEmpty) {
          final idx = norm.codeUnitAt(0) - 65;
          if (idx >= 0 && idx < options.length) chosenText = '${options[idx]}';
        }
        final errCat = correct ? '' : classifyError(quiz, chosenText);
        account(correct ? 1.0 : 0.0);
        review.add({
          'item_id': qid,
          'node_id': nodeId,
          'stem': quiz['stem'],
          'type': quiz['type'],
          'options': options,
          'is_correct': correct,
          'answer': quiz['answer'],
          'answer_key': quiz['answer'],
          'chosen': chosenText,
          'explanation': quiz['explanation'] ?? '',
          'source_chunk_id': quiz['source_chunk_id'],
          'error_category': errCat,
          'error_label': errorLabel(errCat),
          'error_reason': errorAdvice(quiz, errCat, chosenText),
          'exempt_marked': quiz['exempt_marked'] == true,
          'trial_only': isTrialOnly(quiz),
        });
        attempts.add({
          'node_id': nodeId,
          'quiz_id': qid,
          'test_id': testId,
          'route_id': routeId,
          'answer': ansText,
          'reference': quiz['explanation'] ?? '',
          'source_chunk_id': quiz['source_chunk_id'],
          'is_correct': correct,
          'score': correct ? 1.0 : 0.0,
          'error_category': errCat,
          'confidence': '${a['confidence'] ?? ''}',
        });
      }
    }

    final totalScore = itemScores.isEmpty
        ? 0.0
        : round4(itemScores.reduce((a, b) => a + b) / itemScores.length);
    test['status'] = 'submitted';
    test['submitted_at'] = nowIso();
    test['total_score'] = totalScore;
    LocalDb.tests[testId] = test;
    for (final a in attempts) {
      LocalDb.attempts.add({...a, 'created_at': nowIso()});
    }
    await LocalDb.flushKey('tests');
    await LocalDb.flushKey('attempts');

    final prior = LocalMastery.masteryMap(routeId);
    final masteryOut = <Map<String, dynamic>>[];
    for (final entry in nodeStats.entries) {
      final st = entry.value;
      if (st['official'] != true) continue;
      final total = inum(st['total']);
      final correct = inum(st['correct']);
      final accuracy = total > 0 ? correct / total : 0.0;
      final difficulty =
          total > 0 ? round4(dnum(st['diff_sum']) / total) : 0.5;
      final priorBasis =
          ((prior[entry.key] as Map?)?['basis'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
      final priorStability = dnum(priorBasis['stability']);
      final stability = math.min(
          1.0, math.max(0.0, priorStability + (accuracy >= 0.999 ? 0.3 : -0.1)));
      final patch = <String, dynamic>{
        'accuracy': round4(accuracy),
        'difficulty': difficulty,
        'stability': round4(stability),
      };
      if (st['feynman'] != null) patch['feynman'] = st['feynman'];
      final domErr = dominantError(review, entry.key);
      if (domErr.isNotEmpty) patch['error_category'] = domErr;
      final rec = await LocalMastery.upsert(routeId, entry.key, patch, 'quiz',
          scheduleReview: true);
      final node = OfflineContent.node(entry.key);
      masteryOut.add({
        'node_id': entry.key,
        'name': node?['name'] ?? entry.key,
        'level': rec['level'],
        'score': rec['score'],
        'error_category': domErr,
        'section_id': node?['section_id'] ?? '',
      });
    }

    final calibration = computeCalibration(answers, quizMap, review);
    final gating = LocalMastery.computeGating(
        LocalMastery.masteryMap(routeId), routeId, sectionId);
    test['gating'] = gating;
    test['calibration'] = calibration;
    LocalDb.tests[testId] = test;
    await LocalDb.flushKey('tests');
    return {
      'test_id': testId,
      'total_score': totalScore,
      'mastery': masteryOut,
      'review': review,
      'gating': gating,
      'calibration': calibration,
    };
  }

  // ------------------------------------------------------------ 历史
  static Map<String, dynamic> history(
      {bool onlyWrong = false, int limit = 100, String? sectionId}) {
    var rows = LocalDb.attempts
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    if (onlyWrong) rows = rows.where((r) => r['is_correct'] != true).toList();
    // D136：一次提交里所有小题的 `created_at` 相同，只按时间倒序等于没定义顺序
    // （后端原为 SQL 无 tie-break，单机为不稳定排序）。并列按 quiz_id 升序，两端同式。
    rows.sort((a, b) {
      // D159：按时刻比较而非字符串——created_at 混有 `…Z` 与无时区两种格式
      // 时字符串序会排错（如 `09:00:00Z` 与 `09:00:00.500Z`）。并列仍按 quiz_id 升序。
      final c = LocalDb.compareTimeAsc(b['created_at'], a['created_at']);
      return c != 0 ? c : '${a['quiz_id']}'.compareTo('${b['quiz_id']}');
    });
    // D135：与后端 `quiz_routes.history()` 同式钳制 `max(1, min(limit, 500))`。
    // 原先 limit<=0 时单机回空表、联网回 1 条（同一次点击两种结果）。
    final lim = limit.clamp(1, 500);
    if (rows.length > lim) rows = rows.sublist(0, lim);
    final enriched = rows.map((r) {
      final test = LocalDb.tests['${r['test_id']}'] as Map?;
      final node = OfflineContent.node('${r['node_id']}');
      final quizId = '${r['quiz_id'] ?? ''}';
      final quiz = quizId.isEmpty ? null : OfflineContent.quiz(quizId);
      final errCat = '${r['error_category'] ?? ''}'.trim();
      final chosen = normChoice('${r['answer'] ?? ''}');
      String chosenText = '';
      final options = (quiz?['options'] as List?) ?? const [];
      if (chosen.isNotEmpty) {
        final idx = chosen.codeUnitAt(0) - 65;
        if (idx >= 0 && idx < options.length) chosenText = '${options[idx]}';
      }
      final sectionId = '${test?['section_id'] ?? node?['section_id'] ?? ''}';
      final sec = sectionId.isEmpty ? null : OfflineContent.sectionMeta(sectionId);
      // D167：本题是否申诉过（章节测试结果页记在 test['appeals'] 里），错题本条目标出
      final appeals = (test?['appeals'] as List?) ?? const [];
      Map? appeal;
      for (final e in appeals) {
        if (e is Map && '${e['item_id'] ?? ''}' == quizId) {
          appeal = e;
          break;
        }
      }
      return {
        ...r,
        'attempt_id': '${r['test_id'] ?? ''}/$quizId',
        'section_id': sectionId,
        'section_title': '${sec?['title'] ?? ''}',
        'node_name': '${node?['name'] ?? ''}',
        'stem': '${quiz?['stem'] ?? ''}',
        'type': '${quiz?['type'] ?? ''}',
        'options': options,
        'chosen': chosenText,
        'answer_key': '${quiz?['answer'] ?? ''}',
        'explanation':
            '${r['reference'] ?? quiz?['explanation'] ?? ''}',
        'error_label': errorLabel(errCat),
        'error_reason': quiz == null
            ? ''
            : errorAdvice(quiz, errCat, chosenText),
        'source_chunk_id': r['source_chunk_id'] ?? node?['source_chunk_id'] ?? '',
        'appealed': appeal != null,
        'appeal_reason': '${appeal?['reason'] ?? ''}',
      };
    }).toList();
    if (sectionId != null && sectionId.isNotEmpty) {
      enriched.removeWhere((r) => r['section_id'] != sectionId);
    }
    // 与后端 /api/quiz/history 同构（total / wrong / rows），
    // 前端 TestHistoryScreen 只认这套字段，早先只回 items/count 会导致错题本永远是 0。
    final wrong = enriched.where((r) => r['is_correct'] != true).length;
    return {
      'user_id': LocalDb.userId,
      'total': enriched.length,
      'wrong': wrong,
      'rows': enriched,
      'items': enriched,
      'count': enriched.length,
    };
  }

  /// 删除单条错题/作答记录（错题本删除）。
  /// [attemptId] 为 history 返回的 `attempt_id`（单机侧格式 `test_id/quiz_id`；
  /// 若记录自带 `id` 字段也兼容）。只删记录，不回滚已累积的掌握度信号。
  static Future<Map<String, dynamic>> deleteAttempt(String attemptId) async {
    // 与后端 DELETE /api/quiz/attempt/{id} 同语义：只删一条记录。
    // （同一章重复作答可能产生相同 test_id/quiz_id，不能一次抹完）
    final attempts = LocalDb.attempts;
    var idx = -1;
    for (var i = 0; i < attempts.length; i++) {
      final e = attempts[i];
      if (e is! Map) continue;
      final rec = e.cast<String, dynamic>();
      final composed = '${rec['test_id'] ?? ''}/${rec['quiz_id'] ?? ''}';
      if (composed == attemptId || '${rec['id'] ?? ''}' == attemptId) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      throw LocalApiException(404, '作答记录不存在');
    }
    attempts.removeAt(idx);
    await LocalDb.flushKey('attempts');
    return {'deleted': attemptId};
  }

  static Map<String, dynamic> listTests({int limit = 50}) {
    final out = LocalDb.tests.entries
        .where((e) => e.value is Map)
        .map((e) => (e.value as Map).cast<String, dynamic>())
        .toList();
    out.sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
    return {
      'items': out.take(limit).toList(),
      'count': out.length,
    };
  }
}
