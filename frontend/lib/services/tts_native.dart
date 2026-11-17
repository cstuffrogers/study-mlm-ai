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

import 'tts_settings.dart';
import 'tts_voice_slots.dart';

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
  if (!TtsSettings.instance.loaded) await TtsSettings.instance.load();
  if (!ttsAvailable()) return;
  if (_inited) return;
  _inited = true;
  try {
    final map = await _ch.invokeMapMethod<String, dynamic>('init');
    _ready = map?['ready'] == true;
    _hasChinese = map?['chinese'] == true;
    // 上次选过的语音包：重装/重启后继续用它（引擎没装这个包时保持默认）
    final saved = TtsSettings.instance.voiceName;
    if (_ready && saved.isNotEmpty) {
      try {
        await _ch.invokeMethod<bool>('setVoice', {'name': saved});
      } catch (_) {}
    }
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

/// 本机已装的中文语音包（引擎未就绪时为空表）。
Future<List<TtsVoiceOption>> ttsListVoices() async {
  if (!ttsAvailable()) return const <TtsVoiceOption>[];
  try {
    final map = await _ch.invokeMapMethod<String, dynamic>('voices');
    final raw = (map?['voices'] as List?) ?? const [];
    return raw.map((e) {
      final m = (e as Map).cast<String, dynamic>();
      return TtsVoiceOption(
        name: '${m['name'] ?? ''}',
        label: '${m['label'] ?? ''}',
        locale: '${m['locale'] ?? ''}',
        network: m['network'] == true,
        gender: '${m['gender'] ?? ''}',
      );
    }).where((v) => v.name.isNotEmpty).toList();
  } catch (e) {
    debugPrint('读取语音包列表失败：$e');
    return const <TtsVoiceOption>[];
  }
}

/// 切换语音包；[name] 为空串表示恢复引擎默认。返回是否切换成功。
Future<bool> ttsSetVoice(String name) async {
  if (!ttsAvailable()) return false;
  try {
    final ok = await _ch.invokeMethod<bool>('setVoice', {'name': name}) ?? false;
    if (ok) await TtsSettings.instance.setVoiceName(name);
    return ok;
  } catch (e) {
    debugPrint('切换语音包失败：$e');
    return false;
  }
}

/// 按当前风格档去系统语音包里找对应音色（找不到就返回 null，只做音调语速近似）。
///
/// 安卓没法内置语音包，只能从**已装**的里面挑：各厂家命名五花八门，
/// 所以这里按关键词匹配（见 TtsVoiceSlots.nativeHints），命中 displayName/name 任意其一即用。
/// 用户手动选过语音包时不动——手选优先于预设。
Future<String?> _voiceForSlot(TtsVoiceSlot slot) async {
  if (slot.nativeHints.isEmpty) return null;
  final list = await ttsListVoices();
  if (list.isEmpty) return null;
  // 引擎明确报了性别的，先按性别挑（比关键词可靠得多）
  final wantGender = slot.nativeHints.contains('female')
      ? 'female'
      : (slot.nativeHints.contains('male') ? 'male' : '');
  if (wantGender.isNotEmpty) {
    for (final v in list) {
      if (v.gender == wantGender) return v.name;
    }
  }
  for (final hint in slot.nativeHints) {
    final h = hint.toLowerCase();
    for (final v in list) {
      if ('${v.label} ${v.name}'.toLowerCase().contains(h)) return v.name;
    }
  }
  return null;
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
  // 风格预设：语速在调用方的 rate 上再乘预设倍数，音调交给预设（安卓引擎范围 0.5~2.0）
  final preset = TtsSettings.instance.preset;
  _applySlotVoice();
  _ch.invokeMethod<bool>('speak', {
    'text': body,
    'id': id,
    'rate': rate * preset.rate,
    'pitch': preset.pitch,
  }).then((ok) {
    if (ok != true && ttsCurrent.value == id) ttsCurrent.value = null;
  }).catchError((Object e) {
    if (ttsCurrent.value == id) ttsCurrent.value = null;
    debugPrint('TTS 朗读失败：$e');
  });
}

/// 把当前风格档对应的系统语音包设上去（手选过语音包、或档位没关键词时跳过）。
/// 失败/没找到都静默：音调语速预设仍然生效，不该因为选不到音色就静默不读。
void _applySlotVoice() {
  final settings = TtsSettings.instance;
  if (settings.voiceName.isNotEmpty) return;
  final slot = TtsVoiceSlots.byId(settings.presetId);
  if (slot.nativeHints.isEmpty) return;
  if (_appliedSlot == slot.id) return;
  _appliedSlot = slot.id;
  _voiceForSlot(slot).then((name) {
    if (name == null || settings.voiceName.isNotEmpty) return;
    _ch.invokeMethod<bool>('setVoice', {'name': name}).catchError((Object _) => false);
  }).catchError((Object _) => null);
}

/// 上一次按风格档设过的系统语音（避免每次朗读都重设一遍）。
String? _appliedSlot;

void ttsStop() {
  ttsCurrent.value = null;
  if (!_inited) return;
  _ch.invokeMethod<void>('stop').catchError((Object _) {});
}
