// 升级兼容闸门 + 本机数据备份/恢复。
//
// 设计红线（改动前先读）：
//   · 升级只做**加法**：补默认字段、补新键；绝不删除、绝不重命名、绝不清空；
//   · 每次启动跑一遍 run()，必须幂等——第二遍不能再改动任何东西；
//   · 备份/恢复只覆盖同名记录，**不删除**备份里没有的数据；
//   · API Key 默认不进备份（导出即字符串，容易外泄），换机后请重新填写；
//   · 备份格式带 format 版本号，将来格式变化要能在 import 里识别并兼容。
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_meta.dart';
import 'local_db.dart';
import 'local_store_keys.dart';

class DataCompat {
  DataCompat._();

  /// 本机数据格式版本。升级时只在需要迁移时 +1。
  static const int schema = 2;

  static const int backupFormat = 1;

  /// 启动时调用一次。幂等。
  static Future<void> run() async {
    await LocalDb.ensure();
    await _normalizeDialogues();
    final known = LocalDb.settings['data_schema'];
    if (known is! int || known < schema) {
      // 1 号是「首个正式发布」的隐式版本（没有登记过）。
      LocalDb.settings['data_schema'] = schema;
      LocalDb.settings['data_schema_updated_at'] = _nowIso();
      await LocalDb.flushKey('settings');
      debugPrint('DataCompat: 本机数据已登记到 schema=$schema（未删除任何数据）');
    }
  }

  /// 老版本写下的消息可能缺 mode / created_at；补默认值即可，
  /// 不动正文、不动时间戳、不删任何一条消息。
  static Future<void> _normalizeDialogues() async {
    var touched = false;
    for (final entry in LocalDb.dialogues.entries) {
      final doc = entry.value;
      if (doc is! Map) continue;
      final msgs = doc['messages'];
      if (msgs is! List) continue;
      for (final m in msgs) {
        if (m is! Map) continue;
        if (!m.containsKey('mode')) {
          m['mode'] = doc['current_mode'] ?? 'explain';
          touched = true;
        }
        if (!m.containsKey('created_at')) {
          m['created_at'] = doc['created_at'] ?? '';
          touched = true;
        }
      }
    }
    if (touched) await LocalDb.flushKey('dialogues');
  }

  // ---------------------------------------------------------------- 数据体检
  /// 界面上「我的数据」那一屏的数字，全部现算，不做缓存。
  static Future<Map<String, int>> stats() async {
    await LocalDb.ensure();
    var messages = 0;
    for (final d in LocalDb.dialogues.values) {
      if (d is Map && d['messages'] is List) {
        messages += (d['messages'] as List).length;
      }
    }
    var masteryNodes = 0;
    for (final r in LocalDb.mastery.values) {
      if (r is Map) masteryNodes += r.length;
    }
    final reader = await _readerValues();
    var notes = 0;
    var bookmarks = 0;
    var highlights = 0;
    var readWorks = 0;
    for (final e in reader.entries) {
      final key = e.key;
      final value = e.value;
      int countOf(String suffix) {
        if (!key.endsWith('_$suffix')) return 0;
        if (value is! String || value.isEmpty) return 0;
        try {
          final list = jsonDecode(value);
          return list is List ? list.length : 0;
        } catch (_) {
          return 0;
        }
      }

      notes += countOf(LocalStoreKeys.readerNotes);
      bookmarks += countOf(LocalStoreKeys.readerBookmarks);
      highlights += countOf(LocalStoreKeys.readerHighlights);
      if (key.endsWith('_${LocalStoreKeys.readerLastPage}')) {
        final page = value is int ? value : int.tryParse('$value');
        if (page != null && page > 0) readWorks++;
      }
    }
    return {
      'dialogues': LocalDb.dialogues.length,
      'messages': messages,
      'attempts': LocalDb.attempts.length,
      'tests': LocalDb.tests.length,
      'mastery_nodes': masteryNodes,
      'notes': notes,
      'bookmarks': bookmarks,
      'highlights': highlights,
      'read_works': readWorks,
      'llm_configured':
          (LocalDb.settings['llm_config'] is Map) && _hasApiKey() ? 1 : 0,
    };
  }

  static bool _hasApiKey() {
    final cfg = LocalDb.settings['llm_config'];
    if (cfg is! Map) return false;
    final k = cfg['LLM_API_KEY'];
    return k is String && k.isNotEmpty;
  }

