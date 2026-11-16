// 路线导航/章节列表页（T016）— 渐变头图 + 阶段分组 + 动画掌握条 + 今日推荐/复习/动机横幅
import 'package:flutter/material.dart';
import '../models/learning_models.dart';
import '../services/routes_service.dart';
import '../services/recommendation_service_api.dart';
import '../widgets/recommendation_card.dart';
import '../widgets/review_card.dart';
import '../services/review_service_api.dart';
import '../services/motivation_service_api.dart';
import '../widgets/motivation_banner.dart';
import '../widgets/anim.dart';
import '../theme/app_theme.dart';
import 'diagnostic_test.dart';
import 'chapter_guide_screen.dart';
import 'profile_dashboard.dart';

class RouteMapScreen extends StatefulWidget {
  final String routeId;
  final String routeName;
  const RouteMapScreen({super.key, required this.routeId, required this.routeName});

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  final _svc = RoutesService();
  final _recApi = RecommendationApi();
  final _reviewApi = ReviewApi();
  final _motApi = MotivationApi();
  late Future<List<RouteSection>> _future;
  Recommendation? _rec;
  List<ReviewItem> _due = const [];
  Map<String, dynamic>? _motivation;

  @override
  void initState() {
    super.initState();
    _reload();
    _recApi.today(routeId: widget.routeId).then((r) {
      if (mounted) setState(() => _rec = r);
    }).catchError((_) {});
    _loadDue();
    _loadMotivation();
  }

  Future<void> _loadMotivation() async {
    try {
      final m = await _motApi.state(routeId: widget.routeId);
      if (mounted) setState(() => _motivation = m);
    } catch (_) {}
  }

  Future<void> _loadDue() async {
    try {
      final d = await _reviewApi.interleaved(routeId: widget.routeId, n: 8);
      if (mounted) setState(() => _due = d);
    } catch (_) {}
  }

  Future<void> _onReview(String nodeId, double ratio) async {
    try {
      await _reviewApi.submit(nodeId: nodeId, correctRatio: ratio, routeId: widget.routeId);
      await _loadDue();
    } catch (_) {}
  }

  void _reload() {
    _future = _svc.sections(widget.routeId);
  }

  IconData _icon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle;
      case 'in_progress':
        return Icons.play_arrow_rounded;
      case 'unlocked':
        return Icons.play_circle_outline;
      case 'locked':
      default:
        return Icons.lock;
    }
  }

  Color _color(String status) {
    switch (status) {
      case 'completed':
        return AppColors.success;
      case 'in_progress':
        return AppColors.brand;
      case 'unlocked':
        return AppColors.info;
      default:
        return AppColors.ink400;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          GradientHeader(
            leading: Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.maybePop(ctx),
              ),
            ),
            title: widget.routeName,
            subtitle: '自由学习 · 可从任意章节开始、跳着学',
            actions: [
              IconButton(
                icon: const Icon(Icons.insights, color: Colors.white),
                tooltip: '学情档案',
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ProfileDashboardScreen(routeId: widget.routeId))),
              ),
            ],
          ),
          Expanded(
            child: AuroraBackground(
              child: FutureBuilder<List<RouteSection>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) return Center(child: Text('加载失败：${snap.error}'));
                  final secs = snap.data ?? [];
                  int lastStage = -1;
                  final children = <Widget>[];
                  if (_motivation != null) {
                    children.add(Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: AnimatedEntrance(child: MotivationBanner(state: _motivation!)),
                    ));
                  }
                  if (_due.isNotEmpty) {
                    children.add(Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: AnimatedEntrance(delayMs: 60, child: ReviewCard(items: _due, onReview: _onReview)),
                    ));
                  }
                  if (_rec != null) {
                    children.add(Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: AnimatedEntrance(
                        delayMs: 120,
                        child: RecommendationCard(
                          rec: _rec!,
                          compact: true,
                          onEnter: () async {
                            final target = _rec!.targetSectionId;
                            if (target.isEmpty) return;
                            final sec = secs.firstWhere((x) => x.id == target,
                                orElse: () => RouteSection(
                                    id: target, orderIndex: 0, stageNo: 0, work: '', title: '推荐章节',
                                    isFoundation: false, status: 'unlocked',
                                    masteryScore: 0, unlockThreshold: 0.8));
                            final changed = await Navigator.push<bool>(context, MaterialPageRoute(
                                builder: (_) => ChapterGuideScreen(
                                    routeId: widget.routeId,
                                    sectionId: target,
                                    sectionTitle: sec.title,
                                    hasBank: sec.hasBank)));
                            if (changed == true) setState(_reload);
                          },
                        ),
                      ),
                    ));
                  }
                  children.add(Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.quiz_outlined, size: 18),
                        label: const Text('重新摸底测'),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) =>
                                DiagnosticTestScreen(routeId: widget.routeId, routeName: widget.routeName))),
                      ),
                    ),
                  ));
                  for (final s in secs) {
                    if (s.stageNo != lastStage) {
                      lastStage = s.stageNo;
                      children.add(Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                        child: Row(children: [
                          Container(
                            width: 6,
                            height: 16,
                            decoration: BoxDecoration(
                              gradient: AppColors.brandGradient,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('阶段 ${s.stageNo}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, color: AppColors.ink700, fontSize: 14)),
                        ]),
                      ));
                    }
                    children.add(AnimatedEntrance(delayMs: 40, child: _sectionTile(s)));
                  }
                  children.add(const SizedBox(height: 24));
                  // 懒挂载：AnimatedEntrance 等每项都带动画 State，章节多时
                  // 一次性挂载全部会拖慢首帧；builder 只建可见区间。
                  return ListView.builder(
                    itemCount: children.length,
                    itemBuilder: (_, i) => children[i],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTile(RouteSection s) {
    final color = _color(s.status);
    // 「理想顺序下一章」：尚未开始、且前序都已完成 → 高亮推荐；否则为可自由进入的普通章
    final isSuggested = s.status == 'unlocked' && s.prevCompleted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () async {
            final changed = await Navigator.push<bool>(context, MaterialPageRoute(
                builder: (_) => ChapterGuideScreen(
                    routeId: widget.routeId,
                    sectionId: s.id,
                    sectionTitle: s.title,
                    hasBank: s.hasBank)));
            if (changed == true) setState(_reload);
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: isSuggested ? color.withValues(alpha: 0.45) : AppColors.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_icon(s.status), color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(s.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                        if (isSuggested)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('推荐下一章',
                                style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
                          ),
                        if (s.isFoundation) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.brandSoft,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('公共地基',
                                style: TextStyle(fontSize: 10, color: AppColors.brandDeep)),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        s.hasBank
                            ? '${s.work} · ${s.status == 'completed' ? '已完成' : (s.status == 'in_progress' ? '进行中' : '可学')}'
                            : '${s.work} · 阅读章',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.ink400),
                      ),
                      if (s.hasBank) ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: AnimatedBar(
                              value: s.masteryScore,
                              height: 6,
                              color: s.masteryScore >= s.unlockThreshold ? AppColors.success : color,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('${(s.masteryScore * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: s.masteryScore >= s.unlockThreshold
                                      ? AppColors.success
                                      : AppColors.ink500)),
                        ]),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  s.hasBank ? Icons.chevron_right : Icons.check_circle_outline,
                  color: AppColors.ink400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
