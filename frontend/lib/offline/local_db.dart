// 单机版本地数据仓：学情/进度/答题/对话全部存本机（SharedPreferences）。
//
// 全部文档一次读进内存、改动后整篇回写（体积都在几十 KB 级别），
// 因此业务层像操作普通 Map 一样简单，不需要 SQL。
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_config.dart';
import 'local_store_keys.dart';
import 'offline_content.dart';

class LocalDb {
  LocalDb._();

  // 键名统一登记在 local_store_keys.dart：改键名等于把老用户数据丢在旧键里。
  static const String _kMastery = LocalStoreKeys.mastery;
  static const String _kProgress = LocalStoreKeys.progress;
  static const String _kAttempts = LocalStoreKeys.attempts;
  static const String _kTests = LocalStoreKeys.tests;
  static const String _kDialogues = LocalStoreKeys.dialogues;
  static const String _kSettings = LocalStoreKeys.settings;
  static const String _kSignals = LocalStoreKeys.signals;

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
  ///
  /// 注意：每个 case 必须 `break`——Dart 允许 switch 空落（fall-through），
  /// 漏掉 break 会让任意单键 flush 实际把全部文档都写一遍。
  static Future<void> flushKey(String key) async {
    if (!_ready || _memoryOnly || _prefs == null) return;
    final p = _prefs!;
    switch (key) {
      case 'mastery':
        await p.setString(_kMastery, jsonEncode(mastery));
        break;
      case 'progress':
        await p.setString(_kProgress, jsonEncode(progress));
        break;
      case 'attempts':
        await p.setString(_kAttempts, jsonEncode(attempts));
        break;
      case 'tests':
        await p.setString(_kTests, jsonEncode(tests));
        break;
      case 'dialogues':
        await p.setString(_kDialogues, jsonEncode(dialogues));
        break;
      case 'settings':
        await p.setString(_kSettings, jsonEncode(settings));
        break;
      case 'signals':
        await p.setString(_kSignals, jsonEncode(signals));
        break;
    }
  }

  /// 取指定路线的作答流水（学情/校准/错题等分析只应看到本路线的数据）。
  ///
  /// 解析顺序（与后端「事件自带 route_id 优先」同口径）：
  ///  ① 记录自带 `route_id` → 直接匹配；
  ///  ② 无 `route_id` 但 `test_id` 在本机测试表 → 按测试归属路线；
  ///  ③ 无 `route_id` 但 `node_id` 可定位到节点 → 按节点所在章节的路线；
  ///  ④ 三者皆无（老版本遗留的手工/损坏数据）→ 归入当前路线，避免静默丢数据。
  static List<Map<String, dynamic>> attemptsForRoute(String routeId) {
    final out = <Map<String, dynamic>>[];
    for (final a in attempts.whereType<Map>()) {
      final rec = a.cast<String, dynamic>();
      final rid = '${rec['route_id'] ?? ''}';
      if (rid.isNotEmpty) {
        if (rid == routeId) out.add(rec);
        continue;
      }
      final testId = '${rec['test_id'] ?? ''}';
      if (testId.isNotEmpty) {
        final t = tests[testId];
        if (t is Map) {
          if ('${t['route_id'] ?? ''}' == routeId) out.add(rec);
          continue;
        }
      }
      final nodeId = '${rec['node_id'] ?? ''}';
      if (nodeId.isNotEmpty) {
        final node = OfflineContent.node(nodeId);
        final secId = '${node?['section_id'] ?? ''}';
        if (secId.isNotEmpty) {
          final secRoute = '${OfflineContent.sectionMeta(secId)?['route_id'] ?? ''}';
          if (secRoute.isNotEmpty) {
            // 节点归属路线明确：严格按该路线归属，与查询路线不符即排除
            // （原先 secRoute != routeId 时会落进兜底分支被归到当前路线，
            //  跨路线数据串线）。
            if (secRoute == routeId) out.add(rec);
            continue;
          }
        }
      }
      // 完全无法归属的遗留记录：按当前路线处理（不丢数据）
      out.add(rec);
    }
    return out;
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

  /// 仅供测试：丢掉内存缓存并重新从本机读取（模拟「升级后重启应用」）。
  /// 不会删除任何已存数据。
  @visibleForTesting
  static void reloadForTest() {
    _prefs = null;
    _memoryOnly = false;
    _ready = false;
    _loading = null;
    mastery = {};
    progress = {};
    attempts = [];
    tests = {};
    dialogues = {};
    settings = {};
    signals = [];
  }
}
