// D112 门禁：书本图标自绘（不依赖 Material 图标字体，避免 tree-shake 后变豆腐块）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/widgets/book_icon.dart';

void main() {
  testWidgets('BookIcon 渲染为自绘 CustomPaint，尺寸受控', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(child: BookIcon(size: 17, color: Color(0xFFC8161D))),
      ),
    ));
    final size = t.getSize(find.byType(BookIcon));
    expect(size.width, 17);
    expect(size.height, 17);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
