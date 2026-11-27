// 本机原著「分页阅读器」——把已入库的原著正文按行精确分页（不是无限长的一页），
// 提供市面阅读器常见功能：翻页 / 目录跳转 / 页码跳转 / 字号缩放 / 复制 / 划线标色
// / 标签 / 笔记 / 书签 / 进度记忆（下次自动跳到上次页面）/ 会话（选区五模式 AI 精读，含「对话」）。
//
// 数据：GET /api/chunks/by_work/{work}（content_provider → book_chunks，内存）。
// 分页：用 TextPainter 逐行测量，精确切到「填满可视区」的行，杜绝滚动与内容丢失。
// 本地持久化：shared_preferences，按著作名分 key 存 进度/笔记/标签/书签/字号。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/message.dart';
import '../offline/local_store_keys.dart';
import '../offline/offline_content.dart';
import '../services/chat_service.dart';
import '../services/content_service_api.dart';
import '../services/reader_paginator.dart';
import '../services/reader_autoplay.dart';
import '../services/tts.dart';
import '../services/tts_autostop.dart';
import '../theme/app_theme.dart';
import 'chapter_guide_screen.dart';
import '../widgets/floating_chat.dart';
import '../widgets/related_original_button.dart';
import '../widgets/speak_button.dart';

// ─────────────────────────── 数据模型 ───────────────────────────

class _Bookmark {
  final int page;
  final String label;
  final int createdAt;
  _Bookmark(this.page, this.label, this.createdAt);
  Map<String, dynamic> toJson() => {'p': page, 'l': label, 't': createdAt};
  factory _Bookmark.fromJson(Map<String, dynamic> j) => _Bookmark((j['p'] as num).toInt(), (j['l'] ?? '').toString(), (j['t'] as num?)?.toInt() ?? 0);
}

class _Note {
  final int page;
  String note;
  String tag;
  int color;
  final int createdAt;
  _Note({required this.page, required this.note, required this.tag, required this.color, required this.createdAt});
  Map<String, dynamic> toJson() => {'p': page, 'n': note, 'g': tag, 'c': color, 't': createdAt};
  factory _Note.fromJson(Map<String, dynamic> j) => _Note(page: (j['p'] as num).toInt(), note: (j['n'] ?? '').toString(), tag: (j['g'] ?? '').toString(), color: (j['c'] as num?)?.toInt() ?? 0, createdAt: (j['t'] as num?)?.toInt() ?? 0);
}

// 划线/标色：段落级（para 段整段着色），同时记录选区区间用于列表展示
class _Highlight {
  final int page;
  final int para;
  final int start;
  final int end;
  int color;
  String label;
  String note;
  final int createdAt;
  _Highlight({required this.page, required this.para, required this.start, required this.end, required this.color, required this.label, this.note = '', required this.createdAt});
  Map<String, dynamic> toJson() => {'p': page, 'i': para, 's': start, 'e': end, 'c': color, 'l': label, 'n': note, 't': createdAt};
  factory _Highlight.fromJson(Map<String, dynamic> j) => _Highlight(page: (j['p'] as num).toInt(), para: (j['i'] as num).toInt(), start: (j['s'] as num).toInt(), end: (j['e'] as num).toInt(), color: (j['c'] as num?)?.toInt() ?? 0, label: (j['l'] ?? '').toString(), note: (j['n'] ?? '').toString(), createdAt: (j['t'] as num?)?.toInt() ?? 0);

  /// 悬停提示用的备注文本（笔记 / 标签二者之一）。
  String get memo => note.trim().isNotEmpty ? note.trim() : label.trim();
}

const _kColors = <int>[
  0xFFFFE08A, // 黄
  0xFFB9E6A8, // 绿
  0xFFAFD6F6, // 蓝
  0xFFF6B8C8, // 粉
  0xFFE5D4F7, // 紫
];

// ─────────────────────────── 屏幕 ───────────────────────────

class WorkReaderScreen extends StatefulWidget {
  final String work;
  final String title;

  /// 要直接定位到的原文分片（「相关原文」跳转用）。
  /// 打开后自动翻到该分片所在页，而不是回上次进度；找不到则按常规进度打开。
  final String? focusChunkId;

  /// 打开后要替用户发问的选文（来自原文卡片/溯源卡片里选中的话）。
  /// 会话浮窗全应用只有本页一份实现，别处想发问就把内容带到这里。
  final String? askText;

  /// 与 [askText] 配套的模式；为空时用释义。
  final String? askMode;
  const WorkReaderScreen(
      {super.key,
      required this.work,
      required this.title,
      this.focusChunkId,
      this.askText,
      this.askMode});

  @override
  State<WorkReaderScreen> createState() => _WorkReaderScreenState();
}

class _WorkReaderScreenState extends State<WorkReaderScreen> {
  static const _padding = EdgeInsets.fromLTRB(20, 12, 20, 12);

  bool _loading = true;
  String? _error;
  List<String> _paragraphs = const [];
  /// 待定位的段落下标（一次性，定位后清空，避免影响后续翻页/字号重排）
  int? _focusPara;

  /// 打开时带过来的待发问内容（只发一次，发完置空）。
  String? _pendingAsk;
  String? _pendingAskMode;

  ReaderDoc? _doc;
  Size? _docSize;
  // 系统字号缩放也参与分页，变了必须重排（否则缩放后仍是旧排版，末行被裁）
  TextScaler? _docScaler;
  double _fontSize = 18;
  final double _lineHeight = 1.9;
  int? _keepPage; // 重排后要停留的页
  bool _building = false;

  PageController? _pc;
  int _page = 0;

  // ── 自动连续发声（当前页循环 / 播到结束 / 播完再整篇循环）──
  /// 当前模式；null = 没开。
  ReaderAutoMode? _autoMode;
  /// 连续朗读正在念第几页（自动翻页以它为准）。
  int _autoPage = 0;
  /// 我们自己发起的那条朗读的 id（用来识别「被别的喇叭抢走」）。
  String? _autoId;
  /// 正在由我们切换页面/分段：此时 ttsCurrent 短暂为空属正常，不算被停止。
  bool _autoLinking = false;
  /// 连续朗读是否处于暂停态（暂停只停发声、保留进度，可继续）。
  bool _autoPaused = false;

  /// 兜底看门狗：不是所有厂商的语音引擎都会老实回调 onDone
  /// （小米/部分讯飞版本、离线包里都见过「读完不吭声」）。
  /// 只靠回调的话，那种机器上连续朗读就会「一页读完就彻底停住」。
  /// 这里按字数估个上限，超时当这一页念完处理 —— 宁可多翻一页，也不能装死。
  Timer? _autoWatchdog;

  String _selected = '';

  // 浮层：会话浮窗（可任意拖动的对话）
  bool _sheetOpen = false;
  ChatService? _chatSvc;
  VoidCallback? _chatListener;

  List<_Bookmark> _bookmarks = [];
  List<_Note> _notes = [];
  List<_Highlight> _highlights = [];

  /// 这本书在学习路线里出现在哪几章（离线索引 work_sections.json）。
  List<Map<String, dynamic>> _routeRows = const [];

  // 键名取自登记处（local_store_keys.dart）：升级版本时键必须一字不变，
  // 否则老用户的书签/笔记/划线/阅读进度会「凭空消失」。
  String _k(String suffix) => LocalStoreKeys.reader(widget.work, suffix);

