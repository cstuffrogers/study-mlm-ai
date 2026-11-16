// 学习分析 & 元认知校准 API（P3 看板 / P2-④ 校准聚合）
import 'api_client.dart';
import 'api_config.dart';

class AnalyticsApi {
  Future<Map<String, dynamic>> overview({String routeId = 'route_A', String userId = kDemoUserId}) async {
    return ApiClient.get('/api/analytics/overview', query: {'route_id': routeId, 'user_id': userId});
  }

  Future<Map<String, dynamic>> calibration({String routeId = 'route_A', String userId = kDemoUserId}) async {
    return ApiClient.get('/api/analytics/calibration', query: {'route_id': routeId, 'user_id': userId});
  }
}
