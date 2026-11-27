// D176：一个知识点只出一道题（取消「易 / 中 / 难」分档）。
//
// 用户实报（接 D169 之后）：「所谓不同难度实际上就换了一种表述而已。」
// D169 按难度名额抽 12 题，但题库里同知识点的各档共用同一张「概念—定义」对照表，
// 换个问法而已 —— 一章 3 个知识点被问成 12 道重复题。
//
// 这里锁单机版口径（与 `backend/services/quiz_service._select_items` 一致）：
//   1. 每个知识点（node_id）只出一道，题量 = 知识点数，不再凑到 8 题；
//   2. 同题干卷内只出一次；重考换同知识点的另一道变体；
//   3. 费曼自述题每卷必出，知识点 ≥6 时再配一道应用题，均排卷末；
//   4. 题库每章都要有客观题节点 + 费曼节点，且不含套话选项。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_quiz.dart';

/// kind: objective / feyn（主观费曼）/ apply（案例应用）
Map<String, dynamic> _raw(
  int i, {
  int? node,
  String kind = 'objective',
  String? stem,
}) {
  return {
    'id': 'q_t$i',
    'section_id': 'sec_X',
    'node_id': 'kn_${node ?? i}',
    'type': kind == 'apply' ? 'application' : 'concept_discrimination',
    'stem': stem ?? '第 $i 题',
    'options': ['a', 'b', 'c', 'd'],
    'answer': kind == 'objective' ? 'A' : '',
    'explanation': '',
    'difficulty': 0.5,
    'source_chunk_id': 'CH-1',
    'authority_status': 'reviewed',
    'exempt_marked': false,
    'trial_only': false,
    'subjective': kind != 'objective',
  };
}

String _kind(Map<String, dynamic> it) => LocalQuiz.challengeKind(it);

