// 中文语音优选逻辑单元测试（纯 Dart，不依赖浏览器）。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/services/tts_voice_pick.dart';

void main() {
  test('优先选普通话 zh-CN，而不是排在前面的英文/台湾腔/粤语', () {
    final voices = [
      const VoiceCand('English (United States)', 'en-US'),
      const VoiceCand('Chinese (Taiwan)', 'zh-TW'),
      const VoiceCand('Sinji (Cantonese)', 'yue-HK'),
      const VoiceCand('Microsoft Huihui - Chinese (Simplified)', 'zh-CN'),
      const VoiceCand('Google 普通话（中国大陆）', 'zh-CN'),
    ];
    final idx = bestVoiceIndex(voices);
    expect(voices[idx].lang.toLowerCase(), 'zh-cn');
    // 且应命中带普通话关键词的优质语音
    expect(voiceScore(name: voices[idx].name, lang: voices[idx].lang), greaterThan(100));
  });

  test('没有中文语音时返回 -1（不会误选英文）', () {
    final voices = [
      const VoiceCand('English (United States)', 'en-US'),
      const VoiceCand('Deutsch', 'de-DE'),
      const VoiceCand('日本語', 'ja-JP'),
    ];
    expect(bestVoiceIndex(voices), -1);
    expect(hasChineseVoice(voices), false);
  });

  test('只有台湾腔/粤语时，仍能选到（优先 zh-TW 略高于粤语）', () {
    final idx = bestVoiceIndex([
      const VoiceCand('Cantonese', 'yue-HK'),
      const VoiceCand('Chinese Taiwan', 'zh-TW'),
    ]);
    expect(idx, 1); // zh-TW(60-25=35) > yue(45-25=20)
    expect(hasChineseVoice([const VoiceCand('Cantonese', 'yue-HK')]), true);
  });

  test('zh-Hans 与 cmn-CN 都算优质中文', () {
    expect(voiceScore(name: 'x', lang: 'zh-Hans'), greaterThan(80));
    expect(voiceScore(name: 'x', lang: 'cmn-CN'), greaterThan(80));
    expect(voiceScore(name: 'x', lang: 'cmn-Hant'), greaterThan(50));
  });

  test('非中文语音打负分', () {
    expect(voiceScore(name: 'English', lang: 'en-US'), lessThan(0));
    expect(voiceScore(name: 'français', lang: 'fr-FR'), lessThan(0));
  });
}