  // ---------------------------------------------------------------- 导出
  /// 导出为 JSON 字符串。includeApiKey=false 时抹掉密钥（默认）。
  static Future<String> exportJson({bool includeApiKey = false}) async {
    await LocalDb.ensure();
    Map<String, dynamic> settings =
        jsonDecode(jsonEncode(LocalDb.settings)) as Map<String, dynamic>;
    if (!includeApiKey) {
      final cfg = settings['llm_config'];
      if (cfg is Map) {
        final copy = Map<String, dynamic>.from(cfg);
        copy.remove('LLM_API_KEY');
        settings['llm_config'] = copy;
      }
    }
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'xxmz',
      'format': backupFormat,
      'data_schema': schema,
      'client_version': AppMeta.clientVersion,
      'user_id': LocalDb.userId,
      'route_id': LocalDb.routeId,
      'exported_at': _nowIso(),
      'docs': {
        LocalStoreKeys.mastery: LocalDb.mastery,
        LocalStoreKeys.progress: LocalDb.progress,
        LocalStoreKeys.attempts: LocalDb.attempts,
        LocalStoreKeys.tests: LocalDb.tests,
        LocalStoreKeys.dialogues: LocalDb.dialogues,
        LocalStoreKeys.settings: settings,
        LocalStoreKeys.signals: LocalDb.signals,
        LocalStoreKeys.badges: LocalDb.badges,
      },
      'reader': (await _readerValues())
        ..removeWhere((k, v) => v == null || (v is String && v.isEmpty)),
    });
  }

  // ---------------------------------------------------------------- 恢复
  /// 合并恢复：同名记录以备份为准，备份里没有的本机数据**原样保留**。
  /// 返回各项恢复条数；解析失败抛 [FormatException]。
  static Future<Map<String, int>> importJson(String raw,
      {bool keepCurrentApiKey = true}) async {
    await LocalDb.ensure();
    final Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } catch (e) {
      throw FormatException('不是合法的 JSON：$e');
    }
    if (parsed is! Map) throw const FormatException('备份文件顶层必须是对象');
    if (parsed['app'] != null && parsed['app'] != 'xxmz') {
      throw const FormatException('这不是本软件的备份文件');
    }
    final format = parsed['format'];
    if (format is int && format > backupFormat) {
      throw FormatException('备份格式 v$format 比本版本（v$backupFormat）新，请先升级软件');
    }
    // D159：数据结构版本同样不可高于本版本——否则新版写下的新增字段会被
    // 老代码静默丢弃（老代码不认识、merge 不进去，也不报错）。
    final bSchema = parsed['data_schema'];
    if (bSchema is int && bSchema > DataCompat.schema) {
      throw FormatException(
          '备份数据结构 v$bSchema 比本版本（v$schema）新，请先升级软件再恢复');
    }

    final counts = <String, int>{};
    final docs = parsed['docs'];
    if (docs is Map) {
      counts.addAll(_mergeDocs(docs.cast<String, dynamic>(),
          keepCurrentApiKey: keepCurrentApiKey));
    }
    final reader = parsed['reader'];
    if (reader is Map) {
      final prefs = await _prefsOrNull();
      var n = 0;
      for (final e in reader.entries) {
        final key = '${e.key}';
        if (LocalStoreKeys.readerWorkOf(key) == null) continue;
        final v = e.value;
        if (prefs != null) {
          if (v is int) {
            await prefs.setInt(key, v);
          } else if (v is double) {
            await prefs.setDouble(key, v);
          } else {
            await prefs.setString(key, '$v');
          }
        }
        n++;
      }
      counts['reader_keys'] = n;
    }
    await LocalDb.flush();
    return counts;
  }

  static Map<String, int> _mergeDocs(Map<String, dynamic> docs,
      {required bool keepCurrentApiKey}) {
    final counts = <String, int>{};
    // 单层对象文档：只合并 Map 条目（非对象条目静默丢弃，防止备份把
    // 对话/测验文档里的既有记录整体换成非法值）。
    void mergeMap(String key, Map<String, dynamic> current, Object? incoming) {
      if (incoming is! Map) return;
      for (final e in incoming.entries) {
        if (e.value is! Map) continue;
        // 字段级合并：同名记录以备份为准，但备份记录里缺失的字段保留本地
        // 已有值，避免旧备份（缺新字段）整体覆盖把本地字段清空。
        final existing = current[e.key];
        current[e.key] = (existing is Map)
            ? {...existing.cast<String, dynamic>(),
                ...e.value.cast<String, dynamic>()}
            : e.value;
      }
      counts[key] = incoming.length;
    }

    /// 两层文档（routeId -> {nodeId / sectionId: 记录}）必须**逐条合并**：
    /// 直接 addAll 会把整条路线的旧记录盖掉，造成「恢复一次丢了一条线」。
    ///
    /// 防御：备份可能被篡改/伪造。`inner` 不是 Map 时**跳过**而不是照单覆盖——
    /// 否则一个字符串就能把某条路线的整份掌握/进度文档盖成垃圾，后续读取整线失效。
    void mergeNested(String key, Map<String, dynamic> current, Object? incoming) {
      if (incoming is! Map) return;
      var added = 0;
      for (final e in incoming.entries) {
        final route = '${e.key}';
        final inner = e.value;
        if (inner is! Map) continue; // 非对象条目丢弃，保护既有路线文档
        final existing = current[route];
        if (existing is Map) {
          // 逐条字段级合并：同名节点记录以备份为准，但备份缺失的字段保留
          // 本地已有值，避免旧备份把新字段整体覆盖掉。
          final merged = Map<String, dynamic>.from(existing);
          for (final r in inner.entries) {
            final ex = merged[r.key];
            if (r.value is Map) {
              merged[r.key] = (ex is Map)
                  ? {...ex.cast<String, dynamic>(),
                      ...r.value.cast<String, dynamic>()}
                  : r.value;
            }
          }
          current[route] = merged;
        } else {
          current[route] = inner;
        }
        added += inner.length;
      }
      counts[key] = added;
    }

    mergeNested(LocalStoreKeys.mastery, LocalDb.mastery, docs[LocalStoreKeys.mastery]);
    mergeNested(LocalStoreKeys.progress, LocalDb.progress,
        docs[LocalStoreKeys.progress]);
    mergeMap(LocalStoreKeys.tests, LocalDb.tests, docs[LocalStoreKeys.tests]);
    mergeMap(
        LocalStoreKeys.dialogues, LocalDb.dialogues, docs[LocalStoreKeys.dialogues]);

    mergeMap(LocalStoreKeys.badges, LocalDb.badges, docs[LocalStoreKeys.badges]);

    final settingsIn = docs[LocalStoreKeys.settings];
    if (settingsIn is Map) {
      final incoming = settingsIn.cast<String, dynamic>();
      // 备份里默认没有密钥：保留本机现有的，避免「恢复一次把 API 配好又丢了」
      final localCfg = LocalDb.settings['llm_config'];
      LocalDb.settings.addAll(incoming);
      if (keepCurrentApiKey && localCfg is Map) {
        final merged = (LocalDb.settings['llm_config'] as Map?) ?? {};
        final localKey = localCfg['LLM_API_KEY'];
        if (localKey is String && localKey.isNotEmpty) {
          final m = Map<String, dynamic>.from(merged);
          m['LLM_API_KEY'] = localKey;
          LocalDb.settings['llm_config'] = m;
        }
      }
      counts[LocalStoreKeys.settings] = incoming.length;
    }

    for (final key in [LocalStoreKeys.attempts, LocalStoreKeys.signals]) {
      final incoming = docs[key];
      if (incoming is! List) continue;
      final current = key == LocalStoreKeys.attempts
          ? LocalDb.attempts
          : LocalDb.signals;
      // 按内容去重合并，顺序保留（本机在前、备份在后），不丢任一侧。
      // 只接受 Map 条目：非对象条目（字符串/数字等伪造数据）直接丢弃，
      // 避免脏条目混进作答/信号流水，拖垮后续按 Map 读取的统计。
      final seen = current.whereType<Map>().map((e) => jsonEncode(e)).toSet();
      var added = 0;
      for (final item in incoming) {
        if (item is! Map) continue;
        if (seen.add(jsonEncode(item))) {
          current.add(item);
          added++;
        }
      }
      counts[key] = added;
    }
    return counts;
  }

  // ---------------------------------------------------------------- 底层
  static Future<SharedPreferences?> _prefsOrNull() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null; // 测试 / 无插件环境
    }
  }

  /// 取出全部 `reader_*` 键值（键 -> 原始值）。
  static Future<Map<String, Object?>> _readerValues() async {
    final prefs = await _prefsOrNull();
    if (prefs == null) return {};
    return {
      for (final k in prefs.getKeys())
        if (k.startsWith(LocalStoreKeys.readerPrefix)) k: prefs.get(k),
    };
  }

  static String _nowIso() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)}T'
        '${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }
}
