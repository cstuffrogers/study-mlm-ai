// D134 门禁：单机版接口返回「键集合」必须覆盖联网后端（黄金样本）。
//
// 背景：联网版走 FastAPI，单机版走 `frontend/lib/offline/local_router.dart`，
// 同一界面两条实现路径。前几轮修的是数值/文案不一致；这一层查的是**键形状**
// ——单机少一个键，界面就静默少一块内容，REST 冒烟和内容审计都发现不了。
//
// 黄金样本 `test/fixtures/api_shape_golden.json` 由联网后端生成
// （`.local/p189_api_shape_golden.py`），两侧用**同一套种子**：
//   POST /api/quiz/section/sec_A_00/start 后「空作答」提交（全错，分数 <0.8，
//   weak_points 非空，列表项形状才可比）。
//
// 判定线：
//   · 黄金样本里的每个层级、每个键，单机版**必须有** → 缺则失败；
//   · 单机版**多**出来的键不算缺陷（兼容键 / 额外便利字段），只在文档记录；
//   · `optional_keys` 里登记的键是「条件出现」的，两侧任一侧缺席都不算问题。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_router.dart';

import 'helpers/offline_assets_guard.dart';

/// 键集合（深度 2）：顶层键 + 一级子对象键 + 一级列表首项的键。
/// 与 `.local/p189_api_shape_golden.py` 的 `shape()` 逐字同式。
Map<String, List<String>> _shape(dynamic v, [String prefix = '', int depth = 0]) {
  final out = <String, List<String>>{};
  if (v is List) {
    if (v.isNotEmpty) out.addAll(_shape(v.first, '$prefix[]', depth)); // 列表不算一层
    return out;
  }
  if (v is Map) {
    if (depth > 1) return out;
    out[prefix.isEmpty ? '.' : prefix] = (v.keys.map((k) => '$k').toList()..sort());
    for (final e in v.entries) {
      out.addAll(_shape(e.value, prefix.isEmpty ? '${e.key}' : '$prefix.${e.key}', depth + 1));
    }
  }
  return out;
}

const _postBodies = <String, Map<String, dynamic>>{
  '/api/quiz/section/sec_A_02/start': {'user_id': 'demo_user', 'route_id': 'route_A'},
  '/api/recommendation/next': {
    'user_id': 'demo_user',
    'route_id': 'route_A',
    'current_section_id': 'sec_A_00',
  },
  '/api/mastery/summary': {'user_id': 'demo_user', 'route_id': 'route_A', 'period': 'week'},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (skipWithoutOfflineAssets()) return;

  test('单机版接口形状覆盖联网后端黄金样本', () async {
    final file = File('test/fixtures/api_shape_golden.json');
    expect(file.existsSync(), isTrue,
        reason: '缺少黄金样本，重跑 .local/p189_api_shape_golden.py');
    final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final paths = (fixture['paths'] as Map).cast<String, dynamic>();
    final optional =
        ((fixture['optional_keys'] as Map?) ?? const {}).cast<String, dynamic>();

    // —— 与黄金样本同种子：空作答（全错），叶子分低、weak_points 非空
    final started = await LocalRouter.post('/api/quiz/section/sec_A_00/start', const {});
    if (((started['items'] as List?) ?? const []).isNotEmpty) {
      await LocalRouter.post('/api/quiz/${started['test_id']}/submit', {
        'answers': const [],
      });
    }

    final failures = <String>[];
    for (final entry in paths.entries) {
      final key = entry.key; // "GET /api/xxx"
      final golden = (entry.value as Map).cast<String, dynamic>();
      final method = key.split(' ').first;
      final path = key.substring(method.length + 1);
      final Map<String, dynamic> actualBody;
      try {
        actualBody = method == 'GET'
            ? await LocalRouter.get(path, const {})
            : await LocalRouter.post(path, _postBodies[path] ?? const {});
      } catch (e) {
        failures.add('$key :: 单机版直接抛异常：$e');
        continue;
      }
      final actual = _shape(actualBody);
      // 黄金样本的顶层键里，「条件出现」的登记在 optional_keys 中
      final opt = ((optional[key] as List?) ?? const []).map((e) => '$e').toSet();
      for (final scope in golden.keys) {
        final want = (golden[scope] as List).map((e) => '$e').toSet();
        // 联网那一侧该层级本身就是空对象 / 空列表 → 没有键要单机版覆盖。
        if (want.isEmpty) continue;
        final have = (actual[scope] ?? const <String>[]).toSet();
        if (have.isEmpty && opt.contains(scope)) continue;
        if (have.isEmpty) {
          failures.add('$key :: 单机版没有层级 $scope（联网有 ${want.toList()..sort()}）');
          continue;
        }
        final missing = (want.difference(have).difference(opt)).toList()..sort();
        if (missing.isNotEmpty) {
          failures.add('$key :: $scope 单机版缺键 $missing');
        }
      }
    }

    expect(failures, isEmpty,
        reason: '单机版返回形状与联网后端不一致（缺键 = 界面静默少内容）：\n'
            '${failures.map((f) => '  · $f').join('\n')}\n'
            '修法：在 frontend/lib/offline/ 对应方法补齐键；若确属有意差异，'
            '在 api_shape_golden.json 的 optional_keys 里登记并在文档说明。');
  });
}
