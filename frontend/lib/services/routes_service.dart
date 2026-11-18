// 路线 API 封装（T017）
import '../models/learning_models.dart';
import 'api_client.dart';
import 'api_config.dart';

class RoutesService {
  Future<List<LearningRoute>> listRoutes() async {
    final j = await ApiClient.get('/api/routes');
    return ((j['routes'] as List?) ?? const [])
        .map((e) => LearningRoute.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<RouteSection>> sections(String routeId, {String userId = kDemoUserId}) async {
    final view = await sectionsView(routeId, userId: userId);
    return view.sections;
  }

  /// 章节列表 + 公共地基（D152）。一次请求拿全，避免「章节一次、地基再一次」。
  Future<RouteSectionsView> sectionsView(String routeId,
      {String userId = kDemoUserId}) async {
    final j = await ApiClient.get('/api/routes/$routeId/sections', query: {'user_id': userId});
    return RouteSectionsView.fromJson(j);
  }

  /// 选择路线只改服务端「当前路线」标记，不改变任何章节进度，
  /// 因此不让它清空 sections/guide 的 GET 缓存。
  Future<Map<String, dynamic>> select(String routeId, {String userId = kDemoUserId}) =>
      ApiClient.post('/api/routes/$routeId/select', {'user_id': userId}, invalidate: false);

  Future<Map<String, dynamic>> startDiagnostic(String routeId, {String userId = kDemoUserId}) =>
      ApiClient.post('/api/routes/$routeId/diagnostic', {'user_id': userId});

  Future<Map<String, dynamic>> submitDiagnostic(String diagId,
          List<Map<String, dynamic>> answers, {String userId = kDemoUserId}) =>
      ApiClient.post('/api/routes/diagnostic/$diagId/submit',
          {'user_id': userId, 'answers': answers});

  Future<Map<String, dynamic>> gating(String routeId, String sectionId,
          {String userId = kDemoUserId}) =>
      ApiClient.get('/api/routes/$routeId/sections/$sectionId/gating', query: {'user_id': userId});

  Future<Map<String, dynamic>> guide(String routeId, String sectionId) =>
      ApiClient.get('/api/routes/$routeId/sections/$sectionId/guide');
}
