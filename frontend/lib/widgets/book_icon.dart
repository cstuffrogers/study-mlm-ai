// 书本图标（自绘）—— 比 Material 的 menu_book / auto_stories 更接近纸书，
// 且按小尺寸优化：15~18px 下靠「左右两页 + 中缝」辨识，页纹只在大尺寸才画。
//
// 之所以自绘：书卡、章节卡、目录里要用同一个「书」符号，Material 那几枚
// 要么是厚线条方块（menu_book），要么是描边太重（auto_stories_outlined），
// 在这一版偏轻薄的界面里都显得笨。这里用两页微弧的纸页 + 一条中缝，
// 形体轻，放大缩小都不糊。
import 'package:flutter/material.dart';

class BookIcon extends StatelessWidget {
  /// 图标边长（逻辑像素）
  final double size;

  /// 主色（页面色）；中缝与页纹自动取浅一档
  final Color color;

  /// 是否画页纹（细节）。小尺寸下默认关闭，避免糊成一团。
  final bool? lines;

  const BookIcon({super.key, this.size = 16, required this.color, this.lines});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BookPainter(
          color: color,
          lines: lines ?? size >= 22,
        ),
      ),
    );
  }
}

class _BookPainter extends CustomPainter {
  final Color color;
  final bool lines;

  _BookPainter({required this.color, required this.lines});

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;
    final ink = Paint()
      ..color = color
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;

    // 中缝留白（左右页之间的空隙）
    final gutter = w * 0.075;

    // —— 左页：底边平、顶边略扬，外侧圆一点，像一张被摊开的纸
    final left = Path()
      ..moveTo(w * 0.04, h * 0.24)
      ..quadraticBezierTo(w * 0.24, h * 0.16, w * 0.5 - gutter / 2, h * 0.22)
      ..lineTo(w * 0.5 - gutter / 2, h * 0.86)
      ..quadraticBezierTo(w * 0.24, h * 0.82, w * 0.04, h * 0.76)
      ..close();
    canvas.drawPath(left, ink);

    // —— 右页：镜像
    final right = Path()
      ..moveTo(w * 0.5 + gutter / 2, h * 0.22)
      ..quadraticBezierTo(w * 0.76, h * 0.16, w * 0.96, h * 0.24)
      ..lineTo(w * 0.96, h * 0.76)
      ..quadraticBezierTo(w * 0.76, h * 0.82, w * 0.5 + gutter / 2, h * 0.86)
      ..close();
    canvas.drawPath(right, ink);

    if (!lines) return;

    // 页纹：只在够大时画，否则小尺寸会糊
    final thin = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = h * 0.045
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    for (final dy in const [0.38, 0.52, 0.66]) {
      final y = h * dy;
      canvas.drawLine(Offset(w * 0.14, y - h * 0.012), Offset(w * 0.44, y + h * 0.008), thin);
      canvas.drawLine(Offset(w * 0.56, y + h * 0.008), Offset(w * 0.86, y - h * 0.012), thin);
    }
  }

  @override
  bool shouldRepaint(covariant _BookPainter old) =>
      old.color != color || old.lines != lines;
}
