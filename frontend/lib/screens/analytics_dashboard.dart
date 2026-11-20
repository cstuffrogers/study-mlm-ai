// 学习分析看板（P3）— 学习健康度 + 掌握分布 + 保持率 + 校准 + 错因 + 短板 + 动机 + FSRS 拟合
import 'package:flutter/material.dart';
import '../offline/local_db.dart';
import '../offline/local_quiz.dart';
import '../services/analytics_service_api.dart';
import '../services/api_client.dart';
import '../services/motivation_service_api.dart';
import '../services/review_service_api.dart';
import '../services/sync_controller.dart';
import '../widgets/motivation_banner.dart';
import '../widgets/anim.dart';
import '../theme/app_theme.dart';

const _dimLabels = {
  'materialism': '唯物论',
  'dialectics': '辩证法',
  'epistemology': '认识论',
  'historical_materialism': '历史唯物主义',
  'political_economy': '政治经济学',
};

const _levelLabels = {
  'unseen': '未接触',
  'beginner': '初学',
  'familiar': '熟悉',
  'proficient': '精通',
  'mastered': '贯通',
};

const _levelColors = {
  'unseen': Color(0xFF94A3B8),
  'beginner': Color(0xFFEA580C),
  'familiar': Color(0xFFD97706),
  'proficient': Color(0xFFD4A017),
  'mastered': Color(0xFF16A34A),
};

const _errLabels = {
  'term_misuse': '术语误用',
  'logic_gap': '逻辑断裂',
  'concept_layer_confusion': '概念层次混淆',
  'stance_deviation': '立场偏移',
  'real_unknown': '真实未掌握',
  'concept_application': '应用不当',
  'careless': '粗心',
};

/// 错因展示：未收录的编码回退到引擎统一标签（不再把内部编码抛给学习者）。
String _errName(String code) => _errLabels[code] ?? LocalQuiz.errorLabel(code);

class AnalyticsDashboardScreen extends StatefulWidget {
  final String routeId;
  const AnalyticsDashboardScreen({super.key, required this.routeId});

