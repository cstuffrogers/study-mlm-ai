// 非 Web 平台空实现（保证跨平台编译通过）。
import 'package:flutter/foundation.dart';

final ValueNotifier<String?> ttsCurrent = ValueNotifier<String?>(null);

bool ttsAvailable() => false;
bool ttsHasChineseVoice() => false;
bool ttsVoicesLoaded() => false;
bool ttsNeuralReady() => false;
void ttsSpeak(String text, {String id = '__default__', double rate = 1.0}) {}
void ttsStop() {}
