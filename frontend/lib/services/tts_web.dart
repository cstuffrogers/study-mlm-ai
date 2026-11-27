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

import 'tts_settings.dart';
import 'tts_voice_pick.dart';

/// 当前正在朗读的「条目 id」。null 表示空闲。全局同一时刻只朗读一段。
final ValueNotifier<String?> ttsCurrent = ValueNotifier<String?>(null);

/// 当前播放是否已从后端神经语音**回退**到浏览器原生语音（机器腔）。
///
/// 为什么会有它：神经语音偶发失败（微软侧/网络抖动）时，本文件会重试到全部失败
/// 才回退浏览器语音。两种音色差异极大，回退在用户听感上就是「突然变声」；
/// 连续朗读的状态条读这个值，明确显示「已切本机语音」，避免被当成故障。
final ValueNotifier<bool> ttsNeuralFallback = ValueNotifier<bool>(false);

/// 与原生实现保持 API 一致：Web 端不存在异步初始化，这里只在语音列表就绪时自增。
final ValueNotifier<int> ttsReadyTick = ValueNotifier<int>(0);

/// 启动时调用：预取浏览器语音列表（拿不到也会在首次朗读时重试）。
Future<void> ttsInit() async {
  _ensureVoices();
  if (_voices.isEmpty) _refreshVoices();
  ttsReadyTick.value++;
}

// 正在播放的 <audio>（神经语音路径）。
html.AudioElement? _audio;
Timer? _watchdog;

/// 「提前一页」预热缓存：url → 已经开始下载的 <audio>。
///
/// 连续朗读换页时直接复用它，接得上、不断档。**只预热一段**（不超过 _segMaxLen），
/// 绝不预生成整篇——那样会把后端语音合成排满，且用户明确要求「不要全文生成」。
final Map<String, html.AudioElement> _warm = <String, html.AudioElement>{};

// ---- 浏览器语音（兜底）相关状态 ----
List<web.SpeechSynthesisVoice> _voices = [];

/// 「语音包设置」里手选的浏览器语音名（null = 自动优选 / 走神经语音）。
String? _voiceOverride;

/// 用户在设置页点了「本机浏览器语音」，因此不再走后端神经语音。
///
/// 为什么需要它：Web 端的音色来自**后端微软神经语音**（晓晓/晓伊/云扬/云健），
/// 而浏览器 speechSynthesis 的音色完全取决于本机系统装了哪些语音。
/// 两者是不同引擎：用户在「语音包设置」里明确挑了某个浏览器语音，就该真的用它，
/// 否则会出现「选了却不生效」的假开关。
bool get _neuralDisabled => (_voiceOverride ?? TtsSettings.instance.voiceName).isNotEmpty;
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
  final override = _voiceOverride ?? TtsSettings.instance.voiceName;
  if (override.isNotEmpty) {
    for (final v in _voices) {
      if (v.name == override) return v;
    }
  }
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

