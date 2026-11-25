// 复习卡交互门禁（D160）：用户实报「点还记得没反应 / 点忘了卡片被吞」。
//
// 根因：队列里混着 `kind='due'`（真到期）与 `kind='interleave'`（交错巩固，引擎不看到期，
// 只要 score>=0.6 就补进池），交错条目永远不会因为自评离开队列 → 「没反应」；
// 到期条目自评后 `next_review_at` 立刻推后 → 本应消失，但原先没有任何提示 → 像被吞。
// 本文件守住四条：
//  ① 「到期 N 项」只数到期条目，交错巩固另记一项；
//  ② 交错条目不给自评按钮，只给「去做巩固题」（进该章章节测试）；
//  ③ 到期条目自评成功后立刻移出并告知下次复习时间；
//  ④ 自评没生效（applied:false）或抛异常时，条目保留且明确说原因，不静默。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/models/learning_models.dart';
import 'package:marxism_reader/widgets/review_card.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

ReviewItem _due(String id, String name, {double retention = 0.5}) => ReviewItem(
      nodeId: id,
      name: name,
      sectionId: 'sec_A_02',
      score: 0.5,
      stability: 0.2,
      retention: retention,
      elapsedDays: 3,
      kind: 'due',
    );

ReviewItem _consol(String id, String name) => ReviewItem(
      nodeId: id,
      name: name,
      sectionId: 'sec_A_03',
      score: 0.86,
      stability: 0.8,
      retention: 1.0,
      elapsedDays: 0,
      kind: 'interleave',
    );

void main() {
  testWidgets('① 计数：到期只数 kind=due，交错巩固另记一项', (t) async {
    await t.pumpWidget(_host(ReviewCard(items: [
      _due('kn_a', '实践'),
      _due('kn_b', '矛盾'),
      _consol('kn_c', '直观'),
      _consol('kn_d', '感性认识'),
    ])));
    expect(find.text('到期 2 项'), findsOneWidget);
    expect(find.text('建议巩固 2 项'), findsOneWidget);
    // 两组标题都在，说明没有把交错条目伪装成「到期」
    expect(find.textContaining('到期复习'), findsOneWidget);
    expect(find.textContaining('建议巩固'), findsWidgets);
  });

  testWidgets('② 交错巩固条目：没有自评按钮，只有「去做巩固题」', (t) async {
    ReviewItem? practiced;
    await t.pumpWidget(_host(ReviewCard(
      items: [_consol('kn_c', '直观')],
      onReview: (node, r) async => {'applied': true},
      onPractice: (it) => practiced = it,
    )));
    expect(find.text('还记得'), findsNothing);
    expect(find.text('忘了'), findsNothing);
    expect(find.textContaining('保持率'), findsNothing);
    await t.tap(find.text('去做巩固题'));
    expect(practiced?.nodeId, 'kn_c');
    // 点过即从列表移出（不再「点了没反应」）
    await t.pumpAndSettle();
    expect(find.text('直观'), findsNothing);
  });

  testWidgets('③ 到期条目自评成功：立刻移出并告知下次复习', (t) async {
    final calls = <String, double>{};
    await t.pumpWidget(_host(ReviewCard(
      items: [_due('kn_a', '实践')],
      onReview: (node, r) async {
        calls[node] = r;
        return {
          'node_id': node,
          'applied': true,
          'next_review_at':
              DateTime.now().add(const Duration(days: 1)).toUtc().toIso8601String(),
        };
      },
    )));
    await t.tap(find.text('还记得'));
    await t.pumpAndSettle();
    expect(calls['kn_a'], 1.0);
    expect(find.text('实践'), findsNothing);
    expect(find.textContaining('已记录'), findsOneWidget);
    expect(find.textContaining('明天'), findsOneWidget);
  });

  testWidgets('③b 「忘了」同样回写 0.2 并移出', (t) async {
    final calls = <String, double>{};
    await t.pumpWidget(_host(ReviewCard(
      items: [_due('kn_a', '实践')],
      onReview: (node, r) async {
        calls[node] = r;
        return {'applied': true, 'next_review_at': '2026-11-26T00:00:00Z'};
      },
    )));
    await t.tap(find.text('忘了'));
    await t.pumpAndSettle();
    expect(calls['kn_a'], 0.2);
    expect(find.text('实践'), findsNothing);
  });

  testWidgets('④ applied:false：条目保留并说明原因', (t) async {
    await t.pumpWidget(_host(ReviewCard(
      items: [_due('kn_a', '实践')],
      onReview: (node, r) async => {'applied': false, 'reason': '尚无掌握记录'},
    )));
    await t.tap(find.text('还记得'));
    await t.pumpAndSettle();
    expect(find.text('实践'), findsOneWidget); // 没生效就不许假装成功
    expect(find.text('尚无掌握记录'), findsOneWidget);
  });

  testWidgets('④b 抛异常：提示「记录失败」而不是静默吞掉', (t) async {
    await t.pumpWidget(_host(ReviewCard(
      items: [_due('kn_a', '实践')],
      onReview: (node, r) async => throw Exception('boom'),
    )));
    await t.tap(find.text('还记得'));
    await t.pumpAndSettle();
    expect(find.text('实践'), findsOneWidget);
    expect(find.textContaining('记录失败'), findsOneWidget);
  });

  testWidgets('全部处理完：卡片整体收起，不留空壳', (t) async {
    await t.pumpWidget(_host(ReviewCard(
      items: [_due('kn_a', '实践')],
      onReview: (node, r) async => {'applied': true, 'next_review_at': '2026-11-26T00:00:00Z'},
    )));
    await t.tap(find.text('还记得'));
    await t.pumpAndSettle();
    expect(find.textContaining('该复习了'), findsNothing);
  });
}
