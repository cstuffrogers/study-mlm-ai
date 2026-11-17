// 语音朗读（TTS）—— Android 原生实现（系统 TextToSpeech 引擎，离线可用）。
//
// 为什么要有它：Web 端走浏览器 speechSynthesis / 后端神经语音，但**单机安卓包没有后端**，
// 之前非 Web 平台直接落到空实现（ttsAvailable()==false），于是全站喇叭按钮被隐藏，
// 表现为「释义浮框、章节导读顶端、原文阅读器的喇叭都不见了」。
// 现在改用系统 TTS（android.speech.tts.TextToSpeech），走 MethodChannel 调用，无需网络。
//
// 与 tts_web.dart 保持同一套 API（ttsCurrent / ttsAvailable / ttsSpeak / ttsStop ...），
// UI 侧（widgets/speak_button.dart）不需要区分平台。
//
// 性能红线：无常驻 Timer / 动画，只通过 ttsCurrent 局部刷新单个按钮。
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 当前正在朗读的「条目 id」。null 表示空闲。全局同一时刻只朗读一段。
final ValueNotifier<String?> ttsCurrent = ValueNotifier<String?>(null);

/// 引擎就绪状态：初始化是异步的，就绪后自增一次，让喇叭按钮重新求值。
final ValueNotifier<int> ttsReadyTick = ValueNotifier<int>(0);

const MethodChannel _ch = MethodChannel('xxmz/tts');

bool _inited = false;
bool _ready = false;
bool _hasChinese = false;

/// 测试用开关：可在非安卓宿主上验证通道协议。
bool? _forceAvailable;

/// 只有安卓有原生实现；iOS/桌面仍返回 false（按钮自动隐藏，不会点了没反应）。
bool ttsAvailable() => _forceAvailable ?? Platform.isAndroid;

/// 仅供测试：强制认为引擎可用（配合 TestDefaultBinaryMessengerBinding 断言通道协议）。
@visibleForTesting
void debugSetTtsAvailable(bool v) => _forceAvailable = v;

bool ttsHasChineseVoice() => _hasChinese;
bool ttsVoicesLoaded() => _ready;
bool ttsNeuralReady() => false;

/// 启动时调一次：初始化系统 TTS 引擎并探测中文支持。
Future<void> ttsInit() async {
  if (!ttsAvailable()) return;
  if (_inited) return;
  _inited = true;
  try {
    final map = await _ch.invokeMapMethod<String, dynamic>('init');
    _ready = map?['ready'] == true;
    _hasChinese = map?['chinese'] == true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'done') {
        final id = call.arguments as String?;
        if (id == null || ttsCurrent.value == id) ttsCurrent.value = null;
      }
      return null;
    });
  } catch (e) {
    _ready = false;
    debugPrint('TTS 初始化失败：$e');
  }
  ttsReadyTick.value++;
}

void ttsSpeak(String text, {String id = '__default__', double rate = 1.0}) {
  final body = text.trim();
  if (body.isEmpty) return;
  if (!_inited) {
    // 首次点击才初始化（正常路径在 main() 里已经 init 过）
    ttsInit().then((_) {
      if (_ready) ttsSpeak(body, id: id, rate: rate);
    });
    return;
  }
  ttsCurrent.value = id;
  _ch.invokeMethod<bool>('speak', {
    'text': body,
    'id': id,
    'rate': rate,
  }).then((ok) {
    if (ok != true && ttsCurrent.value == id) ttsCurrent.value = null;
  }).catchError((Object e) {
    if (ttsCurrent.value == id) ttsCurrent.value = null;
    debugPrint('TTS 朗读失败：$e');
  });
}

void ttsStop() {
  ttsCurrent.value = null;
  if (!_inited) return;
  _ch.invokeMethod<void>('stop').catchError((Object _) {});
}
