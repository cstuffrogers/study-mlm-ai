// 浮动会话窗（替代底部 Sheet）—— 浮在正文之上，可拖到任意位置、贴边不越界。
//
// 设计要点：
// - 只有「头部标题栏」负责拖动，正文列表可正常滚动、输入框可正常输入，互不抢手势。
// - 位置用 Offset 存于 State，拖动仅重建本浮层（不重建下方阅读页），无抖动。
// - 性能红线：无 Timer / 无常驻动画，只有 onPanUpdate 触发的 setState。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/message.dart';
import '../services/chat_service.dart';
import '../theme/app_theme.dart';
import 'chat_markdown.dart';
import 'instant_summary_card.dart';
import 'related_original_button.dart';
import 'speak_button.dart';

/// 通用可移动方块：整体可拖动、边界内钳制、纯点击不受影响（用于选中文字后的追问工具条）。
class MovableBox extends StatefulWidget {
  final Widget child;
  final Offset initialOffset;
  final Size bounds;
  final Size size;
  const MovableBox({
    super.key,
    required this.child,
    required this.initialOffset,
    required this.bounds,
    required this.size,
  });

  @override
  State<MovableBox> createState() => _MovableBoxState();
}

class _MovableBoxState extends State<MovableBox> {
  late Offset _pos = _clamp(widget.initialOffset);

  Offset _clamp(Offset p) {
    final maxX = (widget.bounds.width - widget.size.width - 8).clamp(0.0, double.infinity);
    final maxY = (widget.bounds.height - widget.size.height - 8).clamp(0.0, double.infinity);
    return Offset(p.dx.clamp(8.0, maxX), p.dy.clamp(8.0, maxY));
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _pos.dx,
      top: _pos.dy,
      width: widget.size.width,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _pos = _clamp(_pos + d.delta)),
        child: Material(color: Colors.transparent, child: widget.child),
      ),
    );
  }
}

/// 浮动会话窗本体。
class FloatingChat extends StatefulWidget {
  final List<ChatTurn> turns;
  final String status;
  final bool criticalReading;
  final VoidCallback onToggleCritical;
  final void Function(String text) onSend;
  final VoidCallback onClear;
  final VoidCallback onClose;
  // 会话请求状态：等待回复 / 失败重试。缺省关闭，保持旧调用点/测试兼容。
  /// 「相关原文」跳转：由宿主页面接管（先撤浮窗 → 打开原文 → 回来恢复浮窗）。
  final Future<void> Function(List<String> ids)? onOpenOriginal;

  /// 「配置在线大模型」入口：未配 Key 时告诉用户怎么开启模型作答。
  final VoidCallback? onOpenLlmConfig;

  final bool pending;
  final String? error;
  final VoidCallback? onRetry;
  final Offset initialOffset;
  final Size bounds;
  final Size size;

  const FloatingChat({
    super.key,
    required this.turns,
    required this.status,
    required this.criticalReading,
    required this.onToggleCritical,
    required this.onSend,
    required this.onClear,
    required this.onClose,
    this.onOpenOriginal,
    this.onOpenLlmConfig,
    this.pending = false,
    this.error,
    this.onRetry,
    required this.initialOffset,
    required this.bounds,
    required this.size,
  });

  @override
  State<FloatingChat> createState() => _FloatingChatState();
}

class _FloatingChatState extends State<FloatingChat> {
  late Offset _pos = _clamp(widget.initialOffset);
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// 上一次参与布局的面板高度（高度变了就重新贴底）。
  double? _lastPanelH;

  Offset _clamp(Offset p) {
    final maxX = (widget.bounds.width - widget.size.width - 8).clamp(0.0, double.infinity);
    final maxY = (widget.bounds.height - widget.size.height - 8).clamp(0.0, double.infinity);
    return Offset(p.dx.clamp(8.0, maxX), p.dy.clamp(8.0, maxY));
  }

