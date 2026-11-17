// D143 门禁（第三批）：多音色真的接上了。
//
// 检查项（都是「线上真会踩」的脱线点）：
//  ① 四种风格的音色档存在、neuralVoice 全在后端白名单内（白名单外的 name 会被后端
//     静默替换成默认晓晓，表现为「四个档听起来一模一样」）；
//  ② Web 端请求后端神经语音时**必须带 voice 参数**（不带就永远是晓晓）；
//  ③ 安卓端 speak 必须带 pitch（否则音调预设无效），并按档位去找系统语音包；
//  ④ 后端 ALLOWED_VOICES 与前端 neuralVoices 是同一份集合；
//  ⑤ 设置页必须如实说明「安卓端音色取决于装机语音包」。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/services/tts_settings.dart';
import 'package:marxism_reader/services/tts_voice_slots.dart';

String _read(String p) => File(p).readAsStringSync();

/// 从 backend/services/tts_service.py 里抠出 ALLOWED_VOICES 的字符串集合。
Set<String> _backendVoices() {
  final src = _read('../backend/services/tts_service.py');
  final start = src.indexOf('ALLOWED_VOICES = {');
  expect(start, greaterThan(0), reason: '后端白名单结构变了，门禁要同步');
  final block = src.substring(start, src.indexOf('}', start));
  // 方言语音（liaoning / shaanxi）带连字符，正则必须一并覆盖，否则两边集合永远对不上
  return RegExp(r'"(zh-CN-[A-Za-z-]+Neural)"')
      .allMatches(block)
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  group('音色档位表', () {
    test('五档齐全，id 与 TtsPresets 一一对应', () {
      expect(TtsVoiceSlots.all.length, 5);
      final slotIds = TtsVoiceSlots.all.map((s) => s.id).toList();
      final presetIds = TtsPresets.all.map((p) => p.id).toList();
      expect(slotIds, presetIds, reason: '档位表与风格预设的 id 顺序必须一致');
      expect(slotIds.toSet().length, 5, reason: 'id 不许重复');
    });

    test('每档的神经语音都在后端白名单内（否则后端静默换成默认女声）', () {
      final allowed = _backendVoices();
      expect(allowed.length, 8);
      for (final s in TtsVoiceSlots.all) {
        expect(allowed.contains(s.neuralVoice), isTrue,
            reason: '${s.label} 的 ${s.neuralVoice} 不在后端 ALLOWED_VOICES 里，'
                '请求会被替换成默认晓晓 → 选了没用');
      }
    });

    test('四个「特色音色」各自指向不同神经语音（不能四档一个音）', () {
      final featured = TtsVoiceSlots.all
          .where((s) => s.id != 'natural')
          .map((s) => s.neuralVoice)
          .toSet();
      expect(featured.length, 4, reason: '四个调性档必须是四个不同音色');
    });

    test('前端 neuralVoices 与后端 ALLOWED_VOICES 集合完全相同', () {
      expect(TtsVoiceSlots.neuralVoices.toSet(), _backendVoices());
    });

    test('未知 id 回落自然档', () {
      expect(TtsVoiceSlots.byId('nope').id, 'natural');
      expect(TtsVoiceSlots.byId(null).id, 'natural');
    });

    test('安卓关键词里不含空串（空串会匹配任意语音）', () {
      for (final s in TtsVoiceSlots.all) {
        for (final h in s.nativeHints) {
          expect(h.trim().isNotEmpty, isTrue, reason: '${s.label} 有空白关键词');
        }
      }
    });
  });

  group('Web 端接线', () {
    test('请求 /api/tts/speak 时带上 voice', () {
      final src = _read('lib/services/tts_web.dart');
      final i = src.indexOf("Uri.parse('/api/tts/speak')");
      expect(i, greaterThan(0));
      final block = src.substring(i, i + 400);
      expect(block, contains("'voice':"),
          reason: '不带 voice 参数 → 后端永远用默认晓晓，四档听起来一模一样');
      expect(block, contains('neuralVoice'));
    });

    test('手选浏览器语音时不再走神经语音（否则是假开关）', () {
      final src = _read('lib/services/tts_web.dart');
      expect(src, contains('_neuralDisabled'));
      expect(src, contains('_browserSpeak(t, id, rate)'));
    });

    test('非中文的本机语音也列出来（否则本机只有英文时列表全空像没做）', () {
      final src = _read('lib/services/tts_web.dart');
      expect(src, contains('chinese: _voiceScore(v) > 0'));
      expect(src, contains('out.sort'));
    });
  });

  group('安卓端接线', () {
    test('speak 带 pitch，且按档位去系统语音包里找音色', () {
      final src = _read('lib/services/tts_native.dart');
      expect(src, contains("'pitch': preset.pitch"));
      expect(src, contains('_applySlotVoice()'));
      expect(src, contains('_voiceForSlot'));
      expect(src, contains("invokeMethod<bool>('setVoice'"));
    });

    test('手选语音包优先于风格档位', () {
      final src = _read('lib/services/tts_native.dart');
      final i = src.indexOf('void _applySlotVoice()');
      expect(i, greaterThan(0));
      final block = src.substring(i, i + 400);
      expect(block, contains('if (settings.voiceName.isNotEmpty) return;'),
          reason: '手选过的语音包不能被预设覆盖');
    });

    test('Kotlin 通道有 voices / setVoice / pitch', () {
      final kt = _read(
          'android/app/src/main/kotlin/com/weiwu/marxism_reader/MainActivity.kt');
      for (final k in ['"voices"', '"setVoice"', '"pitch"', 'setPitch']) {
        expect(kt, contains(k), reason: '缺 $k');
      }
    });
  });

  group('设置页如实说明', () {
    test('写明 Web 走神经语音、安卓随系统语音包', () {
      final src = _read('lib/screens/tts_settings_screen.dart');
      expect(src, contains('微软神经语音'));
      expect(src, contains('系统语音包'));
      expect(src, contains('App 不内置语音包'));
      expect(src, contains('_neuralRow()'));
    });
  });
}
