// 功能中心 →「AI 对话引擎」配置页。
//
// 单机版也支持接入在线大模型：填 API Key + Base URL + 模型（OpenAI 兼容）后，
// 对话改由该模型作答；不填则用本机检索式引擎。凭证只写本机，不上传。
// 无论哪种引擎，输出都要过本机立场层（LocalGuard），偏离表述照样拦。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/llm_config_api.dart';
import '../services/llm_config_store.dart';
import '../theme/app_theme.dart';
import '../widgets/anim.dart';

class LlmConfigScreen extends StatefulWidget {
  const LlmConfigScreen({super.key});

  @override
  State<LlmConfigScreen> createState() => _LlmConfigScreenState();
}

class _LlmConfigScreenState extends State<LlmConfigScreen> {
  final _keyCtrl = TextEditingController();
  final _baseCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _concurrentCtrl = TextEditingController();
  final _retriesCtrl = TextEditingController();
  final _timeoutCtrl = TextEditingController();
  final _interactiveCtrl = TextEditingController();
  final _maxTokensCtrl = TextEditingController();

  Map<String, dynamic>? _status;
  Map<String, dynamic>? _test;
  bool _disableThinking = true;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _keyCtrl,
      _baseCtrl,
      _modelCtrl,
      _concurrentCtrl,
      _retriesCtrl,
      _timeoutCtrl,
      _interactiveCtrl,
      _maxTokensCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _numText(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    final d = v is num ? v.toDouble() : double.tryParse('$v');
    if (d == null) return '$v';
    return d == d.roundToDouble() ? '${d.toInt()}' : '$d';
  }

