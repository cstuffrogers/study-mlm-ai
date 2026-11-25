// 在线大模型调用（OpenAI 兼容 /chat/completions）。
//
// 单机版没有后端进程，因此这里直接由 App 发 HTTPS 请求；协议、参数与后端
// `core/llm/cloud.py::CloudLayer._call` 保持一致，便于两边行为对齐：
//   · 推理型模型「关思维链」的参数各家不一（thinking / enable_thinking），
//     按实测稳定性逐个变体尝试，最后一个变体不带私有参数；
//   · 「正文为空」不算致命错误，换变体再试，避免只拿到思维链；
//   · 交互式对话用更短的超时且不重试，端点不通时尽快回落本机引擎。
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_config_store.dart';

class LlmResult {
  const LlmResult({
    required this.ok,
    this.text = '',
    this.message = '',
    this.source = 'error',
    this.model = '',
    this.elapsedMs = 0,
    this.statusCode,
    this.variant = '',
  });

  final bool ok;
  final String text;
  final String message;
  final String source; // 'cloud' | 'error'
  final String model;
  final int elapsedMs;
  final int? statusCode;
  final String variant;

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'source': source,
        'model': model,
        'elapsed_ms': elapsedMs,
        'message': message,
        'preview': text.length > 80 ? text.substring(0, 80) : text,
        if (statusCode != null) 'status_code': statusCode,
      };
}

class LlmClient {
  LlmClient._();

  /// 关思维链的私有参数变体（与后端 _THINK / _ENABLE / _BOTH 同序）
  static const List<Map<String, Object>> _thinkOff = [
    {
      'thinking': {'type': 'disabled'},
    },
    {'enable_thinking': false},
    {
      'thinking': {'type': 'disabled'},
      'enable_thinking': false,
    },
    <String, Object>{},
  ];

  static const List<Map<String, Object>> _thinkOn = [
    <String, Object>{},
    {
      'thinking': {'type': 'disabled'},
    },
    {'enable_thinking': false},
  ];

  /// 对话（对话浮层 / 章节问答）
  static Future<LlmResult> chat(
    LlmConfig cfg, {
    required String system,
    required String user,
    double? timeoutSec,
    int? retries,
    http.Client? client,
    double temperature = 0.4,
  }) {
    if (!cfg.enabled) {
      return Future.value(const LlmResult(
        ok: false,
        message: '未配置 API Key / Base URL / 模型，使用本机引擎',
      ));
    }
    final body = <String, dynamic>{
      'model': cfg.model,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'max_tokens': cfg.maxTokens,
      'temperature': temperature,
      'stream': false,
    };
    return _post(
      cfg,
      body,
      timeoutSec: timeoutSec ?? cfg.interactiveTimeout,
      retries: retries ?? 0,
      client: client,
    );
  }

  /// 「测试连接」：真实发一条极短 prompt，不重试、不写任何档案
  static Future<LlmResult> test(LlmConfig cfg, {http.Client? client}) {
    if (!cfg.enabled) {
      return Future.value(const LlmResult(
        ok: false,
        message: '未配齐 API Key / Base URL / 模型，当前为本机引擎',
      ));
    }
    final body = <String, dynamic>{
      'model': cfg.model,
      'messages': [
        {'role': 'user', 'content': '请只回复：连接成功'},
      ],
      'max_tokens': 32,
      'stream': false,
    };
    return _post(
      cfg,
      body,
      timeoutSec: cfg.timeout < 15 ? cfg.timeout : 15,
      retries: 0,
      client: client,
    );
  }