  @override
  void initState() {
    super.initState();
    // 浮窗每次打开都是**新建 State**：`_scroll` 偏移量从 0 开始，而 svc.turns 里
    // 可能已经有一串历史（选中原文追问时，用户那句话甚至已经进了 turns）。
    // 旧实现只在「条数变化」时才贴底，于是打开瞬间看到的是最早那几句，
    // 得自己往下拖（用户实报）。这里首帧就贴底。
    _pinToBottomSoon();
  }

  /// 连续几帧贴底：首帧就能拿到 maxScrollExtent，但 Markdown/「相关原文」卡片
  /// 的高度常在后续帧才落定，只跳一次会停在倒数第二条。
  void _pinToBottomSoon({int frames = 3}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      if (frames > 1) _pinToBottomSoon(frames: frames - 1);
    });
  }

  @override
  void didUpdateWidget(covariant FloatingChat old) {
    super.didUpdateWidget(old);
    if (widget.turns.length != old.turns.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
        }
      });
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 键盘弹起时必须把浮窗抬到键盘上方：浮窗挂在 Overlay 里，不参与
    // Scaffold 的 resizeToAvoidBottomInset，旧实现于是一直停在原位——
    // 输入框被键盘压住，用户看不到自己正在打的字（用户实报）。
    // 屏幕放不下时同步压缩高度，保证「输入框 + 至少几行对话」始终可见。
    final double insets = MediaQuery.viewInsetsOf(context).bottom;
    final double availH = MediaQuery.sizeOf(context).height - insets;
    final double panelH = insets <= 0
        ? widget.size.height
        : math.min(widget.size.height, math.max(availH - 24, 220.0));
    if (_lastPanelH != panelH) {
      // 键盘弹出/收起会改变可视高度：接着贴底，别让用户再拖一次。
      _lastPanelH = panelH;
      _pinToBottomSoon();
    }
    double top = _pos.dy;
    if (insets > 0) {
      final double maxTop = math.max(availH - panelH - 8, 8.0);
      if (top > maxTop) top = maxTop;
    }
    return Positioned(
      left: _pos.dx,
      top: top,
      width: widget.size.width,
      height: panelH,
      child: Material(
        color: Colors.white,
        elevation: 14,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _header(),
            Expanded(
              child: widget.turns.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(
                                color: AppColors.brandSoft, shape: BoxShape.circle),
                            child: const Icon(Icons.touch_app_outlined,
                                size: 26, color: AppColors.brand),
                          ),
                          const SizedBox(height: 10),
                          const Text('拖动标题栏可移动 · 选中原文唤起 AI',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.ink400, fontSize: 12)),
                          if (widget.onOpenLlmConfig != null) ...[
                            const SizedBox(height: 6),
                            const Text('当前为本机检索引擎：回答是原文逐字摘录，不是模型生成。',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.ink400, fontSize: 11.5)),
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: widget.onOpenLlmConfig,
                              child: const Text('接入在线大模型（填 API Key）',
                                  style: TextStyle(fontSize: 11.5)),
                            ),
                          ],
                        ]),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(10),
                      itemCount: widget.turns.length,
                      itemBuilder: (_, i) => _turn(widget.turns[i], i),
                    ),
            ),
            if (widget.pending || widget.error != null) _stateBar(),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  // 头部：整行可拖动；右侧关闭按钮点击优先（tap 与 pan 由手势竞技场区分）。
  Widget _header() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) => setState(() => _pos = _clamp(_pos + d.delta)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        child: Row(
          children: [
            const Icon(Icons.drag_indicator, size: 18, color: Colors.white70),
            const SizedBox(width: 4),
            Expanded(
              child: Text(widget.status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, color: Colors.white.withValues(alpha: 0.9))),
            ),
            // 模式选择已移到输入框左侧（与「这次提问怎么回答」放在一起），
            // header 只保留引擎状态与全局开关，避免两处都能改模式且窄屏互挤。
            // 批判性阅读开关：图标 + 文字 + 开/关状态，避免只靠 tooltip 才能看懂。
            // 点开后仅对「之后发送」的问题生效；再点一次关闭。
            Tooltip(
              message: widget.criticalReading
                  ? '批判性阅读：已开启。涉及非正统概念时以「指出其错误」的批判姿态呈现，再点一次关闭'
                  : '批判性阅读：已关闭。点此开启（仅涉及非正统概念时生效）',
              child: InkWell(
                onTap: widget.onToggleCritical,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: widget.criticalReading
                        ? const Color(0xFFFCA5A5).withValues(alpha: 0.28)
                        : Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: widget.criticalReading
                            ? const Color(0xFFFCA5A5)
                            : Colors.white.withValues(alpha: 0.45)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.swap_horiz, size: 16,
                        color: widget.criticalReading
                            ? const Color(0xFFFCA5A5) : Colors.white),
                    const SizedBox(width: 3),
                    Text(widget.criticalReading ? '批判 开' : '批判 关',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Deng',
                            fontFamilyFallback: const ['Deng', 'Roboto', 'WarnSym'],
                            color: widget.criticalReading
                                ? const Color(0xFFFFE4E4) : Colors.white)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 2),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              iconSize: 18,
              tooltip: '清空会话',
              icon: const Icon(Icons.delete_outline, color: Colors.white70),
              onPressed: widget.onClear,
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              iconSize: 20,
              tooltip: '收起',
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }

  Widget _turn(ChatTurn t, int index) {
    final modeColor = ChatMode.values
        .firstWhere((m) => m.name == t.mode, orElse: () => ChatMode.chat)
        .color;

    if (t.role == 'user') {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8, left: 30),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(3),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Flexible(
                  child: Text(t.content,
                      style: const TextStyle(color: Colors.white, fontSize: 13))),
              const SizedBox(width: 4),
              SpeakButton(
                id: 'fc-user-$index',
                compact: true,
                onDark: true,
                color: Colors.white,
                text: ChatMarkdown.toSpeech(t.content),
              ),
            ]),
            if (t.selectedText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                    '锚点: «${t.selectedText.length > 26 ? '${t.selectedText.substring(0, 26)}…' : t.selectedText}»',
                    style: const TextStyle(color: Color(0xFFFDE7C9), fontSize: 9.5)),
              ),
          ]),
        ),
      );
    }

    final isBlocked = t.role == 'blocked';
    return Container(
      margin: const EdgeInsets.only(bottom: 8, right: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(3),
          topRight: Radius.circular(12),
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        border: Border(left: BorderSide(color: Color(modeColor), width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (isBlocked)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              border: Border.all(color: const Color(0xFFFECACA)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.block, color: Color(0xFFE11D48), size: 15),
                SizedBox(width: 4),
                Text('防偏离拦截',
                    style: TextStyle(
                        color: Color(0xFFB91C1C),
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ]),
              const SizedBox(height: 3),
              Text(t.content,
                  style: const TextStyle(color: Color(0xFF7F1D1D), fontSize: 12.5)),
              if (t.blockedReason != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('原因: ${t.blockedReason}',
                      style: const TextStyle(fontSize: 10.5, color: Color(0xFFB91C1C))),
                ),
              if (t.allowCriticalReading)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                      '↔ 可点标题栏「批判 开」开启批判性阅读，再点「重试」重新提问；'
                      '该开关会以指出错误的方式呈现非正统概念。',
                      style: TextStyle(fontSize: 10.5, height: 1.4,
                          color: Color(0xFFB91C1C))),
                ),
            ]),
          )
        else ...[
          // 每条回答都标明「这条是哪个模式生成的」：不能只靠左边细线的颜色去猜，
          // 尤其曾经有两个模式同色，用户根本分不出。
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Color(modeColor).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                    ChatMode.values
                        .firstWhere((m) => m.name == t.mode,
                            orElse: () => ChatMode.chat)
                        .label,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: Color(modeColor),
                        fontFamily: 'Deng',
                        fontFamilyFallback: const ['Deng', 'Roboto', 'WarnSym'])),
              ),
              if (t.engine.isNotEmpty) ...[
                const SizedBox(width: 5),
                Icon(
                    t.engine.startsWith('cloud')
                        ? Icons.cloud_done_rounded
                        : Icons.offline_bolt_rounded,
                    size: 12,
                    color: AppColors.ink400),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(_engineLabel(t.engine, t.engineNote),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.ink400)),
                ),
              ],
            ]),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            SpeakButton(
              id: 'fc-ai-$index-${t.mode}',
              compact: true,
              text: ChatMarkdown.toSpeech(t.content),
            ),
          ]),
          ChatMarkdown(text: t.content, baseColor: AppColors.ink900),
        ],
        if (t.instantSummary != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: InstantSummaryCard(
              oneLine: t.instantSummary!['one_line'] ?? '',
              checkQuestion: t.instantSummary!['check_question'] ?? '',
            ),
          ),
        if (_relatedIds(t).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: RelatedOriginalButton(
              chunkIds: _relatedIds(t),
              onOpen: widget.onOpenOriginal,
            ),
          ),
      ]),
    );
  }

  /// 回答来源（本机引擎 / 在线模型），让用户知道 API Key 是否真的生效。
  /// 本机引擎还要区分「没配」和「配了但调用失败」——否则用户无从判断。
  String _engineLabel(String engine, String note) {
    if (engine.startsWith('cloud:')) {
      return '在线模型 · ${engine.substring('cloud:'.length)}';
    }
    // 联网版同一提问二次提问会命中服务端精确缓存，回答不重算但也不是本机答的
    if (engine == 'cache') return '缓存回答（同一提问此前生成过）';
    if (engine == 'cloud') return '在线模型';
    if (engine == 'local:guard-fallback') return '本机引擎（在线回答被立场层拦截）';
    if (note == 'not-configured') return '本机检索引擎 · 未配置 API Key（回答为原文摘录）';
    if (note == 'empty-reply') return '本机引擎（在线模型返回空正文）';
    if (note.startsWith('failed:')) {
      return '本机引擎（在线模型失败：${note.substring('failed:'.length)}）';
    }
    return '本机引擎';
  }

  /// 等待 / 错误状态条：后端慢或失败时浮窗里必须有可见反馈，而不是「点了没反应」。
  Widget _stateBar() {
    if (widget.pending) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        color: AppColors.brandSoft,
        child: const Row(children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text('正在生成回复…请先读原文，稍候片刻',
                style: TextStyle(fontSize: 11.5, color: AppColors.ink700)),
          ),
        ]),
      );
    }
    final err = widget.error ?? '请求失败';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: const Color(0xFFFEF2F2),
      child: Row(children: [
        const Icon(Icons.error_outline, size: 16, color: Color(0xFFB91C1C)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(err,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF7F1D1D))),
        ),
        if (widget.onRetry != null)
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: widget.onRetry,
            child: const Text('重试', style: TextStyle(fontSize: 11.5)),
          ),
      ]),
    );
  }

  /// 正文里的内部编码 + RAG 溯源卡片合并为一个「相关原文」入口。
  List<String> _relatedIds(ChatTurn t) {
    final ids = <String>{};
    final out = <String>[];
    void add(String? id) {
      final v = (id ?? '').trim();
      if (v.isNotEmpty && ids.add(v)) out.add(v);
    }

    for (final id in t.sourceChunks) {
      add(id);
    }
    for (final id in ChatMarkdown.chunkIdsIn(t.content)) {
      add(id);
    }
    for (final c in t.provenance) {
      add(c.chunkId);
    }
    return out;
  }

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _input,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: ChatMode.chat.inputHint,
              isDense: true,
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            ),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) {
                widget.onSend(v.trim());
                _input.clear();
              }
            },
          ),
        ),
        const SizedBox(width: 6),
        Container(
          decoration: const BoxDecoration(
              gradient: AppColors.brandGradient, shape: BoxShape.circle),
          child: IconButton(
            iconSize: 18,
            constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.send, color: Colors.white, size: 18),
            onPressed: () {
              final v = _input.text.trim();
              if (v.isNotEmpty) {
                widget.onSend(v);
                _input.clear();
              }
            },
          ),
        ),
      ]),
    );
  }
}
