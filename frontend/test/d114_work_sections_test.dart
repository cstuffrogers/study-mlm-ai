// D114 门禁：书 → 章节的反向索引，以及三章补白后的延伸阅读通路。
//
// 背景：原著库 122 部里有 94 部「只挂在某章的延伸阅读」、没有独立章节。
// 读者从「原著浏览」点进这类书时，看不到它在哪一章学，读完也不知道
// 该回哪一章。所以导出时生成 work_sections.json（书 → 章节），
// 阅读器顶部给一个「这本书在路线里的哪几章」入口。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marxism_reader/offline/offline_content.dart';
import 'helpers/offline_assets_guard.dart';

void main() {
  if (skipWithoutOfflineAssets()) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await OfflineContent.ensureMeta();
  });

  test('反向索引覆盖库内每部著作', () {
    // meta.works 里含统编教材的注释/解析层（is_book=false），它们不是独立著作、
    // 没有路线入口，只校验真正的书。
    final works = OfflineContent.works
        .where((w) => w['is_book'] == true)
        .map((w) => '${w['work']}')
        .toSet();
    expect(works, isNotEmpty);
    final withoutIndex = <String>[];
    for (final w in works) {
      if (OfflineContent.sectionsOfWork(w).isEmpty) withoutIndex.add(w);
    }
    expect(withoutIndex, isEmpty,
        reason: '这些书在学习路线里没有入口（应该挂某章延伸阅读）：$withoutIndex');
  });

  test('只做延伸阅读的书也能反查到章节', () {
    // 《反杜林论（哲学篇）》不是任何章节主书，只在 sec_A_11 的延伸阅读里
    final rows = OfflineContent.sectionsOfWork('反杜林论（哲学篇）');
    expect(rows, isNotEmpty);
    expect(rows.map((r) => r['section_id']), contains('sec_A_11'));
    expect(rows.first['kind'], 'ext');
    // 《实践论》是 sec_A_03 的主书，同时也是公共地基的延伸读物
    final shijian = OfflineContent.sectionsOfWork('实践论');
    expect(shijian.first['kind'], 'main');
    expect(shijian.map((r) => r['section_id']), containsAll(['sec_A_03', 'sec_B_00']));
  });

  test('索引行的字段完整（跳导读页需要）', () {
    for (final work in ['矛盾论', '国家与革命', '哲学的贫困']) {
      final rows = OfflineContent.sectionsOfWork(work);
      expect(rows, isNotEmpty, reason: '$work 没有索引');
      for (final r in rows) {
        expect('${r['route_id']}', startsWith('route_'));
        expect('${r['section_id']}', startsWith('sec_'));
        expect('${r['section_title']}', isNotEmpty);
        expect(['main', 'ext'], contains(r['kind']));
      }
    }
  });

  test('原先空白的 3 章现在有延伸阅读', () async {
    for (final sid in ['sec_A_03', 'sec_A_05', 'sec_B_00']) {
      final payload = await OfflineContent.sectionPayload(sid);
      final ext = (payload['extensions'] as List?) ?? const [];
      expect(ext.length, greaterThanOrEqualTo(2), reason: '$sid 延伸阅读仍然太少');
      for (final e in ext) {
        final m = (e as Map).cast<String, dynamic>();
        expect('${m['title']}', isNotEmpty);
        // 全部走本机正文，不依赖外部链接
        expect('${m['local_work'] ?? ''}', isNotEmpty, reason: '${m['title']} 没有 local_work');
      }
    }
  });
}
