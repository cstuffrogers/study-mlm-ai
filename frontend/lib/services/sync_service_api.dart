// 跨设备同步 / 断点续学 API 封装（NFR-004 / T051-T052）
import 'api_client.dart';
import 'api_config.dart';

class SyncApi {
  /// 上行业务增量（离线暂存的作答/进度/信号批量合并）
  Future<Map<String, dynamic>> push(
          List<Map<String, dynamic>> events, {String routeId = 'route_A', String userId = kDemoUserId}) =>
      ApiClient.post('/api/sync/push', {'user_id': userId, 'route_id': routeId, 'events': events});

  /// 拉取服务端权威进度快照（断点续学）
  Future<Map<String, dynamic>> pull({String routeId = 'route_A', String userId = kDemoUserId}) =>
      ApiClient.get('/api/sync/pull?route_id=$routeId&user_id=$userId');

  /// 上报单章学习位置
  Future<Map<String, dynamic>> saveProgress(String sectionId, int lastPosition,
          {String routeId = 'route_A', String status = 'in_progress', String userId = kDemoUserId}) =>
      ApiClient.post('/api/sync/progress', {
        'user_id': userId,
        'route_id': routeId,
        'section_id': sectionId,
        'last_position': lastPosition,
        'status': status,
      });
}