  Future<void> _load({bool fresh = true}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await LlmConfigApi.status(fresh: fresh);
      if (!mounted) return;
      setState(() {
        _status = data;
        _baseCtrl.text = '${data['base_url'] ?? ''}';
        _modelCtrl.text = '${data['model'] ?? ''}';
        _concurrentCtrl.text = _numText(data['max_concurrent'], '3');
        _retriesCtrl.text = _numText(data['max_retries'], '2');
        _timeoutCtrl.text = _numText(data['timeout'], '60');
        _interactiveCtrl.text = _numText(data['interactive_timeout'], '30');
        _maxTokensCtrl.text = _numText(data['max_tokens'], '2048');
        _disableThinking = data['disable_thinking'] != false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _applyPreset(String key, Map<String, dynamic> preset) {
    setState(() {
      _baseCtrl.text = '${preset['base_url'] ?? ''}';
      _modelCtrl.text = '${preset['model'] ?? ''}';
      _notice = '已填入「${(preset['label'] ?? key)}」的端点与模型，密钥仍需自己填';
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final data = await LlmConfigApi.save({
        'api_key': _keyCtrl.text.trim(),
        'base_url': _baseCtrl.text.trim(),
        'model': _modelCtrl.text.trim(),
        'max_concurrent': _concurrentCtrl.text.trim(),
        'max_retries': _retriesCtrl.text.trim(),
        'timeout': _timeoutCtrl.text.trim(),
        'interactive_timeout': _interactiveCtrl.text.trim(),
        'max_tokens': _maxTokensCtrl.text.trim(),
        'disable_thinking': _disableThinking,
      });
      if (!mounted) return;
      _keyCtrl.clear();
      setState(() {
        _status = data;
        _saving = false;
        _notice = data['configured'] == true
            ? '已保存，下一次提问即走在线大模型'
            : '已保存；密钥未填写，仍用本机引擎作答';
        _test = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('ApiException(400): ', '');
        _saving = false;
      });
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _test = null;
      _error = null;
    });
    try {
      final data = await LlmConfigApi.test();
      if (!mounted) return;
      setState(() {
        _test = data;
        _testing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _test = {'ok': false, 'message': '$e'};
        _testing = false;
      });
    }
  }

  Future<void> _clearKey() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空 API Key'),
        content: const Text('清空后对话回到本机检索式引擎（不联网）。确定清空？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      final data = await LlmConfigApi.clear();
      if (!mounted) return;
      setState(() {
        _status = data;
        _saving = false;
        _test = null;
        _notice = '已清空密钥，当前使用本机引擎';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status ?? const <String, dynamic>{};
    final configured = s['configured'] == true;
    final presets = (s['presets'] as Map?) ?? const {};
    final labels = (s['preset_labels'] as Map?) ?? const {};

    return Scaffold(
      appBar: AppBar(title: const Text('AI 对话引擎')),
      body: AuroraBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                children: [
                  AnimatedEntrance(child: _modeBanner(configured, s)),
                  // 自愈告知：本机设置文档上次没读完整（升级装包时进程被杀、
                  // 写到一半被截断），密钥已从独立副本自动恢复——必须说出来，
                  // 否则用户会把「升级后 AI 用不了」当成又要重新配一遍。
                  if (LlmConfigStore.restoredFromShadow) ...[
                    const SizedBox(height: 10),
                    _messageCard('本机设置文件上次没读完整（多半是升级装包时被中断），'
                        'AI 配置已从独立副本自动恢复，不用重新填写。建议点一下「测试连接」确认可用。'),
                  ],
                  const SizedBox(height: 14),
                  AnimatedEntrance(child: _presetCard(presets, labels)),
                  const SizedBox(height: 14),
                  AnimatedEntrance(child: _formCard()),
                  const SizedBox(height: 14),
                  AnimatedEntrance(child: _actions()),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _messageCard(_error!, danger: true),
                  ],
                  if (_notice != null) ...[
                    const SizedBox(height: 12),
                    _messageCard(_notice!),
                  ],
                  if (_test != null) ...[
                    const SizedBox(height: 12),
                    _testCard(_test!),
                  ],
                ],
              ),
      ),
    );
  }

  // ---------------------------------------------------------- 分区
  // 卡片里的 SwitchListTile 会自己画背景与水波纹，而水波纹只能画在最近的 Material 上：
  // 直接放进带背景色的 Container 会遮住点击反馈（Debug 下 Flutter 会直接报错）。
  // 因此统一在卡片内部垫一层透明 Material。
  Widget _card({required Widget child, Color? tint}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tint ?? Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.line.withValues(alpha: 0.8)),
        ),
        child: Material(type: MaterialType.transparency, child: child),
      );

