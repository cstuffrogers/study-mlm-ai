// D143 门禁（第四批）：安卓「没有男声」的可见性修复。
//
// 用户实报「APP 没有男声」。安卓引擎的 Voice 对象不保证有性别信息，但 Google 引擎
// 在 features 里带 gender=female|male，原来我们完全没读 → 界面上两个音色都只写
// 「中文」，用户分不出男女，看起来就像只有一个。
//
// 锁四件事：
//  ① Kotlin 读 features 里的 gender，读不到就返回 null（不是猜）；
//  ② Dart 侧把 gender 透传到 TtsVoiceOption.genderLabel；
//  ③ 语音包语言过滤不能只认 zh|cmn|yue（有的引擎报 und / zh-Hans → 整张表空掉）；
//  ④ 按档位挑语音时，引擎报了性别就优先按性别挑，比关键词可靠。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/services/tts_settings.dart';
import 'package:marxism_reader/services/tts_voice_slots.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  final kt = _read(
      'android/app/src/main/kotlin/com/weiwu/marxism_reader/MainActivity.kt');

  group('安卓性别标签', () {
    test('读 Voice.features 里的 gender，且不按名字猜', () {
      expect(kt, contains('voice.features'));
      expect(kt, contains('startsWith("gender")'));
      expect(kt, contains('"gender" to genderOf(v),'));
      // 关键：拿不到必须是空/null，不能默认成某个性别
      expect(kt, contains('return ""'));
    });

    test('语言过滤放宽到 zh* / -cn / hans / hant（否则整张表可能空）', () {
      final i = kt.indexOf('?.filter { v ->');
      expect(i, greaterThan(0));
      final block = kt.substring(i, i + 700);
      expect(block, contains('startsWith("zh")'));
      expect(block, contains('hans'));
      expect(block, contains('hant'));
    });
  });

  group('Dart 侧透传', () {
    test('gender 解析进 TtsVoiceOption 并给出中文标签', () {
      const male = TtsVoiceOption(name: 'x', label: '中文', locale: 'zh-CN', gender: 'male');
      const female =
          TtsVoiceOption(name: 'y', label: '中文', locale: 'zh-CN', gender: 'female');
      const unknown = TtsVoiceOption(name: 'z', label: '中文', locale: 'zh-CN');
      expect(male.genderLabel, '男声');
      expect(female.genderLabel, '女声');
      expect(unknown.genderLabel, '',
          reason: '引擎不报性别时必须留空，界面显示「未知」，不能猜');
      final native = _read('lib/services/tts_native.dart');
      expect(native, contains("gender: '\${m['gender'] ?? ''}'"));
    });

    test('引擎报了性别时优先按性别挑语音包（比关键词可靠）', () {
      final native = _read('lib/services/tts_native.dart');
      final i = native.indexOf('Future<String?> _voiceForSlot');
      expect(i, greaterThan(0));
      final block = native.substring(i, i + 700);
      expect(block, contains('wantGender'));
      expect(block, contains('v.gender == wantGender'));
    });

    test('Web 端从语音名里取性别线索，取不到留空', () {
      final web = _read('lib/services/tts_web.dart');
      expect(web, contains('_genderOf'));
      expect(web, contains("low.contains('female')"));
      expect(web, contains("low.contains('male')"));
    });

    test('设置页列表显示「男声 · / 女声 ·」前缀', () {
      final screen = _read('lib/screens/tts_settings_screen.dart');
      expect(screen, contains('v.genderLabel'));
    });
  });

  group('五个档位的性别期望', () {
    test('女声档要求 female、男声档要求 male；自然档不指定', () {
      expect(TtsVoiceSlots.natural.nativeHints.contains('female'), isFalse);
      expect(TtsVoiceSlots.natural.nativeHints.contains('male'), isFalse);
      for (final s in [TtsVoiceSlots.gentleFemale, TtsVoiceSlots.sweetFemale]) {
        expect(s.nativeHints.contains('female'), isTrue, reason: '${s.label} 应优先找女声');
      }
      for (final s in [TtsVoiceSlots.anchorMale, TtsVoiceSlots.powerfulMale]) {
        expect(s.nativeHints.contains('male'), isTrue, reason: '${s.label} 应优先找男声');
      }
    });
  });
}
