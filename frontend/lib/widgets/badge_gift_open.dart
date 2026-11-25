// 勋章达成开箱动画（spec 001 / D168 重做）
//
// 用户实报：旧版是「礼物盒掀盖 + 一枚勋章」，而且一次拿到多枚时只弹第一枚
// （`badge_screen` 只传 `unseenAwards.first`）。要求改成：
//   ① 中间爆开的烟花；
//   ② 中间「从无到有」弹出**已获得的勋章图片**（不是礼物盒）；
//   ③ 一次拿到几枚就显示几枚。
//
// 现在的时序（总长 2.4s，之后停在展示态等用户点「收下勋章」）：
//   0.00–0.55s  三簇烟花从中心炸开（扩散圆环 + 粒子 + 余辉淡出）
//   0.22s 起    勋章逐个从 scale 0 弹性弹出（elasticOut 过冲，每枚错开 60ms）
//   0.62–0.90s  标题/描述淡入
//   1    完成   底部出现「收下勋章」
//
// 兜底：`awards` 为空时只播烟花、显示一句兜底文案，不崩；控制器异常不影响主流程。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 一枚已获得的勋章（从 `/api/badges/unseen` 的 award 记录映射而来）。
class BadgeAward {
  const BadgeAward({
    required this.name,
    required this.iconKey,
    this.description = '',
    this.awardId = '',
  });

  final String name;
  final String iconKey;
  final String description;
  final String awardId;

  factory BadgeAward.fromMap(Map<String, dynamic> m) => BadgeAward(
        name: '${m['name'] ?? ''}'.trim(),
        iconKey: '${m['icon_key'] ?? 'star'}'.trim(),
        description: '${m['description'] ?? ''}'.trim(),
        awardId: '${m['award_id'] ?? ''}'.trim(),
      );
}

/// 勋章达成动画：中间爆开烟花 → 勋章从无到有弹出 → 展示名称。
///
/// [awards] 一次拿到的全部勋章（几枚就画几枚）；[onClose] 点关闭时回调。
class BadgeGiftOpen extends StatefulWidget {
  const BadgeGiftOpen({
    super.key,
    required this.awards,
    required this.onClose,
    this.duration = const Duration(milliseconds: 2400),
  });

  final List<BadgeAward> awards;
  final VoidCallback onClose;
  final Duration duration;

  /// 勋章图标键 -> 图标（29 枚勋章各配唯一图标，均动感可辨）
  static IconData iconFor(String key) {
    const map = {
      // 知识掌握
      'seed': Icons.spa_rounded,
      'sprout': Icons.grass_rounded,
      'book': Icons.menu_book_rounded,
      'expert': Icons.workspace_premium_rounded,
      'sage': Icons.auto_awesome_rounded,
      'master': Icons.emoji_events_rounded,
      // 贯通
      'depart': Icons.directions_run_rounded,
      'navigate': Icons.navigation_rounded,
      'route_way': Icons.route_rounded,
      'travel': Icons.travel_explore_rounded,
      // 里程碑
      'flag_first': Icons.flag_outlined,
      'explore': Icons.explore_rounded,
      'bolt': Icons.bolt_rounded,
      'guard': Icons.security_rounded,
      // 答题
      'quiz': Icons.quiz_rounded,
      'touch': Icons.touch_app_rounded,
      'check': Icons.check_circle_rounded,
      'psyche': Icons.psychology_rounded,
      'tune': Icons.tune_rounded,
      // 路线
      'map_one': Icons.map_rounded,
      'map_three': Icons.map_outlined,
      'globe': Icons.language_rounded,
      'all_path': Icons.all_inbox_rounded,
      // 连续学习
      'fire7': Icons.local_fire_department_rounded,
      'flame': Icons.speed_rounded,
      'timer': Icons.hourglass_top_rounded,
      'love': Icons.favorite_rounded,
      // 对话
      'chat': Icons.chat_rounded,
      'forum': Icons.forum_rounded,
      // 兼容旧分类键
      'knowledge': Icons.menu_book_rounded,
      'journey': Icons.route_rounded,
      'milestone': Icons.flag_rounded,
      'route': Icons.map_rounded,
      'streak': Icons.local_fire_department_rounded,
      'dialogue': Icons.chat_rounded,
    };
    return map[key] ?? Icons.star_rounded;
  }

  @override
  State<BadgeGiftOpen> createState() => _BadgeGiftOpenState();
}

