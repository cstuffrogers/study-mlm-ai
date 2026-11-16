// 章节导读页 — 路线 → 章节正文/导读加载 + 知识点清单 + 进入章节测试
// 数据来自 GET /api/routes/{route}/sections/{section}/guide
// （原始著作全文未随仓库提供：本页展示权威「学习导读」，非原著正文；
//   sec_A_02《提纲》可跳转三层阅读器看全文分片）
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/content_service_api.dart';
import '../services/mastery_service_api.dart';
import '../services/chat_service.dart';
import '../services/sync_service_api.dart';
import '../models/message.dart';
import '../widgets/chunk_tag.dart';
import '../widgets/chat_markdown.dart';
import '../widgets/speak_button.dart';
import '../widgets/floating_chat.dart';
import '../widgets/related_original_button.dart';
import '../widgets/selection_ask_box.dart';
import '../services/open_url.dart';
import '../widgets/anim.dart';
import '../widgets/author_art.dart';
import '../theme/app_theme.dart';
import 'chapter_test.dart';
import 'llm_config_screen.dart';
import 'work_reader_screen.dart';

class ChapterGuideScreen extends StatefulWidget {
  final String routeId;
  final String sectionId;
  final String sectionTitle;
  final bool hasBank;
  const ChapterGuideScreen({
    super.key,
    required this.routeId,
    required this.sectionId,
    required this.sectionTitle,
    this.hasBank = true,
  });

  @override
  State<ChapterGuideScreen> createState() => _ChapterGuideScreenState();
}

class _ChapterGuideScreenState extends State<ChapterGuideScreen> {
  Map<String, dynamic>? _guide;
  List<dynamic> _nodes = const [];
  List<dynamic> _extensions = const [];
  String _localWork = '';
  // 章节 → 真实原文分片的只读链接索引（后端 source_links）：
  // {chapter: {...}, nodes: [...], blocks: {...}}
  Map<String, dynamic> _sourceLinks = const {};
  Map<String, dynamic> _profile = const {};
  bool _loading = true;
  String? _error;

  // 朗读 / 提问浮窗状态
  bool _sheetOpen = false;
  ChatService? _chatSvc;
  VoidCallback? _chatListener;
  OverlayEntry? _chatEntry;

  // 选中正文后的释义浮框状态。
  // _selected 只保存「最后一次有效选区」：点击释义/追问 chip 时浏览器/Flutter
  // 会先清空选区，若此时同步清空 _selected，onAsk 就会把空锚点发给后端。
  String _selected = '';

  void _onSelectionChanged(SelectedContent? sel) {
    final t = (sel?.plainText ?? '').trim();
    // 与 work_reader_screen 一致：忽略空选区，只接受 <800 字的新锚点。
    // 关闭选区由 _dismissSelection() 显式完成，不再被 onSelectionChanged(null) 抢跑。
    if (t.isNotEmpty && t.length < 800 && t != _selected) {
      setState(() => _selected = t);
    }
  }

  void _dismissSelection() {
    if (_selected.isEmpty) return;
    setState(() => _selected = '');
  }

