// 三层阅读器 — 原文/注释/解析切换 + 概念高亮 + 选中文本唤起五模式工具栏
// 注释/解析层由后端 RAG 提供（会话中获取），前端阅读器默认显示原文层
// 概念高亮：本地内置核心术语列表

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import '../data/theses.dart';
import '../models/message.dart';
import '../services/mastery_service_api.dart';
import '../widgets/chapter_summary_sheet.dart';
import '../widgets/speak_button.dart';
import '../widgets/anim.dart';
import '../theme/app_theme.dart';
import 'chapter_test.dart';
import 'route_picker.dart';

// 本地高亮术语（与后端 concepts 对齐，标注红色 = 术语红线重点）
const _highlightTerms = {
  '实践': 0xFF10B981,
  '对象性活动': 0xFF10B981,
  '市民社会': 0xFFD4A017,
  '人的本质': 0xFFC8161D,
  '社会关系': 0xFFC8161D,
  '革命': 0xFFD4A017,
  '直观': 0xFFF59E0B,
};

class ReaderScreen extends StatefulWidget {
  final void Function(String selectedText, String paragraphId, ChatMode mode) onAsk;
  final ChatMode currentMode;
  const ReaderScreen({super.key, required this.onAsk, required this.currentMode});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  int _layer = 0; // 0原文 1注释 2解析（注释/解析层提示用户通过会话获取）
  String _selectedText = '';
  String _selectedPid = '';

  void _onSelectionChanged(SelectedContent? selection, String pid) {
    final t = (selection?.plainText ?? '').trim();
    if (t.isNotEmpty && t.length < 200) {
      setState(() { _selectedText = t; _selectedPid = pid; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('关于费尔巴哈的提纲'),
        actions: [
          IconButton(
            icon: const Icon(Icons.summarize_outlined),
            tooltip: '本章小结',
            onPressed: _showChapterSummary,
          ),
          ToggleButtons(
            isSelected: [_layer == 0, _layer == 1, _layer == 2],
            onPressed: (i) => setState(() => _layer = i),
            constraints: const BoxConstraints(minWidth: 56, minHeight: 36),
            children: const [Text('原文'), Text('注释'), Text('解析')],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AuroraBackground(
        child: Column(
          children: [
            Expanded(child: _buildBody()),
            if (_selectedText.isNotEmpty)
              AnimatedEntrance(offsetY: 40, duration: const Duration(milliseconds: 260), child: _buildToolbar()),
          ],
        ),
      ),
    );
  }

  // 章末小结：拉取学情总结 → 底部弹卡（要点 + 待巩固 + 去测试）
  Future<void> _showChapterSummary() async {
    Map<String, dynamic> summary = {};
    try {
      summary = await MasteryApi().summary(routeId: 'route_A', period: 'all');
    } catch (_) {}
    if (!mounted) return;
    final mastered = (summary['mastered'] as List?)?.cast<dynamic>() ?? const [];
    final reinforce = (summary['to_reinforce'] as List?)?.cast<dynamic>() ?? const [];
    final keyPoints = mastered.isNotEmpty
        ? mastered.take(5).map((e) => '已掌握：$e').toList()
        : <String>['实践是感性的人的活动', '人的本质是一切社会关系的总和', '问题在于改变世界'];
    final toReinforce = reinforce.map((e) => '$e 需巩固').toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChapterSummarySheet(
        keyPoints: keyPoints,
        toReinforce: toReinforce,
        onGoTest: () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(
              builder: (_) => const ChapterTestScreen(
                  routeId: 'route_A', sectionId: 'sec_A_02', sectionTitle: '提纲精读章 · 章节测试')));
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_layer != 0) {
      // 注释/解析层：提示用户选中原文唤起 AI，由会话返回 L3/L4 内容
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Icon(_layer == 1 ? Icons.notes : Icons.lightbulb, size: 48, color: const Color(0xFFC8161D)),
          const SizedBox(height: 12),
          Text(
            _layer == 1 ? '注释层' : '解析层',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '注释/解析内容由 AI 基于正典教材生成。请在「原文」层选中某条文本，'
            '点击下方五模式按钮唤起 AI，回答将携带 L3 注释与 L4 解析溯源。',
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: kTheses.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) return _buildIntroHeader();
        return AnimatedEntrance(
          delayMs: (i - 1) * 45,
          child: _buildThesis(kTheses[i - 1]),
        );
      },
    );
  }

  // 顶部导读卡：深蓝→靓紫渐变 + 光斑 + 统计小药丸
  Widget _buildIntroHeader() {
    return AnimatedEntrance(
      child: GradientCard(
        margin: const EdgeInsets.only(bottom: 14),
        border: true,
        radius: AppRadius.hero,
        gradient: AppColors.heroGradient,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.auto_stories, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('马克思 · 1845',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13)),
              const Spacer(),
              SpeakButton(
                  id: 'thesis-intro',
                  compact: true,
                  onDark: true,
                  text: '关于费尔巴哈的提纲。改变世界，而非解释世界。'
                      '选中任意一句原文，唤起五模式 AI 精读；术语已高亮。'
                      '完整三路线学习请点右下角「学习路线」。'),
              const SizedBox(width: 8),
              _pill('${kTheses.length} 条'),
            ]),
            const SizedBox(height: 10),
            const Text('改变世界，而非解释世界',
                style: TextStyle(
                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            const SizedBox(height: 6),
            Text('本文是「精读示例 · 提纲」：选中任意一句原文即可唤起五模式 AI 精读，术语已高亮、可点🔊朗读。完整三条学习路线请点右下角「学习路线」。',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 12.5, height: 1.5)),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const RoutePickerScreen())),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.route, size: 16, color: AppColors.brand),
                      const SizedBox(width: 6),
                      Text('进入三路线学习',
                          style: TextStyle(
                              color: AppColors.brand,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_forward_rounded, size: 15, color: AppColors.brand),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
      );

