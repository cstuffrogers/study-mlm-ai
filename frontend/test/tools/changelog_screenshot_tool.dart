// 「更新说明」截图工具（手动跑，不进全量测试）。
//
// 运行：flutter test test/tools/changelog_screenshot_tool.dart
// 输出：.local/changelog_shots/popup.png（启动弹框）
//       .local/changelog_shots/about_card.png（关于页的更新说明卡片）
//
// 说明：
//   · 文件名不带 _test 后缀 → `flutter test` 不会自动收集它；
//   · 本模型看不到图，用像素统计自检（ink 占比太低 = 没渲染出来）；
//   · 落盘后 exit(0)：避免页面里的动画/Ticker 让 teardown 一直等定时器。
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/src/rendering/proxy_box.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marxism_reader/config/changelog.dart';
import 'package:marxism_reader/screens/about_screen.dart';
import 'package:marxism_reader/theme/app_theme.dart';
import 'package:marxism_reader/widgets/whats_new_dialog.dart';

const _outDir = 'E:/xxmz/.local/changelog_shots';

Future<void> _writePng(ui.Image img, String path) async {
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  await File(path).writeAsBytes(data!.buffer.asUint8List());
  print('[out] $path (${data.lengthInBytes} bytes, ${img.width}x${img.height})');
}

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

String _inkStats(ByteData raw) {
  final px = raw.buffer.asUint8List();
  final hist = <int, int>{};
  for (var i = 0; i + 3 < px.length; i += 4) {
    final c = (px[i] << 16) | (px[i + 1] << 8) | px[i + 2];
    hist[c] = (hist[c] ?? 0) + 1;
  }
  final total = px.length ~/ 4;
  final sorted = hist.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final ink = total - sorted.first.value;
  return 'ink=${(ink * 100 / total).toStringAsFixed(1)}% colors=${hist.length}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('更新说明：启动弹框 + 关于页卡片', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Directory(_outDir).createSync(recursive: true);

    // —— ① 启动弹框（跨版本：把 1.4.19/1.4.20 两版一起展示）——
    tester.view.physicalSize = const Size(420, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final popupKey = GlobalKey();
    // RepaintBoundary 要包住整个 MaterialApp：弹框画在 App 自己的 Overlay 里，
    // 只包住 home 的 Scaffold 会截到一片空白（ink=0%）。
    await tester.pumpWidget(RepaintBoundary(
      key: popupKey,
      child: MaterialApp(
        theme: AppTheme.build(),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    ));
    final ctx = tester.element(find.byType(Scaffold));
    final entries = changelogSince('1.4.18');
    print('[diag] popup entries=${entries.map((e) => e.version).toList()}');
    showWhatsNewDialog(ctx, entries: entries);
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final b = popupKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 2);
      print('[diag] popup ${_inkStats((await img.toByteData(format: ui.ImageByteFormat.rawRgba))!)}');
      await _writePng(img, '$_outDir/popup.png');
    });

    // —— ② 关于页里的「更新说明」卡片 ——
    tester.view.physicalSize = const Size(420, 3000);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: const RepaintBoundary(child: AboutScreen()),
    ));
    await tester.pumpAndSettle();

    final cardRect = tester.getRect(find.text('更新说明').first);
    // 逻辑坐标 → 设备像素（pixelRatio=1，抓图时再 ×2）
    final top = (cardRect.top - 90).clamp(0.0, 2900.0);
    print('[diag] card top=${cardRect.top}');

    await tester.runAsync(() async {
      final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
          find.byType(RepaintBoundary).first);
      final full = await boundary.toImage(pixelRatio: 2);
      print('[diag] about full=${full.width}x${full.height} '
          '${_inkStats((await full.toByteData(format: ui.ImageByteFormat.rawRgba))!)}');
      final part = await _crop(full, (top * 2).round(), 1180);
      print('[diag] card ${_inkStats((await part.toByteData(format: ui.ImageByteFormat.rawRgba))!)}');
      await _writePng(part, '$_outDir/about_card.png');
    });

    exit(0);
  });
}
