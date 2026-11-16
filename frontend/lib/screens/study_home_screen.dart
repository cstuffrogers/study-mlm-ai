// 学习首页 — 选路线 / 选章节 / 深入学习 / 查看原文。
//
// 性能：路由与章节列表用短缓存瞬时呈现（stale-while-revalidate），切换路线时
// 不再等待 select 的 POST 才能开始加载 sections；章节列表用 ListView.builder 懒构建。
// 学习路径：默认选「第一个未完成章节」，并显式给出「继续学习」提示与阶段/进度信息。
import 'package:flutter/material.dart';
import '../models/learning_models.dart';
import '../services/api_client.dart';
import '../services/routes_service.dart';
import '../widgets/anim.dart';
import '../widgets/author_art.dart';
import '../theme/app_theme.dart';
import '../widgets/guide_dialog.dart';
import 'analytics_dashboard.dart';
import 'chapter_guide_screen.dart';
import 'route_picker.dart';
import 'tools_screen.dart';
import 'work_reader_screen.dart';

const _routeAccents = <List<Color>>[
  [Color(0xFFC8161D), Color(0xFF9E1520)],
  [Color(0xFF9E1520), Color(0xFF7A0E13)],
  [Color(0xFFB45309), Color(0xFFC8161D)],
];
const _routeIcons = <IconData>[Icons.menu_book, Icons.groups, Icons.public];

class StudyHomeScreen extends StatefulWidget {
  const StudyHomeScreen({super.key});

  @override
  State<StudyHomeScreen> createState() => _StudyHomeScreenState();
}

class _StudyHomeScreenState extends State<StudyHomeScreen> {
  final _svc = RoutesService();

  List<LearningRoute> _routes = const [];
  List<RouteSection> _sections = const [];
  String? _routeId;
  String? _sectionId;
  bool _loadingRoutes = true;
  bool _loadingSections = false;
  String? _error;
  int _loadToken = 0; // 快速连点路线时丢弃过期响应

