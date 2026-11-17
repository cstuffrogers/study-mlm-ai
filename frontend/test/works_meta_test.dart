// D131 门禁：原著浏览书单不能再把内部注释层当原著，且每条要带作者/段数。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/offline_content.dart';

import 'helpers/offline_assets_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (skipWithoutOfflineAssets()) return;

  test('离线书单不含内部注释层', () async {
    await OfflineContent.ensureMeta();
    final works = OfflineContent.works;
    expect(works, isNotEmpty);
    for (final w in works) {
      final name = '${w['work'] ?? ''}';
      expect(name.contains('正典注释'), isFalse, reason: name);
      expect(name.contains('正典解析'), isFalse, reason: name);
    }
  });

  test('书单条目带作者与段数（作者可空，不许缺字段）', () async {
    await OfflineContent.ensureMeta();
    for (final w in OfflineContent.works) {
      expect(w.containsKey('author'), isTrue, reason: '${w['work']}');
      expect(w.containsKey('chunk_count'), isTrue, reason: '${w['work']}');
      expect((w['chunk_count'] as num?)?.toInt() ?? 0, greaterThan(0),
          reason: '${w['work']} 段数为 0');
    }
  });

  test('《关于费尔巴哈的提纲》在书单里且署名马克思', () async {
    await OfflineContent.ensureMeta();
    final th =
        OfflineContent.works.firstWhere((w) => '${w['work']}' == '关于费尔巴哈的提纲');
    expect('${th['author']}', '马克思');
  });
}
