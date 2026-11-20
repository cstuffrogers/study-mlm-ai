// 离线暂存队列 + 同步控制器（NFR-004 / D7）
// 服务端权威：在线时直接上报进度；离线时本地暂存，恢复连接或进入页面时批量合并。
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sync_service_api.dart';
import '../offline/local_store_keys.dart';

class SyncController extends ChangeNotifier {
  // 键名登记在 local_store_keys.dart（升级不能改键，否则待同步队列丢失）
  static const _kQueue = LocalStoreKeys.syncQueue;
  final SyncApi _api;

  /// `api` 只在测试里注入替身；业务代码用默认实现。
  SyncController({SyncApi? api}) : _api = api ?? SyncApi();
  bool _online = true;
  int _pending = 0;
  String _message = '';

  bool get online => _online;
  int get pending => _pending;
  String get message => _message;

  Future<void> init() async {
    try {
      await _refreshPending();
    } catch (_) {
      // 插件不可用（如纯单测环境）时静默降级
    }
  }

  Future<List<Map<String, dynamic>>> _loadQueue() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_kQueue);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveQueue(List<Map<String, dynamic>> q) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kQueue, jsonEncode(q));
    _pending = q.length;
    notifyListeners();
  }

  Future<void> _refreshPending() async {
    final q = await _loadQueue();
    _pending = q.length;
    notifyListeners();
  }

  /// 清空离线待同步队列（重置学习进度时调用，避免重置前的旧事件回灌覆盖）。
  static Future<void> clearQueue() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_kQueue);
    } catch (_) {
      // 插件不可用（如纯单测环境）时静默降级
    }
  }

  /// 上报学习进度（断点续学）。离线则入队。
  Future<void> reportProgress(String sectionId, int lastPosition,
      {String routeId = 'route_A', String status = 'in_progress'}) async {
    final ev = {
      'type': 'progress',
      'section_id': sectionId,
      'last_position': lastPosition,
      'status': status,
      'route_id': routeId,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    try {
      final res = await _api.push([ev], routeId: routeId);
      _online = true;
      final rejected = res['skipped'];
      if (rejected is int && rejected > 0) {
        // 服务端拒收（章节不存在 / 路线不认识）→ 与离线同待遇：留在队列重试，
        // 不能回一句「已同步」把这条进度悄悄吞掉。
        final q = await _loadQueue();
        q.add(ev);
        await _saveQueue(_trimQueue(q));
        _message = '服务端未接受这条进度，已暂存 $_pending 条待重试';
      } else {
        _message = '已同步';
      }
      notifyListeners();
    } catch (_) {
      final q = await _loadQueue();
      q.add(ev);
      await _saveQueue(_trimQueue(q));
      _online = false;
      _message = '当前离线，已暂存 $_pending 条进度，恢复后自动同步';
      notifyListeners();
    }
  }

  /// 离线队列上限（离线学很久也不该把 prefs 撑爆）：超出丢**最旧**的，
  /// 保留最近的进度——服务端按事件顺序应用，最新一条才决定最终状态。
  static const int maxQueuedEvents = 500;

  List<Map<String, dynamic>> _trimQueue(List<Map<String, dynamic>> q) =>
      q.length <= maxQueuedEvents
          ? q
          : q.sublist(q.length - maxQueuedEvents);

  /// 将暂存事件批量合并到服务端（进入页面/恢复连接时调用）。
  ///
  /// 两条口径（原先都错）：
  ///  · **按事件的 route_id 分组上报**：队列里可能混着用户在 route_B 学过的事件，
  ///    整批用默认 route_A 发上去会把进度写到错的路线；
  ///  · 服务端回 `skipped` 的事件**不能跟着整队一起清掉**（静默丢失），
  ///    带 tries 留在队列重试，满 3 次才丢弃并在文案里说清楚。
  Future<void> flush() async {
    final q = await _loadQueue();
    if (q.isEmpty) return;
    final byRoute = <String, List<Map<String, dynamic>>>{};
    for (final ev in q) {
      final r = '${ev['route_id'] ?? 'route_A'}';
      byRoute.putIfAbsent(r, () => []).add(ev);
    }
    var appliedCount = 0;
    var rejectedCount = 0;
    var droppedCount = 0;
    final keep = <Map<String, dynamic>>[];
    try {
      for (final entry in byRoute.entries) {
        final res = await _api.push(entry.value, routeId: entry.key);
        appliedCount += (res['applied'] is int) ? res['applied'] as int : 0;
        // 服务端把「拒绝」写成 details[].event（整条事件回传），按 JSON 逐条比对，
        // 命中的留在队列重试——原来的 `_saveQueue([])` 会把它们一起丢掉。
        final rejectedJson = <String>{};
        final details = res['details'];
        if (details is List) {
          for (final d in details) {
            if (d is! Map) continue;
            final ev = d['event'];
            if (ev is Map) rejectedJson.add(jsonEncode(ev));
          }
        }
        for (final ev in entry.value) {
          if (!rejectedJson.contains(jsonEncode(ev))) continue;
          rejectedCount++;
          final tries = (ev['tries'] is int ? ev['tries'] as int : 0) + 1;
          if (tries < 3) {
            ev['tries'] = tries;
            keep.add(ev);
          } else {
            droppedCount++;
          }
        }
      }
      await _saveQueue(keep);
      _online = true;
      _message = rejectedCount == 0
          ? '已合并 $appliedCount 条离线进度'
          : '已合并 $appliedCount 条离线进度，$rejectedCount 条被服务端拒绝'
              '${droppedCount == 0 ? '（保留待重试）' : '（$droppedCount 条重试 3 次仍失败，已丢弃）'}';
    } catch (_) {
      _online = false;
      _message = '同步失败，稍后重试（暂存 $_pending 条）';
    }
    notifyListeners();
  }

  /// 拉取服务端断点（断点续学定位）
  Future<Map<String, dynamic>?> pullAnchor(String routeId) async {
    try {
      await flush();
      return await _api.pull(routeId: routeId);
    } catch (_) {
      _online = false;
      notifyListeners();
      return null;
    }
  }
}
