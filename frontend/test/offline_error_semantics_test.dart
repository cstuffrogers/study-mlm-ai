// D135 门禁：单机版（`frontend/lib/offline/`）的**异常输入语义**必须与联网后端同口径。
//
// D131~D134 查的是同一界面两条实现路径的**正常路径**（数值 / 文案 / 键形状）。
// 这一层查反面：同一组非法/越界/缺失输入，两侧的状态码与兜底语义是否一致。
// 本轮实测（`.local/p190_offline_errors.py` × `test/_probe_offline_errors.dart`
// 29 个用例逐条比对）在两端口径不一致 5 处，其中真缺陷：
//  · 未知分片：后端 200 + `{error:'not_found'}`，单机抛 404 —— 而
//    `widgets/chunk_tag.dart` 正是靠 `error == 'not_found'` 显示「未找到该分片」；
//  · 未知节点：后端永远回 14 键完整兜底，单机只回 `{error, node_id}`；
//  · 无题库章节开考：后端 409（OrthodoxyViolation），单机 200 + 空 items；
//  · 重复提交 / 测试不存在：单机抛裸 `Exception`（界面拿不到状态码）；
//  · `review/interleaved?n=-3`：单机 `take(n)` 抛 `RangeError`（整页报错）。
//
// 后端侧同门禁：`backend/tests/test_d135_error_semantics.py`。
import 'package:flutter_test/flutter_test.dart';
// `local_router.dart` 已 `export 'local_api_exception.dart'`，无需重复 import。
import 'package:marxism_reader/offline/local_router.dart';

import 'helpers/offline_assets_guard.dart';

Future<Object?> _get(String path, [Map<String, String> q = const {}]) async {
  try {
    return await LocalRouter.get(path, {'user_id': 'demo_user', 'route_id': 'route_A', ...q});
  } on LocalApiException catch (e) {
    return e;
  }
}

Future<Object?> _post(String path, [Map<String, dynamic> body = const {}]) async {
  try {
    return await LocalRouter.post(path, {'user_id': 'demo_user', 'route_id': 'route_A', ...body});
  } on LocalApiException catch (e) {
    return e;
  }
}

int _status(Object? r) => r is LocalApiException ? r.status : 200;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (skipWithoutOfflineAssets()) return;

  test('未知分片按后端形状回 200 + error:not_found（chunk_tag 依赖此键）', () async {
    final r = await _get('/api/chunks/nope');
    expect(_status(r), 200);
    final m = r as Map;
    expect(m['error'], 'not_found');
    expect(m['chunk_id'], 'nope');
  });

  test('未知节点的掌握度是完整兜底形状，不是只有 error', () async {
    final r = await _get('/api/mastery/node/kn_not_exist');
    expect(_status(r), 200);
    final m = r as Map;
    for (final k in const [
      'node_id', 'name', 'definition', 'section_id', 'ability_dim', 'exam_weight',
      'source_chunk_id', 'level', 'score', 'basis', 'signals', 'prerequisites',
      'dependents', 'dependents_count',
    ]) {
      expect(m.containsKey(k), isTrue, reason: '缺键 $k（后端 node_detail 有）');
    }
    expect(m['node_id'], 'kn_not_exist');
  });

  test('未知章节导读是 404（后端同为 404，不再 500）', () async {
    final r = await _get('/api/routes/route_A/sections/sec_Z_99/guide');
    expect(_status(r), 404);
    expect((r as LocalApiException).detail, contains('章节不存在'));
  });

  test('未知章节门控仍给兜底 200，且阅读章补 completed', () async {
    final r = await _get('/api/routes/route_A/sections/sec_Z_99/gating');
    expect(_status(r), 200);
    expect((r as Map)['section_id'], 'sec_Z_99');
  });

  test('无题库章节开考与后端同 409（不能静默开一张空卷）', () async {
    final r = await _post('/api/quiz/section/sec_Z_99/start');
    expect(_status(r), 409);
    expect((r as LocalApiException).detail, contains('暂无题库'));
  });

  test('测试不存在 404 / 重复提交 409，且都是带状态码的异常', () async {
    expect(_status(await _post('/api/quiz/nope/submit', {'answers': <dynamic>[]})), 404);

    final started = await _post('/api/quiz/section/sec_A_00/start');
    final tid = '${(started as Map)['test_id']}';
    await _post('/api/quiz/$tid/submit', {'answers': <dynamic>[]});
    final again = await _post('/api/quiz/$tid/submit', {'answers': <dynamic>[]});
    expect(_status(again), 409);
    expect((again as LocalApiException).detail, contains('请勿重复提交'));
  });

  test('review/interleaved 的 n<=0 回空表（不能抛 RangeError）', () async {
    for (final n in const ['-3', '0']) {
      final r = await _get('/api/review/interleaved', {'n': n});
      expect(_status(r), 200, reason: 'n=$n');
      expect(((r as Map)['items'] as List), isEmpty, reason: 'n=$n');
    }
  });

  test('weak-top 的 n<0 与后端同为空表', () async {
    for (final n in const ['-1', '0']) {
      final r = await _get('/api/recommendation/weak-top', {'n': n});
      expect(_status(r), 200, reason: 'n=$n');
      expect(((r as Map)['weak_points'] as List), isEmpty, reason: 'n=$n');
    }
  });

  test('quiz/history 的 limit<=0 与后端同式钳到 1 条', () async {
    final started = await _post('/api/quiz/section/sec_A_00/start');
    await _post('/api/quiz/${(started as Map)['test_id']}/submit', {'answers': <dynamic>[]});
    for (final lim in const ['-1', '0']) {
      final r = await _get('/api/quiz/history', {'limit': lim});
      expect(_status(r), 200, reason: 'limit=$lim');
      expect(((r as Map)['rows'] as List).length, 1, reason: 'limit=$lim');
    }
  });

  test('sync/progress 平铺后端键（last_position / status 不能被埋进 progress）', () async {
    final r = await _post('/api/sync/progress', {'section_id': 'sec_A_00', 'last_position': 7});
    expect(_status(r), 200);
    final m = r as Map;
    expect(m['section_id'], 'sec_A_00');
    expect(m['last_position'], 7);
    expect(m['status'], isNotEmpty);
  });
}