  void _copySelection() {
    if (_selected.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _selected));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制选中文本'), duration: Duration(seconds: 1)),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (_chatListener != null && _chatSvc != null) {
      _chatSvc!.removeListener(_chatListener!);
    }
    _chatEntry?.remove();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final j = await ContentApi().guide(widget.routeId, widget.sectionId);
      setState(() {
        _guide = (j['guide'] as Map?)?.cast<String, dynamic>();
        _nodes = (j['nodes'] as List?) ?? const [];
        _extensions = (j['extensions'] as List?) ?? const [];
        _localWork = (j['local_work'] ?? '').toString();
        _sourceLinks = (j['source_links'] as Map?)?.cast<String, dynamic>() ?? const {};
        _loading = false;
      });
      // 学情档案用于「该加强哪部分理解」提醒（失败不阻断导读）
      MasteryApi()
          .profile(routeId: widget.routeId)
          .then((p) {
            if (!mounted) return;
            setState(
              () => _profile = {
                'weak_points': p.weakPoints
                    .map(
                      (w) => {
                        'node_id': w.nodeId,
                        'name': w.name,
                        'level': w.level,
                        'score': w.score,
                      },
                    )
                    .toList(),
              },
            );
          })
          .catchError((_) {});
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  // ==================== 对话浮窗 / 朗读 ====================
  void _openChat() {
    final svc = context.read<ChatService>();
    _openFloatingChat(svc);
  }

  void _askWith(String text, ChatMode mode) {
    // 锚点用调用方捕获的快照；空锚点不发请求，避免后端收到 selected_text: ""。
    final anchor = text.trim();
    if (anchor.isEmpty) return;
    final svc = context.read<ChatService>();
    svc.switchMode(mode);
    svc.send(content: '请就这段导读展开${mode.label}', selectedText: anchor);
    _dismissSelection();
    _openFloatingChat(svc);
  }

  /// 未配 API Key 时从浮窗直达「AI 对话引擎」配置页。
  Future<void> _openLlmConfig() async {
    _closeChat();
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => const LlmConfigScreen()));
  }

  void _openFloatingChat(ChatService svc) {
    if (_sheetOpen) return;
    final overlay = Overlay.of(context);
    final size = MediaQuery.of(context).size;
    final w = (size.width - 64).clamp(280.0, 372.0);
    final h = (size.height * 0.62).clamp(300.0, 560.0);
    final entry = OverlayEntry(
      builder: (_) => FloatingChat(
        turns: svc.turns,
        status: svc.status,
        currentMode: svc.currentMode,
        criticalReading: svc.criticalReading,
        onModeChanged: svc.switchMode,
        onToggleCritical: svc.toggleCriticalReading,
        onSend: (t) => svc.send(content: t),
        onClear: svc.clear,
        onClose: _closeChat,
        onOpenOriginal: _openRelatedOriginal,
        onOpenLlmConfig: _openLlmConfig,
        pending: svc.pending,
        error: svc.lastError,
        onRetry: svc.retryLast,
        initialOffset: Offset(size.width - w - 16, 96),
        bounds: size,
        size: Size(w, h),
      ),
    );
    _chatListener = () {
      if (entry.mounted) entry.markNeedsBuild();
    };
    _chatSvc = svc..addListener(_chatListener!);
    overlay.insert(entry);
    _chatEntry = entry;
    setState(() => _sheetOpen = true);
  }

  /// 「相关原文」跳转：先撤下浮窗（它在 Overlay 之上会压住原文页），读完再恢复。
  Future<void> _openRelatedOriginal(List<String> ids) async {
    final svc = context.read<ChatService>();
    final nav = Navigator.of(context, rootNavigator: true);
    _closeChat();
    await showRelatedOriginalsFrom(nav, ids);
    if (!mounted) return;
    _openFloatingChat(svc);
  }

  void _closeChat() {
    if (_chatListener != null && _chatSvc != null) {
      _chatSvc!.removeListener(_chatListener!);
    }
    _chatEntry?.remove();
    _chatEntry = null;
    _chatListener = null;
    if (mounted) setState(() => _sheetOpen = false);
  }

  // 整页导读的朗读文本（标题/著者/背景/概念/正文/要点/思考题/知识点/延伸阅读）
  // 页面只保留标题处一枚啪叭：点一下即可把整页读完；长文由 tts 自动分段续播。
  String _chapterSpeech(Map<String, dynamic> g) {
    final parts = <String>[];
    final title = (g['title'] ?? widget.sectionTitle).toString();
    final work = (g['work'] ?? '').toString();
    final author = (g['work_author'] ?? '').toString();
    if (title.isNotEmpty) parts.add(title);
    if (work.isNotEmpty) parts.add(work);
    if (author.isNotEmpty) parts.add('著者：$author');

    final bg = (g['background'] ?? '').toString();
    if (bg.isNotEmpty) parts.add('写作背景。$bg');

    final concepts = (g['core_concepts'] as List?) ?? const [];
    if (concepts.isNotEmpty) parts.add('核心概念。');
    for (final c in concepts) {
      final l = (c as List?) ?? const [];
      if (l.isNotEmpty) parts.add('${l[0]}：${l.length > 1 ? l[1] : ''}');
    }

    final sections = (g['sections'] as List?) ?? const [];
    if (sections.isNotEmpty) parts.add('正文导读。');
    for (final s in sections) {
      final m = (s as Map?) ?? const {};
      parts.add('${m['heading'] ?? ''}。${m['body'] ?? ''}');
    }

    final keyPoints = (g['key_points'] as List?) ?? const [];
    if (keyPoints.isNotEmpty) parts.add('要点提炼。');
    for (final k in keyPoints) {
      parts.add(k.toString());
    }

    final discussion = (g['discussion'] as List?) ?? const [];
    if (discussion.isNotEmpty) parts.add('思考题。');
    for (final k in discussion) {
      parts.add(k.toString());
    }

    if (_nodes.isNotEmpty) {
      parts.add('本章知识点。');
      for (final n in _nodes) {
        final m = (n as Map?) ?? const {};
        final name = (m['name'] ?? '').toString();
        final def = (m['definition'] ?? '').toString();
        if (name.isNotEmpty) parts.add(def.isEmpty ? name : '$name：$def');
      }
    }

    if (_extensions.isNotEmpty) {
      parts.add('延伸阅读，选学，不计入掌握度。');
      for (final e in _extensions) {
        final m = (e as Map?) ?? const {};
        final t = (m['title'] ?? '').toString();
        if (t.isEmpty) continue;
        final a = (m['author'] ?? '').toString();
        final intro = (m['intro'] ?? '').toString();
        final kind = (m['kind'] ?? 'classic').toString();
        parts.add(
          kind == 'contested'
              ? '批判对象，非借鉴。$t。$a。${stripExtensionMarkup(intro)}'
              : '$t。$a。${stripExtensionMarkup(intro)}',
        );
      }
    }

    final note = (g['source_note'] ?? '').toString();
    if (note.isNotEmpty) parts.add(note);

    return ChatMarkdown.toSpeech(parts.join('。'));
  }

  // 滚动到「正文导读」+ 闪一下高亮，回应「该读哪部分原文」
  void _scrollToReading() {
    final ctx = _readingKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
        alignment: 0.02,
      );
    }
  }

  final GlobalKey _readingKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    // 面板构造时捕获锚点快照：点击 chip 触发选区清空后，onAsk 仍拿到这段文本。
    final selectedText = _selected;
    return Scaffold(
      backgroundColor: const Color(0xFFFBF7F5),
      appBar: AppBar(
        title: Text(
          widget.sectionTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_localWork.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.menu_book),
              tooltip: '看原文全文',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WorkReaderScreen(
                    work: _localWork,
                    title: widget.sectionTitle,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: AuroraBackground(
        child: LayoutBuilder(
          builder: (context, cons) {
            final bodySize = Size(cons.maxWidth, cons.maxHeight);
            return Stack(
              children: [
                Positioned.fill(child: _buildBody()),
                // 选中正文后的「释义/追问」浮框（选中出现，可拖动）
                if (selectedText.isNotEmpty)
                  MovableBox(
                    key: ValueKey('sel-${widget.sectionId}-${selectedText.length}'),
                    bounds: bodySize,
                    size: const Size(360, 118),
                    initialOffset: Offset(
                      ((bodySize.width - 360) / 2).clamp(8.0, double.infinity),
                      (bodySize.height - 300).clamp(8.0, double.infinity),
                    ),
                    child: SelectionAskPanel(
                      text: selectedText,
                      speakId:
                          'sel-lect-${widget.sectionId}-${selectedText.length}',
                      onCopy: _copySelection,
                      onDismiss: _dismissSelection,
                      onAsk: (m) => _askWith(selectedText, m),
                    ),
                  ),
                // 自由浮动的对话按钮（可任意拖动；点开 AI 会话浮窗；窗开时隐藏，用窗内「收起」关闭）
                if (!_sheetOpen)
                  MovableChatFab(
                    initialOffset: Offset(
                      (bodySize.width - 72).clamp(8.0, double.infinity),
                      (bodySize.height - 84).clamp(8.0, double.infinity),
                    ),
                    bounds: bodySize,
                    onTap: _openChat,
                  ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: _buildActionBar(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: AppColors.ink400,
                size: 40,
              ),
              const SizedBox(height: 10),
              Text(
                '加载导读失败：$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.ink500),
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    final g = _guide ?? {};
    if (g.isEmpty) {
      return const Center(
        child: Text('该章暂无导读内容', style: TextStyle(color: AppColors.ink400)),
      );
    }
    final concepts = (g['core_concepts'] as List?) ?? const [];
    final keyPoints = (g['key_points'] as List?) ?? const [];
    final discussion = (g['discussion'] as List?) ?? const [];
    final sections = (g['sections'] as List?) ?? const [];
    final links = _sourceLinks;
    final nodeLinks = (links['nodes'] as List?) ?? const [];
    final blockLinks = (links['blocks'] as Map?)?.cast<String, dynamic>() ?? const {};
    final chapterLink = (links['chapter'] as Map?)?.cast<String, dynamic>() ?? const {};

    return SelectionArea(
      // 选中任意导读正文 → 浮出「释义/追问」浮框（与原文阅读器一致的交互）
      onSelectionChanged: _onSelectionChanged,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
        children: [
          _headerCard(g),
          const SizedBox(height: 14),
          _reminderCard(g, chapterLink),
          const SizedBox(height: 14),
          if ((g['background'] ?? '').toString().isNotEmpty) ...[
            _sectionTitle('写作背景', '写作背景'),
            _prose(g['background'].toString(), id: 'bg',
                link: blockLinks['background'] is Map
                    ? (blockLinks['background'] as Map).cast<String, dynamic>() : null),
            const SizedBox(height: 14),
          ],
          if (concepts.isNotEmpty) ...[
            _sectionTitle('核心概念', '核心概念'),
            ...concepts.asMap().entries.map((e) => _conceptTile(e.value,
                link: _linkAt(blockLinks['concepts'], e.key))),
            const SizedBox(height: 10),
          ],
          if (sections.isNotEmpty) ...[
            _sectionTitle('正文导读', '正文导读', key: _readingKey),
            ...sections.asMap().entries.map((e) => _bodyBlock(e.value,
                link: _linkAt(blockLinks['sections'], e.key))),
            const SizedBox(height: 6),
          ],
          if (keyPoints.isNotEmpty) ...[
            _sectionTitle('要点提炼', '要点提炼'),
            ...keyPoints.asMap().entries.map((e) => _bullet(e.value.toString(),
                AppColors.brand, link: _linkAt(blockLinks['key_points'], e.key))),
            const SizedBox(height: 10),
          ],
          if (discussion.isNotEmpty) ...[
            _sectionTitle('思考题（可用于会话演练）', '思考题'),
            ...discussion.asMap().entries.map(
              (e) => _bullet(
                e.value.toString(),
                AppColors.ink400,
                icon: Icons.help_outline,
                link: _linkAt(blockLinks['discussion'], e.key),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (_nodes.isNotEmpty) ...[
            _sectionTitle('本章知识点（掌握度判定依据）', '本章知识点'),
            ..._nodes.asMap().entries.map((e) => _nodeChip(
                (e.value as Map).cast<String, dynamic>(),
                link: _linkAt(nodeLinks, e.key))),
          ],
          if (_extensions.isNotEmpty) ...[
            const SizedBox(height: 18),
            _extensionsSection(),
          ],
          if ((g['source_note'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                g['source_note'].toString(),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.ink400,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _headerCard(Map<String, dynamic> g) {
    final author = (g['work_author'] ?? '').toString();
    final art = authorArtFor(author);
    return AnimatedEntrance(
      child: GradientCard(
        radius: AppRadius.hero,
        gradient: AppColors.heroGradient,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: art == null ? 0 : 104),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: EdgeInsets.only(right: art == null ? 0 : 86),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SpeakButton(
                          id: 'guide-head-${widget.sectionId}',
                          compact: true,
                          onDark: true,
                          text: _chapterSpeech(g),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.auto_stories,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            (g['work'] ?? '').toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      (g['title'] ?? widget.sectionTitle).toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (author.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '著者：$author',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // 红白人物像：按著者贴右上角（马/恩/列/斯/毛/周/托）。
              // 最后绘制，完整叠在红底上，不被文字层遮挡。
              if (art != null)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: AuthorArt(asset: art, height: 104),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // AI 学习导航卡：告诉你「该读哪部分原文」+「该加强哪部分理解」
  Widget _reminderCard(Map<String, dynamic> g, Map<String, dynamic> chapterLink) {
    final sections = (g['sections'] as List?) ?? const [];
    final readParts = <String>[];
    for (final s in sections) {
      final h = ((s as Map?) ?? const {})['heading']?.toString() ?? '';
      if (h.isNotEmpty) readParts.add(h);
    }
    final nodeNameById = <String, String>{};
    for (final n in _nodes) {
      final m = (n as Map);
      nodeNameById[m['id']?.toString() ?? ''] = m['name']?.toString() ?? '';
    }
    final weakNames = <String>[];
    for (final w in (_profile['weak_points'] as List?) ?? const []) {
      final m = (w as Map?) ?? const {};
      final id = m['node_id']?.toString() ?? '';
      final lvl = m['level']?.toString() ?? 'unseen';
      if (nodeNameById.containsKey(id) &&
          lvl != 'mastered' &&
          lvl != 'proficient') {
        weakNames.add(nodeNameById[id]!);
      }
    }
    // 没有学情命中时，把本章前两个知识点作为“重点验证”对象
    if (weakNames.isEmpty) {
      weakNames.addAll(nodeNameById.values.take(2));
    }

    final readText = readParts.isEmpty
        ? '从「正文导读」开始通读'
        : '先读「正文导读」：${readParts.join('、')}';
    final learnText = weakNames.isEmpty
        ? '本章暂无知识点，先通读要点'
        : '重点加强理解：${weakNames.take(3).join('、')}';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.brand.withValues(alpha: 0.06),
            AppColors.gold.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.explore_rounded,
                size: 17,
                color: AppColors.brand,
              ),
              const SizedBox(width: 6),
              const Text(
                '学习导航',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _navRow(
            icon: Icons.menu_book_rounded,
            tint: AppColors.brand,
            label: '该读哪部分原文',
            text: readText,
            actionLabel: '定位',
            onAction: _scrollToReading,
          ),
          _chapterLinkRow(chapterLink),
          const SizedBox(height: 8),
          _navRow(
            icon: Icons.trending_up_rounded,
            tint: AppColors.gold,
            label: '该加强哪部分理解',
            text: learnText,
            actionLabel: '去补',
            onAction: () => _askWith(
              '请针对「${weakNames.take(3).join('、')}」帮我查漏补缺，指出我容易混淆的地方',
              ChatMode.dig,
            ),
          ),
        ],
      ),
    );
  }

  Widget _navRow({
    required IconData icon,
    required Color tint,
    required String label,
    required String text,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: tint),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: tint,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                text,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: AppColors.ink700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            minimumSize: const Size(0, 28),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onAction,
          child: Text(
            actionLabel,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: tint,
            ),
          ),
        ),
      ],
    );
  }

  // 章节主文通读入口：点开本章第一段原文分片。
  Widget _chapterLinkRow(Map<String, dynamic>? chapter) {
    final cid = (chapter?['first_chunk_id'] ?? '').toString();
    if (cid.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ChunkTag(chunkId: cid, compact: true,
          tooltip: '本章著作在正文库中的第一段，可由此核对原文'),
    );
  }

  /// 取链接列表第 i 项（后端按正文顺序逐条给出）。
  Map<String, dynamic>? _linkAt(dynamic list, int i) {
    if (list is! List || i >= list.length) return null;
    final m = list[i];
    return m is Map ? m.cast<String, dynamic>() : null;
  }

  /// 「溯源 / 相关原文」小型标签。
  /// kind=authoritative → 内容表逐条标注的权威分片；
  /// kind=related → 按板块文字在本章原文中只读检索到的相关片段（非逐条权威溯源）。
  Widget _linkChip(Map<String, dynamic>? link, {String? fallbackText}) {
    final cid = (link?['chunk_id'] ?? '').toString();
    final kind = (link?['kind'] ?? '').toString();
    if (cid.isEmpty) {
      if (link == null || kind != 'none') return const SizedBox.shrink();
      // 明确告诉用户为什么这条没有链接，而不是「莫名消失」。
      return Tooltip(
        message: (link['reason'] ?? '').toString().isEmpty
            ? '导读型知识点：未逐条标注原文出处'
            : link['reason'].toString(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.ink400.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.line),
          ),
          child: const Text('无链接',
              style: TextStyle(fontSize: 10.5, color: AppColors.ink400)),
        ),
      );
    }
    return ChunkTag(
      chunkId: cid,
      fallbackText: fallbackText,
      compact: true,
      tooltip: kind == 'related'
          ? '相关原文片段（关键词检索，非逐条权威溯源）'
          : '已标注原著对应位置',
    );
  }

  Widget _linkRow(Map<String, dynamic>? link, {String? fallbackText}) {
    final cid = (link?['chunk_id'] ?? '').toString();
    if (cid.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _linkChip(link, fallbackText: fallbackText),
    );
  }

  Widget _sectionTitle(String t, String ttsId, {Key? key}) => Padding(
    key: key,
    padding: const EdgeInsets.only(bottom: 8, top: 2),
    child: Row(
      children: [
        Container(
          width: 3,
          height: 15,
          color: AppColors.brand,
          margin: const EdgeInsets.only(right: 8),
        ),
        Expanded(
          child: Text(
            t,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.ink700,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _prose(String text, {required String id, Map<String, dynamic>? link}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            height: 1.75,
            color: AppColors.ink700,
          ),
        ),
        _linkRow(link),
      ],
    ),
  );

  Widget _conceptTile(dynamic c, {Map<String, dynamic>? link}) {
    final list = (c as List?) ?? const [];
    final name = list.isNotEmpty ? list[0].toString() : '';
    final desc = list.length > 1 ? list[1].toString() : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: AppColors.ink700,
            ),
          ),
          _linkRow(link),
        ],
      ),
    );
  }

  Widget _bodyBlock(dynamic s, {Map<String, dynamic>? link}) {
    final m = (s as Map?) ?? const {};
    final heading = (m['heading'] ?? '').toString();
    final body = (m['body'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  heading,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 14,
              height: 1.8,
              color: AppColors.ink700,
            ),
          ),
          _linkRow(link),
        ],
      ),
    );
  }

  Widget _bullet(
    String text,
    Color color, {
    IconData icon = Icons.check_circle_outline,
    Map<String, dynamic>? link,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.6,
                  color: AppColors.ink700,
                ),
              ),
              _linkRow(link),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _nodeChip(Map<String, dynamic> n, {Map<String, dynamic>? link}) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.hub_outlined, size: 16, color: AppColors.brand),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                n['name']?.toString() ?? '',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink700,
                ),
              ),
            ),
            _linkChip(link ??
                ((n['source_chunk_id'] ?? '').toString().isNotEmpty
                    ? <String, dynamic>{
                        'kind': 'authoritative',
                        'chunk_id': n['source_chunk_id'].toString(),
                      }
                    : null),
                fallbackText: n['definition']?.toString()),
          ],
        ),
        if ((n['definition'] ?? '').toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 24),
            child: Text(
              n['definition'].toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppColors.ink400,
              ),
            ),
          ),
      ],
    ),
  );

  // ==================== 延伸阅读（扩展读物·分档） ====================
  static const _kindColor = <String, Color>{
    'classic': Color(0xFF15803D), // 绿：经典原文
    'historical': Color(0xFFB45309), // 橙：历史文献
    'private': Color(0xFF1D4ED8), // 蓝：私人版本/民间理论（非官方）
    'contested': Color(0xFFB91C1C), // 红：争议版本·仅供批判
  };
  static const _kindLabel = <String, String>{
    'classic': '经典原文 / 权威文献',
    'historical': '历史文献 / 实践经验',
    'private': '私人版本 · 民间理论（非官方）',
    'contested': '争议版本 · 仅供批判',
  };

  Widget _extensionsSection() {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final e in _extensions) {
      final m = (e as Map).cast<String, dynamic>();
      final k = (m['kind'] ?? 'classic').toString();
      groups.putIfAbsent(k, () => []).add(m);
    }
    const order = ['classic', 'historical', 'private', 'contested'];
    final ordered = order.where((k) => groups.containsKey(k)).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.library_books_outlined,
                size: 18,
                color: AppColors.gold,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '延伸阅读（选学·不计入掌握度）',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.only(left: 26, bottom: 6),
            child: Text(
              '主线之外的可选读物，按正统性与敏感性分档标注；绿色可正面学、红色仅供批判。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppColors.ink400,
              ),
            ),
          ),
          ...ordered.expand(
            (k) => [
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: _kindHeader(k, groups[k]!.length),
              ),
              ...groups[k]!.map((m) => _extensionCard(m)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kindHeader(String kind, int n) {
    final color = _kindColor[kind] ?? AppColors.ink500;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Text(
            '${_kindLabel[kind] ?? kind} · $n',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _extensionCard(Map<String, dynamic> m) {
    final kind = (m['kind'] ?? 'classic').toString();
    final isContested = kind == 'contested';
    final color = _kindColor[kind] ?? AppColors.ink500;
    final points = (m['points'] as List?) ?? const [];
    final title = (m['title'] ?? '').toString();
    final author = (m['author'] ?? '').toString();
    final intro = (m['intro'] ?? '').toString();
    final howto = (m['how_to_use'] ?? '').toString();
    final caution = (m['caution'] ?? '').toString();
    final link = (m['link'] ?? '').toString();
    final localWork = (m['local_work'] ?? '').toString();

    // 供朗读/渲染：争议版本用【批判对象·非借鉴】包裹，让 ChatMarkdown 渲染成红框
    final pointMd = points.map((p) => '- ${p.toString()}').join('\n');
    final bodyMd = isContested
        ? '【批判对象·非借鉴】\n**$title**（$author）\n\n$intro\n\n$pointMd\n【/批判对象】'
        : ([
            if (intro.isNotEmpty) intro,
            if (pointMd.isNotEmpty) pointMd,
          ].join('\n\n'));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isContested ? const Color(0xFFFFF7F7) : const Color(0xFFFBFBFA),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: isContested ? const Color(0xFFFECACA) : AppColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题（整页朗读统一走顶部喇叭，卡片内不再重复放喇叭）
          Text(
            title,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: isContested ? const Color(0xFF991B1B) : AppColors.ink700,
            ),
          ),
          if (author.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                author,
                style: const TextStyle(fontSize: 11.5, color: AppColors.ink400),
              ),
            ),
          const SizedBox(height: 8),
          // 正文（Markdown 渲染；争议版本自动变红框）
          ChatMarkdown(text: bodyMd, baseColor: AppColors.ink700),
          // 怎么用
          if (howto.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.tips_and_updates_outlined,
                    size: 14,
                    color: AppColors.gold,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.55,
                          color: AppColors.ink500,
                          fontFamily: 'Deng',
                          fontFamilyFallback: ['Deng', 'Roboto', 'WarnSym'],
                        ),
                        children: [
                          const TextSpan(
                            text: '怎么用：',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          ...extensionMarkupSpans(
                            howto,
                            const TextStyle(
                              fontSize: 12,
                              height: 1.55,
                              color: AppColors.ink500,
                              fontFamily: 'Deng',
                              fontFamilyFallback: ['Deng', 'Roboto', 'WarnSym'],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // 注意（private/contested）
          if (caution.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 14, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.5,
                          color: color,
                          fontFamily: 'Deng',
                          fontFamilyFallback: const ['Deng', 'Roboto', 'WarnSym'],
                        ),
                        children: extensionMarkupSpans(
                          caution,
                          TextStyle(
                            fontSize: 11.5,
                            height: 1.5,
                            color: color,
                            fontFamily: 'Deng',
                            fontFamilyFallback: const ['Deng', 'Roboto', 'WarnSym'],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // 阅读原文：经典条目优先进「本机知识库」阅读器；无本地正文时才降级到外部权威文库。
          if (localWork.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 0,
                  ),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(
                  Icons.menu_book_rounded,
                  size: 14,
                  color: AppColors.brand,
                ),
                label: const Text(
                  '阅读原文',
                  style: TextStyle(fontSize: 12, color: AppColors.brand),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        WorkReaderScreen(work: localWork, title: title),
                  ),
                ),
              ),
            )
          else if (link.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 0,
                  ),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(
                  Icons.open_in_new,
                  size: 14,
                  color: AppColors.brand,
                ),
                label: const Text(
                  '阅读原文（权威文库）',
                  style: TextStyle(fontSize: 12, color: AppColors.brand),
                ),
                onPressed: () => openExternal(link),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _loading || _error != null ? null : _onPrimaryAction,
                icon: Icon(
                  widget.hasBank
                      ? Icons.quiz_outlined
                      : Icons.check_circle_outline,
                ),
                label: Text(widget.hasBank ? '学完导读，开始章节测试' : '已通读，标记本章完成'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onPrimaryAction() async {
    if (widget.hasBank) {
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ChapterTestScreen(
            routeId: widget.routeId,
            sectionId: widget.sectionId,
            sectionTitle: widget.sectionTitle,
          ),
        ),
      );
      if (changed == true && mounted) Navigator.pop(context, true);
    } else {
      try {
        await SyncApi().saveProgress(
          widget.sectionId,
          1,
          routeId: widget.routeId,
          status: 'completed',
        );
      } catch (_) {}
      if (mounted) Navigator.pop(context, true);
    }
  }
}

// ==================== 延伸阅读文案的 Markdown 清理 ====================

/// 延伸阅读的「注意 / 怎么用」是普通 `Text` 渲染（不走 Markdown），但内容层为了
/// 强调在 `caution` 里写了 `**节选声明**` 这类标记——直接上屏就会露出星号。
///
/// 两条路：① 改数据（去掉全部 `**`）② 渲染前剥掉标记只留文字。
/// 这里选 ②：`caution` 里强调的「节选声明」「篇名与构成须声明」对读者是有效分级，
/// 数据侧保留完整标记，显示时按 `**` 分段并让被标记部分加粗，既不出星号也不丢重点。
///
/// 与 `ChatMarkdown` 的 `strong` 保持一致（w700），并且只处理成对的 `**`；
/// 落单的 `**` 原样保留（宁可露出两个星号，也不要吞掉正文）。
List<TextSpan> extensionMarkupSpans(String text, TextStyle base) {
  final spans = <TextSpan>[];
  final re = RegExp(r'\*\*(.+?)\*\*', dotAll: true);
  var start = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > start) {
      spans.add(TextSpan(text: text.substring(start, m.start), style: base));
    }
    spans.add(TextSpan(
      text: m.group(1) ?? '',
      style: base.copyWith(fontWeight: FontWeight.w700),
    ));
    start = m.end;
  }
  if (start < text.length) {
    spans.add(TextSpan(text: text.substring(start), style: base));
  }
  return spans;
}

/// 剥掉全部 Markdown 强调标记，用于朗读与纯文本场合（不朗读星号）。
String stripExtensionMarkup(String text) =>
    text.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*', dotAll: true), (m) => m.group(1) ?? '');