  @override
  State<AnalyticsDashboardScreen> createState() => _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen> {
  final _api = AnalyticsApi();
  final _motApi = MotivationApi();
  final _reviewApi = ReviewApi();
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _motivation;
  Map<String, dynamic>? _fit;
  bool _loading = true;
  String? _error;
  bool _loadingDone = false;
  bool _busyReset = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 页面重新可见时刷新数据（从做题/复习返回后 initState 不执行，需主动刷新）
    if (_loadingDone && !_loading && mounted) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await _api.overview(routeId: widget.routeId);
      Map<String, dynamic>? mot;
      Map<String, dynamic>? fit;
      try {
        mot = await _motApi.state(routeId: widget.routeId);
      } catch (_) {}
      try {
        fit = await _reviewApi.fit(routeId: widget.routeId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _data = d;
        _motivation = mot;
        _fit = fit;
        _loading = false;
        _loadingDone = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _loadingDone = true;
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
            title: '学习分析',
            subtitle: '健康度 · 掌握分布 · 保持 · 校准',
            actions: [
              IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _load),
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
    final d = _data!;
    final health = (d['health_score'] ?? 0) as int;
    final dist = (d['mastery_distribution'] as Map?)?.cast<String, dynamic>() ?? {};
    final total = (d['total_nodes'] ?? 12) as int;
    final avgRet = d['avg_retention'];
    final dueCount = (d['due_count'] ?? 0) as int;
    final cal = (d['calibration'] as Map?)?.cast<String, dynamic>() ?? {};
    final errs = (d['error_breakdown'] as Map?)?.cast<String, dynamic>() ?? {};
    final ability = (d['ability_radar'] as Map?)?.cast<String, dynamic>() ?? {};
    final weakest = (d['weakest_dim'] as Map?)?.cast<String, dynamic>() ?? {};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_motivation != null) AnimatedEntrance(child: MotivationBanner(state: _motivation!)),
        AnimatedEntrance(child: _healthCard(health, d)),
        const SizedBox(height: 12),
        AnimatedEntrance(
          delayMs: 60,
          child: _sectionCard('掌握度分布', [
            ..._levelLabels.entries.map((e) {
              final cnt = (dist[e.key] ?? 0) as int;
              final ratio = total == 0 ? 0.0 : cnt / total;
              final color = _levelColors[e.key] ?? AppColors.brand;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(
                      width: 56,
                      child: Text(e.value, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600))),
                  Expanded(
                    child: AnimatedBar(value: ratio, height: 8, color: color),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 24,
                    child: Text('$cnt', textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12, color: AppColors.ink500, fontWeight: FontWeight.w600)),
                  ),
                ]),
              );
            }),
          ]),
        ),
        const SizedBox(height: 12),
        AnimatedEntrance(
          delayMs: 100,
          child: _sectionCard('记忆与复习', [
            _kv('平均记忆保持率', avgRet == null ? '—' : '${(avgRet * 100).toStringAsFixed(0)}%'),
            _kv('到期积压', '$dueCount 项'),
            _kv('累计作答', '${d['total_attempts'] ?? 0} 题'),
            _kv('平均得分', d['avg_score'] == null ? '—' : '${((d['avg_score'] as num) * 100).toStringAsFixed(0)}%'),
          ]),
        ),
        const SizedBox(height: 12),
        AnimatedEntrance(delayMs: 140, child: _calibrationCard(cal)),
        const SizedBox(height: 12),
        AnimatedEntrance(
          delayMs: 180,
          child: _sectionCard('错因分布', errs.isEmpty
              ? [const Text('暂无明显错误，继续保持', style: TextStyle(fontSize: 12, color: AppColors.ink500))]
              : errs.entries.map((e) {
                  final label = _errName(e.key);
                  return _kv(label, '${e.value} 次');
                }).toList()),
        ),
        const SizedBox(height: 12),
        AnimatedEntrance(
          delayMs: 220,
          child: _sectionCard('能力短板', [
            _kv('最弱维度', weakest['dim'] == null ? '—' : '${_dimLabels[weakest['dim']] ?? weakest['dim']}'),
            _kv('短板得分', weakest['score'] == null ? '—' : '${((weakest['score'] as num) * 100).toStringAsFixed(0)}%'),
            const SizedBox(height: 8),
            ...ability.entries.map((e) {
              final v = (e.value as num).toDouble();
              final low = (weakest['dim'] == e.key);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(width: 88, child: Text(_dimLabels[e.key] ?? e.key, style: const TextStyle(fontSize: 12))),
                  Expanded(child: AnimatedBar(value: v, height: 7, color: low ? AppColors.danger : AppColors.brand)),
                  const SizedBox(width: 8),
                  Text('${(v * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              );
            }),
          ]),
        ),
        const SizedBox(height: 12),
        AnimatedEntrance(delayMs: 260, child: _fitCard()),
        const SizedBox(height: 24),
        _dataManageCard(),
      ],
    );
  }

  /// 数据管理：本机数据清除入口（使用说明里承诺的「应用内可重置进度」）。
  Widget _dataManageCard() {
    return _sectionCard('数据管理', [
      const Text(
        '学习进度、作答记录、掌握度、复习计划与学情信号都存于本机。'
        '如需清空重来，可重置学习进度（阅读笔记与原文标注不受影响，操作不可恢复）。',
        style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.ink500),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _busyReset ? null : _resetProgress,
        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
        label: const Text('重置学习进度'),
      ),
    ]);
  }

  Future<void> _resetProgress() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置学习进度？'),
        content: const Text(
          '将清除：掌握度、章节进度、作答记录、测验记录、复习计划与学情信号。\n\n'
          '阅读笔记、划线与书签**不会**被清除。此操作不可恢复，建议先到「本机数据」页复制一份备份。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认重置')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyReset = true);
    try {
      await LocalDb.resetAll();
      // 清掉离线待同步队列：重置前的事件若回灌会把旧进度又写回来。
      await SyncController.clearQueue();
      // 清缓存：重置后各接口要立刻返回空数据，而不是命中重置前的缓存。
      ApiClient.invalidatePrefix();
      if (!mounted) return;
      setState(() => _busyReset = false);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyReset = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('重置失败：$e')));
    }
  }

  Widget _fitCard() {
    final fit = _fit;
    if (fit == null) return const SizedBox.shrink();
    final available = fit['available'] == true;
    final cur = (fit['current'] as Map?)?.cast<String, dynamic>() ?? {};
    final sug = (fit['suggested'] as Map?)?.cast<String, dynamic>() ?? {};
    return _sectionCard('复习参数自校准（FSRS）', [
      if (!available)
        Text('${fit['message'] ?? '样本不足，继续积累复习记录'}',
            style: const TextStyle(fontSize: 12, color: AppColors.ink500))
      else ...[
        _kv('复习成功率', '${((fit['succ_rate'] ?? 0) * 100).toStringAsFixed(0)}%'),
        _kv('当前 gain', '${cur['gain']}'),
        _kv('建议 gain', '${sug['gain']}'),
        const SizedBox(height: 4),
        Text('${fit['note'] ?? ''}', style: const TextStyle(fontSize: 12, color: AppColors.ink700)),
      ],
      const SizedBox(height: 4),
      const Text('说明：基于你的真实复习日志估计记忆增益，仅给建议不自动改配置。',
          style: TextStyle(fontSize: 10, color: AppColors.ink400)),
    ]);
  }

  Widget _healthCard(int health, Map<String, dynamic> d) {
    // 无作答/无评估时健康度没有意义：不显示 0 分（刺眼）也不显示虚高分，
    // 直接给「—」并提示先做一次章节测试。
    final hasData = d['has_data'] == true;
    final color = !hasData
        ? AppColors.ink400
        : health >= 75
            ? AppColors.success
            : health >= 50
                ? AppColors.warning
                : AppColors.danger;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.soft,
      ),
      padding: const EdgeInsets.all(18),
      child: Row(children: [
        AnimatedProgressRing(
          value: hasData ? health / 100 : 0,
          size: 92,
          strokeWidth: 10,
          color: color,
          center: hasData
              ? CountUp(
                  value: health,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color),
                )
              : Text('—',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('学习健康度', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text('已评估 ${d['assessed_nodes'] ?? 0}/${d['total_nodes'] ?? 0} 个知识点 · 连续学习 ${d['streak_days'] ?? 0} 天',
                style: const TextStyle(fontSize: 12, color: AppColors.ink700)),
            const SizedBox(height: 4),
            Text(
                hasData
                    ? '掌握面 40% · 长期保持 25% · 元认知校准 15% · 近期正确 20%（无数据的维度不计入，权重按剩余维度归一）'
                    : '还没有作答记录：先做一次章节测试，健康度就会开始计算（无数据的维度不计分）',
                style: const TextStyle(fontSize: 11, color: AppColors.ink400, height: 1.4)),
          ]),
        ),
      ]),
    );
  }

  Widget _calibrationCard(Map<String, dynamic> cal) {
    final verdict = cal['verdict'] ?? 'unknown';
    final color = verdict == 'overconfident'
        ? AppColors.danger
        : verdict == 'underconfident'
            ? AppColors.brand
            : verdict == 'calibrated'
                ? AppColors.success
                : AppColors.ink500;
    final label = {
      'overconfident': '元认知：偏高估',
      'underconfident': '元认知：偏低估',
      'calibrated': '元认知：校准良好',
      'unknown': '元认知：数据不足',
    }[verdict];
    final icon = verdict == 'calibrated'
        ? Icons.verified
        : verdict == 'unknown'
            ? Icons.help_outline
            : Icons.tune;
    return _sectionCard(
      '元认知校准',
      [Text('${cal['tip'] ?? ''}', style: const TextStyle(fontSize: 12, height: 1.5))],
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text('$label', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _sectionCard(String title, List<Widget> children, {Widget? trailing}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.soft,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 4,
              height: 15,
              decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            ?trailing,
          ]),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text(k, style: const TextStyle(fontSize: 13, color: AppColors.ink500)),
        const Spacer(),
        Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
