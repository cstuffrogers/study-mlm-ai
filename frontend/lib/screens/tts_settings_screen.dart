// 功能中心 →「语音包设置」页：朗读风格预设 + 系统中文语音包选择 + 试听。
//
// 口径（务必如实，不要夸大）：
//  · 「温柔女声 / 广播员男声 / 甜美女声 / 高亢有力的男声」是**音调 + 语速**的组合，
//    不是把男声变女声。真正的音色来自系统里装的语音包，本机没装女声包就选不出女声。
//  · 系统（Android TextToSpeech）不提供可靠的性别字段，页面不编造「女声 / 男声」标签，
//    只列引擎实际装了什么（语言显示名 + 内部名），把选择权交给用户。
//  · 试听与正式朗读走同一条通道（ttsSpeak），所以听到的就是点喇叭后的效果。
import 'package:flutter/material.dart';

import '../services/tts.dart';
import '../services/tts_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/anim.dart';

class TtsSettingsScreen extends StatefulWidget {
  const TtsSettingsScreen({super.key});

  @override
  State<TtsSettingsScreen> createState() => _TtsSettingsScreenState();
}

class _TtsSettingsScreenState extends State<TtsSettingsScreen> {
  static const String _sample =
      '全世界无产者，联合起来。人的正确思想是从哪里来的？是从天上掉下来的吗？不是。';

  final TtsSettings _s = TtsSettings.instance;

  bool _loading = true;
  List<TtsVoiceOption> _voices = const <TtsVoiceOption>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_s.loaded) await _s.load();
    final list = await ttsListVoices();
    if (!mounted) return;
    setState(() {
      _voices = list;
      _loading = false;
    });
  }

  Future<void> _pickPreset(TtsPreset p) async {
    await _s.setPreset(p.id);
    if (!mounted) return;
    setState(() {});
    _preview();
  }

  Future<void> _pickVoice(String name) async {
    final ok = await ttsSetVoice(name);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? (name.isEmpty ? '已恢复系统默认语音' : '已切换语音包') : '切换失败：本机语音引擎没接受这个语音'),
      duration: const Duration(seconds: 2),
    ));
    if (ok) _preview();
  }

  void _preview() {
    if (!ttsAvailable()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('本平台没有可用的语音引擎，朗读按钮不显示'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    ttsStop();
    ttsSpeak(_sample, id: 'tts_preview');
  }

  @override
  void dispose() {
    ttsStop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF7F5),
      appBar: AppBar(title: const Text('语音包设置')),
      body: AuroraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            AnimatedEntrance(child: _header()),
            const SizedBox(height: 14),
            AnimatedEntrance(child: _presetCard()),
            const SizedBox(height: 12),
            AnimatedEntrance(child: _voiceCard()),
            const SizedBox(height: 12),
            AnimatedEntrance(child: _noteCard()),
          ],
        ),
      ),
    );
  }

  Widget _header() => GradientCard(
        radius: AppRadius.hero,
        gradient: AppColors.heroGradient,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Row(children: [
          const Icon(Icons.record_voice_over_outlined, color: Colors.white, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Text('语音包与朗读风格',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              SizedBox(height: 3),
              Text('系统中文语音包 · 音调语速预设 · 即时试听',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
        ]),
      );

  Widget _card(String title, String subtitle, List<Widget> children) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.ink700)),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.ink400)),
            const SizedBox(height: 10),
            ...children,
          ]),
        ),
      );

  Widget _presetCard() {
    return _card('朗读风格', '改的是音调与语速；音色取决于选中的语音包', [
      for (final p in TtsPresets.all)
        _row(
          selected: _s.presetId == p.id,
          title: p.label,
          subtitle: p.hint,
          trailing: Text(
            '音调 ${p.pitch.toStringAsFixed(2)} · 语速 ${p.rate.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 11, color: AppColors.ink400),
          ),
          onTap: () => _pickPreset(p),
        ),
      const SizedBox(height: 4),
      _previewButton(),
    ]);
  }

  Widget _voiceCard() {
    final current = _s.voiceName;
    return _card('语音包', '列出本机语音引擎已装的中文语音（不装就只有系统默认那个）', [
      _row(
        selected: current.isEmpty,
        title: '自动优选（推荐）',
        subtitle: '按普通话优先的规则自动挑一个，通常是系统默认中文语音',
        onTap: () => _pickVoice(''),
      ),
      if (_loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        )
      else if (_voices.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text(
            '没读到中文语音包。安卓可在「设置 → 系统 → 语言和输入 → 文字转语音」里安装'
            '「Google 语音服务」等引擎的中文语音，回到本页下拉重试。',
            style: TextStyle(fontSize: 12, color: AppColors.ink400, height: 1.5),
          ),
        )
      else
        for (final v in _voices)
          _row(
            selected: current.isNotEmpty && current == v.name,
            title: v.label.isEmpty ? v.name : v.label,
            subtitle: '${v.locale}${v.network ? ' · 需联网合成' : ' · 本机离线'} · ${v.name}',
            onTap: () => _pickVoice(v.name),
          ),
      if (!_loading && _voices.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('重新读取语音包'),
          ),
        ),
    ]);
  }

  Widget _noteCard() => _card('说明', '为什么有的「女声」听起来还是男声', const [
    Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Text(
        '· 安卓系统 TTS 只能给你「已安装的语音包」，App 自己造不出音色。\n'
        '· 「温柔女声 / 甜美女声」是通过提高音调、放慢或加快语速得到的近似效果；'
        '本机只装了男声包时，选这两个仍会是男声——想要真女声，请先装中文女声语音包再回来选。\n'
        '· 系统不提供性别字段，所以本页不标注「男 / 女」，只显示语音包的真实名字。\n'
        '· Web 版朗读优先走浏览器语音，规则同上；安卓包的朗读完全离线，不联网。',
        style: TextStyle(fontSize: 12, color: AppColors.ink400, height: 1.6),
      ),
    ),
  ]);

  Widget _previewButton() => ValueListenableBuilder<String?>(
        valueListenable: ttsCurrent,
        builder: (context, current, _) {
          final playing = current == 'tts_preview';
          return SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: playing ? ttsStop : _preview,
              icon: Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
              label: Text(playing ? '停止试听' : '试听当前设置'),
            ),
          );
        },
      );

  Widget _row({
    required bool selected,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    // 底色交给 Material 画，Container 只留边框 —— 否则 InkWell 水波纹被盖住，
    // Debug 下直接 assert（D142 已知坑）。
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.brand.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.brand : AppColors.line,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? AppColors.brand : AppColors.ink400,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: selected ? AppColors.brandDeep : AppColors.ink700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 11, color: AppColors.ink400, height: 1.4)),
                ]),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing,
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
