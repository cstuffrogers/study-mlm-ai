// D143 门禁：两件用户当场能感知的事。
//
// ① 「关于」页的「下载最新安卓版 / 打开 GitHub」在安卓包里点了没反应。
//    根因：open_url 的非 Web 实现是空函数（open_url_stub.dart），整个原生端没有外链能力。
//    → 现在走 url_launcher，且 Android 11+ 必须声明 VIEW+https 的 <queries>，缺了按钮照样死。
//    本文件锁：依赖存在、条件导出真的落到 io 实现、io 实现真的调 launchUrl、
//    manifest 声明了 intent、关于页两个按钮 onPressed 非空。
//
// ② 功能中心新增「语音包设置」：4 种要求音色（温柔女声 / 广播员男声 / 甜美女声 /
//    高亢有力的男声）+ 自然默认，且选择要落到通道上（语速乘预设、音调随预设）。
//    本文件锁：预设定义、持久化、通道协议（voices / setVoice / speak 带 pitch）、页面渲染。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/screens/about_screen.dart';
import 'package:marxism_reader/screens/tools_screen.dart';
import 'package:marxism_reader/screens/tts_settings_screen.dart';
import 'package:marxism_reader/services/tts.dart';
import 'package:marxism_reader/services/tts_native.dart' as native;
import 'package:marxism_reader/services/tts_settings.dart';
import 'package:marxism_reader/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('外链按钮（关于页 / 延伸阅读）在原生端真的能打开', () {
    test('pubspec 声明了 url_launcher', () {
      expect(_read('pubspec.yaml'), contains('url_launcher:'));
    });

    test('open_url 条件导出：Web 走 web 实现，原生走 io 实现，其余才是空实现', () {
      final src = _read('lib/services/open_url.dart');
      expect(src, contains("if (dart.library.js_interop) 'open_url_web.dart'"));
      expect(src, contains("if (dart.library.io) 'open_url_io.dart'"),
          reason: '没有这条分支，安卓/桌面端就会落到空实现，按钮点了没反应');
      expect(src, contains("export 'open_url_stub.dart'"));
    });

    test('io 实现调 launchUrl 且用 externalApplication', () {
      final src = _read('lib/services/open_url_io.dart');
      expect(src, contains('launchUrl('));
      expect(src, contains('LaunchMode.externalApplication'));
      expect(src, isNot(contains('void openExternal(String url) {}')),
          reason: '空实现就是本次修的 bug');
    });

    test('AndroidManifest 声明 VIEW + https 的 queries（Android 11+ 包可见性）', () {
      final mf = _read('android/app/src/main/AndroidManifest.xml');
      expect(mf, contains('android.intent.action.VIEW'));
      expect(mf, contains('android:scheme="https"'));
    });

    testWidgets('关于页两个外链按钮都有回调（不是 null 的死按钮）', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.build(),
        home: const AboutScreen(),
      ));
      await t.pump(const Duration(milliseconds: 300));

      for (final label in ['下载最新安卓版', '打开 GitHub']) {
        final btn = find.widgetWithText(OutlinedButton, label);
        final filled = find.widgetWithText(FilledButton, label);
        final found = btn.evaluate().isNotEmpty ? btn : filled;
        expect(found, findsOneWidget, reason: '找不到「$label」按钮');
        final w = t.widget<ButtonStyleButton>(found.first);
        expect(w.onPressed, isNotNull, reason: '「$label」没有回调，点了不会有反应');
      }
    });
  });

  group('语音包风格预设', () {
    test('四种要求的音色都在，且 id 唯一', () {
      final labels = TtsPresets.all.map((p) => p.label).toList();
      for (final need in ['温柔女声', '广播员男声', '甜美女声', '高亢有力的男声']) {
        expect(labels, contains(need), reason: '缺少要求的音色：$need');
      }
      final ids = TtsPresets.all.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length, reason: '预设 id 不能重复');
    });

    test('预设真的改变了音调或语速，且自然档是 1.0/1.0', () {
      expect(TtsPresets.natural.pitch, 1.0);
      expect(TtsPresets.natural.rate, 1.0);
      for (final p in TtsPresets.all.where((p) => p.id != 'natural')) {
        expect(p.pitch != 1.0 || p.rate != 1.0, isTrue,
            reason: '${p.label} 和自然档完全一样，等于没生效');
      }
    });

    test('音调落在安卓引擎可接受范围 0.5~2.0', () {
      for (final p in TtsPresets.all) {
        expect(p.pitch, inInclusiveRange(0.5, 2.0), reason: '${p.label} 音调越界会被引擎忽略');
        expect(p.rate, inInclusiveRange(0.5, 2.0));
      }
    });

    test('未知 / 空 id 回落到自然档，不炸', () {
      expect(TtsPresets.byId('nope').id, TtsPresets.natural.id);
      expect(TtsPresets.byId(null).id, TtsPresets.natural.id);
      expect(TtsPresets.byId('').id, TtsPresets.natural.id);
    });
  });

  group('朗读设置持久化', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      TtsSettings.instance.debugReset();
    });

    test('选预设后写进 SharedPreferences，重新 load 能读回', () async {
      await TtsSettings.instance.setPreset(TtsPresets.anchorMale.id);
      expect(TtsSettings.instance.preset.label, '广播员男声');

      TtsSettings.instance.debugReset();
      await TtsSettings.instance.load();
      expect(TtsSettings.instance.presetId, TtsPresets.anchorMale.id,
          reason: '重启后必须还是上次选的风格');
    });

    test('选语音包名后写进 SharedPreferences，重新 load 能读回', () async {
      await TtsSettings.instance.setVoiceName('zh-cn-x-ccc-local');
      TtsSettings.instance.debugReset();
      await TtsSettings.instance.load();
      expect(TtsSettings.instance.voiceName, 'zh-cn-x-ccc-local');
    });

    test('未知预设 id 存进来也回落自然档，不把界面搞崩', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{'off_tts_preset': 'ghost'});
      TtsSettings.instance.debugReset();
      await TtsSettings.instance.load();
      expect(TtsSettings.instance.preset.id, TtsPresets.natural.id);
    });
  });

  group('安卓 TTS 通道：语音包列表 / 切换 / 音调', () {
    final sent = <MethodCall>[];

    setUp(() {
      sent.clear();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      TtsSettings.instance.debugReset();
      native.debugSetTtsAvailable(true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('xxmz/tts'), (call) async {
        sent.add(call);
        switch (call.method) {
          case 'init':
            return {'ready': true, 'chinese': true, 'engine': 'com.google.android.tts'};
          case 'voices':
            return {
              'voices': [
                {
                  'name': 'zh-cn-x-ccc-local',
                  'locale': 'zh-CN',
                  'label': '中文（中国）',
                  'quality': 300,
                  'network': false,
                },
                {
                  'name': 'zh-cn-x-ccc-network',
                  'locale': 'zh-CN',
                  'label': '中文（中国）',
                  'quality': 400,
                  'network': true,
                },
              ],
              'current': null,
            };
          case 'setVoice':
            return (call.arguments as Map)['name'] == 'zh-cn-x-ccc-local' ||
                (call.arguments as Map)['name'] == '';
          case 'speak':
            return true;
          default:
            return null;
        }
      });
    });

    tearDown(() {
      native.debugSetTtsAvailable(false);
      ttsCurrent.value = null;
      TtsSettings.instance.debugReset();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('xxmz/tts'), null);
    });

    test('voices 解析出本机中文语音包（名字/locale/是否需联网）', () async {
      final list = await ttsListVoices();
      expect(list.length, 2);
      expect(list.first.name, 'zh-cn-x-ccc-local');
      expect(list.first.locale, 'zh-CN');
      expect(list.first.network, isFalse);
      expect(list.last.network, isTrue);
    });

    test('setVoice 成功后记进设置；失败不记', () async {
      expect(await ttsSetVoice('zh-cn-x-ccc-local'), isTrue);
      expect(TtsSettings.instance.voiceName, 'zh-cn-x-ccc-local');

      expect(await ttsSetVoice('no-such-voice'), isFalse);
      expect(TtsSettings.instance.voiceName, 'zh-cn-x-ccc-local',
          reason: '切换失败不能把上次的选择覆盖掉');
    });

    test('speak 带上预设的音调与「调用方语速 × 预设倍数」', () async {
      await TtsSettings.instance.setPreset(TtsPresets.gentleFemale.id);
      await ttsInit();
      ttsSpeak('人的正确思想是从哪里来的', id: 'p1', rate: 1.0);
      await Future<void>.delayed(Duration.zero);

      final args = sent.firstWhere((c) => c.method == 'speak').arguments as Map;
      expect(args['pitch'], TtsPresets.gentleFemale.pitch);
      expect(args['rate'], closeTo(TtsPresets.gentleFemale.rate, 1e-9));

      // 调用方要更快时，是在预设基础上再乘，而不是丢掉预设
      ttsSpeak('再快一点', id: 'p2', rate: 1.5);
      await Future<void>.delayed(Duration.zero);
      final args2 = sent.last.arguments as Map;
      expect(args2['rate'], closeTo(TtsPresets.gentleFemale.rate * 1.5, 1e-9));
    });
  });

  group('界面接线', () {
    testWidgets('功能中心有「语音包设置」入口，能进到设置页', (t) async {
      // 功能中心是 ListView，入口在可视区之外不会被构建 → 用高一点的视口
      t.view.physicalSize = const Size(400 * 2, 1400 * 2);
      t.view.devicePixelRatio = 2.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.build(),
        home: const ToolsScreen(),
      ));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('语音包设置'), findsOneWidget);

      await t.tap(find.text('语音包设置'));
      await t.pumpAndSettle();
      expect(find.byType(TtsSettingsScreen), findsOneWidget);
    });

    testWidgets('设置页列出全部风格与「语音包」分区，窄屏不溢出', (t) async {
      // 360dp 宽（窄屏、验溢出）× 高视口（让「语音包」分区也被构建出来）
      t.view.physicalSize = const Size(360 * 3, 1800 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);

      await t.pumpWidget(MaterialApp(
        theme: AppTheme.build(),
        home: const TtsSettingsScreen(),
      ));
      await t.pump(const Duration(milliseconds: 400));

      expect(find.text('朗读风格'), findsOneWidget);
      expect(find.text('语音包'), findsOneWidget);
      for (final need in ['自然（默认）', '温柔女声', '甜美女声', '广播员男声', '高亢有力的男声']) {
        expect(find.text(need), findsOneWidget, reason: '缺少风格：$need');
      }
      expect(t.takeException(), isNull, reason: '窄屏 + 长副标题不得溢出');
    });
  });
}
