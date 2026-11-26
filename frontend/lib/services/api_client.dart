// 数据访问层（单机版）：不再发 HTTP 请求，改由本机 LocalRouter 处理。
//
// 保留原有语义以便上层零改动：
//   · get/post 返回同形状的 JSON Map；
//   · GET 仍有短 TTL 内存缓存 + 同 key 在途请求合并；
//   · 写操作后让相关 GET 缓存失效，页面立刻看到新状态。
import 'dart:async';

import '../offline/local_router.dart';

class ApiClient {
  /// 常规 GET 的短缓存：静态内容 30s，进度类接口由写操作主动失效。
  static const Duration cacheTtl = Duration(seconds: 30);

  static final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};
  static final Map<String, Future<Map<String, dynamic>>> _inflight =
      <String, Future<Map<String, dynamic>>>{};

  static Future<Map<String, dynamic>> get(String path,
      {Map<String, String>? query, bool fresh = false}) async {
    final key = _key(path, query);
    if (!fresh) {
      final c = _cache[key];
      if (c != null && !c.isExpired) return c.data;
      final running = _inflight[key];
      if (running != null) return running;
    } else {
      _cache.remove(key);
    }
    final f = _run(() => LocalRouter.get(path, query ?? const {}));
    _inflight[key] = f;
    try {
      final data = await f;
      _cache[key] = _CacheEntry(data);
      return data;
    } finally {
      if (identical(_inflight[key], f)) _inflight.remove(key);
    }
  }

  /// [invalidate] 为 false 时不动 GET 缓存：用于「只改选中态、不改进度」的写接口
  /// （如 select 路线），避免它把并行读取的 sections/guide 缓存清掉。
  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body,
      {bool invalidate = true}) async {
    final resp = await _run(() => LocalRouter.post(path, body));
    if (!invalidate) return resp;
    invalidatePrefix('/api/routes');
    if (path.startsWith('/api/llm-config')) {
      invalidatePrefix('/api/llm-config');
    }
    // 勋章：markRead 之后首页红点数量与开箱动画都靠 GET /api/badges/unseen 判断，
    // 不失效会读到 30s 内的旧缓存 —— 表现为「刚收下勋章，红点数字还在、点开又弹一次」。
    if (path.startsWith('/api/badges')) {
      invalidatePrefix('/api/badges');
    }
    if (path.startsWith('/api/quiz') ||
        path.startsWith('/api/review') ||
        path.startsWith('/api/mastery') ||
        path.startsWith('/api/sync') ||
        path.startsWith('/api/profile')) {
      invalidatePrefix('/api/');
    }
    return resp;
  }

  /// 删除类写操作（如错题本删除作答记录）。与 post 同语义：成功后让相关 GET 失效。
  static Future<Map<String, dynamic>> delete(String path,
      {Map<String, String>? query, bool invalidate = true}) async {
    final resp = await _run(() => LocalRouter.delete(path, query ?? const {}));
    if (!invalidate) return resp;
    invalidatePrefix('/api/');
    return resp;
  }

  static Future<Map<String, dynamic>> _run(
      Future<Map<String, dynamic>> Function() task) async {
    try {
      return await task();
    } on LocalApiException catch (e) {
      throw ApiException(e.status, e.detail);
    }
  }

  static String _key(String path, Map<String, String>? query) {
    if (query == null || query.isEmpty) return path;
    final entries = query.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return '$path?${entries.map((e) => '${e.key}=${e.value}').join('&')}';
  }

  /// 让指定前缀的 GET 缓存失效；无参则清空。
  static void invalidatePrefix([String prefix = '']) {
    if (prefix.isEmpty) {
      _cache.clear();
      return;
    }
    _cache.removeWhere((k, _) => k.contains(prefix));
  }
}

class _CacheEntry {
  final Map<String, dynamic> data;
  final int at = DateTime.now().millisecondsSinceEpoch;
  _CacheEntry(this.data);
  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch - at > ApiClient.cacheTtl.inMilliseconds;
}

class ApiException implements Exception {
  final int status;
  final dynamic detail;
  ApiException(this.status, this.detail);
  @override
  String toString() => 'ApiException($status): $detail';
}
