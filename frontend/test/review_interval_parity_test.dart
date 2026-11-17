// D131 门禁：复习间隔公式必须与后端 `review_service.interval_days` 同式。
// 后端最小间隔有 0.5 天下限、负 stability 归零；单机版曾缺这两条，
// 极低稳定度下两端会差半天的到期时间。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_mastery.dart';
import 'package:marxism_reader/offline/offline_content.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('间隔公式：负/零稳定性仍有下限，且不超上限', () async {
    await OfflineContent.ensureMeta();
    LocalDb.routeId = 'route_A';
    // stability=0 → base(1) × 2^0 = 1 天
    expect(LocalMastery.intervalDays(0), closeTo(1.0, 1e-6));
    // stability=-0.5 → 必须归零（不是 2^-1.67≈0.31）
    expect(LocalMastery.intervalDays(-0.5), closeTo(1.0, 1e-6));
    // 稳定度越高间隔越长，且封顶
    expect(LocalMastery.intervalDays(0.6), greaterThan(LocalMastery.intervalDays(0.3)));
    expect(LocalMastery.intervalDays(9.9), lessThanOrEqualTo(60.0));
  });
}
