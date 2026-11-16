// 间隔复习 API 封装（P1-① D8）
import '../models/learning_models.dart';
import 'api_client.dart';
import 'api_config.dart';

class ReviewApi {
  Future<List<ReviewItem>> due({String routeId = 'route_A', String userId = kDemoUserId}) async {
    final j = await ApiClient.get('/api/review/due', query: {'route_id': routeId, 'user_id': userId});
    return ((j['due'] as List?) ?? const [])
        .map((e) => ReviewItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> submit({
    required String nodeId,
    double correctRatio = 1.0,
    String routeId = 'route_A',
    String userId = kDemoUserId,
  }) async {
    return ApiClient.post('/api/review/submit', {
      'user_id': userId,
      'route_id': routeId,
      'node_id': nodeId,
      'correct_ratio': correctRatio,
    });
  }

  /// 交错复习队列（P2-⑤）
  Future<List<ReviewItem>> interleaved({String routeId = 'route_A', String userId = kDemoUserId, int n = 8}) async {
    final j = await ApiClient.get('/api/review/interleaved',
        query: {'route_id': routeId, 'user_id': userId, 'n': '$n'});
    return ((j['items'] as List?) ?? const [])
        .map((e) => ReviewItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// FSRS 参数拟合建议（D15）
  Future<Map<String, dynamic>> fit({String? routeId, String userId = kDemoUserId}) async {
    return ApiClient.get('/api/review/fit',
        query: {'user_id': userId, 'route_id': ?routeId});
  }
}
