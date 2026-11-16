// 纯 Dart 中文语音优选逻辑（不依赖 package:web，可在 VM 单元测试中直接验证）。
//
// 目标：从浏览器 speechSynthesis.getVoices() 给出的语音列表中，挑出最合适朗读
// 中文（普通话）的那一个，避免「用英文/粤语/台湾腔语音读普通话」导致的发音怪异。
//
// 打分规则（见 voiceScore）：
//   - 普通话 zh-CN / zh-Hans / 带 CN·SG 的 cmn —— 最高分
//   - 其它中文（zh-TW / zh-HK / 其它 cmn）—— 中等分（能用）
//   - 粤语 yue —— 偏低
//   - 非中文 —— 记负分，绝不选
//   - 名称命中普通话/优质引擎关键词（mandarin、huihui、tingting、xiaoxiao…）—— 加分
class VoiceCand {
  final String name;
  final String lang;
  const VoiceCand(this.name, this.lang);
}

/// 给一个语音打分；>0 表示「可用中文语音」，越大越优先。
int voiceScore({required String name, required String lang}) {
  final l = lang.toLowerCase().replaceAll('_', '-');
  final n = name.toLowerCase();
  int s;
  if (l == 'zh-cn') {
    s = 100;
  } else if (l.startsWith('zh-hans')) {
    s = 95;
  } else if (l.startsWith('cmn')) {
    s = (l.contains('hans') || l.contains('cn') || l.contains('sg')) ? 92 : 70;
  } else if (l.startsWith('zh')) {
    s = 60; // zh-TW / zh-HK 等
  } else if (l.startsWith('yue')) {
    s = 45; // 粤语
  } else {
    return -100; // 非中文，直接排除
  }
  if (l.contains('hk') || l.contains('tw')) s -= 25; // 粤语/台湾腔降权
  if (n.contains('mandarin') ||
      n.contains('普通话') ||
      n.contains('putonghua') ||
      n.contains('huihui') ||
      n.contains('yaoyao') ||
      n.contains('tingting') ||
      n.contains('ting-ting') ||
      n.contains('kangkang') ||
      n.contains('xiaoxiao') ||
      n.contains('xiaoyi') ||
      n.contains('yunjian') ||
      n.contains('natural')) {
    s += 8;
  }
  return s;
}

/// 返回最优中文语音下标；无任何中文语音时返回 -1。
int bestVoiceIndex(List<VoiceCand> voices) {
  int best = -1;
  int bestScore = 0; // 只接受正向中文分
  for (var i = 0; i < voices.length; i++) {
    final sc = voiceScore(name: voices[i].name, lang: voices[i].lang);
    if (sc > bestScore) {
      bestScore = sc;
      best = i;
    }
  }
  return best;
}

/// 是否存在可用中文语音。
bool hasChineseVoice(List<VoiceCand> voices) => bestVoiceIndex(voices) >= 0;