  // 概念高亮 span 缓存：术语高亮是静态的，正文不变则无需每次 build 重算。
  static final Map<String, List<InlineSpan>> _spanCache = {};

  Widget _buildThesis(Thesis th) {
    const accent = AppColors.brand;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.soft,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        // 用 Stack + Positioned 左侧色条替代 IntrinsicHeight+Row(stretch)：
        // IntrinsicHeight 会强制子树双 pass 布局（列表滚动/重绘时明显掉帧）；
        // Stack 尺寸只取决于内容，色条自动拉满高度，效果一致但零额外布局成本。
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 4, color: accent.withValues(alpha: 0.85)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
              child: Stack(
                children: [
                  // 大水印序号
                  Positioned(
                    right: -6,
                    top: -14,
                    child: Text(
                      '${th.index}',
                      style: TextStyle(
                        fontSize: 54,
                        fontWeight: FontWeight.w900,
                        color: AppColors.brand.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradient,
                            shape: BoxShape.circle,
                          ),
                          child: Text('${th.index}',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Text('第',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink700)),
                        Text('${th.index} 条',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink700)),
                        const Spacer(),
                        SpeakButton(
                            id: 'thesis-${th.paragraphId}',
                            compact: true,
                            text: th.text),
                      ]),
                      const SizedBox(height: 10),
                      SelectionArea(
                        onSelectionChanged: (s) => _onSelectionChanged(s, th.paragraphId),
                        child: _highlightedText(th.text),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 概念高亮渲染（带缓存）
  Widget _highlightedText(String text) {
    final spans = _spanCache.putIfAbsent(text, () {
      final out = <InlineSpan>[];
      int i = 0;
      while (i < text.length) {
        int? hitStart;
        String? hitTerm;
        for (final term in _highlightTerms.keys) {
          final idx = text.indexOf(term, i);
          if (idx >= 0 && (hitStart == null || idx < hitStart)) {
            hitStart = idx;
            hitTerm = term;
          }
        }
        if (hitStart == null) {
          out.add(TextSpan(text: text.substring(i)));
          break;
        }
        if (hitStart > i) out.add(TextSpan(text: text.substring(i, hitStart)));
        out.add(TextSpan(
          text: hitTerm,
          style: TextStyle(
            color: Color(_highlightTerms[hitTerm]!),
            fontWeight: FontWeight.bold,
          ),
        ));
        i = hitStart + hitTerm!.length;
      }
      return out;
    });
    // 必须用 Text.rich 而非裸 RichText：裸 RichText 不向祖先 SelectionArea
    // 注册可选区（SelectionRegistrar），导致长按/拖拽选不到文字、五模式工具栏弹不出。
    return Text.rich(TextSpan(style: DefaultTextStyle.of(context).style, children: spans));
  }

  // 选中后浮动五模式工具栏
  Widget _buildToolbar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.lift,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.format_quote, size: 14, color: AppColors.ink400),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                  '已选中: «${_selectedText.length > 40 ? '${_selectedText.substring(0, 40)}…' : _selectedText}»',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.ink500)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(
            children: ChatMode.values.map((m) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.5),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(m.color), Color(m.color).withValues(alpha: 0.82)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                            color: Color(m.color).withValues(alpha: 0.28),
                            blurRadius: 10,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          widget.onAsk(_selectedText, _selectedPid, m);
                          setState(() => _selectedText = '');
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Center(
                            child: Text(m.label,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
