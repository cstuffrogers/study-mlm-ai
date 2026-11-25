// 会话（单机版）：不再连接 WebSocket / 后端，回答由本机 LocalDialogue 生成。
// 对外接口与联网版保持一致（connect/send/retryLast/turns/pending），
// 因此浮窗、对话页等界面无需改动。
import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../offline/local_dialogue.dart';
import 'llm_config_store.dart';

// 会话中一条记录（用户/AI/blocked）
class ChatTurn {
  final String role; // user / ai / blocked
  final String content;
  final String mode;
  final String selectedText;
  final List<ProvenanceCard> provenance;
  /// 结构化相关原文 id（界面只用于「相关原文」按钮取数，不在正文出现编码）。
  final List<String> sourceChunks;
  final bool exempt;
  final String? blockedReason;
  // 立场层拦截时置 true：提示用户可切「批判性阅读」后重试
  final bool allowCriticalReading;
  final Map<String, dynamic>? instantSummary;
  /// 作答引擎：local / cloud:模型名 / local:guard-fallback（空=历史旧记录）
  final String engine;

  /// engine=local 时为什么没用在线模型：
  /// not-configured（没填 Key）/ failed:原因（配了但调用失败）/ empty-reply（返回空正文）。
  final String engineNote;

  ChatTurn({
    required this.role,
    required this.content,
    this.mode = 'explain',
    this.selectedText = '',
    this.provenance = const [],
    this.sourceChunks = const [],
    this.exempt = false,
    this.blockedReason,
    this.allowCriticalReading = false,
    this.instantSummary,
    this.engine = '',
    this.engineNote = '',
  });
}

class ChatService extends ChangeNotifier {
  bool _connected = false;
  String _status = '本机模式';

  final List<ChatTurn> turns = [];
  final String dialogueId;
  ChatMode currentMode = ChatMode.chat;
  bool criticalReading = false;

  bool _disposed = false;
  bool _pending = false;
  String? _lastError;
  String? _lastQuestion;
  String _lastSelectedText = '';
  String _lastParagraphId = '';
  ChatMode _lastMode = ChatMode.chat;
  Timer? _timeout;
  // 本机生成是同步计算，只需给检索留出余量；
  // 配置了在线大模型时按「对话超时」放宽，避免模型还没答完就被判超时。
  static const Duration _localTimeout = Duration(seconds: 20);

  Duration get _requestTimeout {
    final cfg = LlmConfigStore.load();
    if (!cfg.enabled) return _localTimeout;
    return Duration(seconds: cfg.interactiveTimeout.ceil() + 8);
  }

  ChatService({String? dialogueId})
      : dialogueId = dialogueId ?? _defaultDialogueId();

  /// 默认会话按**天**分段：同一个学习日的追问记在同一段里，
  /// 历史页才不是一堆只含一两句话的碎片（以前每次启动都新建一个 id）。
  static String _defaultDialogueId() {
    final d = DateTime.now();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return 'd-${d.year}$m$day';
  }

  bool get connected => _connected;
  String get status => _status;
  bool get pending => _pending;
  String? get lastError => _lastError;
  String? get lastQuestion => _lastQuestion;
  String get lastSelectedText => _lastSelectedText;
  ChatMode get lastMode => _lastMode;

  /// 单机版无连接过程：把本机已有会话记录读回列表。
  void connect() {
    if (_connected) return;
    _connected = true;
    _setStatus('本机模式');
    final history = LocalDialogue.messages(dialogueId, limit: 40);
    if (turns.isEmpty && history.isNotEmpty) {
      for (final m in history) {
        final role = '${m['role'] ?? ''}';
        if (role != 'user' && role != 'ai' && role != 'blocked') continue;
        turns.add(ChatTurn(
          role: role,
          content: '${m['content'] ?? ''}',
          mode: '${m['mode'] ?? currentMode.name}',
          engine: '${m['engine'] ?? ''}',
        ));
      }
      notifyListeners();
    }
  }

