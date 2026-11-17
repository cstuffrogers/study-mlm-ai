// 打开外部链接门面——按平台选择 Web / 原生（url_launcher）/ 空实现。
// 典型用法：openExternal('https://...')  （在新标签页或系统浏览器打开权威原文）
//
// 条件导出顺序即优先级：先 Web（dart.library.js_interop，新标签页），
// 再原生（dart.library.io，url_launcher 唤起系统浏览器），其余落空实现。
export 'open_url_stub.dart'
    if (dart.library.js_interop) 'open_url_web.dart'
    if (dart.library.io) 'open_url_io.dart';
