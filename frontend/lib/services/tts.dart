// 语音朗读门面——按平台选择原生（安卓）/ Web / 空实现，供 UI 统一调用。
//
// 典型用法：
//   await ttsInit();                     // 启动时初始化（安卓要探测引擎与中文支持）
//   ttsSpeak(text, id: 'chunk-<id>');
//   ttsStop();
// 并用 ValueListenableBuilder(ttsCurrent) 高亮当前正在播放的喇叭按钮。
//
// 条件导出顺序就是优先级：先 Web（dart.library.js_interop），再原生（dart.library.io），
// 其余（无 io 也无 js 的环境）落到空实现。
export 'tts_stub.dart'
    if (dart.library.js_interop) 'tts_web.dart'
    if (dart.library.io) 'tts_native.dart';
