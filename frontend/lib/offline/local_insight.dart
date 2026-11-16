// 学情档案 / 推荐 / 激励 / 分析（单机版）
// 对应 backend/services/{profile,recommendation,motivation,analytics,calibration}_service.py
import 'dart:math' as math;

import '../offline/offline_content.dart';
import 'local_db.dart';
import 'local_mastery.dart';


class LocalInsight {
  LocalInsight._();

  // ------------------------------------------------------------ 档案
  static Map<String, dynamic> profile(String routeId) {
    final mastery = LocalMastery.masteryMap(routeId);
    final radar = <String, List<double>>{for (final d in kDims) d: <double>[]};
    final dist = <String, int>{for (final lv in kLevels) lv: 0};
    final weak = <Map<String, dynamic>>[];
    for (final n in OfflineContent.allNodes) {
      final nodeId = '${n['id']}';
      final dim = '${n['ability_dim'] ?? ''}';
      final rec = mastery[nodeId] as Map<String, dynamic>?;
      final score = dnum(rec?['score']);
      radar[dim]?.add(score);
      final lv = rec == null ? 'unseen' : '${rec['level'] ?? 'unseen'}';
      dist[lv] = (dist[lv] ?? 0) + 1;
      if (rec == null) continue;
      if (score >= 0.8) continue;
      final examWeight = dnum(n['exam_weight'], 1.0);
      weak.add({
        'node_id': nodeId,
        'name': n['name'],
        'score': score,
        'level': rec['level'],
        'section_id': n['section_id'],
        'error_category':
            '${((rec['basis'] as Map?) ?? const {})['error_category'] ?? ''}',
        'blocking_sections': LocalMastery.blockingSections(nodeId),
        'dependents_count': LocalMastery.dependentsCount(nodeId),
        'impact': round4((1 - score) *
            (1 + LocalMastery.dependentsCount(nodeId)) *
            examWeight),
      });
    }
    weak.sort((a, b) => dnum(b['impact']).compareTo(dnum(a['impact'])));
    final ability = <String, dynamic>{};
    radar.forEach((dim, v) {
      if (v.isEmpty) return;
      ability[dim] = round4(v.reduce((a, b) => a + b) / v.length);
    });
    return {
      'route_id': routeId,
      'ability_radar': ability,
      'weak_points': weak.take(6).toList(),
      'mastery_distribution': dist,
      'assessed_nodes': OfflineContent.allNodes
          .where((n) => mastery.containsKey('${n['id']}'))
          .length,
      'total_nodes': OfflineContent.allNodes.length,
      'summary': summaryText(weak),
    };
  }

  static String summaryText(List<Map<String, dynamic>> weak) {
    if (weak.isEmpty) return '暂无薄弱点，继续保持！';
    final top = weak.first;
    return '当前最需补强：《${top['name']}》（掌握度 ${(100 * dnum(top['score'])).round()}%，'
        '影响后续 ${top['blocking_sections']} 章）。建议优先专项复习，再推进新章节。';
  }

  static Map<String, dynamic> summary(
      String routeId, {String period = 'week'}) {
    final mastery = LocalMastery.masteryMap(routeId);
    final mastered = <String>[];
    final reinforce = <String>[];
    final tags = <String, dynamic>{};
    for (final n in OfflineContent.allNodes) {
      final rec = mastery['${n['id']}'] as Map<String, dynamic>?;
      if (rec == null) continue;
      final score = dnum(rec['score']);
      final flags = ((rec['source_flags'] as Map?) ?? const {})
          .entries
          .where((e) => e.value == true)
          .map((e) => e.key)
          .join('+');
      final name = '${n['name']}';
      if (score >= 0.8) {
        mastered.add(name);
        tags[name] = flags.isEmpty ? 'quiz' : flags;
      } else if (score < 0.45) {
        reinforce.add(name);
        tags[name] = flags.isEmpty ? 'quiz' : flags;
      }
    }
    final nextStep = reinforce.isEmpty
        ? '进入下一章或更高阶内容'
        : '先补强《${reinforce.first}》';
    return {
      'route_id': routeId,
      'period': period,
      'mastered': mastered,
      'to_reinforce': reinforce,
      'next_step': nextStep,
      'summary': '已掌握 ${mastered.length} 项；待巩固 ${reinforce.length} 项。下一步：$nextStep。',
      'source_tags': tags,
    };
  }

