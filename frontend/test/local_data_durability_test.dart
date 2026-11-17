// 升级不丢数据 —— 门禁测试。
//
// 这个文件锁的是「用户数据的位置和行为」，不是界面：
//  ① 存储键名一旦发布就不能改（改了 = 老用户数据还在旧键里，新版本读不到）；
//  ② 升级兼容闸门只做加法：补默认字段、登记数据版本，绝不删、绝不改名；
//  ③ 闸门幂等：第二次启动不能再动任何数据；
//  ④ 原文笔记/书签/划线/阅读进度按著作名分键保存，键形态固定；
//  ⑤ 老版本写下的消息缺字段时也能被补全，且正文与时间戳一字不动。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/data_compat.dart';
import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_store_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _precision = r'《资本论（第一卷）》';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LocalDb.reloadForTest();
  });

  test('存储键名已发布就锁死：改一个字母等于丢用户数据', () {
    // 这些字面量是从 1.2.x 起就写进用户手机的，必须一字不差
    expect(LocalStoreKeys.mastery, 'off_mastery');
    expect(LocalStoreKeys.progress, 'off_progress');
    expect(LocalStoreKeys.attempts, 'off_attempts');
    expect(LocalStoreKeys.tests, 'off_tests');
    expect(LocalStoreKeys.dialogues, 'off_dialogues');
    expect(LocalStoreKeys.settings, 'off_settings');
    expect(LocalStoreKeys.signals, 'off_signals');
    expect(LocalStoreKeys.syncQueue, 'sync_queue_v1');
    // 原文阅读器：reader_<著作名>_<后缀>
    expect(LocalStoreKeys.reader(_precision, LocalStoreKeys.readerNotes),
        'reader_$_precision' '_nt');
    expect(LocalStoreKeys.readerSuffixes,
        ['fs', 'bm', 'nt', 'hl', 'last']);
    expect(LocalStoreKeys.readerWorkOf('reader_$_precision' '_last'), _precision);
    expect(LocalStoreKeys.readerWorkOf('off_mastery'), isNull);
    // 七份文档都登记了（漏登记 = 备份/体检会漏数据）
    expect(LocalStoreKeys.docs.length, 7);
  });

  test('升级后旧数据原样读回：对话/答题/学情/进度/设置都不变', () async {
    // 模拟 1.2.x 用户手机上的数据（消息缺 mode 字段，正是老格式）
    SharedPreferences.setMockInitialValues({
      LocalStoreKeys.dialogues: jsonEncode({
        'd-1712345678': {
          'id': 'd-1712345678',
          'title': '实践是检验真理的唯一标准吗',
          'current_mode': 'explain',
          'created_at': '2026-01-01T10:00:00',
          'messages': [
            {'role': 'user', 'content': '实践是检验真理的唯一标准吗', 'created_at': '2026-01-01T10:00:00'},
            {'role': 'ai', 'content': '原文这样答：实践是检验真理的唯一标准。'},
          ],
        },
      }),
      LocalStoreKeys.attempts: jsonEncode([
        {'item_id': 'q_a01', 'is_correct': true, 'created_at': '2026-01-01T10:05:00'},
      ]),
      LocalStoreKeys.mastery: jsonEncode({
        'route_A': {
          'kn_practice': {'score': 0.8, 'updated_at': '2026-01-01T10:05:00'},
        },
      }),
      LocalStoreKeys.progress: jsonEncode({
        'route_A': {
          'sec_A_02': {'status': 'done', 'anchor': 'a1b2', 'updated_at': '2026-01-01T10:06:00'},
        },
      }),
      LocalStoreKeys.settings: jsonEncode({'route_id': 'route_B'}),
    });

    await LocalDb.ensure();
    expect(LocalDb.dialogues.length, 1);

    // 升级：跑闸门
    await DataCompat.run();

    // 一条不少、一字不改
    final doc = LocalDb.dialogue('d-1712345678')!;
    expect(doc['title'], '实践是检验真理的唯一标准吗');
    final msgs = (doc['messages'] as List).cast<Map>();
    expect(msgs.length, 2);
    expect(msgs[1]['content'], '原文这样答：实践是检验真理的唯一标准。');
    // 老消息补上了 mode（补默认值，不是覆盖内容）
    expect(msgs[1]['mode'], 'explain');
    expect(LocalDb.attempts.length, 1);
    expect(LocalDb.masteryFor('route_A')['kn_practice']['score'], 0.8);
    expect(LocalDb.progressFor('route_A')['sec_A_02']['anchor'], 'a1b2');
    expect(LocalDb.routeId, 'route_B', reason: '用户选的路线不能被升级重置');
    expect(LocalDb.settings['data_schema'], DataCompat.schema);
  });

  test('闸门幂等：第二次启动不再改动数据', () async {
    SharedPreferences.setMockInitialValues({
      LocalStoreKeys.dialogues: jsonEncode({
        'd-1': {
          'id': 'd-1',
          'title': 't',
          'current_mode': 'dig',
          'created_at': '2026-01-01T00:00:00',
          'messages': [
            {'role': 'user', 'content': 'q'},
          ],
        },
      }),
    });
    await LocalDb.ensure();
    await DataCompat.run();
    final first = jsonEncode(LocalDb.dialogues);
    final firstStamp = LocalDb.settings['data_schema_updated_at'];

    await DataCompat.run();
    expect(jsonEncode(LocalDb.dialogues), first, reason: '第二次跑不能再改对话');
    expect(LocalDb.settings['data_schema_updated_at'], firstStamp,
        reason: '版本已登记就不该重复写时间戳');
    // 重开应用再跑一次也一样
    LocalDb.reloadForTest();
    await LocalDb.ensure();
    await DataCompat.run();
    expect(jsonEncode(LocalDb.dialogues), first);
  });

  test('原文笔记/书签/划线/阅读进度按著作名分键，升级后仍能读到', () async {
    SharedPreferences.setMockInitialValues({
      LocalStoreKeys.reader(_precision, LocalStoreKeys.readerNotes): jsonEncode([
        {'para': 12, 'text': '商品的价值由劳动时间决定', 'created_at': '2026-01-01T11:00:00'},
      ]),
      LocalStoreKeys.reader(_precision, LocalStoreKeys.readerBookmarks): jsonEncode([
        {'page': 7, 'label': '第一章'},
      ]),
      LocalStoreKeys.reader(_precision, LocalStoreKeys.readerHighlights): jsonEncode([
        {'para': 3, 'start': 0, 'end': 6, 'color': 'yellow'},
      ]),
      LocalStoreKeys.reader(_precision, LocalStoreKeys.readerLastPage): 7,
      LocalStoreKeys.reader(_precision, LocalStoreKeys.readerFontSize): 20.0,
    });
    LocalDb.reloadForTest();
    await LocalDb.ensure();
    await DataCompat.run();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LocalStoreKeys.reader(_precision, LocalStoreKeys.readerNotes)),
        contains('商品的价值由劳动时间决定'));
    expect(prefs.getInt(LocalStoreKeys.reader(_precision, LocalStoreKeys.readerLastPage)), 7,
        reason: '原文浏览记录不能丢');
    expect(prefs.getDouble(LocalStoreKeys.reader(_precision, LocalStoreKeys.readerFontSize)), 20.0);

    final stats = await DataCompat.stats();
    expect(stats['notes'], 1);
    expect(stats['bookmarks'], 1);
    expect(stats['highlights'], 1);
    expect(stats['read_works'], 1);
  });

  test('大模型 API 设置不因升级被改（含密钥）', () async {
    SharedPreferences.setMockInitialValues({
      LocalStoreKeys.settings: jsonEncode({
        'llm_config': {
          'LLM_API_KEY': 'sk-test-123',
          'LLM_BASE_URL': 'https://api.example.com',
          'LLM_MODEL': 'qwen-plus',
        },
      }),
    });
    LocalDb.reloadForTest();
    await LocalDb.ensure();
    await DataCompat.run();
    final cfg = LocalDb.settings['llm_config'] as Map;
    expect(cfg['LLM_API_KEY'], 'sk-test-123');
    expect(cfg['LLM_BASE_URL'], 'https://api.example.com');
    expect(cfg['LLM_MODEL'], 'qwen-plus');
    final stats = await DataCompat.stats();
    expect(stats['llm_configured'], 1);
  });
}
