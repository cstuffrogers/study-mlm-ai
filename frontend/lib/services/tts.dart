// 语音朗读门面——按平台选择 Web / 空实现，供 UI 统一调用。
//
// 典型用法：
//   ttsSpeak(text, id: 'chunk-<id>');
//   ttsStop();
// 并用 ValueListenableBuilder(ttsCurrent) 高亮当前正在播放的喇叭按钮。
export 'tts_stub.dart' if (dart.library.js_interop) 'tts_web.dart';