/// 一簇烟花（时间/位置/半径/配色/粒子角度一次算好，避免每帧重算导致抖动）。
class _Burst {
  _Burst({
    required this.center,
    required this.delay,
    required this.span,
    required this.radius,
    required this.color,
    required this.count,
  })  : angles = List<double>.generate(
            count, (i) => i * 2 * math.pi / count + math.sin(i * 12.9898) * 0.35),
        speeds = List<double>.generate(count, (i) => 0.72 + (math.sin(i * 7.233) + 1) / 2 * 0.5);

  final Offset center;
  final double delay; // 控制器进度 0..1 里的起点
  final double span; // 持续时间（进度比例）
  final double radius;
  final Color color;
  final int count;
  final List<double> angles;
  final List<double> speeds;
}

class _BadgeGiftOpenState extends State<BadgeGiftOpen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<Animation<double>> _pops; // 每枚勋章的弹出进度
  late final Animation<double> _textFade;
  late final List<_Burst> _bursts;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration);
    final n = widget.awards.isEmpty ? 1 : widget.awards.length;
    _pops = List<Animation<double>>.generate(n, (i) {
      final start = (0.22 + i * 0.055).clamp(0.0, 0.62).toDouble();
      final end = (start + 0.34).clamp(start + 0.05, 1.0).toDouble();
      return Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
        parent: _c,
        curve: Interval(start, end, curve: Curves.elasticOut),
      ));
    });
    _textFade = CurvedAnimation(parent: _c, curve: const Interval(0.62, 0.9, curve: Curves.easeOut));
    _bursts = [
      _Burst(
        center: Offset.zero,
        delay: 0.0,
        span: 0.42,
        radius: 150,
        color: AppColors.gold,
        count: 18,
      ),
      _Burst(
        center: const Offset(-58, -46),
        delay: 0.12,
        span: 0.36,
        radius: 96,
        color: const Color(0xFFE4636A),
        count: 14,
      ),
      _Burst(
        center: const Offset(62, -30),
        delay: 0.2,
        span: 0.34,
        radius: 88,
        color: AppColors.goldSoft,
        count: 12,
      ),
    ];
    // 动画跑完要重建一次：底部「收下勋章」按钮与整屏可点关闭都看 `_c.status`。
    _c.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) setState(() {});
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 勋章直径：一次拿得越多越小，保证一屏放得下。
  double get _medalSize {
    final n = widget.awards.length;
    if (n <= 1) return 118;
    if (n <= 4) return 92;
    if (n <= 8) return 74;
    if (n <= 12) return 62;
    return 54;
  }

  bool get _done => _c.status == AnimationStatus.completed;

  @override
  Widget build(BuildContext context) {
    final awards = widget.awards;
    final title = awards.isEmpty
        ? '恭喜达成'
        : awards.length == 1
            ? awards.single.name
            : '一次获得 ${awards.length} 枚勋章';
    return GestureDetector(
      onTap: _done ? widget.onClose : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.black.withValues(alpha: 0.78),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // —— 烟花 + 勋章：同一个方形舞台，烟花在中心炸开，勋章在中心弹出 ——
            SizedBox(
              width: 340,
              height: 330,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _c,
                        builder: (_, _) => CustomPaint(
                          painter: _FireworksPainter(progress: _c.value, bursts: _bursts),
                        ),
                      ),
                    ),
                  ),
                  // 爆开后的余晖：一圈金色底光，让勋章「亮」出来
                  IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (_, _) {
                        final t = ((_c.value - 0.2) / 0.4).clamp(0.0, 1.0);
                        if (t <= 0) return const SizedBox.shrink();
                        return Container(
                          width: 240 * (0.6 + t * 0.4),
                          height: 240 * (0.6 + t * 0.4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                AppColors.gold.withValues(alpha: 0.30 * t),
                                AppColors.gold.withValues(alpha: 0.10 * t),
                                const Color(0x00000000),
                              ],
                              stops: const [0.0, 0.55, 1.0],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // 勋章：一枚居中，多枚换行排开，全部从无到有弹出
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320, maxHeight: 300),
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < awards.length; i++)
                            _popped(
                              _pops[math.min(i, _pops.length - 1)],
                              _Medal(
                                iconKey: awards[i].iconKey,
                                size: _medalSize,
                                label: awards.length == 1 ? '' : awards[i].name,
                                labelSize: awards.length <= 6 ? 11 : 10,
                              ),
                            ),
                          if (awards.isEmpty) _popped(_pops.first, const _Medal(iconKey: 'star', size: 92)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // —— 名称 / 数量 / 描述 ——
            FadeTransition(
              opacity: _textFade,
              child: Column(
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: awards.length > 1 ? 20 : 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.gold,
                    ),
                  ),
                  if (awards.length == 1 && awards.single.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        awards.single.description,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFE7DCD6), fontSize: 13, height: 1.5),
                      ),
                    ),
                  ],
                  if (awards.length > 1) ...[
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        awards.map((a) => a.name).where((e) => e.isNotEmpty).join(' · '),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFE7DCD6), fontSize: 12, height: 1.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_done)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.brandDeep,
                ),
                onPressed: widget.onClose,
                icon: const Icon(Icons.check_rounded),
                label: const Text('收下勋章', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }

  /// scale 0 → 1（弹性过冲），配一层透明度渐显，保证「从无到有」。
  Widget _popped(Animation<double> a, Widget child) => AnimatedBuilder(
        animation: a,
        builder: (_, _) => Opacity(
          opacity: a.value.clamp(0.0, 1.0).toDouble(),
          child: Transform.scale(
            scale: a.value.clamp(0.0, 1.6).toDouble(),
            child: child,
          ),
        ),
      );
}