  static Map<String, dynamic> nodeDetail(String nodeId, String routeId) {
    final node = OfflineContent.node(nodeId);
    if (node == null) return {'error': 'not_found', 'node_id': nodeId};
    final rec = LocalMastery.masteryMap(routeId)[nodeId] as Map<String, dynamic>?;
    final prerequisiteSatisfied = ((node['prerequisites'] as List?) ?? const [])
        .map((e) => '$e')
        .every((p) => '${(LocalMastery.masteryMap(routeId)[p] as Map?)?['level'] ?? ''}'
            .isNotEmpty);
    return {
      ...node,
      'level': rec?['level'] ?? 'unseen',
      'score': dnum(rec?['score']),
      'basis': (rec?['basis'] as Map?) ?? const {},
      'source_flags': (rec?['source_flags'] as Map?) ?? const {},
      'dependents_count': LocalMastery.dependentsCount(nodeId),
      'blocking_sections': LocalMastery.blockingSections(nodeId),
      'prerequisites_satisfied': prerequisiteSatisfied,
    };
  }

  // ------------------------------------------------------------ 推荐
  static Map<String, dynamic> nextRecommendation(String routeId,
      {String? currentSectionId}) {
    final mastery = LocalMastery.masteryMap(routeId);
    final secs = OfflineContent.sectionsOf(routeId);
    final due = LocalMastery.dueReviews(routeId);
    if (due.isNotEmpty) {
      final top = due.first;
      return {
        'rec_type': 'review',
        'target_section_id': top['section_id'],
        'target_node_id': top['node_id'],
        'reason': '《${top['name']}》保持率降至 ${(100 * dnum(top['retention'])).round()}%，先复习抗遗忘',
      };
    }
    for (final sec in secs) {
      final sid = '${sec['id']}';
      final prog = LocalMastery.sectionProgress(routeId, sid, mastery);
      if (inum(prog['assessed']) > 0 && prog['completed'] != true) {
        return {
          'rec_type': 'reinforce',
          'target_section_id': sid,
          'target_node_id': '',
          'reason': '《${sec['title']}》掌握度 ${(100 * dnum(prog['score'])).round()}%，'
              '未达 ${(100 * dnum(prog['threshold'])).round()}% 门槛',
        };
      }
    }
    for (final sec in secs) {
      final sid = '${sec['id']}';
      if (sid == currentSectionId) continue;
      final prog = LocalMastery.sectionProgress(routeId, sid, mastery);
      if (prog['completed'] == true) continue;
      return {
        'rec_type': currentSectionId == null ? 'start' : 'next_section',
        'target_section_id': sid,
        'target_node_id': '',
        'reason': '建议继续《${sec['title']}》，按三阶段顺序推进',
      };
    }
    return {
      'rec_type': 'done',
      'target_section_id': currentSectionId ?? '',
      'target_node_id': '',
      'reason': '该路线已全部达标，可进入更高阶学习或复习巩固',
    };
  }

  static Map<String, dynamic> today(String routeId) =>
      {'recommendation': nextRecommendation(routeId)};

