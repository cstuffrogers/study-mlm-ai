// 视觉快照：把自绘书本图标渲成 PNG，便于人工比对形态。
// 本机跑 `flutter test --update-goldens test/d112_book_visual_test.dart` 产出。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/theme/app_theme.dart';
import 'package:marxism_reader/widgets/book_icon.dart';

void main() {
  testWidgets('golden: BookIcon 放大 6 倍', (t) async {
    await t.binding.setSurfaceSize(const Size(240, 240));
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Transform.scale(
            scale: 6,
            child: const BookIcon(size: 20, color: AppColors.brand, lines: true),
          ),
        ),
      ),
    ));
    await expectLater(
      find.byType(Transform).first,
      matchesGoldenFile('goldens/book_icon.png'),
    );
  });
}
