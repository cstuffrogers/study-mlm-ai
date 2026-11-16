// 推荐 API 封装（T049）
import '../models/learning_models.dart';
import 'api_client.dart';
import 'api_config.dart';

class RecommendationApi {
  Future<Recommendation> today({String routeId = 'route_A', String userId = kDemoUserId}) async {
    final j = await ApiClient.get('/api/recommendation/today', query: {'route_id': routeId, 'user_id': userId});
    return Recommendation.fromJson((j['recommendation'] as Map).cast<String, dynamic>());
  }

  Future<Recommendation> next({String routeId = 'route_A', String? currentSectionId, String userId = kDemoUserId}) async {
    final j = await ApiClient.post('/api/recommendation/next', {
      'user_id': userId,
      'route_id': routeId,
      'current_section_id': currentSectionId,
    });
    return Recommendation.fromJson(j);
  }

  Future<List<WeakPoint>> weakTop({String routeId = 'route_A', String userId = kDemoUserId, int n = 5}) async {
    final j = await ApiClient.get('/api/recommendation/weak-top',
        query: {'route_id': routeId, 'user_id': userId, 'n': '$n'});
    return ((j['weak_points'] as List?) ?? const [])
        .map((e) => WeakPoint.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
