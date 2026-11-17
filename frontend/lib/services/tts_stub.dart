// 非 Web 平台空实现（保证跨平台编译通过）。
import 'package:flutter/foundation.dart';

final ValueNotifier<String?> ttsCurrent = ValueNotifier<String?>(null);

/// 与原生/Web 实现保持 API 一致（空实现永不就绪）
final ValueNotifier<int> ttsReadyTick = ValueNotifier<int>(0);

Future<void> ttsInit() async {}

bool ttsAvailable() => false;
bool ttsHasChineseVoice() => false;
bool ttsVoicesLoaded() => false;
bool ttsNeuralReady() => false;
void ttsSpeak(String text, {String id = '__default__', double rate = 1.0}) {}
void ttsStop() {}
