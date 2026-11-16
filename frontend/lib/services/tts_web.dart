// 语音朗读（TTS）—— 两级引擎，优先级从高到低：
//
//   1) 后端「微软神经语音」合成（真人级，如 zh-CN-Xiaoxiao「晓晓」/ Yunxi「云希」）。
//   2) 浏览器原生 speechSynthesis（离线可用，但 Win10/夸克上只有老式「机器腔」语音）。
//
// 关键设计（避免「异步导致自动播放被拦 → 退回机器人声」）：
//   把 <audio> 的 src 直接指向后端 URL 并**在当前点击手势内同步 play()**，
//   浏览器不会因「用户手势失效」拦截播放；合成在后端边生成边下载（可能等 1~3 秒）。
//   若后端不可用 / 加载失败 / 播放被拒 → 自动回退浏览器语音。
//
// 只在 conditionally import 的场景下被真正使用：
//   services/tts.dart      —— 跨平台门面（永远可 import）
//   services/tts_web.dart  —— Web 实现
//   services/tts_stub.dart —— 非 Web 空实现
//
// 性能红线：无常驻动画/Timer（仅一次性看门狗），只通过 ttsCurrent 局部刷新。
//
// 说明：本文件仅在 Web 构建被引入（条件导入），故 dart:html 的 web-only 告警为误报；
// dart:html 对 <audio> 的用法比 package:web 更简洁可靠，这里显式忽略相关 lint。
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'tts_voice_pick.dart';

/// 当前正在朗读的「条目 id」。null 表示空闲。全局同一时刻只朗读一段。
final ValueNotifier<String?> ttsCurrent = ValueNotifier<String?>(null);

// 正在播放的 <audio>（神经语音路径）。
html.AudioElement? _audio;
Timer? _watchdog;

// ---- 浏览器语音（兜底）相关状态 ----
List<web.SpeechSynthesisVoice> _voices = [];
bool _hooked = false;
final List<void Function()> _pending = <void Function()>[];

void _refreshVoices() {
  try {
    _voices = web.window.speechSynthesis.getVoices().toDart.toList();
  } catch (_) {
    _voices = [];
  }
  if (_voices.isNotEmpty && _pending.isNotEmpty) {
    final queued = List<void Function()>.from(_pending);
    _pending.clear();
    for (final f in queued) {
      try {
        f();
      } catch (_) {}
    }
  }
}

void _ensureVoices() {
  if (_hooked) return;
  _hooked = true;
  _refreshVoices();
  try {
    web.window.speechSynthesis.onvoiceschanged =
        ((web.Event e) => _refreshVoices()).toJS;
  } catch (_) {}
}

int _voiceScore(web.SpeechSynthesisVoice v) =>
    voiceScore(name: v.name, lang: v.lang);

web.SpeechSynthesisVoice? _bestVoice() {
  _ensureVoices();
  if (_voices.isEmpty) _refreshVoices();
  web.SpeechSynthesisVoice? best;
  int bestScore = 0;
  for (final v in _voices) {
    final sc = _voiceScore(v);
    if (sc > bestScore) {
      bestScore = sc;
      best = v;
    }
  }
  return best;
}

bool ttsHasChineseVoice() {
  _ensureVoices();
  if (_voices.isEmpty) _refreshVoices();
  return _voices.any((v) => _voiceScore(v) > 0);
}

bool ttsVoicesLoaded() {
  _ensureVoices();
  if (_voices.isEmpty) _refreshVoices();
  return _voices.isNotEmpty;
}

bool ttsAvailable() => true;

// ------------------------- 浏览器语音（兜底） -------------------------

void _speakNowBrowser(String text, String id, double rate) {
  final synth = web.window.speechSynthesis;
  final utter = web.SpeechSynthesisUtterance(text);
  utter.rate = rate;
  utter.pitch = 1.0;
  utter.lang = 'zh-CN';
  final v = _bestVoice();
  if (v != null) {
    utter.voice = v;
    utter.lang = v.lang;
  }
  void clearIfMine() {
    if (ttsCurrent.value == id) ttsCurrent.value = null;
  }

  utter.onstart = ((web.Event e) {
    ttsCurrent.value = id;
  }).toJS;
  utter.onend = ((web.Event e) => clearIfMine()).toJS;
  utter.onerror = ((web.Event e) => clearIfMine()).toJS;
  synth.speak(utter);
  ttsCurrent.value = id;
}

void _browserSpeak(String text, String id, double rate) {
  try {
    final synth = web.window.speechSynthesis;
    synth.cancel();
    _ensureVoices();
    _pending.clear();
    void doSpeak() => _speakNowBrowser(text, id, rate);
    if (_voices.isEmpty) {
      _pending.add(doSpeak);
      Future.delayed(const Duration(milliseconds: 800), () {
        if (_pending.remove(doSpeak)) {
          try {
            doSpeak();
          } catch (_) {
            ttsCurrent.value = null;
          }
        }
      });
    } else {
      doSpeak();
    }
  } catch (_) {
    ttsCurrent.value = null;
  }
}

// ------------------------- 神经语音（后端 URL，同步播放） -------------------------

String _rateToEdge(double rate) {
  final pct = ((rate - 1.0) * 100).round();
  if (pct == 0) return '+0%';
  return pct > 0 ? '+$pct%' : '$pct%';
}