  @override
  void initState() {
    super.initState();
    // 连续朗读要感知「朗读被停 / 被别的喇叭抢走」，只挂一个监听，别轮询。
    ttsCurrent.addListener(_onTtsChanged);
    // 神经语音回退到本机语音时，状态条要立刻更新出提示（不靠别的重绘捎带）。
    ttsNeuralFallback.addListener(_onTtsFallbackChanged);
    _load();
    _loadRouteIndex();
  }

  /// 反向索引：书 → 出现过的章节（主线主书在前，延伸阅读在后）。
  Future<void> _loadRouteIndex() async {
    await OfflineContent.ensureMeta();
    final rows = OfflineContent.sectionsOfWork(widget.work);
    if (!mounted || rows.isEmpty) return;
    setState(() => _routeRows = rows);
  }

  @override
  void dispose() {
    if (_chatListener != null && _chatSvc != null) {
      _chatSvc!.removeListener(_chatListener!);
    }
    ttsCurrent.removeListener(_onTtsChanged);
    ttsNeuralFallback.removeListener(_onTtsFallbackChanged);
    _autoWatchdog?.cancel();
    _autoWatchdog = null;
    // 离开原文页 = 连续朗读的终点：声音停、后台保活开关复位。
    if (_autoMode != null) {
      _autoMode = null;
      _autoId = null;
      ttsBackgroundKeepAlive.value = false;
      ttsStop();
    }
    _chatEntry?.remove();
    _pc?.dispose();
    super.dispose();
  }

