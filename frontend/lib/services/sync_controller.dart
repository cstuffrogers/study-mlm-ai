// 离线暂存队列 + 同步控制器（NFR-004 / D7）
// 服务端权威：在线时直接上报进度；离线时本地暂存，恢复连接或进入页面时批量合并。
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sync_service_api.dart';

class SyncController extends ChangeNotifier {
  static const _kQueue = 'sync_queue_v1';
  final SyncApi _api = SyncApi();
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
      await _api.push([ev], routeId: routeId);
      _online = true;
      _message = '已同步';
      notifyListeners();
    } catch (_) {
      final q = await _loadQueue();
      q.add(ev);
      await _saveQueue(q);
      _online = false;
      _message = '当前离线，已暂存 $_pending 条进度，恢复后自动同步';
      notifyListeners();
    }
  }

  /// 将暂存事件批量合并到服务端（进入页面/恢复连接时调用）
  Future<void> flush() async {
    final q = await _loadQueue();
    if (q.isEmpty) return;
    try {
      await _api.push(q);
      await _saveQueue([]);
      _online = true;
      _message = '已合并 ${q.length} 条离线进度';
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
