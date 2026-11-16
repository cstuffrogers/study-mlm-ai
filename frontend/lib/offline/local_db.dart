// 单机版本地数据仓：学情/进度/答题/对话全部存本机（SharedPreferences）。
//
// 全部文档一次读进内存、改动后整篇回写（体积都在几十 KB 级别），
// 因此业务层像操作普通 Map 一样简单，不需要 SQL。
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_config.dart';

class LocalDb {
  LocalDb._();

  static const String _kMastery = 'off_mastery';
  static const String _kProgress = 'off_progress';
  static const String _kAttempts = 'off_attempts';
  static const String _kTests = 'off_tests';
  static const String _kDialogues = 'off_dialogues';
  static const String _kSettings = 'off_settings';
  static const String _kSignals = 'off_signals';

  static SharedPreferences? _prefs;
  static bool _memoryOnly = false;
  static bool _ready = false;
  static Future<void>? _loading;

  /// routeId -> {nodeId: record}
  static Map<String, dynamic> mastery = {};
  /// routeId -> {sectionId: {status, anchor, updated_at}}
  static Map<String, dynamic> progress = {};
  /// 作答流水（列表，最新在后）
  static List<dynamic> attempts = [];
  /// testId -> {section_id, route_id, item_ids, status, total_score, created_at}
  static Map<String, dynamic> tests = {};
  /// dialogueId -> {id, title, current_mode, created_at, updated_at, messages: []}
  static Map<String, dynamic> dialogues = {};
  /// 用户设置（当前路线、阅读偏好等）
  static Map<String, dynamic> settings = {};
  /// 学情信号（对话/费曼）：[{node_id, type, intensity, created_at}]
  static List<dynamic> signals = [];

  static String get userId => kDemoUserId;

  static String get routeId =>
      (settings['route_id'] as String?)?.isNotEmpty == true ? settings['route_id'] as String : 'route_A';

  static set routeId(String v) => settings['route_id'] = v;

  static Future<void> ensure() {
    if (_ready) return Future.value();
    return _loading ??= () async {
      try {
        _prefs = await SharedPreferences.getInstance();
      } catch (e) {
        // 测试环境没有插件实现时退化为纯内存，读写照常工作。
        _memoryOnly = true;
        debugPrint('LocalDb memory-only: $e');
      }
      mastery = _readMap(_kMastery);
      progress = _readMap(_kProgress);
      attempts = _readList(_kAttempts);
      tests = _readMap(_kTests);
      dialogues = _readMap(_kDialogues);
      settings = _readMap(_kSettings);
      signals = _readList(_kSignals);
      _ready = true;
    }();
  }

  static Map<String, dynamic> _readMap(String key) {
    final raw = _memoryOnly ? null : _prefs?.getString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  static List<dynamic> _readList(String key) {
    final raw = _memoryOnly ? null : _prefs?.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return jsonDecode(raw) as List;
    } catch (_) {
      return [];
    }
  }

  static Future<void> flush() async {
    if (!_ready) return;
    if (_memoryOnly || _prefs == null) return;
    final p = _prefs!;
    await p.setString(_kMastery, jsonEncode(mastery));
    await p.setString(_kProgress, jsonEncode(progress));
    await p.setString(_kAttempts, jsonEncode(attempts));
    await p.setString(_kTests, jsonEncode(tests));
    await p.setString(_kDialogues, jsonEncode(dialogues));
    await p.setString(_kSettings, jsonEncode(settings));
    await p.setString(_kSignals, jsonEncode(signals));
  }

  /// 只刷某个文档（写操作后调用，避免每次都整库序列化）
  static Future<void> flushKey(String key) async {
    if (!_ready || _memoryOnly || _prefs == null) return;
    final p = _prefs!;
    switch (key) {
      case 'mastery':
        await p.setString(_kMastery, jsonEncode(mastery));
      case 'progress':
        await p.setString(_kProgress, jsonEncode(progress));
      case 'attempts':
        await p.setString(_kAttempts, jsonEncode(attempts));
      case 'tests':
        await p.setString(_kTests, jsonEncode(tests));
      case 'dialogues':
        await p.setString(_kDialogues, jsonEncode(dialogues));
      case 'settings':
        await p.setString(_kSettings, jsonEncode(settings));
      case 'signals':
        await p.setString(_kSignals, jsonEncode(signals));
    }
  }

  // ------------------------------------------------------------ 便捷读写
  static Map<String, dynamic> masteryFor(String route) =>
      (mastery[route] as Map?)?.cast<String, dynamic>() ?? {};

  static Map<String, dynamic> progressFor(String route) =>
      (progress[route] as Map?)?.cast<String, dynamic>() ?? {};

  static void putMastery(String route, String nodeId, Map<String, dynamic> rec) {
    final m = (mastery[route] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    m[nodeId] = rec;
    mastery[route] = m;
  }

  static void putProgress(
      String route, String sectionId, Map<String, dynamic> rec) {
    final m = (progress[route] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    m[sectionId] = rec;
    progress[route] = m;
  }

  static Map<String, dynamic>? dialogue(String id) =>
      (dialogues[id] as Map?)?.cast<String, dynamic>();

  static Future<void> resetAll() async {
    mastery = {};
    progress = {};
    attempts = [];
    tests = {};
    dialogues = {};
    settings = {};
    signals = [];
    await flush();
  }
}