  TextStyle _textStyle() => TextStyle(fontSize: _fontSize, height: _lineHeight, color: const Color(0xFF241C1A), fontFamily: 'Deng', fontFamilyFallback: const ['Deng', 'Roboto', 'WarnSym']);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final chunks = await ContentApi().chunksByWork(widget.work);
      final layer1 = chunks.where((c) => (c['layer'] as num?)?.toInt() == 1).toList();
      final picked = layer1.isEmpty ? chunks : layer1;
      final list = <String>[];
      final ids = <String>[];
      for (final c in picked) {
        final t = (c['text'] ?? '').toString().replaceAll('\r', '').trim();
        if (t.isEmpty) continue;
        list.add(t);
        ids.add('${c['id'] ?? ''}');
      }
      await _loadPrefs();
      // 「相关原文」跳转：按分片 id 找到段落下标（找不到则按常规进度打开）
      final focus = widget.focusChunkId;
      int? focusPara;
      if (focus != null && focus.isNotEmpty) {
        final i = ids.indexOf(focus);
        if (i >= 0) focusPara = i;
      }
      // 文本已重新加载，清掉该书的分页缓存，避免用旧文本的分页结果。
      _pageCache.removeWhere((k, _) => k.startsWith('${widget.work}|'));
      setState(() {
        _paragraphs = list;
        _focusPara = focusPara;
        _loading = false;
        _doc = null;
        _docSize = null;
        // 一次性：带上来的问题只发一次，之后翻页/重排都不再重复发
        _pendingAsk = widget.askText;
        _pendingAskMode = widget.askMode;
        _building = false;
      });
      _flushPendingAsk();
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// 把「打开时带过来的问题」发出去（只发一次）。
  ///
  /// 为什么放首帧之后：发问会插一个 OverlayEntry，必须在有 Overlay 的
  /// 帧里做；直接在 setState 同一帧插会在某些机型上拿到尚未挂载的 Overlay。
  void _flushPendingAsk() {
    final text = _pendingAsk;
    final modeName = _pendingAskMode;
    _pendingAsk = null;
    _pendingAskMode = null;
    if (text == null || text.trim().isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final m = ChatMode.values.firstWhere(
        (e) => e.name == (modeName ?? 'explain'),
        orElse: () => ChatMode.chat,
      );
      _ask(text, m.name);
    });
  }

  Future<void> _loadPrefs() async {
    final sp = await SharedPreferences.getInstance();
    _fontSize = sp.getDouble(_k(LocalStoreKeys.readerFontSize)) ?? 18;
    _bookmarks =
        _decode(sp.getString(_k(LocalStoreKeys.readerBookmarks)), _Bookmark.fromJson);
    _notes = _decode(sp.getString(_k(LocalStoreKeys.readerNotes)), _Note.fromJson);
    _highlights = _decode(
        sp.getString(_k(LocalStoreKeys.readerHighlights)), _Highlight.fromJson);
  }

  List<T> _decode<T>(String? raw, T Function(Map<String, dynamic>) f) {
    if (raw == null || raw.isEmpty) return <T>[];
    try {
      return (jsonDecode(raw) as List).map((e) => f(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return <T>[];
    }
  }

  /// 只写当前页码（翻页高频，避免每次全量 encode 书签/笔记/高亮造成卡顿）。
  Future<void> _saveLastPage() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_k(LocalStoreKeys.readerLastPage), _page);
  }

  /// 只写书签/笔记/高亮（标注变更低频，单独写避免连带无关 key）。
  Future<void> _saveAnnotations() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_k(LocalStoreKeys.readerBookmarks),
        jsonEncode(_bookmarks.map((e) => e.toJson()).toList()));
    await sp.setString(_k(LocalStoreKeys.readerNotes),
        jsonEncode(_notes.map((e) => e.toJson()).toList()));
    await sp.setString(_k(LocalStoreKeys.readerHighlights),
        jsonEncode(_highlights.map((e) => e.toJson()).toList()));
  }

  /// 只写字号（改字号时用）。
  Future<void> _saveFontSize() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(_k(LocalStoreKeys.readerFontSize), _fontSize);
  }

  /// 分页缓存：同一本书、同一字号、同一视口、同一系统字号缩放下，
  /// 分页测量结果不变。命中缓存可跳过 TextPainter 逐行测量（进入/返回卡顿主因）。
  static final Map<String, ReaderDoc> _pageCache = <String, ReaderDoc>{};

  Future<void> _buildDoc(Size size) async {
    final width = size.width - _padding.left - _padding.right;
    final height = size.height - _padding.top - _padding.bottom;
    if (width <= 0 || height <= 0) return;
    // 分页测量必须带上系统字号缩放：渲染侧的 Text 会自动应用 textScaler，
    // 测量侧不带就会低估行高，末尾那一行被挤出页面（用户实报）。
    final scaler = MediaQuery.textScalerOf(context);
    // 分页缓存：同一本书 + 字号 + 视口 + 系统缩放的测量结果不变，
    // 命中缓存直接用，跳过 TextPainter 逐行测量（进入/返回卡顿主因）。
    final cacheKey = '${widget.work}|$_fontSize|$width|$height|${scaler.scale}';
    final cached = _pageCache[cacheKey];
    final doc = cached ?? ReaderPaginator.paginate(
      paragraphs: _paragraphs, width: width, height: height,
      style: _textStyle(), textScaler: scaler,
    );
    if (cached == null) _pageCache[cacheKey] = doc;
    final sp = await SharedPreferences.getInstance();
    final last = sp.getInt(_k(LocalStoreKeys.readerLastPage)) ?? 0;
    // 定位优先级：本次要跳到的分片 > 重排前停留页 > 上次进度
    int? focusPage;
    final focusPara = _focusPara;
    if (focusPara != null) {
      for (var i = 0; i < doc.pages.length; i++) {
        if (doc.pages[i].paraIndexes.contains(focusPara)) {
          focusPage = i;
          break;
        }
      }
    }
    final target = (focusPage ?? _keepPage ?? last).clamp(0, doc.pages.length - 1);
    _keepPage = null;
    if (!mounted) return;
    setState(() {
      _doc = doc;
      _docSize = size;
      _docScaler = scaler;
      _page = target;
      _building = false;
      _pc?.dispose();
      _pc = PageController(initialPage: target);
    });
    // 重新分页（转屏 / 系统字号变化）后页码全变了：连续朗读跟到当前这一页重起，
    // 否则它会拿着旧页号去念新排版里的别的段落。
    if (_autoMode != null && _autoPage != target) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _autoMode != null) _autoSpeak(target);
      });
    }
  }

  /// 翻页即停朗读。
  ///
  /// 喇叭 id 里带页码（`reader-page-<work>-<page>`），翻页后旧 id 的朗读
  /// 仍在继续念上一页的内容，用户听到的和看到的对不上。所以只要页码变了就停，
  /// 且**只在真的变了时停**——同一页重建、滚动、改字号都不该打断朗读。
  void _stopSpeechIfPageChanged(int next) {
    if (next == _page) return;
    // 连续朗读中翻页不掐声：要么是它自己在往下推进，要么是用户手动翻页
    // 要换到新的一页接着念（用户要求「连续朗读跟着翻页走」）。
    if (_autoMode != null) return;
    ttsStop();
  }

  Future<void> _goto(int page) async {
    if (_doc == null) return;
    // 用户主动翻页 → 结束「相关原文」定位状态，之后按正常进度记忆
    _focusPara = null;
    final p = page.clamp(0, _doc!.pages.length - 1);
    final auto = _autoMode;
    _stopSpeechIfPageChanged(p);
    await _pc?.animateToPage(p, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    if (!mounted) return;
    setState(() => _page = p);
    _saveLastPage();
    // 连续朗读中手动翻页：从新的一页重新开始念，而不是停掉。
    if (auto != null && _autoMode != null && p != _autoPage) _autoSpeak(p);
  }

  void _setFont(double fs) {
    final next = fs.clamp(13.0, 30.0);
    if (next == _fontSize) return;
    // 改字号会重新分页，「第 N 页」对应的正文换了一批；正在念的那段接不下去，先收掉。
    if (_autoMode != null) _finishAuto();
    _keepPage = _page;
    _focusPara = null;
    setState(() {
      _fontSize = next;
      _doc = null;
      _docSize = null;
      _building = false;
    });
    _saveFontSize();
  }

  /// 只打开/收起会话浮窗，不发送任何内容。
  void _openChatOnly() {
    final svc = context.read<ChatService>();
    if (_sheetOpen) {
      _closeFloatingChat();
    } else {
      _openFloatingChat(svc);
    }
  }

  void _ask(String text, String mode) {
    final svc = context.read<ChatService>();
    final m = ChatMode.values.firstWhere((e) => e.name == mode, orElse: () => ChatMode.chat);
    if (m == ChatMode.chat) {
      // 「对话」是自由提问：只把选中原文挂起并打开输入框，等用户打完自己的问题一起发。
      // 以前这里替他发了一句「这段在说什么？」——用户实报「还没输入就发给 AI 了」，不合理。
      svc.stageSelection(text: text, paragraphId: '${widget.work}:p$_page');
      _openFloatingChat(svc);
      return;
    }
    svc.switchMode(m);
    // 释义 / 追问 / 辩难 / 关联是「就这段怎么展开」的一次性指令：点一下即发，
    // 默认那句话随模式变（不套「展开释义」这类说不通的拼接），选中原文一并进提示词。
    svc.send(content: m.askPrompt(), selectedText: text, paragraphId: '${widget.work}:p$_page');
    _openFloatingChat(svc);
  }

  // 打开（或重新唤起）可任意拖动的会话浮窗。用 Overlay 而非 bottomSheet，
  // 才能让会话浮在正文之上并可自由移动。
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
        criticalReading: svc.criticalReading,
        onToggleCritical: svc.toggleCriticalReading,
        onSend: (t) => svc.send(content: t),
        stagedSelection: svc.stagedSelection,
        onClearStaged: svc.clearStagedSelection,
        onClear: svc.clear,
        onClose: () => _closeFloatingChat(),
        onOpenOriginal: _openRelatedOriginal,
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

  OverlayEntry? _chatEntry;

  /// 「相关原文」跳转：浮窗是插在 Overlay 里的，会压住任何页面，
  /// 所以先撤下浮窗 → 打开原文（定位到分片所在页）→ 回来后恢复浮窗。
  Future<void> _openRelatedOriginal(List<String> ids) async {
    final svc = context.read<ChatService>();
    final nav = Navigator.of(context, rootNavigator: true);
    _closeFloatingChat();
    await showRelatedOriginalsFrom(nav, ids);
    if (!mounted) return;
    _openFloatingChat(svc);
  }

  void _closeFloatingChat() {
    // 关掉会话浮窗就必须停朗读：浮窗里每条回答都有小喇叭，浮窗一收起，
    // 正在念的那条既看不到也点不到，用户只能干等它念完（用户实报）。
    ttsStop();
    if (_chatListener != null && _chatSvc != null) {
      _chatSvc!.removeListener(_chatListener!);
    }
    _chatEntry?.remove();
    _chatEntry = null;
    _chatListener = null;
    if (mounted) setState(() => _sheetOpen = false);
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _snack('已复制到剪贴板');
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s), duration: const Duration(milliseconds: 1100)));
  }

  Future<void> _editAnnotations(int page, int para, {int? selStart, int? selEnd, String? initialLabel, _Highlight? editHighlight, _Note? editNote}) async {
    int color = editHighlight?.color ?? editNote?.color ?? _kColors[0];
    final labelCtl = TextEditingController(text: initialLabel ?? editHighlight?.label ?? editNote?.tag ?? '');
    final noteCtl = TextEditingController(text: editHighlight?.note ?? editNote?.note ?? '');
    final isEdit = editHighlight != null || editNote != null;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Container(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEdit ? '修改标注' : '标色 / 标签 / 笔记',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink900),
              ),
              const SizedBox(height: 12),
              const Text('标色', style: TextStyle(fontSize: 12.5, color: AppColors.ink500)),
              const SizedBox(height: 8),
              Row(
                children: List.generate(_kColors.length, (i) {
                  final cc = _kColors[i];
                  final selected = color == cc;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: () => setSt(() => color = cc),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Color(cc),
                          shape: BoxShape.circle,
                          border: Border.all(color: selected ? AppColors.brand : Colors.transparent, width: 2.5),
                        ),
                        child: selected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: labelCtl,
                decoration: const InputDecoration(labelText: '标签（可选）', hintText: '如：重点 / 待查 / 结论'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '笔记（可选）', hintText: '写下你的想法…'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      final lbl = labelCtl.text.trim();
      final nt = noteCtl.text.trim();
      if (editHighlight != null) {
        // 修改已有高亮：改颜色 / 标签 / 备注（笔记）
        editHighlight.color = color;
        editHighlight.label = lbl;
        editHighlight.note = nt;
      } else if (editNote != null) {
        editNote.color = color;
        editNote.tag = lbl;
        editNote.note = nt;
      } else {
        if (selStart != null && selEnd != null && selEnd > selStart) {
          _highlights.add(_Highlight(page: page, para: para, start: selStart, end: selEnd, color: color, label: lbl, note: nt, createdAt: DateTime.now().millisecondsSinceEpoch));
        }
        if (nt.isNotEmpty || lbl.isNotEmpty) {
          _notes.add(_Note(page: page, note: nt, tag: lbl, color: color, createdAt: DateTime.now().millisecondsSinceEpoch));
        }
      }
    });
    _saveAnnotations();
    _snack(isEdit ? '已更新标注' : '已保存标注');
  }

  void _confirmDeleteHighlight(_Highlight h) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条标注？'),
        content: Text(h.memo.isEmpty ? '删除这条高亮。' : h.memo),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    ).then((ok) {
      if (ok == true) {
        setState(() => _highlights.removeWhere((x) => identical(x, h)));
        _saveAnnotations();
        _snack('已删除标注');
      }
    });
  }

  void _toggleBookmark() {
    final exist = _bookmarks.where((b) => b.page == _page).toList();
    setState(() {
      if (exist.isNotEmpty) {
        _bookmarks.removeWhere((b) => b.page == _page);
        _snack('已取消本页书签');
      } else {
        _bookmarks.add(_Bookmark(_page, '第 ${_page + 1} 页', DateTime.now().millisecondsSinceEpoch));
        _snack('已加书签');
      }
    });
    _saveAnnotations();
  }

  /// 学习路线入口：这本书在哪些章里出现（主线主书 / 延伸阅读），点一下直接跳导读页。
  void _openRouteSheet() {
    final routes = {
      for (final r in OfflineContent.routes)
        (r['id'] ?? '').toString(): (r['title'] ?? '').toString(),
    };
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        margin: EdgeInsets.only(top: MediaQuery.of(ctx).size.height * 0.25),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
                child: Text('《${widget.work}》在学习路线里',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink700)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: Text('点一章直接进入该章导读',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.ink400)),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 10),
                  itemCount: _routeRows.length,
                  itemBuilder: (_, i) {
                    final r = _routeRows[i];
                    final isMain = (r['kind'] ?? '') == 'main';
                    final sid = (r['section_id'] ?? '').toString();
                    final title = (r['section_title'] ?? '').toString();
                    final routeName = routes[(r['route_id'] ?? '').toString()] ?? '';
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isMain ? Icons.flag_rounded : Icons.auto_stories_outlined,
                        size: 18,
                        color: isMain ? AppColors.brand : AppColors.ink400,
                      ),
                      title: Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, color: AppColors.ink700)),
                      subtitle: Text(
                        [
                          if (routeName.isNotEmpty) routeName,
                          isMain ? '本章主书' : '本章延伸阅读',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 11.5, color: AppColors.ink400),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.ink400),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ChapterGuideScreen(
                            routeId: (r['route_id'] ?? '').toString(),
                            sectionId: sid,
                            sectionTitle: title,
                          ),
                        ));
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openToc() {
    if (_doc == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _sheetScaffold('目录 · 书签 · 笔记', [
        _sectionHeader('目录（${_doc!.toc.length}）'),
        ..._doc!.toc.map(
          (e) => ListTile(
            dense: true,
            leading: const Icon(Icons.menu_book, size: 18, color: AppColors.brand),
            title: Text(e.title, style: const TextStyle(fontSize: 13.5)),
            trailing: Text('第 ${e.page + 1} 页', style: const TextStyle(fontSize: 12, color: AppColors.ink400)),
            onTap: () {
              Navigator.pop(context);
              _goto(e.page);
            },
          ),
        ),
        _sectionHeader('书签（${_bookmarks.length}）'),
        if (_bookmarks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text('暂无书签', style: TextStyle(color: AppColors.ink400, fontSize: 12.5)),
          )
        else
          ..._bookmarks.map(
            (b) => ListTile(
              dense: true,
              leading: const Icon(Icons.bookmark, size: 18, color: AppColors.gold),
              title: Text(b.label),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () {
                  setState(() => _bookmarks.remove(b));
                  _saveAnnotations();
                  Navigator.pop(context);
                },
              ),
              onTap: () {
                Navigator.pop(context);
                _goto(b.page);
              },
            ),
          ),
        _sectionHeader('笔记 / 标色（${_notes.length + _highlights.length}）'),
        if (_notes.isEmpty && _highlights.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text('暂无笔记', style: TextStyle(color: AppColors.ink400, fontSize: 12.5)),
          )
        else ...[
          ..._notes.map(
            (n) => ListTile(
              dense: true,
              leading: _swatch(n.color),
              title: Text(n.note.isEmpty ? (n.tag.isEmpty ? '（标色）' : n.tag) : n.note, style: const TextStyle(fontSize: 13)),
              subtitle: Text('第 ${n.page + 1} 页${n.tag.isNotEmpty ? ' · ${n.tag}' : ''}', style: const TextStyle(fontSize: 11.5)),
              trailing: _noteActions(
                onEdit: () {
                  Navigator.pop(context);
                  _editAnnotations(n.page, n.page >= 0 && n.page < _doc!.pages.length && _doc!.pages[n.page].paraIndexes.isNotEmpty ? _doc!.pages[n.page].paraIndexes.first : 0, editNote: n);
                },
                onDelete: () {
                  setState(() => _notes.remove(n));
                  _saveAnnotations();
                  Navigator.pop(context);
                  _snack('已删除笔记');
                },
              ),
              onTap: () {
                Navigator.pop(context);
                _goto(n.page);
              },
            ),
          ),
          ..._highlights.map(
            (h) => ListTile(
              dense: true,
              leading: _swatch(h.color),
              title: Text(_hlExcerpt(h), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              subtitle: Text('第 ${h.page + 1} 页${h.label.isNotEmpty ? ' · ${h.label}' : ''}${h.note.isNotEmpty ? ' · 有备注' : ''}', style: const TextStyle(fontSize: 11.5)),
              trailing: _noteActions(
                onEdit: () {
                  Navigator.pop(context);
                  _editAnnotations(h.page, h.para, editHighlight: h);
                },
                onDelete: () {
                  setState(() => _highlights.removeWhere((x) => identical(x, h)));
                  _saveAnnotations();
                  Navigator.pop(context);
                  _snack('已删除标注');
                },
              ),
              onTap: () {
                Navigator.pop(context);
                _goto(h.page);
              },
            ),
          ),
        ],
      ]),
    );
  }

  Widget _noteActions({required VoidCallback onEdit, required VoidCallback onDelete}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.brand),
        tooltip: '修改',
        onPressed: onEdit,
      ),
      IconButton(
        icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
        tooltip: '删除',
        onPressed: onDelete,
      ),
    ],
  );

  Widget _swatch(int color) => Container(
    width: 18,
    height: 18,
    decoration: BoxDecoration(color: Color(color), borderRadius: BorderRadius.circular(4)),
  );

  String _hlExcerpt(_Highlight h) {
    if (h.para < _paragraphs.length) {
      final t = _paragraphs[h.para];
      final s = h.start.clamp(0, t.length);
      final e = h.end.clamp(s, t.length);
      return t.substring(s, e);
    }
    return '划线';
  }

  Widget _sectionHeader(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Text(
      t,
      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.brand),
    ),
  );

  Widget _sheetScaffold(String title, List<Widget> children) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink900),
                  ),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(controller: controller, children: children),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _promptGoto() async {
    if (_doc == null) return;
    final ctl = TextEditingController(text: '${_page + 1}');
    final total = _doc!.pages.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳转到页面'),
        content: TextField(
          controller: ctl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1 - $total'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('跳转'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final n = int.tryParse(ctl.text.trim());
      if (n != null) _goto(n - 1);
    }
  }

  void _onSelectionChanged(SelectedContent? sel) {
    final t = (sel?.plainText ?? '').trim();
    if (t.isNotEmpty && t.length < 500) {
      // 选区文本没变（点了已选区域）就不重建，避免无谓的整页重绘（卡顿主因之一）。
      if (t == _selected) return;
      // 换了一段选区：旧浮框消失，它上面的朗读必须跟着停，
      // 否则会一直念着上一段选中的文字（用户实报）。
      if (_selected.isNotEmpty) ttsStop();
      setState(() => _selected = t);
      return;
    }
    // 选区没了（点空白 / 太长）→ 浮框收起 → 停朗读
    if (_selected.isNotEmpty) {
      ttsStop();
      setState(() => _selected = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF7F5),
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_routeRows.isNotEmpty)
            IconButton(
              tooltip: '这本书在路线里的哪几章',
              icon: const Icon(Icons.alt_route_rounded),
              onPressed: _openRouteSheet,
            ),
          IconButton(tooltip: '目录 / 书签 / 笔记', icon: const Icon(Icons.list_alt_rounded), onPressed: _openToc),
          // 自动连续发声：当前页循环 / 从当前页播到结束 / 播完再整篇循环。
          if (_doc != null && !_loading && _error == null)
            IconButton(
              tooltip: _autoMode == null ? '自动连续发声' : '连续朗读中（点开可换模式 / 停止）',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                _autoMode == null ? Icons.headphones_outlined : Icons.headphones,
                color: _autoMode == null ? null : AppColors.gold,
              ),
              onPressed: _openAutoSheet,
            ),
          // 朗读当前页（发音喇叭）
          if (_doc != null && !_loading && _error == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: SpeakButton(id: 'reader-page-${widget.work}-$_page', text: _pageSpeech()),
            ),
          // 只打开/收起会话浮窗，**不**自动发问。
          // 用户实报：一点就自动释义 —— 上一版把「打开会话」与「就选中文本发问」
          // 混成同一个动作。现在打开是空会话，发什么由用户自己在浮窗里决定。
          IconButton(
            tooltip: '会话（AI 精读 + 对话）',
            icon: const Icon(Icons.forum_outlined),
            onPressed: _openChatOnly,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _errorView()
                : _paragraphs.isEmpty
                ? const Center(
                    child: Text('该著作暂无正文。', style: TextStyle(color: AppColors.ink500)),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final mq = MediaQuery.of(context);
                      // 分页尺寸用**不含软键盘的物理视口**：IME 弹出时 mq.size.height 变小
                      // 但 viewInsets.bottom 增大，两者之和恒定。整数化避免浮点精度导致
                      // needBuild 误判触发 _buildDoc 重新分页（页数多时逐行测量整本书，
                      // 输入/退出各卡一次）。
                      final vpHeight = (mq.size.height + mq.viewInsets.bottom).round();
                      final vpWidth = mq.size.width.round();
                      final size = Size(vpWidth.toDouble(), vpHeight.toDouble());
                      final needBuild = _doc == null ||
                          _docSize != size ||
                          _docScaler != MediaQuery.textScalerOf(context);
                      if (needBuild) {
                        if (!_building) {
                          _building = true;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _buildDoc(size);
                          });
                        }
                        return const Center(child: CircularProgressIndicator());
                      }
                      return _buildReader();
                    },
                  ),
          ),
          // 选中文字后的追问工具条：可任意拖动的浮动面板；默认贴顶出现（
          // 与深入学习页一致，避免浮框盖住刚选中的那句话）。
          if (_doc != null && !_loading && _error == null && _selected.isNotEmpty)
            MovableBox(
              key: ValueKey(_selected.length),
              bounds: MediaQuery.of(context).size,
              size: const Size(360, 120),
              initialOffset: Offset(
                  (MediaQuery.of(context).size.width - 360) / 2, 10),
              child: _selectionFab(),
            ),
        ],
      ),
      bottomNavigationBar: _doc == null || _loading || _error != null
          ? null
          : _buildBottomBar(),
    );
  }

  /// 连续朗读进行中的状态位，**就长在底部栏里面**。
  ///
  /// 为什么不做成单独一条放在底栏上面（用户实报的坑）：底栏一旦变高，
  /// PageView 的可视高度就变小 → `_buildDoc` 用新高度重新分页 →
  /// 每页装的行数变少，当前页顶部就冒出了「上一页的尾巴」。
  /// 排版必须和朗读开关无关，所以这里只替换原有那几个按钮的位置，高度不变。
  Widget _autoInlineStatus() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 暂停 / 继续：左侧按钮，与右侧「停止」配对。
        // 暂停时显示播放图标（点击继续），朗读中显示暂停图标（点击暂停）。
        IconButton(
          onPressed: _toggleAutoPause,
          visualDensity: VisualDensity.compact,
          iconSize: 16,
          padding: const EdgeInsets.only(right: 2),
          tooltip: _autoPaused ? '继续朗读' : '暂停朗读',
          icon: Icon(
            _autoPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            size: 16,
            color: AppColors.gold,
          ),
        ),
        const Icon(Icons.graphic_eq, size: 16, color: AppColors.gold),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            _autoPaused
                ? '已暂停 · ${_autoMode!.short}'
                : (ttsNeuralFallback.value
                    ? '已切本机语音 · ${_autoMode!.short}'
                    : '连续朗读 · ${_autoMode!.short}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: ttsNeuralFallback.value && !_autoPaused ? AppColors.danger : AppColors.ink700,
            ),
          ),
        ),
        TextButton(
          onPressed: _finishAuto,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(0, 28),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: const Text('停止', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _errorView() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('加载失败：$_error', style: const TextStyle(color: AppColors.ink500)),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: _load, child: const Text('重试')),
      ],
    ),
  );

  Widget _buildReader() {
    final doc = _doc!;
    return PageView.builder(
      controller: _pc,
      itemCount: doc.pages.length,
      onPageChanged: (i) {
        // 左右滑动翻页也停朗读（用户实报：翻到下一页，上一页还在念）
        _stopSpeechIfPageChanged(i);
        setState(() => _page = i);
        _saveLastPage();
        // 连续朗读中手动滑到别的页：跟到新的一页接着念（不是停）。
        // 自动翻页时 _autoPage 已经等于 i，这里不会重复触发。
        if (_autoMode != null && i != _autoPage) _autoSpeak(i);
      },
      itemBuilder: (context, i) => _AnnotatedPage(
        page: i,
        item: doc.pages[i],
        style: _textStyle(),
        padding: _padding,
        highlights: _highlights.where((h) => h.page == i).toList(),
        onCopy: _copyText,
        onAsk: _ask,
        onAnnotate: (para, s, e) => _editAnnotations(i, para, selStart: s, selEnd: e),
        onSelectionChanged: _onSelectionChanged,
        onEditHighlight: (h) => _editAnnotations(h.page, h.para, editHighlight: h),
        onDeleteHighlight: (h) => _confirmDeleteHighlight(h),
      ),
    );
  }

  Widget _buildBottomBar() {
    final total = _doc!.pages.length;
    final fs = _fontSize;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            IconButton(tooltip: '上一页', icon: const Icon(Icons.chevron_left), onPressed: _page > 0 ? () => _goto(_page - 1) : null),
            InkWell(
              onTap: _promptGoto,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  '${_page + 1} / $total',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink700),
                ),
              ),
            ),
            IconButton(tooltip: '下一页', icon: const Icon(Icons.chevron_right), onPressed: _page < total - 1 ? () => _goto(_page + 1) : null),
            const Spacer(),
            // 连续朗读中：字号/书签换成状态位（改字号本来就会先停朗读），
            // 行高不变 → 底栏高度不变 → 不会触发重新分页。
            if (_autoMode != null)
              _autoInlineStatus()
            else ...[
              IconButton(tooltip: '缩小字号', icon: const Icon(Icons.text_decrease), onPressed: fs > 13 ? () => _setFont(fs - 1) : null),
              Text('${fs.toInt()}', style: const TextStyle(fontSize: 12, color: AppColors.ink500)),
              IconButton(tooltip: '放大字号', icon: const Icon(Icons.text_increase), onPressed: fs < 30 ? () => _setFont(fs + 1) : null),
              IconButton(
                tooltip: '加书签',
                icon: Icon(_bookmarks.any((b) => b.page == _page) ? Icons.bookmark : Icons.bookmark_border, color: AppColors.gold),
                onPressed: _toggleBookmark,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _selectionFab() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.soft),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _mini(Icons.copy_rounded, '复制', AppColors.ink700, () => _copyText(_selected)),
              const Spacer(),
              _mini(Icons.color_lens_rounded, '标色/标签/笔记', AppColors.gold, () => _annotateSelection()),
              const Spacer(),
              // 朗读当前选中的文字（与全站 TTS 一致）
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: SpeakButton(id: 'reader-sel-${widget.work}-$_page-${_selected.length}', compact: true, text: _selected),
              ),
              const Spacer(),
              _mini(Icons.close_rounded, '关闭', AppColors.ink400, () {
                ttsStop();
                setState(() => _selected = '');
              }),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: kSelectionModes.map((m) {
              return ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text(m.label, style: const TextStyle(fontSize: 11.5, color: Colors.white)),
                backgroundColor: Color(m.color),
                onPressed: () {
                  final t = _selected;
                  // 浮框收起，朗读停（不然发问后还在念选中的那段）
                  ttsStop();
                  setState(() => _selected = '');
                  _ask(t, m.name);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// 当前页纯文本（用于整页朗读）。
  String _pageSpeech() => _pageSpeechAt(_page);

  /// 指定页的纯文本（连续朗读要提前取下一页）。
  String _pageSpeechAt(int page) {
    final doc = _doc;
    if (doc == null || page < 0 || page >= doc.pages.length) return '';
    return doc.pages[page].text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ─────────────────── 自动连续发声 ───────────────────

  /// 弹出三个模式选项（当前页循环 / 播到结束 / 播完再整篇循环）。
  void _openAutoSheet() {
    final doc = _doc;
    if (doc == null) return;
    // 进弹层前先清掉上次可能没用完的一次性豁免，别让它跨场景生效。
    ttsSkipStopOnNextSheetClose = false;
    final total = doc.pages.length;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.headphones_rounded, size: 20, color: AppColors.brand),
                  const SizedBox(width: 8),
                  const Text('自动连续发声',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink900)),
                  const Spacer(),
                  Text('第 ${_page + 1} / $total 页',
                      style: const TextStyle(fontSize: 12, color: AppColors.ink400)),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '从现在这一页开始念，念完自动翻下一页；切后台、息屏也继续，退出本页才停。',
                style: TextStyle(fontSize: 12, color: AppColors.ink500),
              ),
              const SizedBox(height: 8),
              if (_autoMode != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.stop_circle_outlined, color: AppColors.danger),
                  title: const Text('停止连续朗读', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('正在：${_autoMode!.label}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.ink500)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _finishAuto();
                  },
                ),
              ...ReaderAutoMode.values.map(
                (m) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    m == ReaderAutoMode.pageLoop
                        ? Icons.repeat_one_rounded
                        : m == ReaderAutoMode.toEnd
                            ? Icons.trending_flat_rounded
                            : Icons.repeat_rounded,
                    color: _autoMode == m ? AppColors.gold : AppColors.brand,
                  ),
                  title: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(m.hint,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.ink500)),
                  trailing: _autoMode == m
                      ? const Icon(Icons.graphic_eq, size: 18, color: AppColors.gold)
                      : const Icon(Icons.chevron_right, size: 18, color: AppColors.ink400),
                  onTap: () {
                    // 关闭本弹层正是为了开始念：给观察者一个一次性豁免，
                    // 否则「关弹层就停」那条规则会把刚起头的连续朗读掐掉。
                    ttsSkipStopOnNextSheetClose = true;
                    Navigator.pop(ctx);
                    _startAuto(m);
                  },
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  void _startAuto(ReaderAutoMode mode) {
    final doc = _doc;
    if (doc == null || doc.pages.isEmpty) return;
    ttsStop();
    setState(() {
      _autoMode = mode;
      _autoPage = _page.clamp(0, doc.pages.length - 1);
      _autoPaused = false;
    });
    // 用户要求：连续朗读时切后台/息屏也得继续，由它自己管到退出本页为止。
    ttsBackgroundKeepAlive.value = true;
    _autoSpeak(_autoPage);
  }

  /// 念第 [page] 页，并提前把下一页的开头音频拉好（只一段，不预生成整篇）。
  void _autoSpeak(int page) {
    final mode = _autoMode;
    final doc = _doc;
    if (mode == null || doc == null) return;
    // 手动翻页 / 自动推进时取消暂停态，从新页开始念。
    if (_autoPaused) setState(() => _autoPaused = false);
    if (page < 0 || page >= doc.pages.length) {
      _finishAuto(announce: true);
      return;
    }
    final text = _pageSpeechAt(page);
    if (text.isEmpty) {
      // 空页（分页边界的极端情况）：跳过去，别让它把连续朗读卡死。
      final skip = nextAutoPage(mode: mode, current: page, pageCount: doc.pages.length);
      if (skip == null || skip == page) {
        _finishAuto(announce: true);
        return;
      }
      _autoPage = skip;
      _autoGoto(skip);
      _autoSpeak(skip);
      return;
    }
    _autoPage = page;
    _autoGoto(page);
    final id = 'reader-auto-${widget.work}-$page';
    _autoId = id;
    _autoLinking = true;
    ttsSpeak(text, id: id, onDone: _onAutoPageDone);
    _autoLinking = false;
    _armAutoWatchdog(text);
    // 只预热「下一页的第一段」：换页时接得上、不断档，又不把全文送去合成。
    final next = nextAutoPage(mode: mode, current: page, pageCount: doc.pages.length);
    if (next != null && next != page) ttsPrefetch(_pageSpeechAt(next));
  }

  /// 给「这一页」装一个超时兜底：引擎不回调 onDone 时，到点自己接下一页。
  ///
  /// 估时口径：中文语音在语速 1.0 下约 4~5 字/秒，这里按 4 字/秒算再乘 3 倍余量，
  /// 另加 15 秒起停开销（长句气口、引擎排队）。只有明显「读完很久还没动静」
  /// 才会触发，正常朗读不会被打断。上限 15 分钟，免得极端长页把计时器撑爆。
  void _armAutoWatchdog(String text) {
    _autoWatchdog?.cancel();
    final chars = text.runes.length;
    final seconds = (chars / 4.0 * 3 + 15).clamp(20.0, 900.0);
    _autoWatchdog = Timer(Duration(milliseconds: (seconds * 1000).round()), () {
      if (!mounted || _autoMode == null) return;
      debugPrint('连续朗读：这一页 ${seconds.round()} 秒没有收到读完回调，按读完处理');
      _onAutoPageDone();
    });
  }

  /// 这一页念完了：按模式接下一页，或到此为止。
  void _onAutoPageDone() {
    final mode = _autoMode;
    final doc = _doc;
    if (mode == null || doc == null) return;
    final next = nextAutoPage(mode: mode, current: _autoPage, pageCount: doc.pages.length);
    if (next == null) {
      _finishAuto(announce: true);
      return;
    }
    _autoSpeak(next);
  }

  /// 连续朗读自己翻页：页码与 PageView 立刻对齐。
  /// 用 jumpToPage 而不是动画 —— 切后台/息屏时不出帧，动画会停在半路，
  /// 页码和实际显示的页就对不上了。
  void _autoGoto(int page) {
    final doc = _doc;
    if (doc == null) return;
    final p = page.clamp(0, doc.pages.length - 1);
    if (_page == p) return;
    if (mounted) setState(() => _page = p);
    final pc = _pc;
    if (pc != null && pc.hasClients) pc.jumpToPage(p);
    _saveLastPage();
  }

  /// 收掉连续朗读（用户点停止 / 读到末尾 / 被别的朗读接管）。
  void _finishAuto({bool announce = false}) {
    final wasOn = _autoMode != null;
    _autoMode = null;
    _autoId = null;
    _autoLinking = false;
    _autoPaused = false;
    _autoWatchdog?.cancel();
    _autoWatchdog = null;
    // 开关必须复位：否则退出本页后切后台也不停朗读了。
    ttsBackgroundKeepAlive.value = false;
    if (wasOn) ttsStop();
    if (!mounted) return;
    setState(() {});
    if (wasOn && announce) _snack('已读到最后一页，连续朗读结束');
  }

  /// 暂停 / 继续连续朗读。
  ///
  /// 暂停只停当前发声、保留进度（不释放音频缓冲），看门狗一并取消，
  /// 避免暂停期间误判读完、把朗读错接到下一页。继续时从暂停处接上。
  void _toggleAutoPause() {
    if (_autoMode == null) return;
    if (_autoPaused) {
      setState(() => _autoPaused = false);
      ttsResume();
      // 续播也要重新武装看门狗：暂停时已取消，引擎不回调的机型否则会永远静默。
      _armAutoWatchdog(_pageSpeechAt(_autoPage));
    } else {
      _autoWatchdog?.cancel();
      _autoWatchdog = null;
      setState(() => _autoPaused = true);
      ttsPause();
    }
  }

  /// 神经语音回退到浏览器本机语音：状态条立刻刷新，明确提示，别让用户误以为出故障。
  void _onTtsFallbackChanged() {
    if (!mounted || _autoMode == null) return;
    setState(() {});
  }

  /// 朗读被停 / 被别的喇叭抢走 → 连续朗读跟着收摊，
  /// 避免留下一个「看着还在播、其实早没声了」的状态条。
  void _onTtsChanged() {
    if (_autoMode == null || _autoLinking) return;
    if (ttsCurrent.value == _autoId) return;
    // 念完一页接下一页时 ttsCurrent 会在同一个 tick 里短暂为 null，
    // 所以等这轮事件循环结束再判定，别把正常接续误判成「被停止」。
    Future.microtask(() {
      if (!mounted || _autoMode == null) return;
      if (ttsCurrent.value == _autoId) return;
      _finishAuto();
    });
  }

  void _annotateSelection() {
    final sel = _selected;
    // 收起释义浮框：标注弹层打开后不再需要它，且浮框与输入法候选框叠加
    // 会导致每次按键触发重绘（填入内容卡顿的主因）。
    if (sel.isNotEmpty) setState(() => _selected = '');
    final page = _doc!.pages[_page];
    // 在当前页所有段落里找包含选中文本的段落 + 字符偏移，保证黄底高亮精确落在选中片段上
    final candidates = page.paraIndexes.isNotEmpty ? page.paraIndexes : <int>[0];
    for (final para in candidates) {
      final pText = para < _paragraphs.length ? _paragraphs[para] : '';
      final i = sel.isEmpty ? -1 : pText.indexOf(sel);
      if (i >= 0) {
        _editAnnotations(_page, para, selStart: i, selEnd: i + sel.length);
        return;
      }
    }
    final para = candidates.first;
    _editAnnotations(_page, para, selStart: 0, selEnd: sel.length.clamp(0, (_paragraphs.length > para ? _paragraphs[para].length : 0)));
  }

  Widget _mini(IconData ic, String label, Color c, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ic, size: 18, color: c),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10.5, color: c)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── 单页渲染 ───────────────────────────

