// 可复运动效组件 — 入场过渡 / 渐变卡 / 动画进度环 / 动画条形 / 渐变头图 / 光斑背景 / 数字滚动 / 按压缩放
// 全部无第三方依赖，仅用 Flutter 内建动画原语。
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 入场动画：淡入 + 自下向上浮起。destinations 在树中始终存在（FadeTransition 不移除子树），
/// 因此测试里的 find.text 不受影响。
class AnimatedEntrance extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final double offsetY;
  final Duration duration;
  const AnimatedEntrance({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.offsetY = 14,
    this.duration = const Duration(milliseconds: 300),
  });

  @override
  State<AnimatedEntrance> createState() => _AnimatedEntranceState();
}

class _AnimatedEntranceState extends State<AnimatedEntrance>
    with SingleTickerProviderStateMixin {
  // 错峰延迟封顶：避免长列表尾部按 (index*step) 累积出 1s 以上的“空白等待”，
  // 既拖慢首屏观感，也让动画控制器堆叠更久。180ms 足够形成递次感。
  static const int _maxDelayMs = 180;
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    final delay = widget.delayMs.clamp(0, _maxDelayMs);
    final total = delay + widget.duration.inMilliseconds;
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: total),
    );
    final begin = total == 0 ? 0.0 : delay / total;
    final curve = CurvedAnimation(
      parent: _c,
      curve: Interval(begin.clamp(0.0, 1.0), 1.0, curve: Curves.easeOutCubic),
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(curve);
    _slide = Tween<Offset>(
      begin: Offset(0, widget.offsetY),
      end: Offset.zero,
    ).animate(curve);
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary：入场动画只重绘自身，不连累列表其余部分。
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: widget.child),
      ),
    );
  }
}

/// 渐变卡片：柔和投影 + 可选渐变描边，悬停/按压有轻微上浮。
class GradientCard extends StatelessWidget {
  final Widget child;
  final Gradient gradient;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double radius;
  final bool border;

  const GradientCard({
    super.key,
    required this.child,
    required this.gradient,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.radius = AppRadius.card,
    this.border = false,
  });

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: border
            ? Border.all(color: Colors.white.withValues(alpha: 0.35))
            : null,
        boxShadow: AppShadows.soft,
      ),
      // 右侧人物像若高于文字内容，默认 clipBehavior 会把顶部裁掉；
      // 红卡本身不裁剪子级，让整张图完整落在红色渐变区域内。
      clipBehavior: Clip.none,
      child: child,
    );
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: onTap == null
          ? body
          : _Pressable(onTap: onTap!, radius: radius, child: body),
    );
  }
}

/// 按压缩放包装（交互反馈）。
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double radius;
  const _Pressable({
    required this.child,
    required this.onTap,
    required this.radius,
  });

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// 动画进度环 — 从 0 增长到 [value]（0..1），中心可放内容。
class AnimatedProgressRing extends StatelessWidget {
  final double value; // 0..1
  final double size;
  final double strokeWidth;
  final Color color;
  final Color trackColor;
  final Widget? center;
  final Duration duration;

  const AnimatedProgressRing({
    super.key,
    required this.value,
    this.size = 88,
    this.strokeWidth = 9,
    this.color = AppColors.brand,
    this.trackColor = AppColors.line,
    this.center,
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: v,
                strokeWidth: strokeWidth,
                strokeCap: StrokeCap.round,
                backgroundColor: trackColor,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            ?center,
          ],
        ),
      ),
    );
  }
}

/// 动画横向进度条 — 从 0 增长到 [value]。
class AnimatedBar extends StatelessWidget {
  final double value; // 0..1
  final double height;
  final Color color;
  final Color trackColor;
  final Duration duration;

  const AnimatedBar({
    super.key,
    required this.value,
    this.height = 8,
    this.color = AppColors.brand,
    this.trackColor = AppColors.line,
    this.duration = const Duration(milliseconds: 750),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          backgroundColor: trackColor,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    );
  }
}

