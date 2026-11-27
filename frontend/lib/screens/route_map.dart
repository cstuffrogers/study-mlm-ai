// 路线导航/章节列表页（T016）— 渐变头图 + 阶段分组 + 动画掌握条 + 今日推荐/复习
import 'package:flutter/material.dart';
import '../models/learning_models.dart';
import '../services/routes_service.dart';
import '../services/recommendation_service_api.dart';
import '../widgets/recommendation_card.dart';
import '../widgets/review_card.dart';
import '../services/review_service_api.dart';
import '../widgets/anim.dart';
import '../theme/app_theme.dart';
import 'diagnostic_test.dart';
import 'chapter_guide_screen.dart';
import 'chapter_test.dart';
import 'profile_dashboard.dart';
import '../offline/offline_content.dart';

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
  late Future<RouteSectionsView> _future;
  Recommendation? _rec;
  List<ReviewItem> _due = const [];

  @override
  void initState() {
    super.initState();
    _reload();
    _recApi.today(routeId: widget.routeId).then((r) {
      if (mounted) setState(() => _rec = r);
    }).catchError((_) {});
    _loadDue();
  }

  Future<void> _loadDue() async {
    try {
      final d = await _reviewApi.interleaved(routeId: widget.routeId, n: 8);
      if (mounted) setState(() => _due = d);
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _onReview(String nodeId, double ratio) async {
    // 不吞异常：失败时由 ReviewCard 向用户明说「记录失败」并保留条目，
    // 否则点一下什么也没发生（用户实报）。
    final r = await _reviewApi.submit(
        nodeId: nodeId, correctRatio: ratio, routeId: widget.routeId);
    await _loadDue();
    return r;
  }

  /// 「去做巩固题」：直接进该知识点所在章节的**试题**。
  ///
  /// 原先跳的是「深入学习」导读页 —— 用户点了「去做练习」却落到只读页面，
  /// 还得再往下翻才找到入口（用户实报：怎么跳到深入学习界面了，应该去试题）。
  /// 章节测试本身一个知识点只出一道（D176），正好对上「巩固」的语义。
  /// 无题库的章节由 ChapterTestScreen 自己报「暂无题库」并留在原页，不静默开空卷。
  void _practice(ReviewItem it) {
    if (it.sectionId.isEmpty) return;
    final meta = OfflineContent.sectionMeta(it.sectionId);
    final title = '${meta?['title'] ?? ''}'.trim();
    Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => ChapterTestScreen(
            routeId: widget.routeId,
            sectionId: it.sectionId,
            sectionTitle: title.isEmpty ? '章节' : title))).then((back) {
      if (back == true && mounted) {
        setState(_reload);
        _loadDue();
      }
    });
  }

  void _reload() {
    _future = _svc.sectionsView(widget.routeId);
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
              child: FutureBuilder<RouteSectionsView>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) return Center(child: Text('加载失败：${snap.error}'));
                  final view = snap.data ?? RouteSectionsView(sections: const []);
                  final secs = view.sections;
                  int lastStage = -1;
                  final children = <Widget>[];
                  if (_due.isNotEmpty) {
                    children.add(Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: AnimatedEntrance(
                          delayMs: 60,
                          child: ReviewCard(
                              items: _due, onReview: _onReview, onPractice: _practice)),
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
                        onPressed: () async {
                          await Navigator.push(context, MaterialPageRoute(
                              builder: (_)
                                  => DiagnosticTestScreen(routeId: widget.routeId, routeName: widget.routeName)));
                          // 诊断测试必写掌握度，返回后无条件刷新
                          if (mounted) setState(_reload);
                        },
                      ),
                    ),
                  ));
                  // 公共地基（D152）：B/C 的章节列表里没有地基章，这里补上，
                  // 免得切到 B 就以为「地基已经过关」。路线 A 自己列了，不重复展示。
                  if (view.sharedOnly.isNotEmpty) {
                    children.add(Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                      child: AnimatedEntrance(delayMs: 60, child: _foundationCard(view)),
                    ));
                  }
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

  /// 公共地基卡（D152）：三条路线共用三章，只排在路线 A。
  ///
  /// 这里只展示「本路线没有的那几章」：读完的打勾，没读的提示去路线 A 补。
  /// 点行进去时 routeId 用地基章自己的路线（route_A）——掌握度按「用户 × 路线」存，
  /// 在 B 路线名义下读地基章，记录会落在 B 名下，回到 A 又显示没学。
  Widget _foundationCard(RouteSectionsView view) {
    final rows = view.sharedOnly;
    final done = view.doneCount;
    final total = view.foundation.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.brandSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.foundation_outlined, size: 18, color: AppColors.brandDeep),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('公共地基（三条路线共用）',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
            ),
            Text('已读 $done/$total',
                style: const TextStyle(fontSize: 11.5, color: AppColors.ink500)),
          ]),
          const SizedBox(height: 4),
          const Text(
            '《大众哲学》两章 + 《关于费尔巴哈的提纲》一章，只在「纯理论研究」路线里上课；'
            '学完一次，三条路线都算数。',
            style: TextStyle(fontSize: 11.5, color: AppColors.ink400, height: 1.4),
          ),
          const SizedBox(height: 6),
          for (final s in rows) _foundationRow(s),
        ],
      ),
    );
  }

  Widget _foundationRow(RouteSection s) {
    final color = _color(s.status);
    final label = s.status == 'completed'
        ? '已读'
        : (s.status == 'in_progress' ? '在读' : '待补');
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final back = await Navigator.push<bool>(context, MaterialPageRoute(
            builder: (_) => ChapterGuideScreen(
                routeId: s.routeId ?? widget.routeId,
                sectionId: s.id,
                sectionTitle: s.title,
                hasBank: s.hasBank)));
        if (back == true) setState(_reload);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Icon(_icon(s.status), size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(s.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
          ),
          const Icon(Icons.chevron_right, size: 16, color: AppColors.ink400),
        ]),
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