/// 浏览器语音的性别。
///
/// 浏览器不提供性别字段，能用的线索只有语音名里的 female/male（Edge/Chrome 的
/// "Microsoft Yunxi Online (Natural) - Chinese" 这类名字里就带）。名字里没有就返回空，
/// 界面显示「未知」——不按音高去猜。
String _genderOf(web.SpeechSynthesisVoice v) {
  final low = v.name.toLowerCase();
  if (low.contains('female') || low.contains(' woman')) return 'female';
  if (low.contains('male') || low.contains(' man')) return 'male';
  return '';
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

/// 浏览器里的语音包（**只列中文，英文等非中文语音一律不出现**）。
///
/// 用户要求「语音包不要英文的」：避免用户手选英文语音去读普通话，导致发音怪异。
/// 后端神经语音（晓晓等）本就是高质量中文语音，浏览器语音仅作兜底，故这里只保留
/// voiceScore>0 的中文项；无任何中文语音时返回空表（朗读仍会走后端神经语音或
/// 自动优选，不会因此静默）。
Future<List<TtsVoiceOption>> ttsListVoices() async {
  _ensureVoices();
  if (_voices.isEmpty) _refreshVoices();
  final out = <TtsVoiceOption>[];
  for (final v in _voices) {
    if (_voiceScore(v) <= 0) continue; // 非中文（英文等）一律不列
    out.add(TtsVoiceOption(
      name: v.name,
      label: v.name,
      locale: v.lang,
      network: v.localService == false,
      chinese: true,
      gender: _genderOf(v),
    ));
  }
  // 仅剩中文，保持引擎给的顺序
  return out;
}

/// 选中某个浏览器语音；空串 = 回到自动优选。浏览器没有「设置失败」，
/// 只要名字非空且能在列表里找到就算成功。
Future<bool> ttsSetVoice(String name) async {
  _ensureVoices();
  if (_voices.isEmpty) _refreshVoices();
  final target = name.trim();
  if (target.isEmpty) {
    _voiceOverride = null;
    await TtsSettings.instance.setVoiceName('');
    return true;
  }
  final hit = _voices.where((v) => v.name == target);
  if (hit.isEmpty) return false;
  _voiceOverride = target;
  await TtsSettings.instance.setVoiceName(target);
  return true;
}

// ------------------------- 浏览器语音（兜底） -------------------------

void _speakNowBrowser(String text, String id, double rate) {
  final synth = web.window.speechSynthesis;
  final utter = web.SpeechSynthesisUtterance(text);
  final preset = TtsSettings.instance.preset;
  utter.rate = rate * preset.rate;
  utter.pitch = preset.pitch;
  utter.lang = 'zh-CN';
  final v = _bestVoice();
  if (v != null) {
    utter.voice = v;
    utter.lang = v.lang;
  }
  void clearIfMine() {
    if (ttsCurrent.value == id) _finishChain();
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

/// 每段神经语音最多尝试次数；全部失败才回退浏览器语音。
///
/// 为什么要重试：连续朗读中最常见的失败是微软侧/网络的**瞬时**抖动（连接重置、
/// 限流、响应变慢），这类失败重试一次基本就能成功。直接回退成浏览器机器腔，
/// 用户听到的就是「突然变声」。
const int _neuralMaxAttempts = 2;

/// 神经语音看门狗：这段时间内一个音频字节都没到（后端挂起/离线且未触发
/// onError），才判定失败。
///
/// 口径：后端单次合成有 20 秒超时，且响应是**缓冲式**的——第一字节要等合成
/// 完才下发。35 秒 = 20 秒合成 + 下载/网络余量。旧版 15 秒会在合成仍在进行
/// 时误判失败、切到机器腔，正是「突然变声」的直接原因之一。
const Duration _neuralWatchdog = Duration(seconds: 35);

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
  //
  // voice：Web 端的「温柔女声 / 广播员男声」等预设**就是**这几个微软神经语音，
  // 不带 voice 参数就永远是默认晓晓，页面上选了也没用。
  final uri = Uri.parse('/api/tts/speak').replace(queryParameters: {
    'text': t,
    'rate': rateStr,
    'voice': TtsSettings.instance.slot.neuralVoice,
  });
  return uri.toString();
}

/// 真正放掉一个 <audio>：暂停、断开 src、再 load()。
///
/// 只 pause() 不够：预热的元素还在后台继续下载，解码后的缓冲也不会释放；
/// `removeAttribute('src') + load()` 才会中止请求、把已下载/已解码的数据丢掉。
void _release(html.AudioElement? a) {
  if (a == null) return;
  try {
    a.pause();
    a.removeAttribute('src');
    a.load();
  } catch (_) {}
}

void _stopAudio() {
  _watchdog?.cancel();
  _watchdog = null;
  final a = _audio;
  if (a != null) {
    _release(a);
    _audio = null;
  }
}

/// 用后端 URL 同步播放；失败**先重试**，全部失败才回退浏览器语音。
/// [onDone] 在本段播放自然结束时回调（用于「整页长文」分段续播与连续朗读换页）。
void _playNeuralUrl(
  String url,
  String id,
  String text,
  double rate, {
  void Function()? onDone,
}) {
  _playNeuralAttempt(url, id, text, rate, onDone, attempt: 0);
}

/// 单次尝试：[attempt] 从 0 开始，失败且还有余量时原地重试（同 URL 重新请求）。
///
/// 重试会新建 <audio> 并 `_stopAudio()` 放掉上一个：只 pause 不够，
/// 上一个的下载/缓冲不释放，重试等于白费。
void _playNeuralAttempt(
  String url,
  String id,
  String text,
  double rate,
  void Function()? onDone, {
  required int attempt,
}) {
  _stopAudio();
  ttsNeuralFallback.value = false;
  // 命中了「下一页预热」：这一段音频已经在下或在缓存里了，直接拿来播，换页没空档。
  final warm = _warm.remove(url);
  final audio = warm ?? html.AudioElement();
  audio.preload = 'auto';
  _audio = audio;
  bool fellBack = false;
  void fallback() {
    if (fellBack) return;
    fellBack = true;
    _stopAudio();
    // 重试全部失败：切浏览器语音，并明确置位供状态条提示。
    ttsNeuralFallback.value = true;
    if (ttsCurrent.value == id) {
      _browserSpeak(text, id, rate);
    }
  }

  /// 本次尝试失败：还有余量就重试，否则回退。
  void fail() {
    if (fellBack) return;
    if (attempt + 1 < _neuralMaxAttempts) {
      _playNeuralAttempt(url, id, text, rate, onDone, attempt: attempt + 1);
      return;
    }
    fallback();
  }

  audio.onEnded.listen((_) {
    if (ttsCurrent.value != id) return;
    if (onDone != null) {
      onDone();
    } else {
      ttsCurrent.value = null;
    }
  });
  audio.onError.listen((_) => fail());
  // 预热过的元素不重设 src：按 HTML 规范重设会走一遍加载算法，白白丢掉已下载的数据。
  if (warm == null) audio.src = url;
  // 关键：在点击手势内同步 play()（异步后才 play 会被自动播放策略拦截）。
  audio.play().then((_) {}).catchError((_) {
    fail();
    return null;
  });
  ttsCurrent.value = id;

  // 看门狗：若 _neuralWatchdog 内仍没有任何音频数据（后端挂起/离线且未触发
  // onError），按失败处理（重试或回退）。
  _watchdog = Timer(_neuralWatchdog, () {
    if (ttsCurrent.value == id && audio.readyState == 0) {
      fail();
    }
  });
}

/// 提前抓取 [text] 开头的这一段音频（只一段，<= _segMaxLen）。
///
/// 连续朗读换页时用它把「下一页的第一段」先拉下来，避免念完一页要等 1~3 秒合成。
/// 已经选了本机浏览器语音（不走后端）时无事可做；安卓端不等网络，见 tts_native.dart。
void ttsPrefetch(String text, {double rate = 1.0}) {
  if (_neuralDisabled) return;
  final t = text.trim();
  if (t.isEmpty) return;
  final segs = _splitForTts(t);
  if (segs.isEmpty) return;
  final url = _neuralUrl(segs.first, _rateToEdge(rate));
  if (_warm.containsKey(url)) return; // 已经在拉了
  try {
    final a = html.AudioElement();
    a.preload = 'auto';
    // 预热失败（后端 500 / 断网）就丢掉，别让调用方以为「已就绪」。
    a.onError.listen((_) => _warm.remove(url));
    a.src = url;
    _warm[url] = a;
    // 只留最近 3 条：多读几页后旧的不再需要，继续下载纯属浪费流量。
    while (_warm.length > 3) {
      final key = _warm.keys.first;
      if (key == url) break;
      _release(_warm.remove(key));
    }
  } catch (_) {}
}

// ------------------------- 长文分段（整页朗读） -------------------------

// 当前朗读任务的分段队列（整页长文按句切分，逐段合成播放，避免 URL/合成超长被截断）。
List<String> _segments = const <String>[];
int _segIndex = 0;
double _segRate = 1.0;
String _segId = '__default__';

/// 本次朗读任务全部念完后的一次性回调（连续朗读用它接下一页）。
void Function()? _segOnDone;
const int _segMaxLen = 600;

/// 一条「朗读任务」结束（念完 / 兜底浏览器语音念完）。
///
/// 顺序很关键：**先**清状态、**再**回调。回调里通常会立刻开始念下一段（连续朗读下一页），
/// 它会把 ttsCurrent 设成新的 id，不能被这里的清理覆盖。
void _finishChain() {
  final done = _segOnDone;
  _segOnDone = null;
  _segments = const <String>[];
  _segIndex = 0;
  ttsCurrent.value = null;
  done?.call();
}

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
    _finishChain();
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
/// [onDone] 整段文本念完时回调一次（连续朗读靠它接下一页）。
void ttsSpeak(
  String text, {
  String id = '__default__',
  double rate = 1.0,
  void Function()? onDone,
}) {
  final t = text.trim();
  if (t.isEmpty) return;
  // 先停掉旧的（含浏览器语音）
  try {
    web.window.speechSynthesis.cancel();
  } catch (_) {}
  _pending.clear();
  _stopAudio();
  _segOnDone = onDone;
  // 新一轮朗读开始：回退标志复位（神经路径重新尝试，浏览器手选路径本就不是回退）。
  ttsNeuralFallback.value = false;
  if (_neuralDisabled) {
    // 用户在设置页手选了浏览器语音：直接用它，不再先试神经语音
    _segments = const <String>[];
    _segIndex = 0;
    _segRate = rate;
    _segId = id;
    ttsCurrent.value = id;
    _browserSpeak(t, id, rate);
    return;
  }
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
  // 预热元素也要放掉：只 pause 的话它还在后台继续拉下一页的音频，
  // 而且解码后的缓冲一直占着（语音是临时产物，声一停就该释放干净）。
  for (final a in _warm.values) {
    _release(a);
  }
  _warm.clear();
  _segments = const <String>[];
  _segIndex = 0;
  _segOnDone = null;
  ttsCurrent.value = null;
  ttsNeuralFallback.value = false;
}

/// 暂停朗读（保留当前进度，可继续）。只暂停，不释放音频缓冲。
///
/// 神经语音路径只 `pause()` 当前 `<audio>`，保留 src 与 currentTime，
/// 继续时能从暂停处接上；同时取消看门狗，避免暂停期间误判读完。
/// 浏览器语音兜底路径用原生 speechSynthesis.pause()。
void ttsPause() {
  if (_audio != null && !_neuralDisabled) {
    _watchdog?.cancel();
    _watchdog = null;
    try {
      _audio!.pause();
    } catch (_) {}
    return;
  }
  try {
    web.window.speechSynthesis.pause();
  } catch (_) {}
}

/// 继续朗读（从暂停处接上）。
void ttsResume() {
  if (_audio != null && !_neuralDisabled) {
    try {
      _audio!.play().catchError((_) {});
    } catch (_) {}
    return;
  }
  try {
    web.window.speechSynthesis.resume();
  } catch (_) {}}