/// 数字滚动（用于分数/百分比）。
class CountUp extends StatelessWidget {
  final num value;
  final int decimals;
  final String prefix;
  final String suffix;
  final TextStyle? style;
  final Duration duration;

  const CountUp({
    super.key,
    required this.value,
    this.decimals = 0,
    this.prefix = '',
    this.suffix = '',
    this.style,
    this.duration = const Duration(milliseconds: 800),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, _) =>
          Text('$prefix${v.toStringAsFixed(decimals)}$suffix', style: style),
    );
  }
}

const TextStyle _titleStyle = TextStyle(
  color: Colors.white,
  fontSize: 24,
  fontWeight: FontWeight.w800,
  letterSpacing: -0.4,
);
final TextStyle _subtitleStyle = TextStyle(
  color: Colors.white.withValues(alpha: 0.82),
  fontSize: 13,
);

/// 按当前 textScaler 测量单行文本高度（与真实渲染同一套样式，避免估算偏差）。
double _measureText(BuildContext context, String text, TextStyle style,
    double maxWidth,
    {int maxLines = 1}) {
  // Text 的 style 是 inherit:true 的：实际行高/字距还要叠一层 DefaultTextStyle
  // （AppTheme 里 bodyMedium 的 height:1.5），测量必须同样叠加，否则会低估。
  final merged = DefaultTextStyle.of(context).style.merge(style);
  final tp = TextPainter(
    text: TextSpan(text: text, style: merged),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: maxLines,
  )..layout(maxWidth: maxWidth);
  return tp.height;
}

/// 渐变头图 — 深蓝→靛紫渐变 + 漂浮光斑，白色标题与副标题。
class GradientHeader extends StatelessWidget {
  final String title;

  /// 自定义标题组件（给了就替代 [title]，用于首页那种分行 + 自带样式的品牌标题）。
  ///
  /// 为什么不直接让调用方传 Widget 到 [title]：这里的头部高度是按文本**实测**出来的
  /// （见下方 _measureText），换成任意 Widget 就量不出高度、窄屏会溢出。
  /// 所以由调用方一并给出 [titleHeight]（自己也用同一套样式量好）。
  final Widget? titleWidget;

  /// 自定义标题在**未缩放**状态下占的高度（px）。给了 [titleWidget] 就必须给。
  /// 实际占用 = titleHeight × 当前 textScaler 的纵向倍数。
  final double? titleHeight;

  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final double height;

  /// 右侧装饰画（如首页红色顶部的红白人物像），不响应点击。
  final Widget? art;

  /// 装饰画的**实际宽度**（px）。给了就按它预留右侧空间；不给退回旧常量。
  /// 必须由调用方给：`Widget` 本身在布局前拿不到尺寸，用常量猜就会把标题压在图上。
  final double? artWidth;

  const GradientHeader({
    super.key,
    required this.title,
    this.titleWidget,
    this.titleHeight,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.height = 128,
    this.art,
    this.artWidth,
  });

