// 勋章页截图工具（手动跑，不进全量测试）。
//
// 运行：flutter test test/tools/badge_screenshot_tool.dart
// 输出：.local/badge_shots/full.png + page1..pageN.png（420 逻辑宽分屏切片）
//
// 说明：
//   · 文件名不带 _test 后缀 → `flutter test` 不会自动收集它。
//   · 图片落盘后直接 exit(0)：BadgeScreen 有无限动画 Ticker，正常 teardown
//     会一直等定时器（实测挂 3 分钟仍未结束）。
//   · 只能靠像素统计判断是否空白（本模型看不到图）：
//     nonBackground 占比 < 5% 基本等于没渲染出来。
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/src/rendering/proxy_box.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'package:marxism_reader/screens/badge_screen.dart';

const _outDir = 'E:/xxmz/.local/badge_shots';
const _viewW = 420.0;
const _viewH = 4200.0;

/// 预置为「已获得」的勋章（其余留未获得，截图里两种状态都能看到）。
const _earned = <String>{
  'mastery_1',
  'mastery_5',
  'mastery_10',
  'mastery_25',
  'journey_5',
  'journey_15',
  'milestone_1',
  'milestone_5',
  'quiz_10',
  'quiz_50',
  'quiz_100',
  'route_1',
  'streak_7',
  'dialogue_10',
};

Future<void> _writePng(ui.Image img, String path) async {
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  await File(path).writeAsBytes(data!.buffer.asUint8List());
  print('[out] $path (${data.lengthInBytes} bytes, ${img.width}x${img.height})');
}

/// 从一张大图裁出 [top, top+height) 竖条。
Future<ui.Image> _crop(ui.Image src, int top, int height) {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawImageRect(
    src,
    Rect.fromLTWH(0, top.toDouble(), src.width.toDouble(), height.toDouble()),
    Rect.fromLTWH(0, 0, src.width.toDouble(), height.toDouble()),
    Paint(),
  );
  return rec.endRecording().toImage(src.width, height);
}

/// 统计非背景像素占比，用来判断截的不是空白页。
String _inkStats(ui.Image img, ByteData raw) {
  final px = raw.buffer.asUint8List();
  final hist = <int, int>{};
  for (var i = 0; i + 3 < px.length; i += 4) {
    final c = (px[i] << 16) | (px[i + 1] << 8) | px[i + 2];
    hist[c] = (hist[c] ?? 0) + 1;
  }
  final total = px.length ~/ 4;
  final sorted = hist.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final ink = total - sorted.first.value;
  final top = sorted
      .take(3)
      .map((e) => '#${e.key.toRadixString(16).padLeft(6, '0')}='
          '${(e.value * 100 / total).toStringAsFixed(1)}%')
      .join(' ');
  return 'ink=${(ink * 100 / total).toStringAsFixed(1)}% '
      'colors=${hist.length} top: $top';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('勋章页截图（混合已获得/未获得）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.ensure();
    // 离线元数据是真实 IO，fake async 下不会自己完成，必须 runAsync 预加载；
    // 否则 badge_screen._load() 永远停在加载态，截出来只有顶栏。
    await tester.runAsync(() async {
      await OfflineContent.ensureMeta();
    });

    final now = DateTime.now().toUtc().toIso8601String();
    LocalDb.badges.clear();
    for (final id in _earned) {
      LocalDb.badges[id] = <String, dynamic>{
        'award_id': id,
        'badge_id': id,
        'awarded_at': now,
        'source_event': 'screenshot',
        'read_flag': true, // 已读 → 不弹开箱动画
      };
    }

    tester.view.physicalSize = const Size(_viewW, _viewH);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(key: key, child: const BadgeScreen()),
    ));
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final full = await boundary.toImage(pixelRatio: 2);
    print('[diag] full=${full.width}x${full.height} '
        '${_inkStats(full, (await full.toByteData(format: ui.ImageByteFormat.rawRgba))!)}');

    Directory(_outDir).createSync(recursive: true);
    const sliceH = 1400; // 设备像素；840x1400 ≈ 手机一屏的比例

    await tester.runAsync(() async {
      await _writePng(full, '$_outDir/full.png');
      final pages = (full.height / sliceH).ceil();
      for (var p = 0; p < pages; p++) {
        final top = p * sliceH;
        final h = (full.height - top).clamp(0, sliceH);
        if (h <= 8) break;
        final part = await _crop(full, top, h);
        await _writePng(part, '$_outDir/page${p + 1}.png');
        part.dispose();
      }
    });

    full.dispose();
    exit(0);
  });
}
