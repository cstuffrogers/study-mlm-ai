// 勋章「我的勋章」页数据契约测试（spec 001 勋章系统）
//
// 覆盖：LocalBadge.mine() 返回的每枚勋章字典结构完整，尤其 sort_order 字段。
// 背景：badge_screen.dart 的 _buildCategory 用 a['sort_order'] as int 排序，
// 若 mine() 漏传 sort_order，null as int 抛 TypeError，整页构建失败、
// 勋章渲染不出来（界面一片灰）。此测试作为该缺陷的回归门禁。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_badge.dart';

void main() {
  group('LocalBadge.mine 勋章字典结构', () {
    late Map<String, dynamic> mine;

    setUp(() {
      mine = LocalBadge.mine('route_A');
    });

    test('顶层结构含 metrics / badges / summary', () {
      expect(mine.containsKey('metrics'), isTrue);
      expect(mine.containsKey('badges'), isTrue);
      expect(mine.containsKey('summary'), isTrue);
    });

    test('每枚勋章含 badge_screen 渲染与排序所需的全部字段', () {
      final badges = mine['badges'] as List;
      expect(badges.isNotEmpty, isTrue, reason: '勋章目录应非空');
      for (final b in badges) {
        final m = b as Map<String, dynamic>;
        // badge_screen._buildCategory 排序依赖
        expect(m.containsKey('sort_order'), isTrue,
            reason: '勋章 ${m['badge_id']} 缺少 sort_order，排序会崩溃');
        expect(m['sort_order'], isA<int>());
        // _BadgeCard 渲染依赖
        for (final key in <String>[
          'badge_id', 'name', 'description', 'category', 'icon_key',
          'condition_text', 'earned', 'progress',
        ]) {
          expect(m.containsKey(key), isTrue,
              reason: '勋章 ${m['badge_id']} 缺少字段 $key');
        }
      }
    });

    test('summary 计数与勋章目录一致', () {
      final badges = mine['badges'] as List;
      final summary = mine['summary'] as Map<String, dynamic>;
      expect(summary['total'], badges.length);
      expect(summary['earned'] + summary['unearned'], summary['total']);
    });
  });
}
