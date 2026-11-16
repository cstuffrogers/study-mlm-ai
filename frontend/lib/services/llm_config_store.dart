// 大模型 API 配置（单机版）。
//
// 与后端 `services/llm_config_service.py` 同构：
//   · 「功能中心 → AI 对话引擎」页填写 API Key / Base URL / 模型；
//   · 填写后对话走真实大模型（OpenAI 兼容协议），不填则用本机检索式引擎；
//   · 凭证只写本机 SharedPreferences，不上传、不写正文库；
//   · GET 只回掩码，绝不回传完整密钥。
//
// 与后端的差异（必须如实告知用户，不能假装等同）：
//   本机没有 .env 概念，因此「清空字段」= 恢复内置缺省值，不存在环境变量回落。
import 'dart:convert';

import '../offline/local_db.dart';

/// 生效中的大模型配置
class LlmConfig {
  const LlmConfig({
    this.apiKey = '',
    this.baseUrl = '',
    this.model = '',
    this.maxConcurrent = 3,
    this.maxRetries = 2,
    this.timeout = 60,
    this.interactiveTimeout = 30,
    this.maxTokens = 2048,
    this.disableThinking = true,
  });

  final String apiKey;
  final String baseUrl;
  final String model;
  final int maxConcurrent;
  final int maxRetries;
  final double timeout;
  final double interactiveTimeout;
  final int maxTokens;
  final bool disableThinking;

  /// 三项齐全才认为可走真实模型
  bool get enabled =>
      apiKey.isNotEmpty && baseUrl.isNotEmpty && model.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'LLM_API_KEY': apiKey,
        'LLM_BASE_URL': baseUrl,
        'LLM_MODEL': model,
        'LLM_MAX_CONCURRENT': '$maxConcurrent',
        'LLM_MAX_RETRIES': '$maxRetries',
        'LLM_TIMEOUT': _num(timeout),
        'LLM_INTERACTIVE_TIMEOUT': _num(interactiveTimeout),
        'LLM_MAX_TOKENS': '$maxTokens',
        'LLM_DISABLE_THINKING': disableThinking ? '1' : '0',
      };

  static String _num(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  factory LlmConfig.fromJson(Map<String, dynamic> raw) {
    num n(String key, num fallback) {
      final v = raw[key];
      if (v is num) return v;
      return num.tryParse('${v ?? ''}') ?? fallback;
    }

    final flag = '${raw['LLM_DISABLE_THINKING'] ?? '1'}'.toLowerCase();
    return LlmConfig(
      apiKey: '${raw['LLM_API_KEY'] ?? ''}',
      baseUrl: '${raw['LLM_BASE_URL'] ?? ''}',
      model: '${raw['LLM_MODEL'] ?? ''}',
      maxConcurrent: n('LLM_MAX_CONCURRENT', 3).toInt().clamp(1, 16),
      maxRetries: n('LLM_MAX_RETRIES', 2).toInt().clamp(0, 5),
      timeout: n('LLM_TIMEOUT', 60).toDouble(),
      interactiveTimeout: n('LLM_INTERACTIVE_TIMEOUT', 30).toDouble(),
      maxTokens: n('LLM_MAX_TOKENS', 2048).toInt().clamp(128, 8192),
      disableThinking: const ['1', 'true', 'yes'].contains(flag),
    );
  }
}

/// 配置校验失败（对应后端 ValueError → 400）
class LlmConfigError implements Exception {
  LlmConfigError(this.message);
  final String message;
  @override
  String toString() => message;
}

class LlmConfigStore {
  LlmConfigStore._();

  static const String _key = 'llm_config';

  /// 国产模型 OpenAI 兼容端点速查（只帮用户填地址，不涉及任何密钥）
  static const Map<String, Map<String, String>> presets = {
    'qwen': {
      'label': '通义千问',
      'base_url': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      'model': 'qwen-plus',
    },
    'deepseek': {
      'label': 'DeepSeek',
      'base_url': 'https://api.deepseek.com/v1',
      'model': 'deepseek-chat',
    },
    'wenxin': {
      'label': '文心一言',
      'base_url': 'https://qianfan.baidubce.com/v2',
      'model': 'ernie-4.0-8k',
    },
    'moonshot': {
      'label': 'Kimi',
      'base_url': 'https://api.moonshot.cn/v1',
      'model': 'moonshot-v1-8k',
    },
    'zhipu': {
      'label': '智谱 GLM',
      'base_url': 'https://open.bigmodel.cn/api/paas/v4',
      'model': 'glm-4-flash',
    },
  };

  static const String defaultBaseUrl =
      'https://dashscope.aliyuncs.com/compatible-mode/v1';
  static const String defaultModel = 'qwen-plus';

  static Map<String, dynamic> _raw() {
    final v = LocalDb.settings[_key];
    if (v is Map) return v.cast<String, dynamic>();
    return const {};
  }

  /// 生效配置（缺省值补齐）
  static LlmConfig load() {
    final raw = _raw();
    return LlmConfig.fromJson({
      'LLM_BASE_URL': defaultBaseUrl,
      'LLM_MODEL': defaultModel,
      ...raw,
    });
  }

