// 「功能中心 → AI 对话引擎」单机版回归测试：
//   · 配置读写/掩码/校验/清空语义与后端 llm_config_service 对齐；
//   · 在线模型调用（OpenAI 兼容）解析、变体降级、空正文处理；
//   · 未配置时对话走本机引擎，配置后走在线模型。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_router.dart';
import 'package:marxism_reader/offline/local_store_keys.dart';
import 'package:marxism_reader/services/llm_client.dart';
import 'package:marxism_reader/services/llm_config_store.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.ensure();
    LocalDb.settings.clear();
    // 冗余副本也要清：否则上一组用例写下的密钥会从副本里「自愈」回来，
    // 本组的「未配置」断言就不成立了。
    await LocalDb.setExtra(LocalStoreKeys.llmConfigShadow, null);
    LlmConfigStore.restoredFromShadow = false;
  });

  group('LlmConfigStore', () {
    test('未配置时如实报告：本机引擎、预设端点齐全、不回传密钥', () async {
      final s = LlmConfigStore.status();
      expect(s['configured'], false);
      expect(s['mode'], 'local');
      expect(s['api_key_set'], false);
      expect(s['masked_api_key'], '');
      expect(s['note'], contains('本机检索式引擎'));
      final presets = (s['presets'] as Map).cast<String, dynamic>();
      expect(presets.keys, containsAll(['qwen', 'deepseek', 'wenxin']));
      expect(presets['qwen']['base_url'], contains('dashscope'));
    });

    test('保存后立即生效，且状态里只有掩码没有完整密钥', () async {
      final s = await LlmConfigStore.save({
        'api_key': 'sk-test-1234567890abcdef',
        'base_url': 'https://api.deepseek.com/v1/',
        'model': 'deepseek-chat',
      });
      expect(s['configured'], true);
      expect(s['mode'], 'cloud');
      expect(s['base_url'], 'https://api.deepseek.com/v1');
      expect(s['model'], 'deepseek-chat');
      expect(s['masked_api_key'], 'sk-t••••cdef');
      expect(jsonEncode(s), isNot(contains('1234567890abcdef')));

      final cfg = LlmConfigStore.load();
      expect(cfg.enabled, true);
      expect(cfg.apiKey, 'sk-test-1234567890abcdef');
    });

    test('api_key 留空表示不修改已有密钥（与后端一致）', () async {
      await LlmConfigStore.save({'api_key': 'sk-aaaaaaaaaaaa'});
      final s = await LlmConfigStore.save({'api_key': '', 'model': 'qwen-max'});
      expect(s['model'], 'qwen-max');
      expect(LlmConfigStore.load().apiKey, 'sk-aaaaaaaaaaaa');
    });

    test('非法密钥/地址/数值被拒绝，且提示原因', () async {
      expect(() => LlmConfigStore.save({'api_key': '密钥中文'}),
          throwsA(isA<LlmConfigError>()));
      expect(() => LlmConfigStore.save({'base_url': 'ftp://x'}),
          throwsA(isA<LlmConfigError>()));
      expect(() => LlmConfigStore.save({'max_tokens': '99999'}),
          throwsA(isA<LlmConfigError>()));
      expect(LlmConfigStore.status()['configured'], false);
    });

    test('__CLEAR__ 清空密钥，回到本机引擎', () async {
      await LlmConfigStore.save({'api_key': 'sk-bbbbbbbbbbbb'});
      final s = await LlmConfigStore.save({'api_key': '__CLEAR__'});
      expect(s['configured'], false);
      expect(s['mode'], 'local');
      expect(LlmConfigStore.load().apiKey, '');
    });

    test('配置经 LocalRouter 暴露给界面（GET 掩码 / POST 保存 / 清空）', () async {
      final before = await LocalRouter.get('/api/llm-config', const {});
      expect(before['configured'], false);

      final saved = await LocalRouter.post('/api/llm-config', {
        'api_key': 'sk-router-0000001111',
        'base_url': 'https://api.moonshot.cn/v1',
        'model': 'moonshot-v1-8k',
        'disable_thinking': true,
      });
      expect(saved['configured'], true);
      expect(saved['masked_api_key'], 'sk-r••••1111');

      final after = await LocalRouter.get('/api/llm-config', const {});
      expect(after['model'], 'moonshot-v1-8k');

      final cleared =
          await LocalRouter.post('/api/llm-config', {'__action__': 'clear'});
      expect(cleared['configured'], false);
    });

    test('路由拒绝非法配置并抛 400（界面显示原因）', () async {
      expect(
        () => LocalRouter.post('/api/llm-config', {'base_url': 'not-a-url'}),
        throwsA(isA<LocalApiException>()
            .having((e) => e.status, 'status', 400)),
      );
    });
  });

  group('LlmClient', () {
    const cfg = LlmConfig(
      apiKey: 'sk-test',
      baseUrl: 'https://example.com/v1',
      model: 'qwen-plus',
      maxTokens: 512,
    );

    test('未配齐凭证时不发请求，直接说明用本机引擎', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return _json({});
      });
      final r = await LlmClient.chat(const LlmConfig(),
          system: 's', user: 'u', client: client);
      expect(r.ok, false);
      expect(called, false);
      expect(r.message, contains('本机引擎'));
    });

    test('正常返回：解析 choices[0].message.content', () async {
      final client = MockClient((req) async {
        expect(req.url.toString(), 'https://example.com/v1/chat/completions');
        expect(req.headers['Authorization'], 'Bearer sk-test');
        final body = jsonDecode(req.body) as Map;
        expect(body['model'], 'qwen-plus');
        return _json({
          'choices': [
            {
              'message': {'content': '连接成功：原文摘录 —— 《提纲》第一条'}
            }
          ]
        });
      });
      final r = await LlmClient.chat(cfg, system: 's', user: 'u', client: client);
      expect(r.ok, true);
      expect(r.source, 'cloud');
      expect(r.text, contains('连接成功'));
    });

    test('首个变体返回空正文时自动换变体，不把空回答当成功', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        final body = jsonDecode(req.body) as Map;
        if (calls == 1) {
          expect(body['thinking'], isNotNull);
          return _json({
            'choices': [
              {
                'message': {'content': ''}
              }
            ]
          });
        }
        return _json({
          'choices': [
            {
              'message': {'content': '第二变体正文'}
            }
          ]
        });
      });
      final r = await LlmClient.chat(cfg, system: 's', user: 'u', client: client);
      expect(r.ok, true);
      expect(r.text, '第二变体正文');
      expect(calls, greaterThan(1));
    });

    test('HTTP 401 直接失败并给出状态码，不谎报成功', () async {
      final client = MockClient((_) async => _json({'error': 'bad key'}, 401));
      final r = await LlmClient.chat(cfg, system: 's', user: 'u', client: client);
      expect(r.ok, false);
      expect(r.statusCode, 401);
      expect(r.message, contains('401'));
    });

    test('测试连接：未配齐时不做无意义请求', () async {
      var called = false;
      final r = await LlmClient.test(
        const LlmConfig(),
        client: MockClient((_) async {
          called = true;
          return _json({});
        }),
      );
      expect(r.ok, false);
      expect(called, false);
      expect(r.message, contains('本机引擎'));
    });
  });

  // 升级丢配置回归（D174）：用户报「更新 APP 后 AI 用不了、又得重新配置一遍」。
  // 根因是 settings 是「一次读出 + 整篇回写」的大文档，升级装包时进程被杀、
  // 写到一半被截断 → 整份读坏 → 被隔离、按空数据启动，掌握/进度都还在，
  // 只有设置类（AI 配置）没了。现在密钥多存一份独立副本，读不到就自愈。
  group('AI 配置自愈（升级后不用重填密钥）', () {
    const body = {
      'api_key': 'sk-selfheal-abcdef123456',
      'base_url': 'https://api.deepseek.com/v1',
      'model': 'deepseek-chat',
    };

    setUp(() async {
      LlmConfigStore.restoredFromShadow = false;
      SharedPreferences.setMockInitialValues({});
      LocalDb.reloadForTest();
      await LocalDb.ensure();
      LocalDb.settings.clear();
    });

    test('保存时同步写一份独立副本，清空时副本一起删', () async {
      await LlmConfigStore.save(body);
      final shadow = LocalDb.extra(LocalStoreKeys.llmConfigShadow);
      expect(shadow, isNotNull);
      expect(shadow, contains('sk-selfheal-abcdef123456'));

      await LlmConfigStore.clear();
      expect(LocalDb.extra(LocalStoreKeys.llmConfigShadow), isNull);
      expect(LlmConfigStore.load().enabled, false);
    });

    test('主存储丢了密钥，从副本自愈并写回主存储', () async {
      await LlmConfigStore.save(body);
      LlmConfigStore.restoredFromShadow = false;

      // 模拟「settings 整份读坏 → 按空数据启动」
      LocalDb.settings.clear();
      final cfg = LlmConfigStore.load();
      expect(cfg.enabled, true);
      expect(cfg.apiKey, 'sk-selfheal-abcdef123456');
      expect(cfg.model, 'deepseek-chat');
      expect(LlmConfigStore.restoredFromShadow, true);
      // 内存里已经写回主存储（异步落盘不影响本次会话可用）
      expect(LocalDb.settings['llm_config'], isA<Map>());
    });

    test('老用户升级上来：启动时把现有密钥补种成副本', () async {
      LocalDb.settings['llm_config'] = {
        'LLM_API_KEY': 'sk-legacy-999888',
        'LLM_BASE_URL': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        'LLM_MODEL': 'qwen-plus',
      };
      await LocalDb.flushKey('settings');
      expect(LocalDb.extra(LocalStoreKeys.llmConfigShadow), isNull);

      await LlmConfigStore.ensureShadow();
      expect(LocalDb.extra(LocalStoreKeys.llmConfigShadow),
          contains('sk-legacy-999888'));
      // 幂等：再跑一次内容不变
      final first = LocalDb.extra(LocalStoreKeys.llmConfigShadow);
      await LlmConfigStore.ensureShadow();
      expect(LocalDb.extra(LocalStoreKeys.llmConfigShadow), first);
    });

    test('「清空本机数据」后副本一起清，密钥不会自己活回来', () async {
      await LlmConfigStore.save(body);
      await LocalDb.resetAll();
      expect(LocalDb.extra(LocalStoreKeys.llmConfigShadow), isNull);
      expect(LlmConfigStore.load().enabled, false);
    });

    test('真的整份设置文档读坏（隔离 + 空启动）也能恢复密钥', () async {
      final shadow = jsonEncode({
        'LLM_API_KEY': 'sk-corrupt-case-777',
        'LLM_BASE_URL': 'https://api.deepseek.com/v1',
        'LLM_MODEL': 'deepseek-chat',
      });
      SharedPreferences.setMockInitialValues({
        'off_settings': '{"route_id": "route_A", ', // 截断的坏 JSON
        'off_llm_config_shadow': shadow,
      });
      LocalDb.reloadForTest();
      await LocalDb.ensure();

      // 坏文档被隔离、按空数据启动（其它数据仍在各自的键里）
      expect(LocalDb.corruptedOnLoad, contains('off_settings'));
      expect(LocalDb.settings, isEmpty);

      // 密钥照样能用，不用用户重填
      final cfg = LlmConfigStore.load();
      expect(cfg.enabled, true);
      expect(cfg.apiKey, 'sk-corrupt-case-777');
      expect(LlmConfigStore.restoredFromShadow, true);
    });
  });
}
