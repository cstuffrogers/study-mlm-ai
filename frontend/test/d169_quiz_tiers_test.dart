// D169：章节测试按「易 / 中 / 难 / 拓展」三档出题 + 清除重复题。
//
// 用户实报「题目重复太多、根本没有易中难三个层次」。这里锁三件事：
//   1. 一套卷子三档都有，且按名额分配（不再随机/顺序补齐）；
//   2. 同题干在卷内只出一次，重考优先换一批；
//   3. 排序由易到难，题库里每章三档齐全、不含套话选项。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_quiz.dart';

Map<String, dynamic> _raw(int i, String band, {String? stem, bool subjective = false}) {
  final diff = {'easy': 0.30, 'medium': 0.50, 'hard': 0.70, 'challenge': 0.70}[band]!;
  return {
    'id': 'q_t$i',
    'section_id': 'sec_X',
    'node_id': 'kn_$i',
    'type': subjective ? 'error_diagnosis' : (band == 'challenge' ? 'application' : 'concept_discrimination'),
    'stem': stem ?? '第 $i 题',
    'options': ['a', 'b', 'c', 'd'],
    'answer': 'A',
    'explanation': '',
    'difficulty': diff,
    'source_chunk_id': 'CH-1',
    'authority_status': 'reviewed',
    'exempt_marked': false,
    'trial_only': false,
    'subjective': subjective,
  };
}