  @override
  Widget build(BuildContext context) {
    // 首页红白图高 116，固定 128 的头部只剩 12px 余量；
    // 安全区/装饰光斑叠加时容易让顶部看起来被压住，这里给足完整高度。
    final double baseHeight = art == null
        ? height
        : (height < 144 ? 144.0 : height);
    final double topInset = MediaQuery.of(context).padding.top;
    // 右侧留出人物像的位置：按 artWidth 真实宽度算，再加上 12 的呼吸间隙。
    // 旧实现写死 104，而首页那张横幅图 116 高时宽 177 → 大标题被压掉一截。
    final double reserveRight =
        art == null ? 8 : ((artWidth ?? 104) + 12).clamp(8.0, 240.0);
    final EdgeInsets padding =
        EdgeInsets.fromLTRB(16, 8, reserveRight, 16);

    // 头部是按内容走的，不能钉死高度：
    //   · 内部 SafeArea 让出状态栏后可用高度只剩 height - inset，标题会被推出去；
    //   · 全局字号放大（或系统无障碍字号）后，标题/副标题/图标行比固定高度还高，
    //     RenderFlex 就会向下溢出，标题的下半截被下面的列表/卡片遮住
    //     （「选择学习路线」「学习分析」的历史问题）。
    // 因此按真实文本高度算：内容高度 + 状态栏，且不小于基准高度。
    final double textWidth = (MediaQuery.sizeOf(context).width -
            padding.left -
            padding.right)
        .clamp(80.0, double.infinity);
    // 图标行取 Material 最小点击区（48）与标题行高，保证不被行内按钮撑破。
    final double rowHeight = (leading != null || actions.isNotEmpty) ? 48.0 : 0.0;
    // 标题允许折两行：窄屏 + 头像占位后单行放不下 9 个字，硬压成省略号更难看。
    // 自定义标题走调用方给的基准高度，同样按 textScaler 缩放，避免大字号溢出。
    final double scaler = MediaQuery.textScalerOf(context).scale(1.0);
    final double usedTitleHeight = titleWidget != null
        ? (titleHeight ?? 40.0) * (scaler <= 1.0 ? 1.0 : scaler)
        : _measureText(context, title, _titleStyle, textWidth, maxLines: 2);
    final double subtitleHeight = subtitle == null
        ? 0.0
        : 4.0 + _measureText(context, subtitle!, _subtitleStyle, textWidth);
    final double needed =
        padding.vertical + rowHeight + usedTitleHeight + subtitleHeight;
    final double headerHeight =
        (baseHeight > needed ? baseHeight : needed) + topInset;
    // RepaintBoundary 默认会裁剪溢出子级；红白图需完整显示，不能用它包住头部。
    return Container(
      height: headerHeight,
      decoration: const BoxDecoration(gradient: AppColors.heroGradient),
      clipBehavior: Clip.none,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(child: _HeaderDecor()),
          SafeArea(
            bottom: false,
            child: Padding(
              // 右侧留出人物像的位置，避免标题/副标题压在像上
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [?leading, const Spacer(), ...actions]),
                  const Spacer(),
                  if (titleWidget != null)
                    titleWidget!
                  else
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _titleStyle,
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _subtitleStyle,
                    ),
                  ],
                ],
              ),
            ),
          ),
          // 人物图最后绘制，完整叠在红底上，不被文字层遮挡。
          if (art != null)
            Positioned(right: 4, bottom: 0, child: IgnorePointer(child: art!)),
        ],
      ),
    );
  }
}

/// 静态头图装饰光斑（不帧动画）。
/// 旧实现用 Infinite AnimationController 每帧重排三个光斑——每个页面都常驻，
/// 在 CanvasKit 下持续触发整屏重绘，是“切换/滚动发涩”的主因之一。
/// 现在改为静态定位：视觉效果一致，但零常驻帧开销。
class _HeaderDecor extends StatelessWidget {
  const _HeaderDecor();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 20,
          top: -20,
          child: _blob(120, Colors.white.withValues(alpha: 0.10)),
        ),
        Positioned(
          right: -10,
          bottom: -30,
          child: _blob(150, AppColors.ink.withValues(alpha: 0.16)),
        ),
        Positioned(
          right: 90,
          top: 10,
          child: _blob(70, const Color(0xFFF3D9A0).withValues(alpha: 0.16)),
        ),
      ],
    );
  }

  Widget _blob(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// 轻度页面背景（渐变 + 极简网格微光），放在 Scaffold body 底层。
class AuroraBackground extends StatelessWidget {
  final Widget child;
  const AuroraBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.pageGradient),
      child: child,
    );
  }
}

/// 通用淡入分段：便于列表中按 index 错峰入场。
class StaggeredList extends StatelessWidget {
  final int count;
  final Widget Function(int index) builder;
  final int stepMs;
  final EdgeInsetsGeometry padding;

  const StaggeredList({
    super.key,
    required this.count,
    required this.builder,
    this.stepMs = 55,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: padding,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedEntrance(delayMs: i * stepMs, child: builder(i)),
      ],
    );
  }
}
