// D113 门禁：学习分析的健康度必须「只在有数据时才给分」。
//
// 背景（实测发现的缺陷）：旧实现里 avg_retention / avg_score 为空时会补 1.0，
// 于是全新用户（0 次作答、0 个评估点）打开学习分析就看到「学习健康度 54」，
// 这是白送的分数，既不科学也误导。现在缺数据的维度不进权重，权重按剩余维度
// 归一；完全无数据时 health=0 且 has_data=false，界面显示「—」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_insight.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'package:marxism_reader/screens/analytics_dashboard.dart';
import 'package:marxism_reader/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.ensure();
    await OfflineContent.ensureMeta();
  });

  setUp(() {
    LocalDb.mastery = {};
    LocalDb.attempts = [];
    LocalDb.settings = {'route_id': 'route_A'};
  });

  test('全新用户：无数据 → 健康度 0 且 has_data=false', () {
    final d = LocalInsight.overview('route_A');
    expect(d['total_attempts'], 0);
    expect(d['assessed_nodes'], 0);
    expect(d['health_score'], 0);
    expect(d['has_data'], false);
    // 无任何维度得分时不应断言「唯物论最弱」
    expect((d['weakest_dim'] as Map)['dim'], isNull);
  });

  test('只答过题、没做过复习：权重按有数据的维度归一，不再白送保持分', () {
    LocalDb.attempts = [
      {'score': 1.0, 'is_correct': true, 'confidence': 'high', 'error_category': ''},
    ];
    final d = LocalInsight.overview('route_A');
    expect(d['has_data'], true);
    expect(d['total_attempts'], 1);
    // 计入的维度：掌握面 0（权重 0.40）· 校准 calibrated 1.0（0.15）· 近期正确 1.0（0.20）
    // 无复习记录 → 保持率维度不进权重。归一后 = 100*(0.15+0.20)/(0.40+0.15+0.20) ≈ 47
    expect(d['health_score'], 47);
    expect(d['avg_retention'], isNull, reason: '没复习记录就不该编出保持率');
  });

  testWidgets('看板：无数据时健康度显示「—」而不是 0/54', (t) async {
    await t.binding.setSurfaceSize(const Size(393, 852));
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: const AnalyticsDashboardScreen(routeId: 'route_A'),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('—'), findsWidgets);
    expect(find.textContaining('还没有作答记录'), findsOneWidget);
    await t.binding.setSurfaceSize(null);
  });

  test('有掌握记录 + 作答：健康度落在 (0,100] 且随掌握面上升', () {
    final n1 = '${OfflineContent.allNodes[0]['id']}';
    final n2 = '${OfflineContent.allNodes[1]['id']}';
    LocalDb.mastery = {
      'route_A': {
        n1: {'level': 'proficient', 'score': 0.9},
        n2: {'level': 'mastered', 'score': 0.95},
      }
    };
    LocalDb.attempts = [
      {'score': 0.9, 'is_correct': true, 'confidence': 'mid', 'error_category': ''},
    ];
    final d = LocalInsight.overview('route_A');
    final h = d['health_score'] as int;
    expect(h, greaterThan(0));
    expect(h, lessThanOrEqualTo(100));
    expect((d['mastery_distribution'] as Map)['proficient'], 1);
    expect((d['mastery_distribution'] as Map)['mastered'], 1);
  });
}

// 界面层：无数据时健康度显示「—」，不再显示一个凭空的分数。