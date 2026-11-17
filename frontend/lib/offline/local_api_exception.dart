// 单机版接口异常（与后端 HTTP 错误同语义：状态码 + detail）。
//
// 单独成文件是为了让 `local_quiz` 这类底层模块能直接抛它，而不用反过来
// import `local_router`（会形成循环依赖）。`local_router.dart` 重新 export，
// 原有 `import 'local_router.dart'` 的地方不受影响。
class LocalApiException implements Exception {
  final int status;
  final String detail;
  LocalApiException(this.status, this.detail);
  @override
  String toString() => detail;
}
