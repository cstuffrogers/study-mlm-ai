// 动机/挫折调节 API（P3 D14）
import 'api_client.dart';
import 'api_config.dart';

class MotivationApi {
  Future<Map<String, dynamic>> state({String routeId = 'route_A', String userId = kDemoUserId}) async {
    return ApiClient.get('/api/motivation/state', query: {'route_id': routeId, 'user_id': userId});
  }
}