  static Map<String, dynamic> weakTop(String routeId, {int n = 5}) {
    final weak = ((profile(routeId)['weak_points'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList()
        .take(n)
        .toList();
    for (final w in weak) {
      w['statement'] = inum(w['blocking_sections']) > 0
          ? '阻塞后续 ${w['blocking_sections']} 章'
          : '同章内薄弱';
    }
    return {'weak_points': weak};
  }

  // ------------------------------------------------------------ 激励
  static int streakOf(List<Map<String, dynamic>> attempts) {
    final days = attempts
        .map((a) => parseTime(a['created_at']))
        .whereType<DateTime>()
        .map((t) => DateTime.utc(t.year, t.month, t.day))
        .toSet();
    var cur = DateTime.now().toUtc();
    cur = DateTime.utc(cur.year, cur.month, cur.day);
    var streak = 0;
    while (days.contains(cur)) {
      streak++;
      cur = cur.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static Map<String, dynamic> motivation(String routeId) {
    final now = DateTime.now().toUtc();
    final since = now.subtract(const Duration(days: 14));
    final signals = LocalDb.signals
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .where((s) {
          final t = parseTime(s['created_at']);
          return t != null && !t.isBefore(since);
        })
        .toList();
    final attempts = LocalDb.attempts
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList()
      ..sort((a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));
    final recent =
        attempts.length > 10 ? attempts.sublist(attempts.length - 10) : attempts;
    final avgRecent = recent.isEmpty
        ? null
        : recent.where((a) => a['is_correct'] == true).length / recent.length;
    final mastery = LocalMastery.masteryMap(routeId);
    var mastered = 0;
    for (final n in OfflineContent.allNodes) {
      if ('${(mastery['${n['id']}'] as Map?)?['level'] ?? ''}' == 'mastered') {
        mastered++;
      }
    }
    final dueCount = LocalMastery.dueReviews(routeId).length;
    final struggleLoad = math.min(
        1.0, signals.fold<double>(0.0, (a, s) => a + dnum(s['intensity'])) / 3.0);
    final accPart = avgRecent == null ? 0.0 : (1.0 - avgRecent);
    final backlogPart = (dueCount / 10.0).clamp(0.0, 1.0);
    final frustration =
        round4((0.5 * struggleLoad + 0.35 * accPart + 0.15 * backlogPart)
            .clamp(0.0, 1.0));
    final level = frustration >= 0.6 ? 'high' : (frustration >= 0.35 ? 'mid' : 'low');
    final drivers = <String>[];
    if (struggleLoad >= 0.4) drivers.add('对话中反复卡顿（${signals.length} 次）');
    if (avgRecent != null && avgRecent < 0.6) {
      drivers.add('近期正确率偏低（${(avgRecent * 100).round()}%）');
    }
    if (dueCount >= 5) drivers.add('待复习积压 $dueCount 项');
    final streak = streakOf(attempts);
    final milestones = <Map<String, dynamic>>[];
    for (final step in [1, 3, 6, OfflineContent.allNodes.length]) {
      milestones.add({
        'key': 'master_$step',
        'label': '贯通 $step 个知识点',
        'achieved': mastered >= step,
      });
    }
    for (final step in [3, 7]) {
      milestones.add({
        'key': 'streak_$step',
        'label': '连续学习 $step 天',
        'achieved': streak >= step,
      });
    }
    for (final step in [10, 25, 50]) {
      milestones.add({
        'key': 'attempts_$step',
        'label': '累计作答 $step 题',
        'achieved': attempts.length >= step,
      });
    }
    return {
      'route_id': routeId,
      'frustration': {'level': level, 'score': frustration, 'drivers': drivers},
      'encouragement': _encourage(level, avgRecent, mastered),
      'avg_recent_accuracy': avgRecent == null ? null : round4(avgRecent),
      'mastered': mastered,
      'due_count': dueCount,
      'streak_days': streak,
      'total_attempts': attempts.length,
      'milestones': milestones,
      'next_best_action': _nextBest(level, mastery, dueCount, avgRecent),
    };
  }

  static String _encourage(String level, double? avgRecent, int mastered) {
    if (level == 'high') {
      return '别急，卡住的时候正是大脑在重新布线。先把目标缩小：挑一个已经会的知识点快速复习，'
          '找回手感，再回来啃难点——进步往往藏在「再来一次」里。';
    }
    if (level == 'mid') {
      if (avgRecent != null && avgRecent >= 0.7) {
        return '节奏在变好，最近的正确率说明方法有效。保持这种小步快跑的节奏，难点会一个个攻下来。';
      }
      return '遇到一点阻力很正常。把注意力放在「今天弄懂一个概念」而不是「一次全懂」，累积会带来质变。';
    }
    if (mastered > 0) {
      return '进展顺利，你已经贯通 $mastered 个知识点，乘胜追击，把相邻的薄弱点也拿下。';
    }
    return '开局不错，保持好奇和追问。理解马克思的问题意识，比记住结论更重要。';
  }

  static Map<String, dynamic> _nextBest(String level,
      Map<String, dynamic> mastery, int dueCount, double? avgRecent) {
    if (level == 'high') {
      for (final n in OfflineContent.allNodes) {
        final lv = '${(mastery['${n['id']}'] as Map?)?['level'] ?? ''}';
        if (lv == 'proficient' || lv == 'mastered') {
          return {
            'kind': 'easy_win',
            'node_id': n['id'],
            'label': '快速复习《${n['name']}》找回手感',
            'reason': '受挫时先用已掌握内容重建信心，再挑战难点',
          };
        }
      }
      return {
        'kind': 'break',
        'label': '先休息 5 分钟',
        'reason': '连续受挫时短暂离开有助于恢复专注与情绪',
      };
    }
    if (dueCount > 0) {
      return {
        'kind': 'light_review',
        'label': '做一轮交错复习（$dueCount 项到期）',
        'reason': '先清掉遗忘积压，避免越学越乱',
      };
    }
    if (avgRecent != null && avgRecent >= 0.8) {
      return {
        'kind': 'keep_going',
        'label': '推进下一节或新知识点',
        'reason': '掌握扎实，可以适度加大挑战',
      };
    }
    return {
      'kind': 'reinforce',
      'label': '回补当前最薄弱的知识点',
      'reason': '先把地基夯实，再向上搭建',
    };
  }

  // ------------------------------------------------------------ 分析
  static Map<String, dynamic> overview(String routeId, {int streakDays = 14}) {
    final mastery = LocalMastery.masteryMap(routeId);
    final nodes = OfflineContent.allNodes;
    final dist = <String, int>{for (final lv in kLevels) lv: 0};
    final radar = <String, List<double>>{for (final d in kDims) d: <double>[]};
    var assessed = 0;
    for (final n in nodes) {
      final rec = mastery['${n['id']}'] as Map<String, dynamic>?;
      final lv = rec == null ? 'unseen' : '${rec['level'] ?? 'unseen'}';
      dist[lv] = (dist[lv] ?? 0) + 1;
      if (rec != null) {
        assessed++;
        // 没有记录就不该给该维度记 0 分：否则「能力短板」会把唯物论
        // 判成 0% 最弱（全新用户根本没测过）。
        radar['${n['ability_dim'] ?? ''}']?.add(dnum(rec['score']));
      }
    }
    final status = LocalMastery.reviewStatus(routeId);
    final rets = (status['items'] as List)
        .whereType<Map>()
        .map((e) => (e['retention'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    final avgRetention =
        rets.isEmpty ? null : round4(rets.reduce((a, b) => a + b) / rets.length);
    final dueCount = inum(status['due_count']);
    final cal = calibration(routeId);

    final attempts = LocalDb.attempts
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    final errors = <String, int>{};
    final scores = <double>[];
    for (final a in attempts) {
      final cat = '${a['error_category'] ?? ''}';
      if (cat.isNotEmpty) errors[cat] = (errors[cat] ?? 0) + 1;
      scores.add(dnum(a['score']));
    }
    final ability = <String, dynamic>{};
    radar.forEach((dim, v) {
      if (v.isEmpty) return;
      ability[dim] = round4(v.reduce((a, b) => a + b) / v.length);
    });
    String? weakestDim;
    double? weakestScore;
    ability.forEach((dim, v) {
      final s = dnum(v);
      if (weakestScore == null || s < weakestScore!) {
        weakestScore = s;
        weakestDim = dim;
      }
    });
    final avgScore =
        scores.isEmpty ? null : round4(scores.reduce((a, b) => a + b) / scores.length);
    final streak = streakOf(attempts);

    final masteryRatio = ((dist['proficient'] ?? 0) + (dist['mastered'] ?? 0)) /
        math.max(1, nodes.length);
    final retentionPart =
        math.max(0.0, (avgRetention ?? 1.0) - math.min(0.5, dueCount * 0.05));
    final calPart = {
          'calibrated': 1.0,
          'underconfident': 0.7,
          'overconfident': 0.5,
        }['${cal['verdict']}'] ??
        0.6;
    // 健康度：只对「真有数据」的维度加权，缺数据不补满分。
    //
    // 早先实现里 avgRetention 为空 → retentionPart 取 1.0、avgScore 为空 →
    // accPart 取 1.0，于是**一次题都没做**的新用户也拿到 54 分「学习健康度」，
    // 这是纯白送的分数，既不科学也误导。现在改为：无数据的维度直接不进权重，
    // 权重按剩余维度重新归一；连掌握面都没有（无作答、无评估）时健康度给 0，
    // 并由 has_data 让界面显示「暂无数据」而不是一个假的分数。
    final parts = <(double, double)>[
      (0.40, masteryRatio),
      if (avgRetention != null) (0.25, retentionPart),
      if ('${cal['verdict']}' != 'unknown') (0.15, calPart),
      if (avgScore != null) (0.20, avgScore),
    ];
    final wSum = parts.fold<double>(0, (a, p) => a + p.$1);
    final health = wSum <= 0
        ? 0
        : (100 * parts.fold<double>(0, (a, p) => a + p.$1 * p.$2) / wSum)
            .round()
            .clamp(0, 100);
    final hasData = assessed > 0 || attempts.isNotEmpty;

    return {
      'route_id': routeId,
      'total_nodes': nodes.length,
      'assessed_nodes': assessed,
      'mastery_distribution': dist,
      'mastered': dist['mastered'] ?? 0,
      'avg_retention': avgRetention,
      'due_count': dueCount,
      'calibration': {
        'n': cal['n'] ?? 0,
        'verdict': cal['verdict'],
        'gap': (cal['overall'] as Map?)?['gap'],
        'tip': cal['tip'],
      },
      'error_breakdown': errors,
      'ability_radar': ability,
      'weakest_dim': {'dim': weakestDim, 'score': weakestScore},
      'total_attempts': attempts.length,
      'avg_score': avgScore,
      'streak_days': streak,
      'health_score': health,
      'has_data': hasData,
    };
  }

  /// 元认知校准：自评把握度 vs 实测正确率
  static Map<String, dynamic> calibration(String routeId) {
    final calCfg =
        ((OfflineContent.config['calibration']) as Map?)?.cast<String, dynamic>() ??
            const {};
    final confMap = ((calCfg['confidence_map'] as Map?) ?? const {
      'low': 0.3,
      'mid': 0.6,
      'high': 0.9,
    }).map((k, v) => MapEntry('$k', dnum(v)));
    final gapLimit = dnum(calCfg['overconfident_gap'], 0.25);
    final rows = LocalDb.attempts
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .where((a) => confMap.containsKey('${a['confidence'] ?? ''}'.toLowerCase()))
        .toList();
    if (rows.isEmpty) {
      return {
        'n': 0,
        'verdict': 'unknown',
        'overall': {'expected': 0.0, 'actual': 0.0, 'gap': 0.0},
        'buckets': <String, dynamic>{},
        'tip': '先完成几次自评把握度的测验，这里会给出元认知校准建议。',
        'available': false,
      };
    }
    final buckets = <String, dynamic>{};
    var sumE = 0.0;
    var sumA = 0.0;
    var n = 0;
    for (final key in confMap.keys) {
      final bucket = rows
          .where((a) => '${a['confidence'] ?? ''}'.toLowerCase() == key)
          .toList();
      if (bucket.isEmpty) continue;
      final exp = confMap[key]!;
      final act = bucket.where((a) => a['is_correct'] == true).length /
          bucket.length;
      buckets[key] = {
        'n': bucket.length,
        'expected': round4(exp),
        'actual': round4(act),
        'gap': round4(exp - act),
      };
      sumE += exp * bucket.length;
      sumA += act * bucket.length;
      n += bucket.length;
    }
    final exp = n > 0 ? sumE / n : 0.0;
    final act = n > 0 ? sumA / n : 0.0;
    final gap = exp - act;
    String verdict;
    String tip;
    if (gap > gapLimit) {
      verdict = 'overconfident';
      tip = '你对自己的把握偏高，部分「觉得会」的题实际错了；建议对存疑点先自测再下结论。';
    } else if (gap < -gapLimit) {
      verdict = 'underconfident';
      tip = '你实际掌握得比自评好，可以更有信心；不必过度复核。';
    } else {
      verdict = 'calibrated';
      tip = '自评与实测大体一致，元认知较准确，保持这种「知之为知之」的判断。';
    }
    return {
      'n': n,
      'verdict': verdict,
      'overall': {'expected': round4(exp), 'actual': round4(act), 'gap': round4(gap)},
      'buckets': buckets,
      'tip': tip,
      'available': true,
    };
  }

  /// 错题本：只看错题，按章节聚合
  static Map<String, dynamic> wrongBook(String routeId, {int limit = 60}) {
    final rows = LocalDb.attempts
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .where((a) => a['is_correct'] != true)
        .toList()
      ..sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final r in rows) {
      final qid = '${r['quiz_id'] ?? ''}';
      if (qid.isNotEmpty && !seen.add(qid)) continue; // 同一题只留最新一条
      final node = OfflineContent.node('${r['node_id']}');
      out.add({
        ...r,
        'node_name': '${node?['name'] ?? ''}',
        'section_id': '${node?['section_id'] ?? ''}',
        'source_chunk_id': r['source_chunk_id'] ?? node?['source_chunk_id'] ?? '',
      });
      if (out.length >= limit) break;
    }
    return {'route_id': routeId, 'items': out, 'count': out.length};
  }

  /// 允许用户重判一道主观/应用题（申诉）：本机只记一笔，不改分
  static Map<String, dynamic> appeal(String testId, String itemId, String reason) {
    final test = LocalDb.tests[testId];
    final appeals =
        (test is Map ? (test['appeals'] as List?) : null) ?? const [];
    final list = [...appeals, {
      'item_id': itemId,
      'reason': reason,
      'created_at': nowIso(),
      'status': 'recorded',
    }];
    if (test is Map) {
      test['appeals'] = list;
      LocalDb.tests[testId] = test;
      LocalDb.flushKey('tests');
    }
    return {
      'status': 'recorded',
      'message': '申诉已在本机记录；单机版不改变既有评分，建议对照原文自行复核。',
      'test_id': testId,
      'item_id': itemId,
      'count': list.length,
    };
  }
}
