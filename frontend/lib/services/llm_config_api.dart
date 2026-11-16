// 「功能中心 → AI 对话引擎」配置接口（单机版）。
//
// 走 ApiClient → LocalRouter → LlmConfigStore，语义与后端
// `api/llm_config_routes.py` 一致：GET 只回掩码、POST 保存、POST /test 真测一次。
import 'api_client.dart';

class LlmConfigApi {
  LlmConfigApi._();

  static Future<Map<String, dynamic>> status({bool fresh = false}) =>
      ApiClient.get('/api/llm-config', fresh: fresh);

  static Future<Map<String, dynamic>> save(Map<String, dynamic> body) =>
      ApiClient.post('/api/llm-config', body);

  static Future<Map<String, dynamic>> test() =>
      ApiClient.post('/api/llm-config/test', const {});

  static Future<Map<String, dynamic>> clear() =>
      ApiClient.post('/api/llm-config', const {'__action__': 'clear'});
}
