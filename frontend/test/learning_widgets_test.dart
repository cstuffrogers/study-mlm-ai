// 学习闭环组件 Widget 测试（US1–US5 前端渲染冒烟）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/models/learning_models.dart';
import 'package:marxism_reader/widgets/mastery_badge.dart';
import 'package:marxism_reader/widgets/weak_point_card.dart';
import 'package:marxism_reader/widgets/recommendation_card.dart';
import 'package:marxism_reader/widgets/instant_summary_card.dart';
import 'package:marxism_reader/widgets/radar_chart.dart';
import 'package:marxism_reader/widgets/sync_notice.dart';
import 'package:marxism_reader/widgets/review_card.dart';
import 'package:marxism_reader/widgets/motivation_banner.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  group('MasteryBadge 五级色阶', () {
    testWidgets('渲染等级标签', (t) async {
      await t.pumpWidget(_host(const MasteryBadge(level: 'mastered', score: 0.9)));
      expect(find.text('贯通 90%'), findsOneWidget);
    });
    testWidgets('五级映射齐全', (t) async {
      expect(MasteryStyle.of('mastered').label, '贯通');
      expect(MasteryStyle.of('proficient').label, '精通');
      expect(MasteryStyle.of('familiar').label, '熟悉');
      expect(MasteryStyle.of('beginner').label, '初学');
      expect(MasteryStyle.of('unseen').label, '未接触');
    });
  });

  testWidgets('WeakPointCard 显示阻塞章数与回补按钮', (t) async {
    var tapped = false;
    final w = WeakPoint(nodeId: 'kn_practice', name: '实践', score: 0.3, level: 'beginner', blockingSections: 3, sectionId: 'sec_A_02');
    await t.pumpWidget(_host(WeakPointCard(item: w, onReinforce: () => tapped = true)));
    expect(find.text('实践'), findsOneWidget);
    expect(find.text('阻塞后续 3 章'), findsOneWidget);
    await t.tap(find.text('去回补'));
    expect(tapped, true);
  });

  testWidgets('RecommendationCard 展示一句话理由 + 一键进入', (t) async {
    var entered = false;
    final rec = Recommendation(recType: 'reinforce', targetSectionId: 'sec_A_02', targetNodeId: 'kn_practice', reason: '『实践』未达标 0.53<0.8');
    await t.pumpWidget(_host(RecommendationCard(rec: rec, onEnter: () => entered = true)));
    expect(find.textContaining('『实践』未达标'), findsOneWidget);
    await t.tap(find.text('一键进入'));
    expect(entered, true);
  });

  testWidgets('InstantSummaryCard 折叠显示一句话小结 + 检验问题', (t) async {
    await t.pumpWidget(_host(const InstantSummaryCard(oneLine: '实践是感性的人的活动', checkQuestion: '实践与直观有何区别？')));
    expect(find.text('即时小结'), findsOneWidget);
    // 展开
    await t.tap(find.text('即时小结'));
    await t.pumpAndSettle();
    expect(find.textContaining('检验：实践与直观有何区别？'), findsOneWidget);
  });

  testWidgets('RadarChart 自绘无异常（5 维）', (t) async {
    await t.pumpWidget(_host(const RadarChart(values: {
      'materialism': 0.5,
      'dialectics': 0.2,
      'epistemology': 0.8,
      'historical_materialism': 0.6,
      'political_economy': 0.1,
    }, labels: {'materialism': '唯物论', 'dialectics': '辩证法'})));
    expect(find.byType(RadarChart), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('SyncNotice 离线态显示重试', (t) async {
    var retried = false;
    await t.pumpWidget(_host(SyncNotice(message: '离线暂存 2 条作答，恢复后自动同步', offline: true, onRetry: () => retried = true)));
    expect(find.textContaining('离线暂存'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    await t.tap(find.text('重试'));
    expect(retried, true);
  });

  testWidgets('ReviewCard 显示到期复习并可自评回写', (t) async {
    String? reviewedNode;
    double? ratio;
    await t.pumpWidget(_host(ReviewCard(
      items: [
        ReviewItem(nodeId: 'kn_practice', name: '实践', sectionId: 'sec_A_02',
            score: 0.8, stability: 0.4, retention: 0.5, elapsedDays: 12),
      ],
      onReview: (node, r) {
        reviewedNode = node;
        ratio = r;
      },
    )));
    expect(find.textContaining('该复习了'), findsOneWidget);
    expect(find.text('实践'), findsOneWidget);
    expect(find.textContaining('保持率'), findsOneWidget);
    await t.tap(find.text('还记得'));
    expect(reviewedNode, 'kn_practice');
    expect(ratio, 1.0);
  });

  testWidgets('ReviewCard 空列表不渲染', (t) async {
    await t.pumpWidget(_host(const ReviewCard(items: [])));
    expect(find.textContaining('该复习了'), findsNothing);
  });

  testWidgets('ReviewCard 显示交错巩固标签', (t) async {
    await t.pumpWidget(_host(ReviewCard(
      items: [
        ReviewItem(nodeId: 'kn_intuition', name: '直观', sectionId: 'sec_A_02',
            score: 0.7, stability: 0.3, retention: 0.95, elapsedDays: 1, kind: 'interleave'),
      ],
    )));
    expect(find.text('交错巩固'), findsOneWidget);
    expect(find.textContaining('跨知识点混合练习'), findsOneWidget);
  });

  testWidgets('MotivationBanner 分级鼓励 + 里程碑 + 下一步', (t) async {
    final state = {
      'frustration': {'level': 'mid', 'score': 0.42, 'drivers': ['近期正确率偏低（50%）']},
      'encouragement': '把注意力放在今天弄懂一个概念。',
      'mastered': 2,
      'streak_days': 5,
      'milestones': [
        {'label': '贯通 1 个知识点', 'achieved': true},
        {'label': '贯通 3 个知识点', 'achieved': false},
      ],
      'next_best_action': {'kind': 'light_review', 'label': '做一轮交错复习', 'reason': '先清掉遗忘积压'},
    };
    await t.pumpWidget(_host(MotivationBanner(state: state)));
    expect(find.text('稳步推进'), findsOneWidget);
    expect(find.textContaining('弄懂一个概念'), findsOneWidget);
    expect(find.text('贯通 1 个知识点'), findsOneWidget);
    expect(find.textContaining('交错复习'), findsOneWidget);
  });

  testWidgets('MotivationBanner 高挫折显示先喘口气', (t) async {
    final state = {
      'frustration': {'level': 'high', 'score': 0.7, 'drivers': []},
      'encouragement': '别急。',
      'mastered': 0,
      'streak_days': 0,
      'milestones': [],
      'next_best_action': {'kind': 'break', 'label': '先休息 5 分钟', 'reason': '连续受挫'},
    };
    await t.pumpWidget(_host(MotivationBanner(state: state)));
    expect(find.text('先喘口气'), findsOneWidget);
  });
}
