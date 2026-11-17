// 朗读风格预设 + 语音包选择（纯 Dart，可在 VM 测试里直接验证）。
//
// 为什么要这一层：系统 TTS 只给「引擎里的语音包」（zh-cn-x-ccc-local 这类内部名），
// 没有「温柔女声 / 广播员男声」这种人类说法，也拿不到可靠的性别字段（Android 的
// Voice 不提供 gender）。所以 App 侧把**音色**（选哪个语音包，取决于本机装了什么）
// 和**风格**（音调 + 语速，App 自己定）拆成两件事：
//
//   · 语音包 = 系统里已装的中文 voice（`voices` 通道，功能中心「语音包设置」页列出）
//   · 风格   = TtsPreset（自然 / 温柔女声 / 广播员男声 / 甜美女声 / 高亢有力男声）
//
// 口径（不要夸大）：风格只是 pitch/rate 的组合，不会把男声变女声；想要真·女声，
// 得在系统里装一个女声语音包（例如 Google 语音服务的「普通话」女声）再选它。
// 页面上如实说明这一点，不承诺「换了预设就有女声」。
import 'package:shared_preferences/shared_preferences.dart';

import '../offline/local_store_keys.dart';
import 'tts_voice_slots.dart';

/// 朗读风格预设：音调 + 语速。
class TtsPreset {
  const TtsPreset({
    required this.id,
    required this.label,
    required this.hint,
    required this.pitch,
    required this.rate,
  });

  final String id;
  final String label;
  final String hint;

  /// 音调倍数（1.0 = 原声；>1 更尖细，<1 更低沉）。Android 引擎接受 [0.5, 2.0]。
  final double pitch;

  /// 语速倍数（1.0 = 原速）。
  final double rate;
}

class TtsPresets {
  TtsPresets._();

  static const TtsPreset natural = TtsPreset(
    id: 'natural',
    label: '自然（默认）',
    hint: '不改音调与语速，跟系统语音包本来的样子一致',
    pitch: 1.0,
    rate: 1.0,
  );

  static const TtsPreset gentleFemale = TtsPreset(
    id: 'gentle_female',
    label: '温柔女声',
    hint: '音调略高、语速放慢，适合睡前长段精读',
    pitch: 1.25,
    rate: 0.9,
  );

  static const TtsPreset anchorMale = TtsPreset(
    id: 'anchor_male',
    label: '广播员男声',
    hint: '音调压低、语速平稳，接近新闻播报',
    pitch: 0.8,
    rate: 1.0,
  );

  static const TtsPreset sweetFemale = TtsPreset(
    id: 'sweet_female',
    label: '甜美女声',
    hint: '音调明显提高、语速稍快，语气轻快',
    pitch: 1.45,
    rate: 1.06,
  );

  static const TtsPreset powerfulMale = TtsPreset(
    id: 'power_male',
    label: '高亢有力的男声',
    hint: '音调略低、语速加快，念号召段落更有劲',
    pitch: 0.92,
    rate: 1.14,
  );

  /// 页面展示顺序：自然在前，其余按「女声 → 男声」。
  static const List<TtsPreset> all = <TtsPreset>[
    natural,
    gentleFemale,
    sweetFemale,
    anchorMale,
    powerfulMale,
  ];

  static TtsPreset byId(String? id) => all.firstWhere(
        (p) => p.id == id,
        orElse: () => natural,
      );
}

/// 一条「语音包」信息（系统/浏览器实际提供的语音）。
class TtsVoiceOption {
  const TtsVoiceOption({
    required this.name,
    required this.label,
    required this.locale,
    this.network = false,
    this.chinese = true,
    this.gender = '',
  });

  /// 引擎内部名（zh-cn-x-ccc-local 这类），切语音时用它。
  final String name;

  /// 给用户看的名字（安卓取语言显示名，浏览器取语音名）。
  final String label;

  /// 语言标签（zh-CN / zh_CN …）。
  final String locale;

  /// 是否需要联网合成（系统语音包可能标 network）。
  final bool network;

  /// 是否为中文语音（Web 端会把非中文语音也列出来，供用户手选）。
  final bool chinese;

  /// 引擎自报的性别特征：'male' / 'female' / ''（引擎不提供 → 界面显示「未知」）。
  /// 注意这是**引擎报的标签**，不是 App 猜的；拿不到就留空，绝不按名字推断。
  final String gender;

  /// 展示用的性别前缀（男声/女声/空）。
  String get genderLabel {
    if (gender == 'male') return '男声';
    if (gender == 'female') return '女声';
    return '';
  }
}

/// 朗读设置：风格预设 + 选中的语音包名（'' = 自动优选）。
///
/// 存两份地方：SharedPreferences（App 启动即读，早于 LocalDb）——键登记在
/// `LocalStoreKeys`，不许在别处写字面量。
class TtsSettings {
  TtsSettings._();

  static final TtsSettings instance = TtsSettings._();

  String _presetId = TtsPresets.natural.id;
  String _voiceName = '';
  bool _loaded = false;

  String get presetId => _presetId;
  TtsPreset get preset => TtsPresets.byId(_presetId);

  /// 选中的系统语音包名；空串 = 自动挑最合适的中文语音。
  String get voiceName => _voiceName;

  /// 当前风格对应的「音色档」：Web 用它挑后端神经语音，安卓用它去系统语音包里
  /// 按关键词找对应音色（找不到就只做音调语速近似）。
  TtsVoiceSlot get slot => TtsVoiceSlots.byId(_presetId);

  bool get loaded => _loaded;

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _presetId = sp.getString(LocalStoreKeys.ttsPreset) ?? _presetId;
      _voiceName = sp.getString(LocalStoreKeys.ttsVoice) ?? _voiceName;
    } catch (_) {
      // 读不到就用默认值：朗读设置坏了不该影响朗读本身
    }
    _loaded = true;
  }

  Future<void> setPreset(String id) async {
    _presetId = TtsPresets.byId(id).id;
    _loaded = true;
    await _persist();
  }

  Future<void> setVoiceName(String name) async {
    _voiceName = name.trim();
    _loaded = true;
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(LocalStoreKeys.ttsPreset, _presetId);
      await sp.setString(LocalStoreKeys.ttsVoice, _voiceName);
    } catch (_) {
      // 同上：本机存储不可用时退化为「本次会话有效」
    }
  }

  /// 仅供测试：重置内存态（不动存储）。
  void debugReset() {
    _presetId = TtsPresets.natural.id;
    _voiceName = '';
    _loaded = false;
  }
}