  Widget _modeBanner(bool configured, Map<String, dynamic> s) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: configured
            ? const LinearGradient(
                colors: [Color(0xFF0F5132), Color(0xFF16A34A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight)
            : AppColors.heroGradient,
        borderRadius: BorderRadius.circular(AppRadius.hero),
      ),
      child: Row(children: [
        Icon(configured ? Icons.cloud_done_rounded : Icons.offline_bolt_rounded,
            color: Colors.white, size: 26),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(configured ? '在线大模型已启用' : '当前：本机引擎',
                style: const TextStyle(
                    color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              configured
                  ? '模型：${s['model']}  ·  密钥：${s['masked_api_key']}'
                  : '不联网、无密钥，回答由原文检索 + 概念卡 + 苏格拉底追问生成',
              style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 6),
            Text('${s['note'] ?? ''}',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 11.5, height: 1.5)),
          ]),
        ),
        if (configured)
          IconButton(
            tooltip: '清空密钥',
            onPressed: _saving ? null : _clearKey,
            icon: const Icon(Icons.key_off_outlined, color: Colors.white),
          ),
      ]),
    );
  }

  Widget _presetCard(Map presets, Map labels) {
    if (presets.isEmpty) return const SizedBox.shrink();
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Icon(Icons.bolt_rounded, size: 18, color: AppColors.gold),
          SizedBox(width: 6),
          Text('端点速查（只填地址与模型，不涉及密钥）',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        ]),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in presets.entries)
              ActionChip(
                label: Text('${labels[e.key] ?? e.key}'),
                onPressed: () => _applyPreset(e.key, (e.value as Map).cast()),
              ),
          ],
        ),
      ]),
    );
  }

  Widget _formCard() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('连接信息',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 12),
        TextField(
          controller: _keyCtrl,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\x20-\x7e]'))],
          decoration: InputDecoration(
            labelText: 'API Key',
            hintText: _status?['api_key_set'] == true ? '已保存，留空表示不修改' : 'sk-…',
            helperText: '只存本机，不上传；留空 = 保留已保存的密钥',
            prefixIcon: const Icon(Icons.key_rounded, size: 18),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _baseCtrl,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Base URL（OpenAI 兼容端点）',
            hintText: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
            prefixIcon: Icon(Icons.link_rounded, size: 18),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _modelCtrl,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: '模型名称',
            hintText: 'qwen-plus / deepseek-chat / glm-4-flash …',
            prefixIcon: Icon(Icons.memory_rounded, size: 18),
          ),
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _disableThinking,
          onChanged: (v) => setState(() => _disableThinking = v),
          title: const Text('关闭思维链（推理型模型建议开启）',
              style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('不关会把 max_tokens 吃光、正文为空且耗时 80s+',
              style: TextStyle(fontSize: 11.5)),
        ),
        const Divider(height: 20),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 4),
          title: const Text('高级参数（一般不用改）',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          children: [
            _numField(_concurrentCtrl, '并发上限', '1–16'),
            const SizedBox(height: 10),
            _numField(_retriesCtrl, '失败重试次数', '0–5'),
            const SizedBox(height: 10),
            _numField(_timeoutCtrl, '单次超时（秒）', '3–180'),
            const SizedBox(height: 10),
            _numField(_interactiveCtrl, '对话超时（秒）', '3–120'),
            const SizedBox(height: 10),
            _numField(_maxTokensCtrl, '单次生成上限（tokens）', '128–8192'),
          ],
        ),
      ]),
    );
  }

  Widget _numField(TextEditingController c, String label, String range) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        decoration: InputDecoration(
          labelText: label,
          helperText: '范围 $range',
          isDense: true,
        ),
      );

  Widget _actions() => Row(children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(_saving ? '保存中…' : '保存并生效'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _testing ? null : _testConnection,
            icon: _testing
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_tethering_rounded, size: 18),
            label: Text(_testing ? '测试中…' : '测试连接'),
          ),
        ),
      ]);

  Widget _messageCard(String text, {bool danger = false}) => _card(
        tint: danger ? AppColors.brandSoft.withValues(alpha: 0.5) : Colors.white,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(danger ? Icons.error_outline : Icons.check_circle_outline,
              size: 18, color: danger ? AppColors.danger : AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: danger ? AppColors.danger : AppColors.ink700)),
          ),
        ]),
      );

  Widget _testCard(Map<String, dynamic> t) {
    final ok = t['ok'] == true;
    return _card(
      tint: ok ? AppColors.goldSoft.withValues(alpha: 0.6) : AppColors.brandSoft.withValues(alpha: 0.45),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 18, color: ok ? AppColors.success : AppColors.danger),
          const SizedBox(width: 6),
          Text(ok ? '连接成功' : '连接失败',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: ok ? AppColors.success : AppColors.danger)),
          const Spacer(),
          if (t['elapsed_ms'] != null)
            Text('${t['elapsed_ms']} ms',
                style: const TextStyle(fontSize: 11.5, color: AppColors.ink400)),
        ]),
        const SizedBox(height: 6),
        Text('${t['message'] ?? ''}',
            style: const TextStyle(fontSize: 12.5, height: 1.5)),
        if ('${t['model'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('模型：${t['model']}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.ink500)),
          ),
        if ('${t['preview'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('返回预览：${t['preview']}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.ink500)),
          ),
      ]),
    );
  }
}
