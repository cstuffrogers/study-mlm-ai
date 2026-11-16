// 五维能力雷达图（T041）— CustomPainter，无第三方依赖 + 渐变填充 + 生长动画
// 性能要点：把「网格 + 轴 + 文本标签」放在静态层（RepaintBoundary，只画一次，
// 文本只 layout 一次），动画层只重绘数据多边形与圆点。旧实现每帧重建 5 个
// TextPainter 并 layout，在 Web 上逐帧做字形整形，是切到分析页卡顿的主因。
import 'dart:math' as math;
import 'package:flutter/material.dart';

class RadarChart extends StatelessWidget {
  final Map<String, double> values; // 0..1
  final Map<String, String>? labels; // 维度→中文
  final double size;

  const RadarChart({super.key, required this.values, this.labels, this.size = 220});

  @override
  Widget build(BuildContext context) {
    final lbl = labels ?? const {};
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // 静态背景层（网格/轴/标签），只在依赖变化时才重绘。
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _RadarBackgroundPainter(values: values, labels: lbl),
              ),
            ),
          ),
          // 动画数据层（多边形 + 圆点），仅重绘自身。
          Positioned.fill(
            child: RepaintBoundary(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 560),
                curve: Curves.easeOutCubic,
                builder: (_, t, _) => CustomPaint(
                  painter: _RadarDataPainter(values: values, progress: t),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// —— 几何计算（纯函数，两个 painter 共用） ——
class _RadarGeo {
  final Offset center;
  final double radius;
  final List<String> keys;
  final int n;
  _RadarGeo(Size size, Map<String, double> values)
      : center = Offset(size.width / 2, size.height / 2),
        radius = math.min(size.width, size.height) / 2 - 30,
        keys = values.keys.toList(),
        n = values.length;

  Offset pointAt(int i, double r) {
    final ang = -math.pi / 2 + 2 * math.pi * i / n;
    return center + Offset(math.cos(ang) * r, math.sin(ang) * r);
  }
}

class _RadarBackgroundPainter extends CustomPainter {
  final Map<String, double> values;
  final Map<String, String> labels;
  _RadarBackgroundPainter({required this.values, required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    final g = _RadarGeo(size, values);
    if (g.n < 3) return;

    final gridPaint = Paint()
      ..color = const Color(0xFFEADCD7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // 网格环
    for (var ring = 1; ring <= 4; ring++) {
      final r = g.radius * ring / 4;
      final path = Path();
      for (var i = 0; i <= g.n; i++) {
        final p = g.pointAt(i, r);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, gridPaint);
    }
    // 轴线
    for (var i = 0; i < g.n; i++) {
      canvas.drawLine(g.center, g.pointAt(i, g.radius), gridPaint);
    }
    // 标签（仅此一次 layout）
    for (var i = 0; i < g.n; i++) {
      final p = g.pointAt(i, g.radius + 16);
      final tp = TextPainter(
        text: TextSpan(
          text: labels[g.keys[i]] ?? g.keys[i],
          style: const TextStyle(fontSize: 10.5, color: Color(0xFF3D2F2C), fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarBackgroundPainter old) =>
      old.labels.toString() != labels.toString() ||
      old.values.keys.join(',') != values.keys.join(',');
}

class _RadarDataPainter extends CustomPainter {
  final Map<String, double> values;
  final double progress;
  _RadarDataPainter({required this.values, this.progress = 1});

  @override
  void paint(Canvas canvas, Size size) {
    final g = _RadarGeo(size, values);
    if (g.n < 3) return;

    final dataPath = Path();
    final pts = <Offset>[];
    for (var i = 0; i < g.n; i++) {
      final v = (values[g.keys[i]] ?? 0).clamp(0.0, 1.0) * progress;
      final p = g.pointAt(i, g.radius * v);
      pts.add(p);
      if (i == 0) {
        dataPath.moveTo(p.dx, p.dy);
      } else {
        dataPath.lineTo(p.dx, p.dy);
      }
    }
    dataPath.close();
    final rect = Rect.fromCircle(center: g.center, radius: g.radius);
    // 品牌红→鎏金（语义色分离后不再使用蓝紫）
    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [const Color(0xFFC8161D).withValues(alpha: 0.33), const Color(0xFFD4A017).withValues(alpha: 0.20)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    final linePaint = Paint()
      ..color = const Color(0xFFC8161D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(dataPath, fillPaint);
    canvas.drawPath(dataPath, linePaint);

    final dotPaint = Paint()..color = const Color(0xFFC8161D);
    for (final p in pts) {
      canvas.drawCircle(p, 2.6, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarDataPainter old) =>
      old.values.toString() != values.toString() || old.progress != progress;
}
