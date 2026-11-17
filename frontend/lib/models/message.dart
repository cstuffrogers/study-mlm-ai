// 后端协议对齐模型 — 见 backend/websocket/protocol.py
// 5 模式 + 消息 + 溯源卡片 + blocked 状态

enum ChatMode {
  explain,  // 释义
  dig,      // 追问
  debate,   // 辩难
  connect,  // 关联
  test,     // 应试
}

extension ChatModeX on ChatMode {
  String get label => const ['释义', '追问', '辩难', '关联', '应试'][index];
  String get name => const ['explain', 'dig', 'debate', 'connect', 'test'][index];
  int get color => const [
        0xFFC8161D, // 释义 · 党旗红
        0xFF10B981, // 追问 · 翠绿
        0xFFD4A017, // 辩难 · 扬金
        0xFFF59E0B, // 关联 · 橙
        0xFF2563EB, // 应试 · 靖蓝（NFR-019 五模式五色；曾与辩难同为扬金）
      ][index];

  /// 一句话说明「这个模式会给出什么」。
  /// 必须与本机引擎 `_compose` 的真实产物一致——不能在界面上承诺它做不到的事。
  String get desc => const [
        '逐字引文当依据：概念界定、它不是什么、怎么自查',
        '只提问不给答案，按原句递进追问三步',
        '先摆反方质疑（基于本轮引文的强断言），再给回应要点',
        '概念的上下位与对立关系，加上别部著作的逐字用例',
        '应试答题架子，并预演一道题、标出得分点',
      ][index];

  /// 输入框的提示语：让用户发问前就知道当前用哪种方式回答。
  String get inputHint => '以「$label」追问…';
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