class _AnnotatedPage extends StatelessWidget {
  final int page;
  final ReaderPage item;
  final TextStyle style;
  final EdgeInsets padding;
  final List<_Highlight> highlights;
  final Future<void> Function(String) onCopy;
  final void Function(String text, String mode) onAsk;
  final void Function(int para, int start, int end) onAnnotate;
  final void Function(SelectedContent?) onSelectionChanged;
  final void Function(_Highlight h) onEditHighlight;
  final void Function(_Highlight h) onDeleteHighlight;

  const _AnnotatedPage({required this.page, required this.item, required this.style, required this.padding, required this.highlights, required this.onCopy, required this.onAsk, required this.onAnnotate, required this.onSelectionChanged, required this.onEditHighlight, required this.onDeleteHighlight});

  int _paraForBlock(String block, List<int> paraIndexes, int order) {
    // 每页的 block 顺序大致对应 paraIndexes 顺序；用长度匹配更稳
    return order < paraIndexes.length ? paraIndexes[order] : (paraIndexes.isNotEmpty ? paraIndexes.first : 0);
  }

  @override
  Widget build(BuildContext context) {
    final blocks = item.text.split('\n\n').where((b) => b.trim().isNotEmpty).toList();
    final hlByPara = <int, List<_Highlight>>{};
    for (final h in highlights) {
      hlByPara.putIfAbsent(h.para, () => []).add(h);
    }
    final children = <Widget>[];
    for (var k = 0; k < blocks.length; k++) {
      final block = blocks[k];
      final paraIdx = _paraForBlock(block, item.paraIndexes, k);
      final hls = hlByPara[paraIdx] ?? const <_Highlight>[];
      // 段落内含标注时，用可直接选中文字的 Text.rich 逐段渲染（黄底 + 下划线 + 悬停备注）
      final Widget body = hls.isEmpty ? Text(block, style: style) : _richPara(block, paraIdx, hls);
      children.add(
        GestureDetector(
          onLongPress: () => _showParaActions(context, block, paraIdx),
          child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: ReaderPaginator.blockPaddingH, vertical: ReaderPaginator.blockPaddingV), child: body),
        ),
      );
      if (k != blocks.length - 1) {
        children.add(const SizedBox(height: ReaderPaginator.paraGap));
      }
    }
    // 每页用 RepaintBoundary 隔离 paint：保存标注 / 输入 / 退出时，
    // 只重绘当前页，不连带其他缓存页整片重绘（页数多时成本随页数增长）。
    return RepaintBoundary(
      child: SelectionArea(
        // 屏蔽系统自带的「copy/share」工具条：本页选中即弹自己的追问浮框（复制/朗读/标色 + 五枚选区模式 chip），
        // 两套浮窗同时出现会互相遮挡，用户也分不清该点哪一个。
        contextMenuBuilder: (context, state) => const SizedBox.shrink(),
        onSelectionChanged: onSelectionChanged,
        child: Padding(
          padding: padding,
          child: SingleChildScrollView(
            // 分页是「精确装下」的，正常不产生滚动；但混排中英数字时行宽可能与
            // 测量有差，留一手可滚，避免最末一行被直接裁掉看不见。
            physics: const ClampingScrollPhysics(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ),
      ),
    );
  }

  /// 把段落按高亮区间切片，被标注的片段：淡黄底色 + 下划线，悬停浮出备注并可直接修改/删除。
  Widget _richPara(String block, int paraIdx, List<_Highlight> hls) {
    // 构造互不重叠的可渲染区间（后建覆盖前者）
    final hs = [...hls]..sort((a, b) => a.start.compareTo(b.start));
    final spans = <InlineSpan>[];
    int cursor = 0;
    for (final h in hs) {
      final s = h.start.clamp(0, block.length);
      final e = h.end.clamp(s, block.length);
      if (e <= cursor) continue;
      final start = s < cursor ? cursor : s;
      if (start > cursor) {
        spans.add(TextSpan(text: block.substring(cursor, start)));
      }
      final seg = block.substring(start, e);
      final bg = Color(h.color == 0 ? 0xFFFFF3B0 : h.color).withValues(alpha: 0.42);
      final mark = WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _HlHover(
          memo: h.memo,
          onEdit: () => onEditHighlight(h),
          onDelete: () => onDeleteHighlight(h),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: bg,
              border: const Border(bottom: BorderSide(color: AppColors.gold, width: 1.6)),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(seg, style: style),
          ),
        ),
      );
      spans.add(mark);
      cursor = e;
    }
    if (cursor < block.length) {
      spans.add(TextSpan(text: block.substring(cursor)));
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }

  void _showParaActions(BuildContext context, String block, int paraIdx) {
    final sel = block.length > 60 ? '${block.substring(0, 60)}…' : block;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                sel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AppColors.ink500),
              ),
            ),
            const Divider(height: 1),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('复制本段'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    onCopy(block);
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.color_lens_rounded, size: 16, color: AppColors.gold),
                  label: const Text('标色 / 标签 / 笔记'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    onAnnotate(paraIdx, 0, block.length);
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text('就本段唤起 AI 精读', style: TextStyle(fontSize: 12.5, color: AppColors.ink500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: kSelectionModes.map((m) {
                return ActionChip(
                  label: Text(m.label, style: const TextStyle(fontSize: 12, color: Colors.white)),
                  backgroundColor: Color(m.color),
                  onPressed: () {
                    Navigator.pop(ctx);
                    onAsk(block, m.name);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一条已标注片段的悬停交互：鼠标移上浮出备注浮层（可选「修改」「删除」）。
/// 桌面/Web 用 MouseRegion.onEnter 控制；触屏无 hover，长按段落仍可走「标色/笔记」入口。
class _HlHover extends StatefulWidget {
  final String memo;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Widget child;
  const _HlHover({required this.memo, required this.onEdit, required this.onDelete, required this.child});
  @override
  State<_HlHover> createState() => _HlHoverState();
}

class _HlHoverState extends State<_HlHover> {
  OverlayEntry? _overlay;
  Timer? _hideTimer;

  /// 光标从标注挪到卡片上要跨过一条 6px 的缝：给个缓冲，别一离开标注就把卡片收掉，
  /// 否则「修改 / 删除」根本点不到。
  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 220), _hide);
  }

  void _cancelHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _show() {
    if (_overlay != null) return;
    final box = context.findRenderObject();
    final mq = MediaQuery.of(context).size;
    double dx = 0, dy = 0, mw = 0, mh = 0;
    if (box is RenderBox && box.hasSize) {
      final origin = box.localToGlobal(Offset.zero);
      dx = origin.dx;
      dy = origin.dy;
      mw = box.size.width;
      mh = box.size.height;
    }
    const gap = 6.0;
    final maxW = mq.width - 24 < 300 ? mq.width - 24 : 300.0;
    // 横向：默认与标注左对齐，靠右边缘会溢出就改成右对齐
    final alignRight = dx + maxW > mq.width - 8;
    // 纵向：下方放不下就翻到上方；用 bottom 定位，卡片高度随文本变也不会压住标注
    final above = mq.height - (dy + mh) < 230;
    final rightInset = mq.width - (dx + mw);
    final memo = widget.memo;
    _overlay = OverlayEntry(
      builder: (_) => Positioned(
        left: alignRight ? null : dx,
        right: alignRight ? rightInset.clamp(8.0, mq.width - 8) : null,
        top: above ? null : dy + mh + gap,
        bottom: above ? mq.height - dy + gap : null,
        child: MouseRegion(
          onEnter: (_) => _cancelHide(),
          onExit: (_) => _scheduleHide(),
          child: Material(
            color: Colors.transparent,
            child: Container(
              // 宽度跟着笔记文字走：短笔记就是一个小气泡，超过 maxW 才换行
              constraints: BoxConstraints(minWidth: 96, maxWidth: maxW),
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.7)),
                boxShadow: AppShadows.soft,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Icon(Icons.sticky_note_2_outlined, size: 16, color: AppColors.gold),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          memo.isEmpty ? '（无备注内容）' : memo,
                          style: const TextStyle(
                            fontSize: 14.5,
                            height: 1.6,
                            color: AppColors.ink900,
                            fontFamily: 'Deng',
                            fontFamilyFallback: ['Deng', 'Roboto', 'WarnSym'],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _act(Icons.edit_outlined, '修改', () {
                        _hide();
                        widget.onEdit();
                      }),
                      const SizedBox(width: 4),
                      _act(Icons.delete_outline, '删除', () {
                        _hide();
                        widget.onDelete();
                      }, danger: true),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlay!);
  }

  Widget _act(IconData ic, String label, VoidCallback onTap, {bool danger = false}) {
    final c = danger ? AppColors.danger : AppColors.brand;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ic, size: 14, color: c),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(fontSize: 11.5, color: c, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  void _hide() {
    _cancelHide();
    _overlay?.remove();
    _overlay = null;
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        _cancelHide();
        _show();
      },
      onExit: (_) => _scheduleHide(),
      child: GestureDetector(onLongPress: widget.onEdit, child: widget.child),
    );
  }
}
