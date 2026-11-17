// 「喇叭」与「释义浮框」回归测试。
//
// 用户反馈过的真问题：释义浮框、章节导读顶端、原文阅读器三处的发音喇叭不见了。
// 根因是非 Web 平台落到了空实现（ttsAvailable()==false），于是 SpeakButton 全部返回
// SizedBox.shrink()。这里锁三件事：
//  ① 三处按钮确实挂在页面上（widget 在树里，只是可能因引擎不可用而收起）；
//  ② 释义浮框本身要能列出「复制 / 标色 / 朗读 + 五个模式」；
//  ③ 安卓原生通道协议（init / speak / stop / done）行为正确。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/models/message.dart';
import 'package:marxism_reader/services/tts.dart';
// 直接引原生实现只为拿调试开关（与 tts.dart 导出的是同一个库实例）
import 'package:marxism_reader/services/tts_native.dart' as native;
import 'package:marxism_reader/theme/app_theme.dart';
import 'package:marxism_reader/widgets/selection_ask_box.dart';
import 'package:marxism_reader/widgets/speak_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('释义浮框', () {
    testWidgets('列出发音喇叭与五个模式（不只靠颜色区分）', (t) async {
      final asked = <ChatMode>[];
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: SelectionAskPanel(
            text: '实践是检验真理的唯一标准',
            speakId: 'sel-test-1',
            onCopy: () {},
            onDismiss: () {},
            onAsk: (m) => asked.add(m),
          ),
        ),
      ));

      // 喇叭按钮必须存在（引擎不可用时内部收起，但 widget 不能少）
      expect(find.byType(SpeakButton), findsOneWidget, reason: '释义浮框丢了朗读入口');
      // 五个模式 chip 的文字标签全在
      for (final m in ChatMode.values) {
        expect(find.text(m.label), findsOneWidget, reason: '释义浮框缺「${m.label}」');
      }
      // 点一个模式能回调出正确的模式名
      await t.tap(find.text(ChatMode.dig.label));
      expect(asked, [ChatMode.dig]);
    });
  });

  group('喇叭按钮', () {
    testWidgets('引擎不可用时收起（不会点了没反应），可用时显示图标', (t) async {
      // 宿主（Windows 测试环境）没有原生 TTS → 收起
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.build(),
        home: const Scaffold(body: SpeakButton(text: '实践是检验真理的唯一标准', id: 'x')),
      ));
      expect(find.byIcon(Icons.volume_up_rounded), findsNothing);

      native.debugSetTtsAvailable(true);
      addTearDown(() => native.debugSetTtsAvailable(false));
      ttsReadyTick.value++;
      await t.pump();
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget,
          reason: '引擎可用时喇叭必须出现');
      expect(find.byTooltip('朗读'), findsOneWidget);
    });

    testWidgets('朗读中图标变成停止', (t) async {
      native.debugSetTtsAvailable(true);
      addTearDown(() {
        native.debugSetTtsAvailable(false);
        ttsCurrent.value = null;
      });
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.build(),
        home: const Scaffold(body: SpeakButton(text: '矛盾', id: 'play-1')),
      ));
      ttsCurrent.value = 'play-1';
      await t.pump();
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      expect(find.byTooltip('停止朗读'), findsOneWidget);
    });
  });

  group('安卓原生 TTS 通道协议', () {
    final calls = <MethodCall>[];
    late List<MethodCall> sent;

    setUp(() {
      sent = [];
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('xxmz/tts'), (call) async {
        sent.add(call);
        switch (call.method) {
          case 'init':
            return {'ready': true, 'chinese': true, 'engine': 'com.google.android.tts'};
          case 'speak':
            return true;
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('xxmz/tts'), null);
    });

    test('init 之后可用，speak 带上 text/id/rate，done 回调熄灭高亮', () async {
      native.debugSetTtsAvailable(true);
      addTearDown(() {
        native.debugSetTtsAvailable(false);
        ttsCurrent.value = null;
      });

      await ttsInit();
      expect(sent.first.method, 'init');
      expect(ttsHasChineseVoice(), isTrue);
      expect(ttsVoicesLoaded(), isTrue);

      ttsSpeak('实践是检验真理的唯一标准', id: 'chunk-1', rate: 1.2);
      await Future<void>.delayed(Duration.zero);
      final speak = sent.firstWhere((c) => c.method == 'speak');
      final args = speak.arguments as Map;
      expect(args['text'], '实践是检验真理的唯一标准');
      expect(args['id'], 'chunk-1');
      expect(args['rate'], 1.2);
      expect(ttsCurrent.value, 'chunk-1');

      // 原生播完 → 通道回调 done（走 SystemChannels 的 method call 方向）
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'xxmz/tts',
        const StandardMethodCodec().encodeMethodCall(const MethodCall('done', 'chunk-1')),
        (_) {},
      );
      await Future<void>.delayed(Duration.zero);
      expect(ttsCurrent.value, isNull, reason: '播完必须熄灭喇叭高亮');
    });

    test('空文本不发请求；stop 会通知原生并立即熄灭', () async {
      native.debugSetTtsAvailable(true);
      addTearDown(() {
        native.debugSetTtsAvailable(false);
        ttsCurrent.value = null;
      });
      await ttsInit();
      sent.clear();

      ttsSpeak('   ', id: 'x');
      await Future<void>.delayed(Duration.zero);
      expect(sent.where((c) => c.method == 'speak'), isEmpty);

      ttsSpeak('矛盾', id: 'y');
      await Future<void>.delayed(Duration.zero);
      expect(ttsCurrent.value, 'y');
      ttsStop();
      await Future<void>.delayed(Duration.zero);
      expect(ttsCurrent.value, isNull);
      expect(sent.last.method, 'stop');
    });
  });

  group('三处喇叭接线（源码级锁定，防再次被改稿删掉）', () {
    String read(String p) => File(p).readAsStringSync();

    test('章节导读顶端：红色顶部卡里的整页朗读', () {
      final src = read('lib/screens/chapter_guide_screen.dart');
      expect(src.contains('SpeakButton('), isTrue, reason: '深入学习顶部卡的喇叭被删了');
      expect(src.contains("id: 'guide-head-"), isTrue);
      expect(src.contains('_chapterSpeech('), isTrue, reason: '整页朗读文本拼装被删了');
    });

    test('原文阅读器：标题栏整页朗读 + 选中浮动条的朗读', () {
      final src = read('lib/screens/work_reader_screen.dart');
      expect(src.contains("id: 'reader-page-"), isTrue, reason: '阅读器标题栏喇叭被删了');
      expect(src.contains("id: 'reader-sel-"), isTrue, reason: '选中浮动条的喇叭被删了');
      expect(src.contains('_pageSpeech()'), isTrue);
    });

    test('导读页选中浮框：五模式 + 朗读都在', () {
      final src = read('lib/screens/chapter_guide_screen.dart');
      expect(src.contains('SelectionAskPanel('), isTrue, reason: '释义浮框没挂到页面上');
      expect(src.contains('selectedText.isNotEmpty'), isTrue);
      final panel = read('lib/widgets/selection_ask_box.dart');
      expect(panel.contains('SpeakButton('), isTrue);
      expect(panel.contains('ChatMode.values'), isTrue);
    });

    test('没有任何页面再引用已删除的 chat_sheet', () {
      final dead = File('lib/screens/chat_sheet.dart');
      expect(dead.existsSync(), isFalse, reason: '死代码已删除，不应复活');
    });
  });
}
