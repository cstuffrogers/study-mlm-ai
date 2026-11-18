// D148 门禁：语音/安装包这类**临时产物**不许攒着。
//
// 用户实报：「tts 生成的音频不是永久保存的吧，要及时清理」。
// 三处会攒东西，逐个钉住：
//  ① 后端响应头若给 max-age=86400 → 浏览器把每段 MP3 落盘存一天，
//     读一本书能堆几十 MB，而且永远不会自己清；
//  ② Web 端只 pause() 不释放 → 预热的元素继续在后台下载、解码缓冲不还，
//     声停了东西还占着；
//  ③ 应用内更新下载的 APK 70+MB，装完不能立刻删（安装器异步读），
//     但也不能永远躺在临时目录里 —— 下次启动清掉。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:marxism_reader/services/app_update.dart';
import 'package:marxism_reader/services/cache_sweep.dart';

String readFile(String p) => File(p).readAsStringSync();

String slice(String src, String from, String to) {
  final i = src.indexOf(from);
  expect(i, greaterThan(-1), reason: '找不到锚点：$from');
  final j = src.indexOf(to, i);
  return j < 0 ? src.substring(i) : src.substring(i, j);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('① 后端不许让浏览器把语音落盘', () {
    final route = readFile('../backend/api/tts_routes.py');

    test('两个 speak 响应（GET/POST）都是 no-store', () {
      final headers = RegExp(r'"Cache-Control":\s*"([^"]+)"')
          .allMatches(route)
          .map((m) => m.group(1)!)
          .toList();
      expect(headers.length, 2, reason: 'GET 和 POST 都要返回语音，头都要写');
      for (final h in headers) {
        expect(h.toLowerCase(), contains('no-store'));
        expect(h, isNot(contains('86400')), reason: '一天的有效期就是把音频存一天');
      }
    });

    test('后端语音缓存有字节上限（只限条数会堆到几百 MB）', () {
      final svc = readFile('../backend/services/tts_service.py');
      expect(svc, contains('_CACHE_MAX_BYTES'));
      final put = slice(svc, 'def _cache_put(', 'def _synth_async(');
      expect(put, contains('_CACHE_MAX_BYTES'),
          reason: '淘汰逻辑必须看总字节，不能只看 len(_cache)');
      expect(put, contains('_cache_bytes_total -= len(dropped)'));
      // 替换同名字段时不许重复累计
      expect(put, contains('old = _cache.pop(key, None)'));
    });
  });

  group('② Web 端点掉朗读后要真的还内存/停下载', () {
    final web = readFile('lib/services/tts_web.dart');

    test('释放动作是 pause + 断开 src + load（只 pause 会继续下载）', () {
      final rel = slice(web, 'void _release(html.AudioElement? a)', 'void _stopAudio()');
      expect(rel, contains('.pause()'));
      expect(rel, contains("removeAttribute('src')"),
          reason: '断开 src 才会中止请求');
      expect(rel, contains('.load()'), reason: 'load() 才会丢掉已下载/解码的数据');
    });

    test('声音停止（ttsStop）与正常收尾都走 _release', () {
      final stop = slice(web, 'void ttsStop() {', 'void ttsPrefetch(');
      expect(stop, contains('_release(a)'), reason: '预热缓存里的元素要逐个释放');
      expect(stop, isNot(contains('a.pause();\n  }')), reason: '不许退回只 pause');

      final stopAudio = slice(web, 'void _stopAudio()', 'void _playNeuralUrl(');
      expect(stopAudio, contains('_release(a)'),
          reason: '换段/换页时上一段也要释放，否则一段一个 <audio> 全留着');
    });

    test('预热缓存淘汰时也释放，不能只是从 map 里删掉', () {
      final pre = slice(web, 'void ttsPrefetch(', 'List<String> _splitForTts(');
      expect(pre, contains('_release(_warm.remove(key))'));
      expect(pre, contains('_warm.length > 3'), reason: '上限 3 条，多读几页不许积');
    });
  });

  group('③ 更新安装包不许留在临时目录里', () {
    test('装完不立刻删（安装器异步读），改成下次启动清', () {
      final src = readFile('lib/services/app_update.dart');
      expect(src, contains('Future<int> cleanDownloadedApks('));
      // 只清自己下载的包，不动临时目录里别人的文件
      final fn = slice(src, 'Future<int> cleanDownloadedApks(', '/// 原生安装通道');
      expect(fn, contains("startsWith('xxmz-')"));
      expect(fn, contains("endsWith('.apk')"));
    });

    test('启动后首帧执行清理', () {
      final main = readFile('lib/main.dart');
      expect(main, contains('cleanDownloadedApks()'));
      expect(main, contains('addPostFrameCallback'), reason: '不能占冷启动关键路径');
    });

    test('只删 xxmz-*.apk，别人的文件和别的后缀都不碰', () async {
      final dir = await Directory.systemTemp.createTemp('d148_apk_');
      try {
        final old = File('${dir.path}/xxmz-1.4.0-android-universal.apk')
          ..writeAsBytesSync(List.filled(16, 1));
        final cur = File('${dir.path}/xxmz-1.5.0.apk')
          ..writeAsBytesSync(List.filled(16, 2));
        final otherApk = File('${dir.path}/微信.apk')
          ..writeAsBytesSync(List.filled(16, 3));
        final txt = File('${dir.path}/xxmz-notes.txt')..writeAsStringSync('x');
        final sub = Directory('${dir.path}/xxmz-sub')..createSync();

        final removed = await cleanDownloadedApks(dir: dir);

        expect(removed, 2);
        expect(old.existsSync(), isFalse);
        expect(cur.existsSync(), isFalse);
        expect(otherApk.existsSync(), isTrue, reason: '不是自己下的包不能删');
        expect(txt.existsSync(), isTrue);
        expect(sub.existsSync(), isTrue);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('目录不存在 / 目录里没东西都不报错', () async {
      final missing = Directory('${Directory.systemTemp.path}/d148_不存在_${DateTime.now().microsecondsSinceEpoch}');
      expect(await cleanDownloadedApks(dir: missing), 0);

      final empty = await Directory.systemTemp.createTemp('d148_empty_');
      try {
        expect(await cleanDownloadedApks(dir: empty), 0);
      } finally {
        await empty.delete(recursive: true);
      }
    });
  });

  group('④ 安卓端 App 自己不写音频文件（写清楚，别乱删）', () {
    final kt = readFile('android/app/src/main/kotlin/com/weiwu/marxism_reader/MainActivity.kt');
    final native = readFile('lib/services/tts_native.dart');

    test('原生朗读只走 TextToSpeech.speak，没有 synthesizeToFile/文件落盘', () {
      expect(kt, contains('engine.speak('));
      expect(kt, isNot(contains('synthesizeToFile')),
          reason: '一旦落盘就必须配套清理；现在的口径是不落盘');
      expect(kt, isNot(contains('synthesizeToFileAsync')));
      expect(kt, isNot(contains('cacheDir')));
      expect(kt, isNot(contains('FileOutputStream')));
    });

    test('Dart 侧朗读实现不碰文件系统', () {
      expect(native, isNot(contains('File(')), reason: '朗读别写盘，只走通道');
      expect(native, isNot(contains('openWrite(')));
      expect(native, isNot(contains('getTemporaryDirectory')));
    });

    test('停止朗读要把引擎停掉（不然系统引擎还在缓冲后面几段）', () {
      expect(native, contains("_ch.invokeMethod<void>('stop')"));
      expect(kt, contains('engine.stop()'));
    });
  });

  group('⑤ 缓存目录里的残留音频：启动自动清 + 设置页可手清', () {
    test('启动后首帧扫一遍音频缓存', () {
      final main = readFile('lib/main.dart');
      expect(main, contains('cleanTempAudio()'));
    });

    test('语音包设置页有「立即清理朗读缓存」，点了先停声再清', () {
      final page = readFile('lib/screens/tts_settings_screen.dart');
      expect(page, contains('立即清理朗读缓存'));
      final fn = slice(page, 'Future<void> _cleanAudio()', 'Widget _previewButton()');
      expect(fn, contains('ttsStop()'));
      expect(fn, contains('cleanTempAudio('));
      expect(fn, contains('olderThan: Duration.zero'), reason: '手清要清干净，不受一小时门槛限制');
    });

    test('只删音频后缀，且只删「一小时没动过」的', () async {
      final dir = await Directory.systemTemp.createTemp('d148_audio_');
      try {
        final now = DateTime.now();
        final oldMp3 = File('${dir.path}/chunk-old.mp3')..writeAsBytesSync(List.filled(2048, 1));
        oldMp3.setLastModifiedSync(now.subtract(const Duration(hours: 3)));
        final oldWav = File('${dir.path}/page.wav')..writeAsBytesSync(List.filled(1024, 2));
        oldWav.setLastModifiedSync(now.subtract(const Duration(hours: 2)));
        final fresh = File('${dir.path}/now.mp3')..writeAsBytesSync(List.filled(512, 3));
        final other = File('${dir.path}/xxmz-1.4.2.apk')..writeAsBytesSync(List.filled(64, 4));
        other.setLastModifiedSync(now.subtract(const Duration(hours: 5)));
        final note = File('${dir.path}/notes.txt')..writeAsStringSync('keep');
        note.setLastModifiedSync(now.subtract(const Duration(hours: 9)));
        final sub = Directory('${dir.path}/sub')..createSync();
        final nested = File('${sub.path}/deep.mp3')..writeAsBytesSync(List.filled(32, 5));

        final r = await cleanTempAudio(dir: dir, now: now);

        expect(r.files, 2, reason: '只删两个过期音频');
        expect(r.bytes, 3072);
        expect(oldMp3.existsSync(), isFalse);
        expect(oldWav.existsSync(), isFalse);
        expect(fresh.existsSync(), isTrue, reason: '刚写进来的可能正在用，不能动');
        expect(other.existsSync(), isTrue, reason: 'APK 由另一条清理负责，别抢');
        expect(note.existsSync(), isTrue);
        expect(nested.existsSync(), isTrue, reason: '不递归，别把别处的文件删了');
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('手清（olderThan 为零）把刚生成的也清掉', () async {
      final dir = await Directory.systemTemp.createTemp('d148_audio_now_');
      try {
        final f = File('${dir.path}/just-made.m4a')..writeAsBytesSync(List.filled(4096, 7));
        final r = await cleanTempAudio(dir: dir, olderThan: Duration.zero);
        expect(r.files, 1);
        expect(r.sizeLabel, '4 KB');
        expect(f.existsSync(), isFalse);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('空目录 / 不存在的目录都返回 0，不抛异常', () async {
      final empty = await Directory.systemTemp.createTemp('d148_audio_empty_');
      try {
        final r = await cleanTempAudio(dir: empty);
        expect(r.isEmpty, isTrue);
        expect(r.sizeLabel, '0 B');
      } finally {
        await empty.delete(recursive: true);
      }
      final missing = Directory('${Directory.systemTemp.path}/d148_no_${DateTime.now().microsecondsSinceEpoch}');
      expect((await cleanTempAudio(dir: missing)).files, 0);
    });

    test('音频后缀清单里没有奇怪的东西', () {
      expect(kAudioExts.every((e) => e.startsWith('.') && e.length <= 6), isTrue);
      expect(kAudioExts.contains('.mp3'), isTrue);
      expect(kAudioExts.contains('.apk'), isFalse);
    });
  });
}
