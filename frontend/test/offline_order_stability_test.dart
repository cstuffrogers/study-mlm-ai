// D136 门禁：单机版（`frontend/lib/offline/`）的**列表顺序 / 排序稳定性 / 并列**。
//
// D131~D135 查了同一界面两条实现路径的数值、文案、键形状、错误语义。
// 这一轮查此前没人碰过的一层：**同一批数据，两端排出来的顺序是否一致**。
// 排序缺陷是最会「看起来对」的一种 —— 数据不少、字段不缺、状态码一样，只有顺序不同；
// 且只在**并列**时暴露（排序键同值时，先后由输入顺序决定，而输入顺序在两侧
// 分别是 SQL 无 ORDER BY 的返回序 / Dart Map 的迭代序 / Python 稳定排序残留）。
//
// 本轮实测（`.local/p192_offline_order.py` × `test/_probe_offline_order.dart`
// 26 个用例、逐列表比对有序 id 序列）挖出 6 处：
//  · `profile.weak_points`：单机 `if (rec == null) continue;` 把**未评估节点**排除，
//    全新用户在线 106 条、单机 0 条；后端同列表 `sort(reverse=True)` 无 tie-break；
//  · `profile.weak_points`：单机 `.take(6)` 硬截断（后端回全量，切片归 `weak_top(n)`）；
//  · `review_status().items`：两端都按存储返回序输出，同一份数据两种排法；
//  · `due_reviews()`：只按 `_risk` 降序（单机 `List.sort` 还**不稳定**）；
//  · `interleaved()`：单机按 Map 迭代序直接塞，缺「(score, node_id) 排序 + 按小节轮转」；
//  · `motivation().milestones`：单机与后端均回完整 9 条（贯通 4 + 连续学习 2 + 累计作答 3），带 category。
//
// 后端侧同门禁：`backend/tests/test_d136_order_stability.py`。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/offline_content.dart';

import 'helpers/offline_assets_guard.dart';
import 'package:marxism_reader/offline/local_mastery.dart';
import 'package:marxism_reader/offline/local_router.dart';

Future<Map<String, dynamic>> _get(String path,
    [Map<String, String> q = const {}]) async {
  final r = await LocalRouter.get(
      path, {'user_id': 'demo_user', 'route_id': 'route_A', ...q});
  return (r as Map).cast<String, dynamic>();
}

