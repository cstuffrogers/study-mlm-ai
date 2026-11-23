// 学习勋章 API 封装（spec 001 勋章系统）
import '../offline/local_badge.dart';
import 'api_client.dart';
import 'api_config.dart';

class BadgeApi {
  BadgeApi._();

  /// 「我的勋章」页数据：全部勋章 + 授予状态 + 进度 + 指标快照。
  static Future<Map<String, dynamic>> mine(
          {String routeId = 'route_A', String userId = kDemoUserId}) async =>
      ApiClient.get('/api/badges/mine',
          query: {'route_id': routeId, 'user_id': userId});

  /// 未查看的新勋章（首页提醒 / 开箱动画触发兜底）。
  static Future<Map<String, dynamic>> unseen(
          {String routeId = 'route_A', String userId = kDemoUserId}) async =>
      ApiClient.get('/api/badges/unseen',
          query: {'route_id': routeId, 'user_id': userId});

  /// 标记已查看。
  static Future<Map<String, dynamic>> markRead(
          List<String> awardIds,
          {String routeId = 'route_A', String userId = kDemoUserId}) =>
      ApiClient.post('/api/badges/read', {
        'user_id': userId,
        'route_id': routeId,
        'award_ids': awardIds,
      });
}

/// 单机版直接走 LocalBadge（与 ApiClient 路径相同，api_client 会自动路由到
/// LocalRouter 的 badges 分支，返回形状与后端一致）。
typedef BadgeDefList = List<BadgeDef>;
