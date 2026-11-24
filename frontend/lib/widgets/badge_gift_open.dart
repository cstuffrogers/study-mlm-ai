// 勋章达成礼物开箱动画（spec 001）
//
// 设计：全屏遮罩 → 礼物盒盖掀开 → 金光溢出 → 勋章弹出旋转 → 停留可点关闭。
// 时长 3s（约束 ≤5s），结束后保留展示，点击关闭。
// 异常兜底：动画控制器出错时直接关闭，不阻断主流程。
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 单枚勋章开箱动画。
///
/// [name] 勋章名、[iconKey] 分类图标键、[description] 描述。
/// 显示 [show] 为 true 时弹出，动画结束自动停止在展示态，点击遮罩或按钮关闭。
class BadgeGiftOpen extends StatefulWidget {
  const BadgeGiftOpen({
    super.key,
    required this.name,
    required this.iconKey,
    this.description = '',
    required this.onClose,
  });

  final String name;
  final String iconKey;
  final String description;
  final VoidCallback onClose;

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

class _BadgeGiftOpenState extends State<BadgeGiftOpen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _lidAngle; // 盖子掀开角度
  late final Animation<double> _lidY; // 盖子上移
  late final Animation<double> _glow; // 金光缩放
  late final Animation<double> _glowAlpha; // 金光透明度
  late final Animation<double> _badgePop; // 勋章弹出缩放
  late final Animation<double> _badgeRotate; // 勋章旋转
  late final Animation<double> _badgeAlpha;
  late final Animation<double> _particles; // 粒子扩散

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));
    const curve = Curves.easeOutCubic;
    _lidAngle = Tween<double>(begin: 0, end: 1.1).animate(CurvedAnimation(
        parent: _c, curve: Interval(0.15, 0.5, curve: curve)));
    _lidY = Tween<double>(begin: 0, end: -70).animate(CurvedAnimation(
        parent: _c, curve: Interval(0.15, 0.5, curve: curve)));
    _glow = Tween<double>(begin: 0.2, end: 1.6).animate(CurvedAnimation(
        parent: _c, curve: Interval(0.35, 0.75, curve: curve)));
    _glowAlpha = Tween<double>(begin: 0, end: 0.7)
        .animate(CurvedAnimation(parent: _c, curve: Interval(0.35, 0.65)));
    _badgePop = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _c, curve: Interval(0.5, 0.85, curve: curve)));
    _badgeRotate = Tween<double>(begin: -0.4, end: 0)
        .animate(CurvedAnimation(parent: _c, curve: Interval(0.5, 0.95, curve: curve)));
    _badgeAlpha = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _c, curve: Interval(0.5, 0.8)));
    _particles = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _c, curve: Interval(0.45, 0.9)));
    _c.forward().whenComplete(() {
      // 动画结束保持展示态，等用户点击关闭。
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  IconData get _icon => BadgeGiftOpen.iconFor(widget.iconKey);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _c.status == AnimationStatus.completed ? widget.onClose : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.black.withValues(alpha: 0.6),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // —— 金光晕染 ——
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, child) => Transform.scale(
                  scale: _glow.value,
                  child: Opacity(
                    opacity: _glowAlpha.value,
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppColors.gold.withValues(alpha: 0.5),
                            AppColors.goldSoft.withValues(alpha: 0.2),
                            const Color(0x00000000),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                child: const SizedBox(),
              ),
            ),
            // —— 粒子光斑 ——
            _Particles(animation: _particles),
            const SizedBox(height: 12),
            // —— 礼物盒（盖掀开后露出勋章） ——
            SizedBox(
              height: 180,
              width: 180,
              child: Stack(
                alignment: Alignment.bottomCenter,
                clipBehavior: Clip.none,
                children: [
                  // 盒身
                  Container(
                    width: 150,
                    height: 120,
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(16)),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 16,
                            offset: Offset(0, 8)),
                      ],
                    ),
                  ),
                  // 盒身金色飘带
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ),
                  // 蝴蝶结
                  Positioned(
                    top: -34,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Transform.rotate(
                        angle: _lidAngle.value,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 56,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.gold,
                                borderRadius: const BorderRadius.horizontal(
                                    left: Radius.circular(12),
                                    right: Radius.circular(12)),
                              ),
                            ),
                            Container(
                              width: 56,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.gold.withValues(alpha: 0.8),
                                borderRadius: const BorderRadius.horizontal(
                                    left: Radius.circular(12),
                                    right: Radius.circular(12)),
                              ),
                              transform: Matrix4.rotationY(0.4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 盒盖（掀开动画）
                  Positioned(
                    top: -40 + _lidY.value,
                    left: -15,
                    right: -15,
                    child: IgnorePointer(
                      child: Transform.rotate(
                        angle: _lidAngle.value,
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.brandDeep,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12)),
                            border: Border.all(color: AppColors.gold),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 勋章（弹出动画，盖掀开后出现）
                  Positioned(
                    top: -90,
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (_, child) => Transform.scale(
                        scale: _badgePop.value,
                        child: Opacity(
                          opacity: _badgeAlpha.value,
                          child: Transform.rotate(
                            angle: _badgeRotate.value,
                            child: Container(
                              width: 92,
                              height: 92,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      AppColors.gold,
                                      AppColors.goldSoft,
                                      AppColors.gold,
                                    ]),
                                boxShadow: [
                                  BoxShadow(
                                      color: AppColors.gold.withValues(alpha: 0.6),
                                      blurRadius: 24,
                                      offset: Offset(0, 6)),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                _icon,
                                size: 48,
                                color: AppColors.brandDeep,
                              ),
                            ),
                          ),
                        ),
                      ),
                    child: const SizedBox(),
                  ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // —— 勋章名称与描述 ——
            FadeTransition(
             opacity: _badgeAlpha,
              child: Column(
                children: [
                  const Icon(Icons.emoji_events_rounded,
                      color: AppColors.gold, size: 28),
                  const SizedBox(height: 6),
                  Text(
                    widget.name,
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.gold),
                  ),
                  if (widget.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.description,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.ink700, fontSize: 14),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_c.status == AnimationStatus.completed)
              FilledButton.icon(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded),
                label: const Text('收下勋章'),
              ),
          ],
        ),
      ),
    );
  }
}

/// 金光粒子扩散（几个光斑从中心向外散开）。
class _Particles extends StatelessWidget {
  const _Particles({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    const seeds = <Offset>[
      Offset(-90, -20),
      Offset(90, -20),
      Offset(-60, -50),
      Offset(60, -50),
      Offset(-110, 10),
      Offset(110, 10),
      Offset(0, -70),
      Offset(-30, -80),
      Offset(30, -80),
    ];
    return AnimatedBuilder(
      animation: animation,
      builder: (_, child) {
        return Stack(
          children: seeds
              .map((p) => Positioned(
                  left: p.dx + 90 + animation.value * p.dx,
                  top: p.dy + 90 + animation.value * p.dy,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.gold.withValues(
                          alpha: (1 - animation.value) * 0.9),
                    ),
                  )))
              .toList(),
        );
      },
    );
  }
}