void main() {
  setUp(() {
    LocalDb.tests.clear();
  });

  test('selectItems：一个知识点只出一道（不再凑 8 题）', () {
    final items = <Map<String, dynamic>>[
      for (var node = 0; node < 3; node++)
        for (var k = 0; k < 5; k++) _raw(node * 10 + k, node: node),
    ];
    final chosen = LocalQuiz.selectItems(items, seed: 7);
    expect(chosen.length, 3);
    expect(chosen.map((it) => '${it['node_id']}').toSet().length, 3);
  });

  test('selectItems：同知识点绝不出现两次', () {
    final items = <Map<String, dynamic>>[
      for (var node = 0; node < 4; node++)
        for (var k = 0; k < 4; k++) _raw(node * 10 + k, node: node),
    ];
    final chosen = LocalQuiz.selectItems(items, seed: 3);
    final nodes = chosen.map((it) => '${it['node_id']}').toList();
    expect(nodes.length, nodes.toSet().length);
  });

  test('selectItems：费曼自述题每卷必出', () {
    final items = <Map<String, dynamic>>[
      _raw(1, node: 1),
      _raw(2, node: 2),
      _raw(3, node: 3, kind: 'feyn'),
    ];
    final chosen = LocalQuiz.selectItems(items, seed: 5);
    expect(chosen.where((it) => _kind(it) == LocalQuiz.challengeFeyn).length, 1);
  });

  test('selectItems：知识点少不塞应用题，够多时费曼 + 应用各一道', () {
    final few = <Map<String, dynamic>>[
      for (var i = 0; i < 4; i++) _raw(i, node: i),
      _raw(100, node: 0, kind: 'apply'),
      _raw(101, node: 1, kind: 'feyn'),
    ];
    final fewKinds = LocalQuiz.selectItems(few, seed: 2).map(_kind).toList();
    expect(fewKinds.contains(LocalQuiz.challengeApply), isFalse);
    expect(fewKinds.where((k) => k == LocalQuiz.challengeFeyn).length, 1);

    final many = <Map<String, dynamic>>[
      for (var node = 0; node < 8; node++) ...[
        _raw(node, node: node),
        _raw(100 + node, node: node, kind: 'feyn'),
        _raw(200 + node, node: node, kind: 'apply'),
      ],
    ];
    final manyKinds = LocalQuiz.selectItems(many, seed: 2).map(_kind).toList();
    expect(manyKinds.where((k) => k == LocalQuiz.challengeFeyn).length, 1);
    expect(manyKinds.where((k) => k == LocalQuiz.challengeApply).length, 1);
  });

  test('selectItems：客观题在前，要自己写的题在卷末', () {
    final items = <Map<String, dynamic>>[
      _raw(0, node: 0, kind: 'feyn'),
      for (var i = 1; i < 6; i++) _raw(i, node: i),
    ];
    final kinds = LocalQuiz.selectItems(items, seed: 4).map(_kind).toList();
    expect(kinds.last, LocalQuiz.challengeFeyn);
    expect(kinds.sublist(0, kinds.length - 1).every((k) => k.isEmpty), isTrue);
  });

  test('selectItems：同题干只出一次（卷内不重复）', () {
    final items = <Map<String, dynamic>>[
      _raw(1, node: 1, stem: '关于「实践」，下列说法正确的是？'),
      _raw(2, node: 2, stem: '关于「实践」 ， 下列说法正确的是？'), // 仅空白不同
      _raw(3, node: 3),
    ];
    final chosen = LocalQuiz.selectItems(items, seed: 1);
    final stems = chosen.map((it) => '${it['stem']}'.replaceAll(RegExp(r'\s+'), '')).toList();
    expect(stems.length, stems.toSet().length);
  });

  test('selectItems：重考换同知识点的另一道变体', () {
    final items = <Map<String, dynamic>>[
      for (var node = 0; node < 4; node++)
        for (var k = 0; k < 3; k++) _raw(node * 10 + k, node: node),
    ];
    final done = items
        .where((it) => '${it['id']}'.endsWith('0'))
        .map((it) => '${it['id']}')
        .toSet();
    final chosen = LocalQuiz.selectItems(items, excludeIds: done, seed: 3);
    expect(chosen.length, 4);
    expect(chosen.where((it) => done.contains('${it['id']}')), isEmpty);
  });

  test('分档入口不许回来', () {
    // 只看编译期是否还能调到旧 API 意义不大，这里锁「没有难度档位字段」
    final pub = LocalQuiz.publicItem(_raw(1));
    expect(pub.containsKey('difficulty_band'), isFalse);
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

    test('每章都有客观题节点 + 费曼节点（否则选题补不齐）', () {
      final bad = <String, List<String>>{};
      final sections = asset['sections'] as Map<String, dynamic>;
      sections.forEach((sec, list) {
        final feyn = <String>{};
        final obj = <String>{};
        for (final it in (list as List)) {
          final m = (it as Map).cast<String, dynamic>();
          final node = '${m['node_id'] ?? ''}';
          if (LocalQuiz.challengeKind(m) == LocalQuiz.challengeFeyn) {
            feyn.add(node);
          } else if (LocalQuiz.challengeKind(m).isEmpty) {
            obj.add(node);
          }
        }
        if (feyn.isEmpty || obj.isEmpty) bad[sec] = ['feyn: $feyn', 'obj: $obj'];
      });
      expect(bad, isEmpty, reason: '这些章节选题会缺口：$bad');
    });

    test('真题库逐章：一节点一题，费曼必有一道', () {
      final sections = asset['sections'] as Map<String, dynamic>;
      final problems = <String>[];
      sections.forEach((sec, list) {
        final items = (list as List).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
        final nodes = items.map((it) => '${it['node_id']}').toSet();
        final chosen = LocalQuiz.selectItems(items, seed: 7);
        if (chosen.length != nodes.length) {
          problems.add('$sec 出了 ${chosen.length} 题、${nodes.length} 个知识点');
        }
        final got = chosen.map((it) => '${it['node_id']}').toList();
        if (got.length != got.toSet().length) problems.add('$sec 同一知识点重复：$got');
        if (nodes.length >= 2 && chosen.where((it) => _kind(it) == LocalQuiz.challengeFeyn).isEmpty) {
          problems.add('$sec 没有费曼自述题');
        }
        if (chosen.where((it) => _kind(it) == LocalQuiz.challengeApply).length > 1) {
          problems.add('$sec 应用题超过一道');
        }
      });
      expect(problems, isEmpty, reason: problems.join('；'));
    });

    test('没有重复题（同章题干+选项完全相同）', () {
      final seen = <String>{};
      final dups = <String>[];
      final sections = asset['sections'] as Map<String, dynamic>;
      sections.forEach((sec, list) {
        for (final it in (list as List)) {
          final m = (it as Map).cast<String, dynamic>();
          final key = '$sec|${'${m['stem']}'.replaceAll(RegExp(r'\s+'), '')}|'
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
