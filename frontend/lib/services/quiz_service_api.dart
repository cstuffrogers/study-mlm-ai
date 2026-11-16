// 测验 API 封装（T034）
import '../models/learning_models.dart';
import 'api_client.dart';
import 'api_config.dart';

class QuizApi {
  /// 返回 (testId, items)
  Future<({String testId, List<QuizItem> items})> start(String sectionId,
      {String routeId = 'route_A', String userId = kDemoUserId}) async {
    final j = await ApiClient.post('/api/quiz/section/$sectionId/start',
        {'user_id': userId, 'route_id': routeId});
    final items = ((j['items'] as List?) ?? const [])
        .map((e) => QuizItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return (testId: j['test_id'] as String? ?? '', items: items);
  }

  Future<Map<String, dynamic>> submit(String testId, List<Map<String, dynamic>> answers,
          {String userId = kDemoUserId}) =>
      ApiClient.post('/api/quiz/$testId/submit', {'user_id': userId, 'answers': answers});

  Future<Map<String, dynamic>> appeal(String testId, String itemId, {String reason = ''}) =>
      ApiClient.post('/api/quiz/appeal', {'test_id': testId, 'item_id': itemId, 'reason': reason});
}
