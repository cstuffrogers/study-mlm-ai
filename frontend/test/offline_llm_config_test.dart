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

}