  /// 学习路径摘要：完成数 / 总数、当前推荐章。
  int get _completedCount => _sections.where((s) => s.status == 'completed').length;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    setState(() {
      _loadingRoutes = true;
      _error = null;
    });
    try {
      final routes = await _svc.listRoutes();
      if (!mounted) return;
      final first = routes.isNotEmpty ? routes.first.id : null;
      setState(() {
        _routes = routes;
        _routeId ??= first;
        _loadingRoutes = false;
      });
      if (first != null) await _loadSections(first);
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loadingRoutes = false; });
    }
  }

  Future<void> _selectRoute(String id) async {
    if (_routeId == id) return;
    setState(() {
      _routeId = id;
      _sections = const [];
      _sectionId = null;
    });
    await _loadSections(id);
  }

  Future<void> _loadSections(String routeId) async {
    final token = ++_loadToken;
    setState(() { _loadingSections = true; });
    // 不再调 select：它只做一次服务端重算（返回建议起点），既不持久化选中态，
    // 结果也没被使用；sections 已直接带 status/prev_completed。省掉一次请求。
    try {
      final secs = await _svc.sections(routeId);
      if (!mounted || token != _loadToken || _routeId != routeId) return;
      RouteSection? start;
      for (final s in secs) {
        if (s.status != 'completed') { start = s; break; }
      }
      start ??= secs.isNotEmpty ? secs.first : null;
      setState(() {
        _sections = secs;
        _sectionId = start?.id;
        _loadingSections = false;
      });
    } catch (e) {
      if (mounted && token == _loadToken) {
        setState(() { _error = '$e'; _loadingSections = false; });
      }
    }
  }

  /// 从章节页返回后刷新学习进度，保证「继续学习」指向最新状态。
  Future<void> _enterStudy() async {
    final s = _selected;
    if (s == null) return;
    ApiClient.invalidatePrefix('/api/routes/${_routeId ?? ''}/sections');
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => ChapterGuideScreen(
              routeId: _routeId!,
              sectionId: s.id,
              sectionTitle: s.title,
              hasBank: s.hasBank,
            )));
    if (changed == true && mounted && _routeId != null) {
      await _loadSections(_routeId!);
    }
  }

  RouteSection? get _selected {
    if (_sectionId == null) return null;
    for (final s in _sections) {
      if (s.id == _sectionId) return s;
    }
    return null;
  }

  int get _routeIndex {
    final i = _routes.indexWhere((r) => r.id == _routeId);
    return i < 0 ? 0 : i;
  }

  void _viewSource() {
    final s = _selected;
    final work = s?.localWork;
    if (work == null || work.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WorkReaderScreen(work: work, title: s!.title)));
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AuroraBackground(
        child: Column(
          children: [
            GradientHeader(
              title: '马列毛思想AI伴读',
              subtitle: '先选学习路线，再选起始章节',
              art: const AuthorArt(asset: kHomeArt, height: 116),
              // 入口放在头部而不是右下浮动按钮：浮动按钮会压住底部「深入学习」
              // 与「查看原文」两个主操作（历史问题），头部图标不遮挡任何内容。
              actions: [
                _HeaderAction(
                  tooltip: '功能中心',
                  icon: Icons.grid_view_rounded,
                  onTap: () => _push(const ToolsScreen()),
                ),
                _HeaderAction(
                  tooltip: '学习路线',
                  icon: Icons.route_rounded,
                  onTap: () => _push(const RoutePickerScreen()),
                ),
                _HeaderAction(
                  tooltip: '学习分析',
                  icon: Icons.insights_rounded,
                  onTap: () => _push(const AnalyticsDashboardScreen(routeId: 'route_A')),
                ),
                _HeaderAction(
                  tooltip: '引导',
                  icon: Icons.help_outline_rounded,
                  onTap: () => showUsageGuide(context),
                ),
              ],
            ),
            Expanded(child: _buildBody()),
            _buildActionBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingRoutes) return const Center(child: CircularProgressIndicator());
    if (_error != null && _routes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: AppColors.ink400, size: 40),
            const SizedBox(height: 10),
            Text('加载失败：$_error\n请确认后端已启动', textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.ink500)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _loadRoutes, child: const Text('重试')),
          ]),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      itemCount: 5 + (_loadingSections || _sections.isEmpty ? 1 : _sections.length),
      itemBuilder: (context, index) {
        if (index == 0) return _stepLabel('① 选择学习路线');
        if (index == 1) return const SizedBox(height: 8);
        if (index == 2) return _routeChips();
        if (index == 3) return const SizedBox(height: 18);
        if (index == 4) return _sectionHeader();
        if (_loadingSections) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (_sections.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('该路线暂无章节', style: TextStyle(color: AppColors.ink400))),
          );
        }
        final s = _sections[index - 5];
        return _chapterCard(index - 5, s);
      },
    );
  }

  Widget _sectionHeader() => Row(children: [
        _stepLabel('② 选择起始章节'),
        const Spacer(),
        if (_sections.isNotEmpty)
          Text('进度 $_completedCount/${_sections.length}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.ink400)),
      ]);

  Widget _stepLabel(String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 3, height: 14, color: AppColors.brand,
            margin: const EdgeInsets.only(right: 8)),
        Text(t, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.ink700)),
      ]);

  Widget _routeChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _routes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (c, i) {
          final r = _routes[i];
          final on = r.id == _routeId;
          final accent = _routeAccents[i % _routeAccents.length];
          return GestureDetector(
            onTap: () => _selectRoute(r.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: on ? LinearGradient(colors: accent) : null,
                color: on ? null : Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: on ? Colors.transparent : AppColors.line),
                boxShadow: on
                    ? [BoxShadow(color: accent.first.withValues(alpha: 0.32), blurRadius: 12, offset: const Offset(0, 5))]
                    : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_routeIcons[i % _routeIcons.length],
                    size: 16, color: on ? Colors.white : AppColors.ink500),
                const SizedBox(width: 7),
                Text(r.name,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: on ? Colors.white : AppColors.ink700)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _chapterCard(int index, RouteSection s) {
    final on = s.id == _sectionId;
    final accent = _routeAccents[_routeIndex % _routeAccents.length];
    return AnimatedEntrance(
      delayMs: (index % 8) * 35,
      child: GestureDetector(
        onTap: () => setState(() => _sectionId = s.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: on ? AppColors.brandSoft.withValues(alpha: 0.55) : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
                color: on ? AppColors.brand.withValues(alpha: 0.7) : AppColors.line,
                width: on ? 1.6 : 1),
            boxShadow: AppShadows.soft,
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: on ? LinearGradient(colors: accent) : null,
                color: on ? null : AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: on
                  ? const Icon(Icons.check, size: 17, color: Colors.white)
                  : Text('${s.orderIndex + 1}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink500)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(s.title,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: on ? AppColors.brandDeep : AppColors.ink700)),
                  ),
                  if (s.status == 'completed') _tag('已完成', AppColors.success),
                  if (s.status == 'in_progress') _tag('进行中', AppColors.brand),
                  if (s.localWork != null && s.localWork!.isNotEmpty)
                    _tag('有原文', AppColors.success),
                  if (s.isFoundation) ...[
                    const SizedBox(width: 6),
                    _tag('地基', AppColors.gold),
                  ],
                ]),
                const SizedBox(height: 3),
                Text(s.work,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.ink400)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        margin: const EdgeInsets.only(left: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      );

  Widget _buildActionBar() {
    final s = _selected;
    final hasSource = s?.localWork != null && s!.localWork!.isNotEmpty;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (s != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                const Icon(Icons.play_circle_outline, size: 15, color: AppColors.ink400),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('继续学习：${s.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.ink500)),
                ),
              ]),
            ),
          Row(children: [
            if (hasSource) ...[
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brand,
                    side: BorderSide(color: AppColors.brand.withValues(alpha: 0.55)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _viewSource,
                  icon: const Icon(Icons.menu_book_rounded, size: 18),
                  label: const Text('查看原文', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: s == null ? null : _enterStudy,
                icon: const Icon(Icons.school_rounded, size: 18),
                label: const Text('深入学习', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// 首页头部的圆形图标入口（白描边、半透明底，压在红色渐变上可读）。
class _HeaderAction extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.white.withValues(alpha: 0.16),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Icon(icon, size: 19, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