  void _handle(Map<String, dynamic> j) {
    if (_disposed) return;
    final type = '${j['type'] ?? ''}';
    switch (type) {
      case 'ai_message':
        _pending = false;
        _lastError = null;
        _timeout?.cancel();
        final provenance = ((j['provenance'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => ProvenanceCard.fromJson(e.cast<String, dynamic>()))
            .toList();
        final sourceIds = ((j['source_chunks'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => '${e['chunk_id'] ?? e['id'] ?? ''}')
            .where((e) => e.isNotEmpty)
            .toList();
        turns.add(ChatTurn(
          role: 'ai',
          content: '${j['content'] ?? ''}',
          mode: '${j['mode'] ?? currentMode.name}',
          provenance: provenance,
          sourceChunks: sourceIds,
          exempt: (j['guard'] as Map?)?['exempt'] == true,
          engine: '${j['engine'] ?? ''}',
          engineNote: '${j['engine_note'] ?? ''}',
        ));
        break;
      case 'blocked':
        _pending = false;
        _lastError = null;
        _timeout?.cancel();
        turns.add(ChatTurn(
          role: 'blocked',
          content: '${j['fallback'] ?? '该提问触发防偏离规则。'}',
          blockedReason: '${j['reason'] ?? ''}',
          allowCriticalReading: j['allow_critical_reading'] == true,
          mode: _lastMode.name,
        ));
        break;
      case 'error':
        _fail('${j['message'] ?? '本机处理失败'}');
        return;
      default:
        break;
    }
    notifyListeners();
  }

  void _fail(String message) {
    if (_disposed) return;
    _pending = false;
    _lastError = message;
    _timeout?.cancel();
    notifyListeners();
  }

  void send(
      {required String content,
      String selectedText = '',
      String paragraphId = ''}) {
    if (content.trim().isEmpty) return;
    // 选中片段在**发出前**就按两端同口径净化：正文页全选整章会有几万字，
    // 联网版后端也会截（`_safe_selected_text`），但没必要先把几十 KB 推过 WS。
    selectedText = LocalDialogue.sanitizeSelection(selectedText);
    // 模式**只对带选区的那一条提问生效**：释义/追问/辩难/关联都是「就这段原文怎么展开」，
    // 没有选区时没有任何原文可展开，一律按普通对话回答。
    // 选区分发完把当前模式回落到普通对话：对话框里此后打字就是聊天，不再沿用上一个模式。
    final mode = selectedText.trim().isEmpty ? ChatMode.chat : currentMode;
    currentMode = ChatMode.chat;
    if (!_connected) connect();
    turns.add(ChatTurn(
      role: 'user',
      content: content,
      mode: mode.name,
      selectedText: selectedText,
    ));
    _pending = true;
    _lastError = null;
    _lastQuestion = content;
    _lastSelectedText = selectedText;
    _lastParagraphId = paragraphId;
    _lastMode = mode;
    _timeout?.cancel();
    _timeout = Timer(_requestTimeout, () {
      if (_pending) _fail('回答生成超时，请点「重试」');
    });
    notifyListeners();
    LocalDialogue.respond(
      dialogueId: dialogueId,
      content: content,
      selectedText: selectedText,
      paragraphId: paragraphId,
      mode: mode.name,
      criticalReading: criticalReading,
    ).then(_handle).catchError((Object e) {
      _fail('本机生成失败: $e');
    });
  }

  /// 用上一次的问题/锚点重试。
  void retryLast() {
    final q = _lastQuestion;
    if (q == null || q.trim().isEmpty) return;
    // 重试沿用**上一条**的模式：带选区的重试仍是同一个模式，否则回到普通对话。
    currentMode = _lastSelectedText.trim().isEmpty ? ChatMode.chat : _lastMode;
    final anchor = _lastSelectedText;
    final paragraph = _lastParagraphId;
    send(content: q, selectedText: anchor, paragraphId: paragraph);
  }

  void switchMode(ChatMode m) {
    currentMode = m;
    notifyListeners();
  }

  void toggleCriticalReading() {
    criticalReading = !criticalReading;
    notifyListeners();
  }

  void clear() {
    turns.clear();
    _pending = false;
    _lastError = null;
    _lastQuestion = null;
    _timeout?.cancel();
    notifyListeners();
  }

  void _setStatus(String s) {
    _status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timeout?.cancel();
    super.dispose();
  }
}
