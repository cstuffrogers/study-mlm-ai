// 学情档案/仪表盘（T040）— 渐变头图 + 雷达 + 薄弱点TOP-N + 总结卡 + 时间筛选 + 空态
import 'package:flutter/material.dart';
import '../models/learning_models.dart';
import '../services/mastery_service_api.dart';
import '../widgets/radar_chart.dart';
import '../widgets/weak_point_card.dart';
import '../widgets/anim.dart';
import '../theme/app_theme.dart';
import 'chapter_test.dart';
import 'analytics_dashboard.dart';

const _dimLabels = {
  'materialism': '唯物论',
  'dialectics': '辩证法',
  'epistemology': '认识论',
  'historical_materialism': '历史唯物主义',
  'political_economy': '政治经济学',
};

class ProfileDashboardScreen extends StatefulWidget {
  final String routeId;
  const ProfileDashboardScreen({super.key, required this.routeId});

  @override
  State<ProfileDashboardScreen> createState() => _ProfileDashboardScreenState();
}

class _ProfileDashboardScreenState extends State<ProfileDashboardScreen> {
  final _api = MasteryApi();
  Profile? _profile;
  Map<String, dynamic>? _summary;
  bool _loading = true;
  String? _error;
  String _period = 'week';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await _api.profile(routeId: widget.routeId);
      final s = await _api.summary(routeId: widget.routeId, period: _period);
      setState(() {
        _profile = p;
        _summary = s;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
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
            title: '学情档案',
            subtitle: '五维能力 · 薄弱点 · AI 学习总结',
            actions: [
              PopupMenuButton<String>(
                initialValue: _period,
                icon: const Icon(Icons.filter_alt_outlined, color: Colors.white),
                onSelected: (v) {
                  setState(() => _period = v);
                  _load();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'week', child: Text('近一周')),
                  PopupMenuItem(value: 'month', child: Text('近一月')),
                  PopupMenuItem(value: 'all', child: Text('全部')),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.insights, color: Colors.white),
                tooltip: '学习分析',
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => AnalyticsDashboardScreen(routeId: widget.routeId))),
              ),
            ],
          ),
          Expanded(
            child: AuroraBackground(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text('加载失败：$_error'))
                      : _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final p = _profile!;
    final radarValues = p.abilityRadar.map((k, v) => MapEntry(k, (v as num).toDouble()));
    final isEmpty = p.weakPoints.isEmpty && radarValues.values.every((v) => v == 0);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AnimatedEntrance(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.line),
              boxShadow: AppShadows.soft,
            ),
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 8),
                const Text('五维能力雷达', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ]),
              const SizedBox(height: 10),
              RadarChart(values: radarValues, labels: _dimLabels, size: 240),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        if (isEmpty)
          AnimatedEntrance(
            delayMs: 80,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.line),
              ),
              child: const Padding(
                padding: EdgeInsets.all(28),
                child: Column(children: [
                  Icon(Icons.auto_stories_outlined, size: 52, color: AppColors.ink400),
                  SizedBox(height: 12),
                  Text('还没有学情数据，去学习并完成一次章节测试吧～',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.ink500)),
                ]),
              ),
            ),
          )
        else ...[
          if (_summary != null) AnimatedEntrance(delayMs: 60, child: _buildSummaryCard(_summary!)),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 6),
            child: Text('薄弱点 TOP-N', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
          ...p.weakPoints.take(5).toList().asMap().entries.map((e) => AnimatedEntrance(
                delayMs: 120 + e.key * 55,
                child: WeakPointCard(
                  item: e.value,
                  onReinforce: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ChapterTestScreen(
                          routeId: widget.routeId,
                          sectionId: e.value.sectionId.isNotEmpty ? e.value.sectionId : 'sec_A_02',
                          sectionTitle: '${e.value.name} · 专项回补'))),
                ),
              )),
        ],
      ],
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic> s) {
    final mastered = (s['mastered'] as List?) ?? const [];
    final reinforce = (s['to_reinforce'] as List?) ?? const [];
    final nextStep = s['next_step'] ?? '';
    return GradientCard(
      gradient: const LinearGradient(
        colors: [Color(0xFFFDF1EF), Color(0xFFFBF1DA)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      border: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.auto_awesome, size: 18, color: AppColors.brand),
            SizedBox(width: 6),
            Text('AI 学习总结', style: TextStyle(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _statPill('已掌握', '${mastered.length}', AppColors.success),
            const SizedBox(width: 10),
            _statPill('待巩固', '${reinforce.length}', AppColors.danger),
          ]),
          const SizedBox(height: 10),
          if (mastered.isNotEmpty)
            Text('已掌握 ${mastered.length} 项：${mastered.take(4).join('、')}',
                style: const TextStyle(fontSize: 13, color: AppColors.success, height: 1.5)),
          if (reinforce.isNotEmpty)
            Text('待巩固 ${reinforce.length} 项：${reinforce.take(4).join('、')}',
                style: const TextStyle(fontSize: 13, color: AppColors.danger, height: 1.5)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              const Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.brand),
              const SizedBox(width: 6),
              Expanded(
                child: Text('下一步：$nextStep',
                    style: const TextStyle(fontSize: 13, color: AppColors.ink700)),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _statPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.ink500)),
      ]),
    );
  }
}