  static String masked(String secret) {
    if (secret.isEmpty) return '';
    if (secret.length <= 8) return '••••••••';
    return '${secret.substring(0, 4)}••••${secret.substring(secret.length - 4)}';
  }

  /// 给界面的状态：只回掩码
  static Map<String, dynamic> status() {
    final cfg = load();
    return {
      'configured': cfg.enabled,
      'enabled': cfg.enabled,
      'masked_api_key': masked(cfg.apiKey),
      'api_key_set': cfg.apiKey.isNotEmpty,
      'base_url': cfg.baseUrl,
      'model': cfg.model,
      'max_concurrent': cfg.maxConcurrent,
      'max_retries': cfg.maxRetries,
      'timeout': cfg.timeout,
      'interactive_timeout': cfg.interactiveTimeout,
      'max_tokens': cfg.maxTokens,
      'disable_thinking': cfg.disableThinking,
      'mode': cfg.enabled ? 'cloud' : 'local',
      'mode_label': cfg.enabled ? '在线大模型' : '本机引擎',
      'storage': '本机（仅存于本设备）',
      'source': {
        'LLM_API_KEY': cfg.apiKey.isEmpty ? '未配置' : '本机配置',
        'LLM_BASE_URL': '本机配置',
        'LLM_MODEL': '本机配置',
      },
      'presets': {
        for (final e in presets.entries)
          e.key: {'base_url': e.value['base_url'], 'model': e.value['model']},
      },
      'preset_labels': {
        for (final e in presets.entries) e.key: e.value['label'],
      },
      'note': cfg.enabled
          ? '已启用在线大模型；断网或调用失败时自动回落到本机引擎。'
          : '未配置密钥，对话使用本机检索式引擎（不联网）。',
    };
  }

  /// 保存配置。语义与后端一致：
  /// · api_key 传空字符串 = 保留原密钥；传 `__CLEAR__` = 明确清空；
  /// · base_url / model 传 null = 本次不修改，传空 = 恢复缺省值。
  static Future<Map<String, dynamic>> save(Map<String, dynamic> body) async {
    await LocalDb.ensure();
    final saved = Map<String, dynamic>.from(_raw());

    final newKey = '${body['api_key'] ?? ''}'.trim();
    if (newKey == '__CLEAR__') {
      saved.remove('LLM_API_KEY');
    } else if (newKey.isNotEmpty) {
      if (!RegExp(r'^[\x20-\x7e]+$').hasMatch(newKey)) {
        throw LlmConfigError('API Key 只能包含 ASCII 可打印字符');
      }
      saved['LLM_API_KEY'] = newKey;
    }

    final baseRaw = body['base_url'];
    if (baseRaw != null) {
      final base = '$baseRaw'.trim();
      if (base.isNotEmpty) {
        if (!RegExp(r'^https?://\S+$').hasMatch(base)) {
          throw LlmConfigError('Base URL 必须是 http(s):// 开头的合法地址');
        }
        saved['LLM_BASE_URL'] = _stripSlash(base);
      } else {
        saved['LLM_BASE_URL'] = defaultBaseUrl;
      }
    }

    final modelRaw = body['model'];
    if (modelRaw != null) {
      final model = '$modelRaw'.trim();
      saved['LLM_MODEL'] = model.isEmpty ? defaultModel : model;
    }

    for (final spec in const [
      ('max_concurrent', 'LLM_MAX_CONCURRENT', 1.0, 16.0, true),
      ('max_retries', 'LLM_MAX_RETRIES', 0.0, 5.0, true),
      ('timeout', 'LLM_TIMEOUT', 3.0, 180.0, false),
      ('interactive_timeout', 'LLM_INTERACTIVE_TIMEOUT', 3.0, 120.0, false),
      ('max_tokens', 'LLM_MAX_TOKENS', 128.0, 8192.0, true),
    ]) {
      if (!body.containsKey(spec.$1) || body[spec.$1] == null) continue;
      final raw = '${body[spec.$1]}'.trim();
      if (raw.isEmpty) {
        saved.remove(spec.$2);
        continue;
      }
      final num = double.tryParse(raw);
      if (num == null) throw LlmConfigError('${spec.$1} 必须是数字');
      if (num < spec.$3 || num > spec.$4) {
        throw LlmConfigError(
            '${spec.$1} 必须在 ${spec.$3.toInt()}–${spec.$4.toInt()} 之间');
      }
      saved[spec.$2] = spec.$5 ? '${num.toInt()}' : LlmConfig._num(num);
    }

    if (body.containsKey('disable_thinking') && body['disable_thinking'] != null) {
      final v = '${body['disable_thinking']}'.toLowerCase();
      saved['LLM_DISABLE_THINKING'] =
          const ['1', 'true', 'yes'].contains(v) ? '1' : '0';
    }

    LocalDb.settings[_key] = jsonDecode(jsonEncode(saved)) as Map;
    await LocalDb.flushKey('settings');
    return status();
  }

  /// 清空全部配置（回到本机引擎）
  static Future<Map<String, dynamic>> clear() async {
    await LocalDb.ensure();
    LocalDb.settings.remove(_key);
    await LocalDb.flushKey('settings');
    return status();
  }

  static String _stripSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