/// 一枚勋章：金色圆盘 + 专属图标（+ 小字名称）。
class _Medal extends StatelessWidget {
  const _Medal({required this.iconKey, required this.size, this.label = '', this.labelSize = 11});

  final String iconKey;
  final double size;
  final String label;
  final double labelSize;

  @override
  Widget build(BuildContext context) {
    final medal = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.goldSoft, AppColors.gold, const Color(0xFFB8860B)],
        ),
        border: Border.all(color: const Color(0xFFFFF3C4), width: 2),
        boxShadow: [
          BoxShadow(color: AppColors.gold.withValues(alpha: 0.55), blurRadius: 20, offset: const Offset(0, 6)),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(BadgeGiftOpen.iconFor(iconKey), size: size * 0.5, color: AppColors.brandDeep),
    );
    if (label.isEmpty) return medal;
    return SizedBox(
      width: size + 18,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          medal,
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: labelSize, color: const Color(0xFFF3E6C4), height: 1.2),
          ),
        ],
      ),
    );
  }
}

/// 中心炸开的烟花：三簇粒子 + 扩散圆环，全部随时间淡出。
class _FireworksPainter extends CustomPainter {
  _FireworksPainter({required this.progress, required this.bursts});

  final double progress;
  final List<_Burst> bursts;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height / 2);
    for (final b in bursts) {
      final p = ((progress - b.delay) / b.span).clamp(0.0, 1.0);
      if (progress < b.delay || p >= 1) continue;
      final c = origin + b.center;
      final eased = Curves.easeOutCubic.transform(p);
      final fade = (1 - p);
      // 爆开瞬间的扩散圆环
      if (p < 0.55) {
        canvas.drawCircle(
          c,
          b.radius * eased * 0.85,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2 * fade
            ..color = b.color.withValues(alpha: fade * 0.55),
        );
      }
      // 粒子
      for (var i = 0; i < b.count; i++) {
        final dist = b.radius * eased * b.speeds[i];
        final pos = c + Offset(math.cos(b.angles[i]), math.sin(b.angles[i])) * dist;
        final r = (1 - p) * 3.4 + 1.0;
        canvas.drawCircle(pos, r, Paint()..color = b.color.withValues(alpha: fade * 0.95));
        // 粒子拖尾（朝向爆心的短线，像烟花轨迹）
        if (p < 0.7) {
          canvas.drawLine(
            pos,
            c + Offset(math.cos(b.angles[i]), math.sin(b.angles[i])) * dist * 0.82,
            Paint()
              ..strokeWidth = r * 0.8
              ..strokeCap = StrokeCap.round
              ..color = b.color.withValues(alpha: fade * 0.5),
          );
        }
      }
      // 爆心白光
      if (p < 0.3) {
        canvas.drawCircle(
          c,
          18 * (1 - p / 0.3),
          Paint()..color = Colors.white.withValues(alpha: (1 - p / 0.3) * 0.85),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FireworksPainter old) =>
      old.progress != progress || old.bursts != bursts;
}
