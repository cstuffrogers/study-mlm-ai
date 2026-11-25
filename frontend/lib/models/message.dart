// 后端协议对齐模型 — 见 backend/websocket/protocol.py
// 5 模式 + 消息 + 溯源卡片 + blocked 状态

enum ChatMode {
  chat,     // 对话（对话框默认，也是唯一可直接打字的模式；界面名就叫「对话」）
  explain,  // 释义
  dig,      // 追问
  debate,   // 辩难
  connect,  // 关联
}

/// 选区（选中原文）浮框里的模式列表：对话 + 四种模式，共五枚 chip。
/// 「对话」排最前：点它就是「带着这句原文直接问」，与对话框里打字的默认路径同一条，
/// 只是把选中的这句话一起塞进提示词，不需要先打了字再选中原文。
/// 选区面板一律遍历这份列表，不要用 `ChatMode.values`
/// （顺序要由这里定：对话在前，四种模式在后）。
const List<ChatMode> kSelectionModes = [
  ChatMode.chat,
  ChatMode.explain,
  ChatMode.dig,
  ChatMode.debate,
  ChatMode.connect,
];

extension ChatModeX on ChatMode {
  String get label => const ['对话', '释义', '追问', '辩难', '关联'][index];
  String get name => const ['chat', 'explain', 'dig', 'debate', 'connect'][index];
  int get color => const [
        0xFF475569, // 对话 · 石墨灰
        0xFFC8161D, // 释义 · 党旗红
        0xFF10B981, // 追问 · 翠绿
        0xFFD4A017, // 辩难 · 扬金
        0xFFF59E0B, // 关联 · 橙
      ][index];

  /// 一句话说明「这个模式会给出什么」。
  /// 必须与本机引擎 `_compose` 的真实产物一致——不能在界面上承诺它做不到的事。
  String get desc => const [
        '直接回答你的问题，引原文当依据，不套模式架子',
        '逐字引文当依据：概念界定、它不是什么、怎么自查',
        '只提问不给答案，按原句递进追问三步',
        '先摆反方质疑（基于本轮引文的强断言），再给回应要点',
        '概念的上下位与对立关系，加上别部著作的逐字用例',
      ][index];

  /// 输入框的提示语：让用户发问前就知道当前用哪种方式回答。
  String get inputHint => this == ChatMode.chat ? '问点什么…' : '以「$label」追问…';

  /// 选区浮框里点这枚 chip 时会默认发出去的那句话。
  /// 对话不套模式词（它不是一种训练，直接问「这段在说什么」），
  /// 选中的原文另外以 `selectedText` 带上，浮框那侧会拼进提示词。
  String askPrompt([String subject = '原文']) =>
      this == ChatMode.chat ? '这段在说什么？' : '请就这段$subject展开$label';
}

// C→S 用户消息
class UserMessage {
  final String type;
  final String dialogueId;
  final String content;
  final String selectedText;
  final String paragraphId;
  final String mode;
  final bool criticalReading;

  UserMessage({
    required this.dialogueId,
    required this.content,
    this.selectedText = '',
    this.paragraphId = '',
    this.mode = 'explain',
    this.criticalReading = false,
  }) : type = 'user_message';

  Map<String, dynamic> toJson() => {
        'type': type,
        'dialogue_id': dialogueId,
        'content': content,
        'selected_text': selectedText,
        'paragraph_id': paragraphId,
        'mode': mode,
        'critical_reading': criticalReading,
      };
}

// 溯源卡片（FR-017）
class ProvenanceCard {
  final String chunkId;
  final String source;
  final String location;
  final double authorityScore;
  final int layer;
  final String excerpt;
  final String factCheck;
  final String terminologyCheck;
  final String stanceCheck;

  ProvenanceCard({
    required this.chunkId,
    required this.source,
    required this.location,
    required this.authorityScore,
    required this.layer,
    required this.excerpt,
    this.factCheck = 'pass',
    this.terminologyCheck = 'pass',
    this.stanceCheck = 'pass',
  });

  factory ProvenanceCard.fromJson(Map<String, dynamic> j) => ProvenanceCard(
        chunkId: j['chunk_id'] ?? '',
        source: j['source'] ?? '',
        location: j['location'] ?? '',
        authorityScore: (j['authority_score'] ?? 0.9).toDouble(),
        layer: j['layer'] ?? 1,
        excerpt: j['excerpt'] ?? '',
        factCheck: j['fact_check'] ?? 'pass',
        terminologyCheck: j['terminology_check'] ?? 'pass',
        stanceCheck: j['stance_check'] ?? 'pass',
      );
}

// S→C 消息（统一信封）
class ServerMessage {
  final String type;
  final Map<String, dynamic> raw;

  ServerMessage(this.type, this.raw);

  String? get aiContent => type == 'ai_message' ? raw['content'] as String? : null;
  bool? get aiIsSafe => type == 'ai_message' ? raw['is_safe'] as bool? : null;
  String? get aiMode => type == 'ai_message' ? raw['mode'] as String? : null;
  Map<String, dynamic>? get guard => type == 'ai_message' ? raw['guard'] as Map<String, dynamic>? : null;
  bool get exempt => (guard?['exempt'] ?? false) as bool;
  List<ProvenanceCard> get provenance {
    final list = raw['provenance'] as List?;
    return list?.map((e) => ProvenanceCard.fromJson(e as Map<String, dynamic>)).toList() ?? [];
  }

  /// 结构化相关原文（后端剥离编码后给出，仅取 id 用于「相关原文」按钮）。
  List<String> get sourceChunkIds {
    if (type != 'ai_message') return const [];
    final list = raw['source_chunks'] as List?;
    if (list == null) return const [];
    final out = <String>[];
    for (final e in list) {
      final id = (e is Map ? (e['chunk_id'] ?? e['id']) : e)?.toString().trim() ?? '';
      if (id.isNotEmpty) out.add(id);
    }
    return out;
  }

  // error（后端 ErrorOut）
  String? get errorCode => type == 'error' ? raw['code'] as String? : null;
  String? get errorMessage => type == 'error' ? raw['message'] as String? : null;

  // blocked
  String? get blockedReason => type == 'blocked' ? raw['reason'] as String? : null;
  String? get blockedLayer => type == 'blocked' ? raw['layer'] as String? : null;
  String? get blockedFallback => type == 'blocked' ? raw['fallback'] as String? : null;
  bool get allowCriticalReading => type == 'blocked' ? (raw['allow_critical_reading'] ?? false) as bool : false;

  // US2 即时小结
  Map<String, dynamic>? get instantSummary =>
      type == 'ai_message' ? (raw['instant_summary'] as Map?)?.cast<String, dynamic>() : null;

  // US2 卡顿信号
  String? get struggleNodeId => type == 'struggle_detected' ? raw['node_id'] as String? : null;
  String? get struggleType => type == 'struggle_detected' ? raw['signal_type'] as String? : null;

  factory ServerMessage.fromJson(Map<String, dynamic> j) =>
      ServerMessage(j['type'] as String? ?? '', j);
}
