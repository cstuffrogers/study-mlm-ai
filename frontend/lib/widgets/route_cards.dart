// 路线卡片列表（首页与「选择学习路线」页共用一份实现）。
//
// 为什么不各写一份：首页现在就是「选路线」页，两处若各留一套卡片代码，
// 文案/徽标/排序迟早漂移（D131 起的双端一致性教训同样适用于同一端的两个页面）。
import 'package:flutter/material.dart';
import '../models/learning_models.dart';
import '../services/routes_service.dart';
import '../theme/app_theme.dart';
import 'anim.dart';
import '../screens/route_map.dart';

const _routeAccents = <List<Color>>[
  [Color(0xFFC8161D), Color(0xFF9E1520)], // 党旗红
  [Color(0xFF9E1520), Color(0xFF7A0E13)], // 绛红
  [Color(0xFFB45309), Color(0xFFC8161D)], // 檀金
];

const _routeIcons = <IconData>[Icons.menu_book, Icons.groups, Icons.public];

/// 三条路线卡片 + 顶部「共享地基」说明。
///
/// 默认点击进入该路线的章节地图（[RouteMapScreen]）；传 [onPick] 可替换跳转行为。
class RouteCardsView extends StatefulWidget {
  final void Function(BuildContext context, LearningRoute route)? onPick;

  /// 顶部说明条是否显示（首页已有副标题时也保留，信息不重复）。
  final bool showFoundationNote;

  const RouteCardsView({super.key, this.onPick, this.showFoundationNote = true});

  @override
  State<RouteCardsView> createState() => _RouteCardsViewState();
}

class _RouteCardsViewState extends State<RouteCardsView> {
  final _svc = RoutesService();
  late Future<List<LearningRoute>> _future;

  @override
  void initState() {
    super.initState();
    _future = _svc.listRoutes();
  }

  Future<void> _pick(LearningRoute r) async {
    if (!mounted) return;
    final custom = widget.onPick;
    if (custom != null) {
      custom(context, r);
      return;
    }
    // 不再先 await select：该接口只返回「重算的起点/已带走地基」，不持久化选中态，
    // 而章节页会直接读 sections 展示真实进度。少一次串行往返，进路线页更快。
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RouteMapScreen(routeId: r.id, routeName: r.name),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LearningRoute>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
              child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('加载失败：${snap.error}\n本地数据可能未随安装包打包（assets/offline）',
                textAlign: TextAlign.center),
          ));
        }
        final routes = snap.data ?? const <LearningRoute>[];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.showFoundationNote) ...[
              AnimatedEntrance(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.brandSoft.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                    border: Border.all(color: AppColors.brand.withValues(alpha: 0.25)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.hub_outlined, color: AppColors.brand, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          '三条路线共享公共地基：《大众哲学》两章 + 《关于费尔巴哈的提纲》。'
                          '地基课只在「纯理论研究」开，学一次三条路线都算。',
                          style: TextStyle(fontSize: 13, color: AppColors.brandDeep)),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
            ],
            ...routes.asMap().entries.map((e) => _routeCard(e.key, e.value)),
          ],
        );
      },
    );
  }

  Widget _routeCard(int index, LearningRoute r) {
    final accent = _routeAccents[index % _routeAccents.length];
    final icon = _routeIcons[index % _routeIcons.length];
    return AnimatedEntrance(
      delayMs: 80 + index * 90,
      child: GradientCard(
        margin: const EdgeInsets.only(bottom: 14),
        padding: EdgeInsets.zero,
        gradient: const LinearGradient(colors: [Colors.white, Colors.white]),
        onTap: () => _pick(r),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: accent),
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                          color: accent.first.withValues(alpha: 0.32),
                          blurRadius: 14,
                          offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(r.name,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chevron_right, color: AppColors.ink400, size: 20),
                ),
              ]),
              const SizedBox(height: 12),
              Text(r.goal, style: const TextStyle(color: AppColors.ink500, height: 1.5)),
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.schedule, size: 14, color: AppColors.ink400),
                const SizedBox(width: 4),
                Text(r.estDuration, style: const TextStyle(fontSize: 12, color: AppColors.ink400)),
                const SizedBox(width: 12),
                if (r.sharesFoundation)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.hub, size: 11, color: AppColors.success),
                      SizedBox(width: 3),
                      Text('共享地基', style: TextStyle(fontSize: 11, color: AppColors.success)),
                    ]),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
