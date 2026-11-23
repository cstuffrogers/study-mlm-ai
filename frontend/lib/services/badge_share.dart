// 勋章分享门面——按平台选择原生 / Web / 空实现，供 UI 统一调用。
//
// 典型用法：
//   final ok = await shareBadgeCard(
//     context: context,
//     appName: AppMeta.appName,
//     earnedCount: earned,
//     totalCount: total,
//     badges: items,
//   );
//
// 条件导出顺序就是优先级：先 Web（dart.library.js_interop），再原生
// （dart.library.io），其余环境落到空实现。
export 'badge_share_stub.dart'
    if (dart.library.js_interop) 'badge_share_web.dart'
    if (dart.library.io) 'badge_share_native.dart';