  static Future<LlmResult> _post(
    LlmConfig cfg,
    Map<String, dynamic> body, {
    required double timeoutSec,
    required int retries,
    http.Client? client,
  }) async {
    final owned = client == null;
    final http.Client c = client ?? http.Client();
    final uri = Uri.parse('${cfg.baseUrl}/chat/completions');
    final variants = cfg.disableThinking ? _thinkOff : _thinkOn;
    final stopwatch = Stopwatch()..start();
    final deadline = timeoutSec;
    final errors = <String>[];
    var emptyBody = 0;
    int? lastStatus;

    try {
      for (var vi = 0; vi < variants.length; vi++) {
        final variant = variants[vi];
        final payload = jsonEncode({...body, ...variant});
        for (var attempt = 0; attempt <= retries; attempt++) {
          final remaining = deadline - stopwatch.elapsedMilliseconds / 1000.0;
          if (remaining <= 0.2) {
            errors.add('总超时预算（${timeoutSec.toInt()}s）耗尽');
            return LlmResult(
              ok: false,
              message: '连接失败：${errors.first}',
              model: cfg.model,
              elapsedMs: stopwatch.elapsedMilliseconds,
              variant: _nameOf(vi),
            );
          }
          try {
            final resp = await c
                .post(
                  uri,
                  headers: {
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer ${cfg.apiKey}',
                  },
                  body: payload,
                )
                .timeout(Duration(milliseconds: (remaining * 1000).round()));
            lastStatus = resp.statusCode;
            if (resp.statusCode >= 200 && resp.statusCode < 300) {
              final text = _extract(resp.bodyBytes);
              if (text.isNotEmpty) {
                return LlmResult(
                  ok: true,
                  text: text,
                  message: '连接成功，模型已返回文本',
                  source: 'cloud',
                  model: cfg.model,
                  elapsedMs: stopwatch.elapsedMilliseconds,
                  statusCode: resp.statusCode,
                  variant: _nameOf(vi),
                );
              }
              // 只回了思维链/空正文：换变体继续
              emptyBody++;
              errors.add('${_nameOf(vi)}: 正文为空');
              break;
            }
            final snippet = _snippet(resp.bodyBytes);
            errors.add('${_nameOf(vi)}: HTTP ${resp.statusCode} $snippet');
            // 4xx（参数不被接受/鉴权失败）换变体无意义但无害；5xx/429 值得重试
            if (resp.statusCode == 401 || resp.statusCode == 403) break;
            if (resp.statusCode >= 500 || resp.statusCode == 429) continue;
            break;
          } on TimeoutException {
            errors.add('${_nameOf(vi)}: 请求超时');
            return LlmResult(
              ok: false,
              message: '连接失败：请求超时（${timeoutSec.toInt()}s）',
              model: cfg.model,
              elapsedMs: stopwatch.elapsedMilliseconds,
              statusCode: lastStatus,
              variant: _nameOf(vi),
            );
          } catch (e) {
            errors.add('${_nameOf(vi)}: ${e.runtimeType}: $e');
            break;
          }
        }
      }
      final msg = errors.isEmpty ? '未返回云端文本' : errors.first;
      return LlmResult(
        ok: false,
        message: '连接失败：$msg${emptyBody > 0 ? '（多次空正文）' : ''}',
        model: cfg.model,
        elapsedMs: stopwatch.elapsedMilliseconds,
        statusCode: lastStatus,
        variant: 'exhausted',
      );
    } finally {
      if (owned) c.close();
    }
  }

  static String _nameOf(int index) => switch (index) {
        0 => 'primary',
        1 => 'enable_thinking',
        2 => 'both',
        _ => 'standard',
      };

  static String _extract(List<int> bytes) {
    try {
      final data = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      if (data is! Map) return '';
      final choices = data['choices'];
      if (choices is! List || choices.isEmpty) return '';
      final first = choices.first;
      if (first is! Map) return '';
      final message = first['message'];
      if (message is Map) {
        final content = message['content'];
        if (content is String) return content.trim();
        if (content is List) {
          final buf = StringBuffer();
          for (final part in content) {
            if (part is Map && part['text'] is String) {
              buf.write(part['text']);
            }
          }
          return buf.toString().trim();
        }
      }
      final text = first['text'];
      return text is String ? text.trim() : '';
    } catch (_) {
      return '';
    }
  }

  static String _snippet(List<int> bytes) {
    final raw = utf8.decode(bytes, allowMalformed: true);
    final clean = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.length > 160 ? '${clean.substring(0, 160)}…' : clean;
  }
}
