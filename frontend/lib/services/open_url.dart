// 打开外部链接门面——按平台选择 Web / 空实现。
// 典型用法：openExternal('https://...')  （在新标签页打开权威原文）
export 'open_url_stub.dart' if (dart.library.js_interop) 'open_url_web.dart';
