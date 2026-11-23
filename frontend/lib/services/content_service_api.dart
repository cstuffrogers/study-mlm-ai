// 原著分片 / 章节导读 / 对话历史 / 测试历史 / 认证 API 封装
import 'api_client.dart';
import 'api_config.dart';

class ContentApi {
  /// 全部著作清单
  Future<List<String>> works() async {
    final j = await ApiClient.get('/api/chunks/works');
    return ((j['works'] as List?) ?? const []).map((e) => e.toString()).toList();
  }

  /// 著作清单（含作者 / 分片数），原著浏览页搜索与筛选用
  Future<List<Map<String, dynamic>>> worksWithMeta() async {
    final j = await ApiClient.get('/api/chunks/works');
    return ((j['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  /// 按著作拉分片（work='all' 返回全部）
  Future<List<Map<String, dynamic>>> chunksByWork(String work) async {
    // 著作名可能含 ( ) · / 等特殊字符，必须整体 URL 编码，否则中间的 /
    // 会被当成路径分隔符导致 404。
    final encoded = Uri.encodeComponent(work);
    final j = await ApiClient.get('/api/chunks/by_work/$encoded');
    return ((j['items'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<Map<String, dynamic>> chunk(String chunkId) =>
      ApiClient.get('/api/chunks/${Uri.encodeComponent(chunkId)}');

  /// 章节导读 + 知识点
  Future<Map<String, dynamic>> guide(String routeId, String sectionId) =>
      ApiClient.get('/api/routes/$routeId/sections/$sectionId/guide');
}

class DialogueApi {
  Future<List<Map<String, dynamic>>> list({String userId = kDemoUserId}) async {
    final j = await ApiClient.get('/api/dialogue/list/$userId');
    return ((j['dialogues'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<List<Map<String, dynamic>>> messages(String dialogueId, {int limit = 50}) async {
    final j = await ApiClient.get('/api/dialogue/$dialogueId/messages', query: {'limit': '$limit'});
    return ((j['messages'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
  }
}

class QuizHistoryApi {
  Future<Map<String, dynamic>> history(
          {String userId = kDemoUserId, bool onlyWrong = false, int limit = 100}) =>
      ApiClient.get('/api/quiz/history', query: {
        'user_id': userId,
        'only_wrong': '$onlyWrong',
        'limit': '$limit',
      });

  /// 删除单条错题/作答记录（错题本删除）。
  Future<Map<String, dynamic>> deleteAttempt(String attemptId,
          {String userId = kDemoUserId}) =>
      ApiClient.delete('/api/quiz/attempt/${Uri.encodeComponent(attemptId)}',
          query: {'user_id': userId});
}

class AuthApi {
  Future<Map<String, dynamic>> register(String email, String password, {String nickname = ''}) =>
      ApiClient.post('/api/auth/register', {'email': email, 'password': password, 'nickname': nickname});

  Future<Map<String, dynamic>> login(String email, String password) =>
      ApiClient.post('/api/auth/login', {'email': email, 'password': password});
}