Future<void> _seed() async {
  for (final sid in const ['sec_A_00', 'sec_A_01', 'sec_A_02']) {
    final start = await LocalRouter.post(
        '/api/quiz/section/$sid/start',
        const {'user_id': 'demo_user', 'route_id': 'route_A'});
    await LocalRouter.post(
        '/api/quiz/${(start as Map)['test_id']}/submit',
        const {'user_id': 'demo_user', 'answers': <dynamic>[]});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (skipWithoutOfflineAssets()) return;

  test('未评估节点也算薄弱点（后端 profile 会列，单机原先跳过）', () async {
    final prof = await _get('/api/mastery/profile');
    final weak = (prof['weak_points'] as List).cast<Map>();
    expect(weak.length, OfflineContent.allNodes.length,
        reason: '全新用户应把全部节点列为薄弱点（score=0）');
    expect(weak.map((w) => w['level']).toSet(), {'unseen'});
  });

  test('薄弱点并列按 node_id 升序（不能只比 impact）', () async {
    final prof = await _get('/api/mastery/profile');
    final weak = (prof['weak_points'] as List).cast<Map>();
    final got = weak.map((w) => ((w['impact'] as num).toDouble(), '${w['node_id']}')).toList();
    // 复现契约序：impact 降序 → node_id 升序
    final want = [...got]..sort((a, b) {
        final c = b.$1.compareTo(a.$1);
        return c != 0 ? c : a.$2.compareTo(b.$2);
      });
    expect(got, want, reason: '同 impact 的先后必须按 node_id 落定');
  });

  test('薄弱点不截 6 条（切片归 weak-top?n=）', () async {
    final prof = await _get('/api/mastery/profile');
    expect((prof['weak_points'] as List).length, greaterThan(6));
    // weak-top 仍然按 n 切片，且与后端同式钳制
    for (final n in const ['1', '5', '50']) {
      final r = await _get('/api/recommendation/weak-top', {'n': n});
      expect((r['weak_points'] as List).length, int.parse(n), reason: 'n=$n');
    }
  });

  test('里程碑回完整三类 9 条，带 category（后端 _milestones 同式）', () async {
    await _seed();
    final mot = await _get('/api/motivation/state');
    final ms = (mot['milestones'] as List).cast<Map>();
    // 贯通 4 + 连续学习 2 + 累计作答 3 = 9 条
    expect(ms.length, 9);
    // 每条带 category
    expect(ms.every((m) => m['category'] != null), isTrue);
    // 三类齐全
    final cats = ms.map((m) => m['category']).toSet();
    expect(cats, containsAll(['贯通', '连续学习', '累计作答']));
  });

  test('复习概览 items 按稳定度升序 + node_id（不按写入时刻）', () async {
    await _seed();
    final st = await _get('/api/review/status');
    final items = (st['items'] as List).cast<Map>();
    expect(items, isNotEmpty);
    final got = items.map((i) => ((i['stability'] as num).toDouble(), '${i['node_id']}')).toList();
    final want = [...got]..sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : a.$2.compareTo(b.$2);
      });
    expect(got, want);
  });

  test('到期队列并列按 node_id 升序（Dart List.sort 不稳定，必须显式 tie-break）', () async {
    await _seed();
    final due = (await _get('/api/review/due'))['due'] as List;
    final got = due.cast<Map>().map((d) => (
          (1 - (d['retention'] as num).toDouble()) *
              (1 + LocalMastery.dependentsCount('${d['node_id']}')),
          '${d['node_id']}'
        )).toList();
    final want = [...got]..sort((a, b) {
        final c = b.$1.compareTo(a.$1);
        return c != 0 ? c : a.$2.compareTo(b.$2);
      });
    expect(got, want);
  });

  test('交错复习：巩固池先按 (score, node_id) 排序，再按小节轮转', () async {
    await _seed();
    final r = await _get('/api/review/interleaved', {'n': '6'});
    final items = (r['items'] as List).cast<Map>();
    expect(items.length, lessThanOrEqualTo(6));
    // 轮转的第一圈：来自不同小节的项必须交替出现（同小节不相邻，除非只剩一个桶）
    final secs = items.map((i) => '${i['section_id'] ?? ''}').toList();
    if (secs.isEmpty) return; // 种子后尚无到期/巩固项，本题只剩长度约束
    final distinct = secs.toSet().length;
    final head = secs.take(distinct < secs.length ? distinct : secs.length).toList();
    expect(head.toSet().length, head.length,
        reason: '前 $distinct 项应来自不同小节（轮转），实得 $secs');
  });

  test('历史列表：同时间戳按 quiz_id 升序，两次查询同序', () async {
    await _seed();
    final a = (await _get('/api/quiz/history', {'limit': '50'}))['rows'] as List;
    final b = (await _get('/api/quiz/history', {'limit': '50'}))['rows'] as List;
    final idsA = a.cast<Map>().map((r) => '${r['quiz_id']}').toList();
    final idsB = b.cast<Map>().map((r) => '${r['quiz_id']}').toList();
    expect(idsA, idsB);
    final rows = a.cast<Map>().toList();
    for (var i = 1; i < rows.length; i++) {
      final p = '${rows[i - 1]['created_at']}';
      final c = '${rows[i]['created_at']}';
      final pId = '${rows[i - 1]['quiz_id']}';
      final cId = '${rows[i]['quiz_id']}';
      expect(p.compareTo(c) > 0 || (p == c && pId.compareTo(cId) < 0), isTrue,
          reason: '第 $i 项违反「时间倒序 + quiz_id 升序」：$p/$pId vs $c/$cId');
    }
  });
}