void main() {
  setUp(() {
    LocalDb.tests.clear();
  });

  test('bandOf：三档阈值 + 主观/应用单列拓展', () {
    expect(LocalQuiz.bandOf(_raw(1, 'easy')), 'easy');
    expect(LocalQuiz.bandOf(_raw(2, 'medium')), 'medium');
    expect(LocalQuiz.bandOf(_raw(3, 'hard')), 'hard');
    expect(LocalQuiz.bandOf(_raw(4, 'challenge')), 'challenge');
    // 客观题即使难度高也不算「拓展」
    expect(LocalQuiz.bandOf({'difficulty': 0.9, 'type': 'logical_deduction'}), 'hard');
    expect(LocalQuiz.bandLabel('easy'), '易');
    expect(LocalQuiz.bandLabel('challenge'), '拓展');
  });

  test('bandQuota：各档名额之和等于题量，每档至少 1', () {
    for (final cap in [8, 9, 10, 11, 12]) {
      final q = LocalQuiz.bandQuota(cap);
      expect(q.values.reduce((a, b) => a + b), cap, reason: 'cap=$cap');
      expect(q.values.every((v) => v >= 1), isTrue, reason: 'cap=$cap');
    }
    expect(LocalQuiz.bandQuota(12), {'easy': 4, 'medium': 4, 'hard': 2, 'challenge': 2});
  });

  test('selectItems：三档都有，且按名额分配', () {
    final items = <Map<String, dynamic>>[
      for (var i = 0; i < 10; i++) _raw(i, 'easy'),
      for (var i = 100; i < 110; i++) _raw(i, 'medium'),
      for (var i = 200; i < 210; i++) _raw(i, 'hard'),
      for (var i = 300; i < 303; i++) _raw(i, 'challenge', subjective: true),
    ];
    final chosen = LocalQuiz.selectItems(items, seed: 7);
    expect(chosen.length, 12);
    final counts = <String, int>{};
    for (final it in chosen) {
      counts.update(LocalQuiz.bandOf(it), (v) => v + 1, ifAbsent: () => 1);
    }
    expect(counts, LocalQuiz.bandQuota(12));
  });

  test('selectItems：同题干只出一次（卷内不重复）', () {
    final items = <Map<String, dynamic>>[
      _raw(1, 'easy', stem: '关于「实践」，下列说法正确的是？'),
      _raw(2, 'easy', stem: '关于「实践」 ， 下列说法正确的是？'), // 仅空白不同
      _raw(3, 'easy'),
    ];
    final chosen = LocalQuiz.selectItems(items, seed: 1);
    final stems = chosen.map((it) => '${it['stem']}'.replaceAll(RegExp(r'\s+'), '')).toList();
    expect(stems.length, stems.toSet().length);
  });

  test('selectItems：重考优先避开最近做过的题', () {
    final items = <Map<String, dynamic>>[for (var i = 0; i < 24; i++) _raw(i, 'easy')];
    final done = items.take(8).map((it) => '${it['id']}').toSet();
    final chosen = LocalQuiz.selectItems(items, excludeIds: done, seed: 3);
    expect(chosen.length, 12);
    expect(chosen.where((it) => done.contains('${it['id']}')).length, lessThanOrEqualTo(4));
  });

  test('orderByTier：由易到难排列', () {
    final items = <Map<String, dynamic>>[
      _raw(1, 'hard'),
      _raw(2, 'easy'),
      _raw(3, 'challenge', subjective: true),
      _raw(4, 'medium'),
    ];
    final ordered = LocalQuiz.orderByTier(items).map(LocalQuiz.bandOf).toList();
    final rank = {for (var i = 0; i < LocalQuiz.bandOrder.length; i++) LocalQuiz.bandOrder[i]: i};
    final ranks = ordered.map((b) => rank[b]!).toList();
    final sorted = [...ranks]..sort();
    expect(ranks, sorted);
  });

  test('recentItemIds / seedForSection：读取本机考次', () {
    expect(LocalQuiz.recentItemIds('sec_X'), isEmpty);
    final seed0 = LocalQuiz.seedForSection('sec_X');
    LocalDb.tests['t1'] = {
      'id': 't1',
      'section_id': 'sec_X',
      'created_at': '2026-11-25T10:00:00',
      'item_ids': ['q1', 'q2'],
      'total': 2,
      'rows': <dynamic>[],
    };
    expect(LocalQuiz.recentItemIds('sec_X'), {'q1', 'q2'});
    expect(LocalQuiz.seedForSection('sec_X'), isNot(seed0));
  });

  group('题库内容门禁（assets/offline/quiz.json）', () {
    late Map<String, dynamic> asset;
    setUpAll(() {
      final f = File('assets/offline/quiz.json');
      expect(f.existsSync(), isTrue, reason: '先跑 scripts/export_offline_assets.py');
      asset = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    });

    test('每章题库三档齐全', () {
      final missing = <String, List<String>>{};
      final sections = asset['sections'] as Map<String, dynamic>;
      sections.forEach((sec, list) {
        final bands = <String>{};
        for (final it in (list as List)) {
          bands.add(LocalQuiz.bandOf((it as Map).cast<String, dynamic>()));
        }
        final lack = ['easy', 'medium', 'hard'].where((b) => !bands.contains(b)).toList();
        if (lack.isNotEmpty) missing[sec] = lack;
      });
      expect(missing, isEmpty, reason: '这些章节缺难度层次：$missing');
    });

    test('没有重复题（题干+选项完全相同）', () {
      final seen = <String>{};
      final dups = <String>[];
      final sections = asset['sections'] as Map<String, dynamic>;
      sections.forEach((sec, list) {
        for (final it in (list as List)) {
          final m = (it as Map).cast<String, dynamic>();
          final key = '${'${m['stem']}'.replaceAll(RegExp(r'\s+'), '')}|'
              '${((m['options'] as List?) ?? const []).map((o) => '$o'.replaceAll(RegExp(r'\s+'), '')).join('~')}';
          if (!seen.add(key)) dups.add('$sec/${m['id']}');
        }
      });
      expect(dups, isEmpty, reason: '重复题：$dups');
    });

    test('选项不是套话（不看知识点也能选对的填充项）', () {
      final bad = <String>[];
      final sections = asset['sections'] as Map<String, dynamic>;
      sections.forEach((sec, list) {
        for (final it in (list as List)) {
          final m = (it as Map).cast<String, dynamic>();
          for (final o in (m['options'] as List?) ?? const []) {
            final s = '$o';
            if (s.contains('与其他概念混淆，并未准确表述其含义') ||
                (s.startsWith('认为「') && s.contains('的含义与实际定义相反')) ||
                s.contains('在学习和运用中，应当完整把握「')) {
              bad.add('$sec/${m['id']}');
            }
          }
        }
      });
      expect(bad, isEmpty, reason: '仍是套话选项：$bad');
    });
  });
}
