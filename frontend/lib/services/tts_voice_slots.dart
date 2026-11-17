// 朗读「语音」的白名单与标签——纯 Dart，无平台依赖，Web / 安卓 / 测试共用。
//
// 为什么要有这一层：
//  · 安卓端的音色取决于**系统装了什么语音包**（各机型差异极大，有的只有男声）；
//  · Web 端优先走后端微软神经语音（真人级），名字是固定的 zh-CN-XxxNeural；
//    **浏览器语音拿不到后端那些音色**，所以 Web 上「温柔女声 / 广播员男声」这类
//    人类说法只能落在后端神经语音上，交给浏览器就退化成本机系统语音。
//
// 于是统一成一张「固定音色表」：五个档位（对应页面上的五种风格），每档给出
// Web 用的神经语音名 + 安卓用的候选关键词。谁先命中用谁，都不命中就退回
// 「音调语速近似」，并在页面上如实说明（不承诺「换了预设就有女声」）。
class TtsVoiceSlot {
  const TtsVoiceSlot({
    required this.id,
    required this.label,
    required this.hint,
    required this.neuralVoice,
    required this.nativeHints,
  });

  /// 与 TtsPresets 的 id 一一对应（natural / gentle_female / sweet_female /
  /// anchor_male / power_male）。
  final String id;

  final String label;
  final String hint;

  /// Web 端用的微软神经语音 ShortName（后端 ALLOWED_VOICES 白名单内）。
  final String neuralVoice;

  /// 安卓端候选关键词：系统语音包 displayName / name 里含其一即视为「命中该音色」。
  /// 只在**用户没手动选语音包**时用于自动匹配（不国内置语音包，安卓没法指定）。
  final List<String> nativeHints;
}

class TtsVoiceSlots {
  TtsVoiceSlots._();

  /// 全站统一默认：晓晓（温暖女声，成人向，最适合长段精读）。
  static const String neuralDefault = 'zh-CN-XiaoxiaoNeural';

  static const TtsVoiceSlot natural = TtsVoiceSlot(
    id: 'natural',
    label: '自然（默认）',
    hint: '不改音调语速；Web 用晓晓，安卓用系统默认中文语音',
    neuralVoice: neuralDefault,
    nativeHints: <String>[],
  );

  static const TtsVoiceSlot gentleFemale = TtsVoiceSlot(
    id: 'gentle_female',
    label: '温柔女声',
    hint: '音调略高、语速放慢，适合睡前长段精读（Web 用「晓晓」）',
    neuralVoice: 'zh-CN-XiaoxiaoNeural',
    nativeHints: <String>['xiaoxiao', 'female', '女', 'huihui', 'tingting', 'xiaoyi'],
  );

  static const TtsVoiceSlot sweetFemale = TtsVoiceSlot(
    id: 'sweet_female',
    label: '甜美女声',
    hint: '音调明显提高、语速稍快，语气轻快（Web 用「晓伊」）',
    neuralVoice: 'zh-CN-XiaoyiNeural',
    nativeHints: <String>['xiaoyi', 'xiaobei', 'xiaoni', 'female', '女', 'yaoyao'],
  );

  static const TtsVoiceSlot anchorMale = TtsVoiceSlot(
    id: 'anchor_male',
    label: '广播员男声',
    hint: '音调压低、语速平稳，接近新闻播报（Web 用「云扬」）',
    neuralVoice: 'zh-CN-YunyangNeural',
    nativeHints: <String>['yunyang', 'male', '男', 'kangkang', 'yunjian'],
  );

  static const TtsVoiceSlot powerfulMale = TtsVoiceSlot(
    id: 'power_male',
    label: '高亢有力的男声',
    hint: '音调略低、语速加快，念号召段落更有劲（Web 用「云健」）',
    neuralVoice: 'zh-CN-YunjianNeural',
    nativeHints: <String>['yunjian', 'yunxi', 'male', '男', 'kangkang'],
  );

  static const List<TtsVoiceSlot> all = <TtsVoiceSlot>[
    natural,
    gentleFemale,
    sweetFemale,
    anchorMale,
    powerfulMale,
  ];

  static TtsVoiceSlot byId(String? id) => all.firstWhere(
        (s) => s.id == id,
        orElse: () => natural,
      );

  /// 后端神经语音白名单（与 backend/services/tts_service.py::ALLOWED_VOICES 同步）。
  static const List<String> neuralVoices = <String>[
    'zh-CN-XiaoxiaoNeural',
    'zh-CN-XiaoyiNeural',
    'zh-CN-YunxiNeural',
    'zh-CN-YunyangNeural',
    'zh-CN-YunjianNeural',
    'zh-CN-YunxiaNeural',
    'zh-CN-liaoning-XiaobeiNeural',
    'zh-CN-shaanxi-XiaoniNeural',
  ];
}
