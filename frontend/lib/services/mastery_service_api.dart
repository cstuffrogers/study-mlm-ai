// 学情档案 API 封装（T043）
import '../models/learning_models.dart';
import 'api_client.dart';
import 'api_config.dart';

class MasteryApi {
  Future<Profile> profile({String routeId = 'route_A', String userId = kDemoUserId}) async {
    final j = await ApiClient.get('/api/mastery/profile', query: {'route_id': routeId, 'user_id': userId});
    return Profile.fromJson(j);
  }

  Future<Map<String, dynamic>> node(String nodeId,
          {String routeId = 'route_A', String userId = kDemoUserId}) =>
      ApiClient.get('/api/mastery/node/$nodeId', query: {'route_id': routeId, 'user_id': userId});

  Future<Map<String, dynamic>> summary({String routeId = 'route_A', String userId = kDemoUserId, String period = 'week'}) =>
      ApiClient.post('/api/mastery/summary', {'user_id': userId, 'route_id': routeId, 'period': period});
}