String _neuralUrl(String text, String rateStr) {
  // URL 太长可能被截断：超长文本截断到 1800 字（朗读场景足够）。
  var t = text;
  if (t.length > 1800) t = t.substring(0, 1800);
  // 相对路径：由当前页面的静态服务（8080）反代到后端 8190 的 /api/tts。
  // 同源 → 无跨端口/CORS 问题，且任何 host 打开页面都能用。
  final uri = Uri.parse(
    '/api/tts/speak',
  ).replace(queryParameters: {'text': t, 'rate': rateStr});
  return uri.toString();
}

void _stopAudio() {
  _watchdog?.cancel();
  _watchdog = null;
  final a = _audio;
  if (a != null) {
    try {
      a.pause();
    } catch (_) {}
    _audio = null;
  }
}

/// 用后端 URL 同步播放；失败自动回退浏览器语音。
/// [onDone] 在本段播放自然结束时回调（用于「整页长文」分段续播）。
void _playNeuralUrl(
  String url,
  String id,
  String text,
  double rate, {
  void Function()? onDone,
}) {
  _stopAudio();
  final audio = html.AudioElement();
  audio.preload = 'auto';
  _audio = audio;
  bool fellBack = false;
  void fallback() {
    if (fellBack) return;
    fellBack = true;
    _stopAudio();
    if (ttsCurrent.value == id) {
      _browserSpeak(text, id, rate);
    }
  }

  audio.onEnded.listen((_) {
    if (ttsCurrent.value != id) return;
    if (onDone != null) {
      onDone();
    } else {
      ttsCurrent.value = null;
    }
  });
  audio.onError.listen((_) => fallback());
  audio.src = url;
  // 关键：在点击手势内同步 play()（异步后才 play 会被自动播放策略拦截）。
  audio.play().then((_) {}).catchError((_) {
    fallback();
    return null;
  });
  ttsCurrent.value = id;

  // 看门狗：若 15 秒仍没有任何音频数据（后端挂起/离线且未触发 onError），回退。
  _watchdog = Timer(const Duration(seconds: 15), () {
    if (ttsCurrent.value == id && audio.readyState == 0) {
      fallback();
    }
  });
}

// ------------------------- 长文分段（整页朗读） -------------------------

// 当前朗读任务的分段队列（整页长文按句切分，逐段合成播放，避免 URL/合成超长被截断）。
List<String> _segments = const <String>[];
int _segIndex = 0;
double _segRate = 1.0;
String _segId = '__default__';
const int _segMaxLen = 600;

/// 按句末标点切句，再把句子合并到 <= maxLen，保证语义边界不被切断。
List<String> _splitForTts(String text, {int maxLen = _segMaxLen}) {
  final sentences = <String>[];
  final cur = StringBuffer();
  for (final r in text.runes) {
    final s = String.fromCharCode(r);
    cur.write(s);
    if (s == '。' ||
        s == '！' ||
        s == '？' ||
        s == '；' ||
        s == '!' ||
        s == '?' ||
        s == ';' ||
        s == '\n') {
      sentences.add(cur.toString());
      cur.clear();
    }
  }
  if (cur.isNotEmpty) sentences.add(cur.toString());

  final parts = <String>[];
  final buf = StringBuffer();
  for (final s in sentences) {
    if (buf.length + s.length > maxLen && buf.isNotEmpty) {
      parts.add(buf.toString());
      buf.clear();
    }
    // 单句本身超长（无标点长段）时按硬长度再切
    if (s.length > maxLen) {
      for (var i = 0; i < s.length; i += maxLen) {
        final end = (i + maxLen < s.length) ? i + maxLen : s.length;
        parts.add(s.substring(i, end));
      }
    } else {
      buf.write(s);
    }
  }
  if (buf.isNotEmpty) parts.add(buf.toString());
  return parts.isEmpty ? <String>[text] : parts;
}

String _remainingText() => _segments.skip(_segIndex).join();

void _playSegment() {
  if (_segIndex >= _segments.length) {
    ttsCurrent.value = null;
    return;
  }
  final seg = _segments[_segIndex];
  _playNeuralUrl(
    _neuralUrl(seg, _rateToEdge(_segRate)),
    _segId,
    _remainingText(),
    _segRate,
    onDone: () {
      _segIndex++;
      if (ttsCurrent.value == _segId) _playSegment();
    },
  );
}

// ------------------------- 对外接口 -------------------------

/// 开始朗读；先试后端神经语音（同步播放），失败回退浏览器语音。
/// 长文本自动分段续播，可「一次点开、整页读完」。
void ttsSpeak(String text, {String id = '__default__', double rate = 1.0}) {
  final t = text.trim();
  if (t.isEmpty) return;
  // 先停掉旧的（含浏览器语音）
  try {
    web.window.speechSynthesis.cancel();
  } catch (_) {}
  _pending.clear();
  _stopAudio();
  _segments = _splitForTts(t);
  _segIndex = 0;
  _segRate = rate;
  _segId = id;
  ttsCurrent.value = id;
  _playSegment();
}

/// 停止朗读。
void ttsStop() {
  _stopAudio();
  try {
    web.window.speechSynthesis.cancel();
  } catch (_) {}
  _pending.clear();
  _segments = const <String>[];
  _segIndex = 0;
  ttsCurrent.value = null;
}
