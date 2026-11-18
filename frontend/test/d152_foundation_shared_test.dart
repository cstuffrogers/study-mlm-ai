// D152 门禁：公共地基（1+3）在「单机版 + 前端模型」两侧的口径
//
// 要钉住的问题：
//   ① 地基章只排在路线 A → 切到 B/C 时页面只剩「别的章节」，学习者会以为地基
//      已经过关。所以 B/C 必须能拿到 `foundation` 里那几章。
//   ② 《提纲》在 B/C 有占位章（sec_B_00 / sec_C_00），《大众哲学》两章没有 ——
//      前端不能把三章一律当「本路线没有」，否则《提纲》显示两遍。
//   ③ 掌握度按「用户 × 路线」存 → 地基进度必须锚 route_A，不然从 A 切到 B
//      会看到刚学完的地基又归零。
//   ④ 路线页的地基卡点进去必须带地基章自己的 routeId（route_A），否则在 B 的
//      名义下学地基章，记录落在 B 名下，回 A 又显示没学。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/models/learning_models.dart';
import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_mastery.dart';
import 'package:marxism_reader/offline/offline_content.dart';

import 'helpers/offline_assets_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RouteSectionsView（前端模型）', () {
    test('解析 foundation 字段，缺省为空表（老后端不崩）', () {
      final v = RouteSectionsView.fromJson({
        'route_id': 'route_B',
        'sections': [
          {'id': 'sec_B_00', 'title': '公共地基：实践观（共享）', 'is_foundation': true}
        ],
        'foundation': [
          {'id': 'sec_A_00', 'is_foundation': true, 'in_route': false,
           'route_id': 'route_A', 'status': 'completed'},
          {'id': 'sec_A_01', 'is_foundation': true, 'in_route': false,
           'route_id': 'route_A', 'status': 'unlocked'},
          {'id': 'sec_A_02', 'is_foundation': true, 'in_route': true,
           'covered_by': 'sec_B_00', 'route_id': 'route_A'},
        ],
      });
      expect(v.sections.single.id, 'sec_B_00');
      expect(v.foundation.length, 3);
      // 《提纲》已被 sec_B_00 覆盖 → 地基卡不再重复展示，只剩《大众哲学》两章
      expect(v.sharedOnly.map((s) => s.id), ['sec_A_00', 'sec_A_01']);
      expect(v.doneCount, 1, reason: '「已读 x/3」要算上被占位章覆盖的《提纲》');
      expect(v.foundation.last.routeId, 'route_A');
      expect(v.foundation.every((s) => s.isFoundation), isTrue);

      final empty = RouteSectionsView.fromJson({'route_id': 'route_X', 'sections': []});
      expect(empty.foundation, isEmpty);
      expect(empty.sharedOnly, isEmpty);
      expect(empty.doneCount, 0);
    });

    test('路线 A 自己列了地基章 → sharedOnly 为空（不重复展示）', () {
      final v = RouteSectionsView.fromJson({
        'sections': [
          {'id': 'sec_A_00', 'is_foundation': true},
          {'id': 'sec_A_01', 'is_foundation': true},
        ],
        'foundation': [
          {'id': 'sec_A_00', 'in_route': true, 'status': 'completed'},
          {'id': 'sec_A_01', 'in_route': true},
          {'id': 'sec_A_02', 'in_route': true},
        ],
      });
      expect(v.sharedOnly, isEmpty);
      expect(v.doneCount, 1);
    });

    test('RouteSection 带 routeId / inRoute，默认值不破坏老调用', () {
      final s = RouteSection.fromJson({'id': 'sec_A_00', 'is_foundation': true});
      expect(s.routeId, isNull);
      expect(s.inRoute, isTrue);
    });
  });

  group('单机版 routesSections().foundation', () {
    if (skipWithoutOfflineAssets()) return;

    setUp(() async {
      await OfflineContent.ensureMeta();
      await LocalDb.resetAll();
      LocalDb.routeId = 'route_A';
    });

    test('三条路线都能拿到地基三章，且只在 B/C 标记「未在本路线」', () async {
      for (final rid in ['route_A', 'route_B', 'route_C']) {
        final j = await LocalMastery.routesSections(rid);
        final rows = (j['foundation'] as List).cast<Map<String, dynamic>>();
        expect(rows.map((e) => e['id']), ['sec_A_00', 'sec_A_01', 'sec_A_02'],
            reason: '$rid 缺少地基三章 → 页面没法提示「地基还没读」');
        expect(rows.every((e) => e['route_id'] == 'route_A'), isTrue,
            reason: '地基章归属恒为 route_A（B/C 只是借用展示）');
        if (rid == 'route_A') {
          expect(rows.every((e) => e['in_route'] == true), isTrue);
        } else {
          // 《大众哲学》两章这条路线没有；《提纲》有占位章 → in_route 且指向占位章
          expect(rows[0]['in_route'], isFalse);
          expect(rows[1]['in_route'], isFalse);
          expect(rows[2]['in_route'], isTrue);
          expect(rows[2]['covered_by'], rid == 'route_B' ? 'sec_B_00' : 'sec_C_00');
        }
      }
    });

    test('地基三章都是 is_foundation=True 且不在 B/C 章节列表里', () async {
      for (final rid in ['route_B', 'route_C']) {
        final ids = OfflineContent.sectionsOf(rid).map((s) => s['id']).toSet();
        expect(ids.contains('sec_A_00'), isFalse);
        expect(ids.contains('sec_A_01'), isFalse);
      }
    });
  });

  group('源码口径（防回退）', () {
    test('路线页地基卡点进去带地基章自己的 routeId', () {
      final src = File('lib/screens/route_map.dart').readAsStringSync();
      expect(src.contains('view.sharedOnly'), isTrue,
          reason: '地基卡只能展示「本路线没有的」地基章');
      expect(src.contains('routeId: s.routeId ?? widget.routeId'), isTrue,
          reason: '在 B 名义下读地基章会把学情记到 B 名下，回 A 又归零');
      expect(src.contains('公共地基（三条路线共用）'), isTrue);
      expect(src.contains('sectionsView'), isTrue,
          reason: '走 sectionsView 一次拿全，别为地基再发一次请求');
    });

    test('单机版锚 route_A 读地基进度，不读当前路线', () {
      final src = File('lib/offline/local_mastery.dart').readAsStringSync();
      final body = src.substring(src.indexOf('_foundationRows(String routeId'));
      expect(body.contains("const anchorRoute = 'route_A'") ||
          body.contains("const anchor = 'route_A'"), isTrue);
      expect(body.contains("mergedFound", ), isFalse); // 占位：无此变量
      expect(body.contains('covered_by'), isTrue,
          reason: '要能说明《提纲》由哪一章占位覆盖');
    });

    test('RoutesService 保留 sections() 兼容，同时提供 sectionsView()', () {
      final src = File('lib/services/routes_service.dart').readAsStringSync();
      expect(src.contains('Future<RouteSectionsView> sectionsView'), isTrue);
      expect(src.contains('final view = await sectionsView'), isTrue,
          reason: 'sections() 要基于 sectionsView，避免两套解析逻辑走偏');
    });
  });
}
