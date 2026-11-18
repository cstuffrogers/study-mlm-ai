// D151 门禁：安卓原生朗读「读完」必须回调 Dart —— 修用户实报「连续朗读只读一页就停」。
//
// 根因（真机现象 → 代码）：
//   MainActivity 的 onDone 里写着 `lastChunkIndex > 0 && id.endsWith("#$lastChunkIndex")`。
//   阅读器一页通常不到 1200 字，splitForTts 只切出一段 → lastChunkIndex == 0 →
//   判断恒为假 → **Dart 永远收不到 done** → 不接下一页、状态条也不复位，
//   表现就是「读完这一页就结束了」。多段长文本才有回调，所以小字号/长页偶发能续。
//
// 钉住三件事：
//  ① 单段朗读也要回调（按完整 utteranceId 比对，不靠「最后一段下标 > 0」）；
//  ② 回调必须回主线程（UtteranceProgressListener 跑在引擎 binder 线程）；
//  ③ 引擎不回调的机型要有 Dart 侧兜底（看门狗），否则照样停在某一页。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readFile(String path) => File(path).readAsStringSync();

String slice(String src, String from, String to) {
  final i = src.indexOf(from);
  if (i < 0) throw StateError('找不到锚点：$from');
  final j = src.indexOf(to, i);
  return j < 0 ? src.substring(i) : src.substring(i, j);
}

void main() {
  final kt = readFile(
      'android/app/src/main/kotlin/com/weiwu/marxism_reader/MainActivity.kt');
  final reader = readFile('lib/screens/work_reader_screen.dart');

  group('① 单段朗读也必须回调 done（本次实报根因）', () {
    test('不许再用「最后一段下标 > 0」当开关', () {
      expect(kt, isNot(contains('lastChunkIndex > 0')),
          reason: '单段朗读的下标是 0，这条判断会让一页读完永远不通知 Dart');
      expect(kt, isNot(contains('lastChunkIndex = chunks.size - 1')));
    });

    test('改按完整 utteranceId 比对，单段（#0）同样命中', () {
      expect(kt, contains('private var lastUtteranceId: String?'));
      expect(kt, contains('lastUtteranceId = "\$id#\${chunks.size - 1}"'),
          reason: '每次 speak 都要记下「这一条任务的最后一段是哪个 id」');
      final onDone = slice(kt, 'override fun onDone(utteranceId: String?)', '@Deprecated');
      expect(onDone, contains('if (utteranceId != expected) return'));
      expect(onDone, contains('notifyDone(expected)'));
      // 通知完要清掉，避免同一条任务重复收尾
      expect(onDone, contains('lastUtteranceId = null'));
    });

    test('speak 失败/空串时把等待目标清空（不许残留上一条）', () {
      final fn = slice(kt, 'private fun speakNow(', 'private fun splitForTts(');
      expect(fn, contains('lastUtteranceId = null'), reason: '失败分支要清');
      expect(fn.indexOf('lastUtteranceId = null'),
          lessThan(fn.indexOf('lastUtteranceId = "\$id#')),
          reason: '先清后设，顺序不能反');
    });

    test('stop 也要清（避免迟到的 onDone 把停掉的朗读错接回去）', () {
      final stop = slice(kt, '"stop" -> {', '"voices" ->');
      expect(stop, contains('lastUtteranceId = null'));
    });
  });

  group('② 回调必须回主线程', () {
    test('notifyDone 走 runOnUiThread', () {
      final fn = slice(kt, 'private fun notifyDone(', 'private fun notifyFailed(');
      expect(fn, contains('runOnUiThread'));
      expect(fn, contains('invokeMethod("done"'));
      expect(fn, contains("substringBeforeLast('#')"),
          reason: 'Dart 侧的 id 不能带 #段号');
    });

    test('引擎报错只在「当前这条任务」上收尾', () {
      final fn = slice(kt, 'private fun notifyFailed(', ') {\n');
      expect(fn, contains('lastUtteranceId ?: return'));
      expect(fn, contains("substringBeforeLast('#')"));
    });
  });

  group('③ 引擎不回调的机型要有 Dart 兜底', () {
    test('阅读器按页武装看门狗，超时当“读完”处理', () {
      expect(reader, contains('Timer? _autoWatchdog'));
      expect(reader, contains('void _armAutoWatchdog(String text)'));
      final fn = slice(reader, 'void _armAutoWatchdog(String text)', 'void _onAutoPageDone()');
      expect(fn, contains('_onAutoPageDone()'), reason: '超时后要接下一页，不是就地停');
      expect(fn, contains('_autoMode == null'), reason: '模式已停就不要再翻');
      // 估时按字数，给足余量，别把正常朗读掐断
      expect(fn, contains('/ 4.0 * 3'));
      expect(fn, contains('clamp(20.0, 900.0)'));
    });

    test('每页起播都重新武装；停止/离开页面时一定取消', () {
      final speak = slice(reader, 'void _autoSpeak(int page)', 'void _onAutoPageDone()');
      expect(speak, contains('ttsSpeak(text, id: id, onDone: _onAutoPageDone)'));
      expect(speak, contains('_armAutoWatchdog(text)'),
          reason: 'call 完不武装，引擎不回调时就会永远静默');
      final finish = slice(reader, 'void _finishAuto(', '/// 这一页念完了');
      expect(finish, contains('_autoWatchdog?.cancel()'));
      final dispose = slice(reader, 'void dispose() {', 'TextStyle _textStyle()');
      expect(dispose, contains('_autoWatchdog?.cancel()'));
    });

    test('看门狗不会跟 onDone 抢：onDone 接下一页时会把旧计时器换掉', () {
      // _armAutoWatchdog 第一行就是 cancel 旧的，属于「同一时刻只有一个看门狗」
      final fn = slice(reader, 'void _armAutoWatchdog(String text)', 'void _onAutoPageDone()');
      final iCancel = fn.indexOf('_autoWatchdog?.cancel()');
      final iArm = fn.indexOf('_autoWatchdog = Timer(');
      expect(iCancel, greaterThan(-1));
      expect(iArm, greaterThan(iCancel), reason: '先取消旧的再装新的');
    });
  });
}
