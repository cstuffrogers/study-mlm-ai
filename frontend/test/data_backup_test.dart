// 本机数据备份 / 恢复 —— 门禁测试。
//
// 锁住三件事：
//  ① 导出的 JSON 包含全部本机数据面（对话/答题/学情/进度/测验/设置/信号/原文数据）；
//  ② 换机场景能真的把数据搬过去（导出 → 空设备 → 导入 → 数字对得上）；
//  ③ 恢复是合并式：不删本机多出来的数据，也不把本机已配好的 API Key 冲掉。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/data_compat.dart';
import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_store_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _work = '《国家与革命》';

Future<void> _seedUserDevice() async {
  SharedPreferences.setMockInitialValues({
    LocalStoreKeys.dialogues: jsonEncode({
      'd-20260101': {
        'id': 'd-20260101',
        'title': '国家与革命的基本结论是什么',
        'current_mode': 'explain',
        'created_at': '2026-01-01T09:00:00',
        'updated_at': '2026-01-01T09:01:00',
        'messages': [
          {'role': 'user', 'content': '国家与革命的基本结论是什么', 'mode': 'explain', 'created_at': '2026-01-01T09:00:00'},
          {'role': 'ai', 'content': '原文摘录…', 'mode': 'explain', 'created_at': '2026-01-01T09:01:00'},
        ],
      },
    }),
    LocalStoreKeys.attempts: jsonEncode([
      {'item_id': 'q_a01', 'is_correct': true},
      {'item_id': 'q_a02', 'is_correct': false},
    ]),
    LocalStoreKeys.mastery: jsonEncode({
      'route_A': {
        'kn_state': {'score': 0.7},
      },
    }),
    LocalStoreKeys.tests: jsonEncode({
      't1': {'section_id': 'sec_A_05', 'status': 'passed'},
    }),
    LocalStoreKeys.progress: jsonEncode({
      'route_A': {
        'sec_A_05': {'status': 'done', 'anchor': 'k9'},
      },
    }),
    LocalStoreKeys.settings: jsonEncode({'route_id': 'route_A', 'font_scale': 1.1}),
    LocalStoreKeys.signals: jsonEncode([
      {'node_id': 'kn_state', 'type': 'dialogue', 'intensity': 2},
    ]),
    LocalStoreKeys.reader(_work, LocalStoreKeys.readerNotes): jsonEncode([
      {'para': 5, 'text': '国家是阶级矛盾不可调和的产物'},
    ]),
    LocalStoreKeys.reader(_work, LocalStoreKeys.readerLastPage): 12,
  });
  LocalDb.reloadForTest();
  await LocalDb.ensure();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 每个用例开头都当「老手机」重新读盘
  setUp(() {
    LocalDb.reloadForTest();
  });

  test('导出的备份包含全部数据面', () async {
    await _seedUserDevice();
    final raw = await DataCompat.exportJson();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    expect(json['app'], 'xxmz');
    expect(json['format'], DataCompat.backupFormat);
    expect(json['data_schema'], DataCompat.schema);
    final docs = json['docs'] as Map<String, dynamic>;
    for (final k in LocalStoreKeys.docs) {
      expect(docs.containsKey(k), isTrue, reason: '备份缺 $k');
    }
    expect((docs[LocalStoreKeys.attempts] as List).length, 2);
    expect((docs[LocalStoreKeys.signals] as List).length, 1);
    final reader = json['reader'] as Map<String, dynamic>;
    expect(reader.containsKey(LocalStoreKeys.reader(_work, LocalStoreKeys.readerNotes)), isTrue);
    expect(reader[LocalStoreKeys.reader(_work, LocalStoreKeys.readerLastPage)], 12);
  });

  test('不导出 API Key（备份就是一串文本，不能带密钥出去）', () async {
    SharedPreferences.setMockInitialValues({
      LocalStoreKeys.settings: jsonEncode({
        'llm_config': {'LLM_API_KEY': 'sk-secret', 'LLM_MODEL': 'qwen-plus'},
      }),
    });
    LocalDb.reloadForTest();
    await LocalDb.ensure();
    final raw = await DataCompat.exportJson();
    expect(raw.contains('sk-secret'), isFalse);
    expect(raw.contains('qwen-plus'), isTrue, reason: '模型名要留着，省得重配');
    // 显式要求时才带密钥
    final withKey = await DataCompat.exportJson(includeApiKey: true);
    expect(withKey.contains('sk-secret'), isTrue);
  });

  test('换机：导出 → 空设备 → 导入，数据回来', () async {
    await _seedUserDevice();
    final backup = await DataCompat.exportJson();
    final before = await DataCompat.stats();

    // 换机：全新的空本机
    SharedPreferences.setMockInitialValues({});
    LocalDb.reloadForTest();
    await LocalDb.ensure();
    expect((await DataCompat.stats())['dialogues'], 0);

    await DataCompat.importJson(backup);
    final after = await DataCompat.stats();
    for (final k in ['dialogues', 'messages', 'attempts', 'mastery_nodes', 'notes', 'read_works', 'tests']) {
      expect(after[k], before[k], reason: '恢复后 $k 应与备份时一致');
    }
    expect(LocalDb.routeId, 'route_A');
    expect(LocalDb.progressFor('route_A')['sec_A_05']['anchor'], 'k9',
        reason: '章节进度也要跟着备份回来');
  });

  test('恢复是合并式：不删本机多出来的数据，也不冲掉本机密钥', () async {
    // 老手机备份
    await _seedUserDevice();
    final backup = await DataCompat.exportJson();

    // 新手机上已经多了一条对话，并且配好了 API Key
    LocalDb.dialogues['d-new'] = {
      'id': 'd-new',
      'title': '只在现在这台机器上的对话',
      'current_mode': 'dig',
      'created_at': '2026-02-02T00:00:00',
      'messages': <dynamic>[],
    };
    LocalDb.settings['llm_config'] = {'LLM_API_KEY': 'sk-keep-me', 'LLM_MODEL': 'qwen-plus'};
    await LocalDb.flush();

    await DataCompat.importJson(backup);

    expect(LocalDb.dialogues.containsKey('d-new'), isTrue, reason: '本机数据不能被恢复删除');
    expect(LocalDb.dialogues.containsKey('d-20260101'), isTrue, reason: '备份数据要合并进来');
    final cfg = LocalDb.settings['llm_config'] as Map;
    expect(cfg['LLM_API_KEY'], 'sk-keep-me', reason: '备份不含密钥，就不能把本机密钥清掉');
  });

  test('同一路线内的掌握度逐条合并：本机独有的节点不被盖掉', () async {
    // 老手机：route_A 只有 kn_state
    await _seedUserDevice();
    final backup = await DataCompat.exportJson();

    // 这台机器上 route_A 里另有 kn_massline（备份里没有），且 kn_state 分数较新
    LocalDb.mastery = {
      'route_A': {
        'kn_massline': {'score': 0.9},
        'kn_state': {'score': 1.0},
      },
    };
    await LocalDb.flush();

    await DataCompat.importJson(backup);

    final a = LocalDb.masteryFor('route_A');
    expect(a.containsKey('kn_massline'), isTrue, reason: '备份里没有的节点不能被删');
    expect(a['kn_massline']['score'], 0.9);
    expect(a['kn_state']['score'], 0.7, reason: '同名节点以备份为准');
  });

  test('坏数据不写入：非 JSON / 别的软件的备份 / 更新格式', () async {
    await _seedUserDevice();
    final before = jsonEncode(LocalDb.dialogues);

    await expectLater(DataCompat.importJson('这不是 json'), throwsA(isA<FormatException>()));
    await expectLater(
        DataCompat.importJson(jsonEncode({'app': 'other'})), throwsA(isA<FormatException>()));
    await expectLater(
        DataCompat.importJson(jsonEncode({'app': 'xxmz', 'format': 99})),
        throwsA(isA<FormatException>()));
    expect(jsonEncode(LocalDb.dialogues), before, reason: '解析失败不能改动本机数据');
  });
}
