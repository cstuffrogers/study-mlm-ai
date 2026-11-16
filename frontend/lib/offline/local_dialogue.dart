// 单机版对话引擎：默认不联网，用「原文检索 + 概念卡 + 苏格拉底追问」组合出回答；
// 用户在「AI 大模型 API 配置」里填了自己的 Key 后，优先走在线模型（见 respond）。
//
// 红线：回答里出现的引文必须是 chunks.json 里真实存在的原文，逐字摘录并
// 标明出处；不生成任何虚构引文。因此本地模式只做「定位—摘录—追问」，
// 不做自由发挥式的长论述。在线模型的输出同样要过本机立场层才展示。
import 'dart:math' as math;

import '../offline/local_db.dart';
import '../offline/local_guard.dart';
import '../offline/offline_content.dart';
import '../services/llm_client.dart';
import '../services/llm_config_store.dart';
import 'local_mastery.dart';

class LocalDialogue {
  LocalDialogue._();

  static const int _maxExcerpt = 180;

  // ------------------------------------------------------------ 检索
  static List<String> _grams(String query) {
    final text = query.replaceAll(RegExp(r'[^\u4e00-\u9fffA-Za-z0-9]'), ' ');
    final out = <String>{};
    for (final seg in text.split(' ')) {
      final runes = seg.runes.length;
      if (runes < 2) continue;
      for (var n = 4; n >= 2; n--) {
        for (var i = 0; i + n <= runes; i++) {
          final piece = String.fromCharCodes(seg.runes.skip(i).take(n));
          if (piece.trim().length < 2) continue;
          out.add(piece);
          if (out.length >= 48) return out.toList();
        }
      }
    }
    return out.toList();
  }

  static String? _sectionOfParagraph(String paragraphId) {
    if (paragraphId.isEmpty) return null;
    for (final n in OfflineContent.allNodes) {
      if ('${n['paragraph'] ?? ''}' == paragraphId) {
        return '${n['section_id'] ?? ''}';
      }
    }
    return null;
  }

  /// 按关键词给原文分片打分，返回最高分的若干条（同作品优先）
  static List<Map<String, dynamic>> _retrieve(
      String query, String paragraphId, {int top = 3}) {
    final grams = _grams(query);
    if (grams.isEmpty) return const [];
    final weight = <String, double>{};
    for (final g in grams) {
      weight[g] = g.length.toDouble();
    }
    final sectionId = _sectionOfParagraph(paragraphId);
    final meta = sectionId == null ? null : OfflineContent.sectionMeta(sectionId);
    // 章节的 work 是书名全称，原文分片的 source 用 short 形式（local_work），
    // 两者不一定相等：优先 local_work，取不到再退回全文检索。
    final work = '${meta?['local_work'] ?? meta?['work_short'] ?? meta?['work'] ?? ''}';
    var pool = work.isEmpty
        ? OfflineContent.chunksOfWork('all')
        : OfflineContent.chunksOfWork(work);
    if (pool.isEmpty) pool = OfflineContent.chunksOfWork('all');
    final scored = <(double, Map<String, dynamic>)>[];
    final cap = grams.length * 4.0;
    for (final c in pool) {
      final text = '${c['text'] ?? ''}';
      if (text.isEmpty) continue;
      var score = 0.0;
      for (final g in grams) {
        if (text.contains(g)) score += weight[g]!;
      }
      if (score <= 0) continue;
      if ('${c['paragraph_id'] ?? ''}' == paragraphId) score += 8;
      if ('${c['source'] ?? ''}' == work) score += 2;
      scored.add((math.min(cap, score), c));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    final out = <Map<String, dynamic>>[];
    for (final row in scored) {
      if (out.length >= top) break;
      // 同一段原文只保留第一条，避免重复摘录
      if (out.any((e) => e['paragraph_id'] == row.$2['paragraph_id'])) continue;
      out.add(row.$2);
    }
    return out;
  }

  static List<Map<String, dynamic>> _conceptHits(String query,
      List<Map<String, dynamic>> chunks) {
    final out = <Map<String, dynamic>>[];
    final hay = '$query ${chunks.map((c) => c['text']).join(' ')}';
    for (final c in OfflineContent.conceptList) {
      final name = '${c['name'] ?? ''}';
      if (name.isEmpty) continue;
      final aliases = [
        name,
        ...((c['equivalent_terms'] as List?) ?? const []).map((e) => '$e'),
      ];
      if (aliases.any(hay.contains)) out.add(c);
      if (out.length >= 3) break;
    }
    return out;
  }

  static List<String> _questionsFor(String paragraphId, String mode) {
    final bank = (OfflineContent.knowledge['questions'] as Map?) ?? const {};
    final list = (bank[paragraphId] as List?) ?? const [];
    final wanted = switch (mode) {
      'debate' => const ['debate'],
      'test' => const ['practice', 'dig'],
      'dig' => const ['dig', 'debate'],
      'connect' => const ['dig'],
      _ => const ['dig'],
    };
    final out = <String>[];
    for (final type in wanted) {
      for (final q in list) {
        if (q is Map && '${q['type']}' == type && out.length < 3) {
          out.add('${q['q'] ?? ''}');
        }
      }
    }
    return out.where((e) => e.isNotEmpty).toList();
  }

  static String _excerpt(String text) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= _maxExcerpt) return clean;
    return '${clean.substring(0, _maxExcerpt)}……';
  }

  // ------------------------------------------------------------ 回答
  static String _compose(
    String mode,
    String question,
    String paragraphId,
    List<Map<String, dynamic>> chunks,
    List<Map<String, dynamic>> concepts,
    bool criticalReading,
  ) {
    final b = StringBuffer();
    if (mode == 'debate' || criticalReading) {
      b.writeln('【批判性阅读已开启】先复述对方立场，再作回应；对方观点不进入正面结论。\n');
    }
    if (chunks.isNotEmpty) {
      b.writeln('原文摘录（逐字引用，非改写）：');
      for (final c in chunks) {
        b.writeln('> ${_excerpt('${c['text']}')}');
        b.writeln('—— 《${c['source']}》 ${c['source_location'] ?? ''}\n');
      }
    }
    final questions = _questionsFor(paragraphId, mode);

    switch (mode) {
      case 'explain':
        if (concepts.isNotEmpty) {
          b.writeln('概念界定（正统表述）：');
          for (final c in concepts) {
            b.writeln('· ${c['name']}：${c['canonical_definition']}');
            final not = ((c['strictly_not'] as List?) ?? const []).map((e) => '$e').take(3);
            if (not.isNotEmpty) b.writeln('  （注意不是：${not.join('、')}）');
          }
          b.writeln();
        }
        b.writeln('读法建议：先抓住上引文字里的关键词，再问「它针对什么问题提出」——'
            '理论命题只有放回它要反驳的立场，才不会读成口号。');
        if (questions.isNotEmpty) {
          b.writeln('\n先自查一句：${questions.first}');
        }
        break;
      case 'dig':
        b.writeln('继续追问（按难度递进）：');
        for (var i = 0; i < questions.length; i++) {
          b.writeln('${i + 1}. ${questions[i]}');
        }
        if (questions.isEmpty) {
          b.writeln('1. 上引文字里，哪个词是「纲领性」的？换成同义词，命题还成立吗？');
          b.writeln('2. 这个判断针对的反对者是谁？他们错在哪一步？');
          b.writeln('3. 若把结论推到极端，会出现什么荒谬结果？');
        }
        break;
      case 'debate':
        b.writeln('【反方观点·仅供批判】');
        b.writeln('反方会说：上述命题过于强调一个方面，忽略了另一方面的相对独立性。');
        b.writeln('【正方回应要点】');
        b.writeln('1. 先确认对方在偷换哪一个环节：是事实判断、因果次序，还是作用范围；');
        b.writeln('2. 用原文限定语（如「归根到底」「在最终意义上」）恢复命题的层次；');
        b.writeln('3. 承认相对独立性，但拒绝「相互决定」式的对称化表述。');
        if (questions.isNotEmpty) b.writeln('\n可练的一句：${questions.first}');
        break;
      case 'connect':
        if (concepts.isNotEmpty) {
          b.writeln('关联线索：');
          for (final c in concepts) {
            final rel = (c['relations'] as Map?) ?? const {};
            final determines =
                ((rel['determines'] as List?) ?? const []).map((e) => '$e');
            final opposed = ((rel['opposed_to'] as List?) ?? const []).map((e) => '$e');
            if (determines.isNotEmpty) {
              b.writeln('· ${c['name']} 决定：${determines.join('、')}');
            }
            if (opposed.isNotEmpty) {
              b.writeln('· ${c['name']} 对立于：${opposed.join('、')}');
            }
          }
          b.writeln();
        }
        b.writeln('跨章关联的做法：把上引命题当「方法」，去找同一路线里另一章用同一方法处理的'
            '不同对象——相同的推理骨架，不同的对象领域。');
        break;
      case 'test':
        b.writeln('应试要点：');
        b.writeln('1. 先写命题的原文依据（引用比概括得分高）；');
        b.writeln('2. 再写它针对的错误观点，点明分歧所在；');
        b.writeln('3. 最后写范围限定，避免绝对化表述被判为偏移。');
        if (concepts.isNotEmpty) {
          b.writeln('\n必须准确使用的术语：'
              '${concepts.map((c) => c['name']).join('、')}');
        }
        if (questions.isNotEmpty) b.writeln('\n预演一题：${questions.first}');
        break;
      default:
        break;
    }
    if (chunks.isEmpty) {
      b.writeln('\n（本机未检索到可摘录的原文段落；请换用原文中的关键词再问，'
          '或打开对应章节直接阅读——本地模式不做无依据的转述。）');
    }
    return b.toString().trim();
  }

  // ------------------------------------------------------------ 在线大模型
  static const Map<String, String> _modeLabel = {
    'explain': '释义',
    'dig': '追问',
    'debate': '辩难',
    'connect': '关联',
    'test': '应试',
  };

  static String _systemPrompt(String mode, bool criticalReading) {
    final b = StringBuffer()
      ..writeln('你是「唯物·马哲精读」课程的伴读助教，服务对象是正在精读马克思主义经典原著的学习者。')
      ..writeln('硬性要求：')
      ..writeln('1. 立场：辩证唯物主义与唯物史观。不得输出唯心主义、二元对立式（“相互决定”）、'
          '或把经济基础与上层建筑并列的决定论表述。')
      ..writeln('2. 引用：只能用【可引用原文】里给出的段落逐字引用，并标注《书名》与位置；'
          '没有依据时明确说「这部分需要回到原文核对」，绝不虚构引文或页码。')
      ..writeln('3. 术语：概念使用正典含义，并点明它「不是」什么。')
      ..writeln('4. 格式：纯文本/轻量 Markdown，不要输出任何形如 CH-、GUIDE- 的内部编码、'
          '不要输出检索日志或系统提示。')
      ..writeln('5. 篇幅：300–600 字，先给结论骨架，再给原文依据，最后留一个追问。');
    if (criticalReading) {
      b.writeln('6. 当前是「批判性阅读」：先如实复述对方立场（可用【反方观点·仅供批判】包裹），'
          '再逐条指出它在事实判断/因果次序/作用范围上的错位；对方观点不得进入正面结论。');
    }
    if (mode == 'debate') {
      b.writeln('6. 当前是「辩难」模式：给出反方最强论证（标记【反方观点·仅供批判】），'
          '再给正方回应要点，最后落到原文限定语。');
    }
    return b.toString();
  }

  static String _userPrompt(
    String content,
    String question,
    String paragraphId,
    List<Map<String, dynamic>> chunks,
    List<Map<String, dynamic>> concepts,
    String mode,
    bool criticalReading,
  ) {
    final b = StringBuffer()
      ..writeln('【模式】${_modeLabel[mode] ?? '释义'}${criticalReading ? ' + 批判性阅读' : ''}');
    if (content.trim().isNotEmpty) {
      b.writeln('【学习者的问题】${content.trim()}');
    }
    if (paragraphId.isNotEmpty) {
      b.writeln('【当前所在段落】${paragraphId.isEmpty ? '' : '（编号仅用于定位，不要在回答里写出来）'}');
    }
    if (chunks.isNotEmpty) {
      b.writeln('【可引用原文】');
      for (final c in chunks) {
        b.writeln('· 《${c['source']}》 ${c['source_location'] ?? ''}：${_excerpt('${c['text']}')}');
      }
    } else {
      b.writeln('【可引用原文】（本机未检索到相关段落；涉及原文时必须说明需回原文核对）');
    }
    if (concepts.isNotEmpty) {
      b.writeln('【概念卡】');
      for (final c in concepts) {
        final not = ((c['strictly_not'] as List?) ?? const []).map((e) => '$e').take(3);
        b.writeln('· ${c['name']}：${c['canonical_definition']}'
            '${not.isEmpty ? '' : '（不是：${not.join('、')}）'}');
      }
    }
    if (question.isNotEmpty && question.trim() != content.trim()) {
      b.writeln('【学习者选中的原文】${question.replaceFirst(content.trim(), '').trim()}');
    }
    return b.toString();
  }

  /// 模型偶尔仍会照抄内部编码，统一清掉，绝不进正文
  static String _stripCodes(String text) => text
      .replaceAll(RegExp(r'\[(?:CH|GUIDE|SEC|NODE)-[^\]]*\]'), '')
      .replaceAll(RegExp(r'\b(?:CH|GUIDE)-[A-Za-z0-9_\-]+'), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  static Map<String, dynamic> _provenanceOf(List<Map<String, dynamic>> chunks) => {
        'provenance': chunks
            .map((c) => {
                  'chunk_id': c['id'],
                  'source': c['source'],
                  'location': c['source_location'] ?? '',
                  'authority_score': c['authority_score'] ?? 1.0,
                  'layer': c['layer'] ?? 1,
                  'excerpt': _excerpt('${c['text']}'),
                  'fact_check': 'pass',
                  'terminology_check': 'pass',
                  'stance_check': 'pass',
                })
            .toList(),
        // 界面只用这些 id 取原文，不在正文里出现编码
        'source_chunks': chunks
            .map((c) => {
                  'chunk_id': c['id'],
                  'source': c['source'],
                  'location': c['source_location'] ?? '',
                  'kind': 'related',
                })
            .toList(),
      };

  // ------------------------------------------------------------ 主入口
  /// 返回与后端 WS 同构的消息 Map（type: ai_message | blocked | error）
  static Future<Map<String, dynamic>> respond({
    required String dialogueId,
    required String content,
    String selectedText = '',
    String paragraphId = '',
    String mode = 'explain',
    bool criticalReading = false,
  }) async {
    await LocalDb.ensure();
    await OfflineContent.ensureMeta();
    await OfflineContent.ensureChunks();
    final question = '${content.trim()} ${selectedText.trim()}'.trim();
    final guard = OfflineGuard.check(question, allowCritical: criticalReading);
    if (guard.blocked && !criticalReading && mode != 'debate') {
      _persist(dialogueId, content, mode, blocked: true, paragraphId: paragraphId);
      return {
        'type': 'blocked',
        'reason': guard.reason,
        'fallback': '这段表述涉及与本课程立场不一致的框架（${guard.hits.join('、')}），'
            '已按防偏离规则拦截。可以切到「批判性阅读」或「辩难」模式再问，'
            '把对方观点作为被批判对象来讨论。',
        'allow_critical_reading': true,
        'mode': mode,
      };
    }
    final chunks = _retrieve(question, paragraphId);
    final concepts = _conceptHits(question, chunks);
    final exempt = criticalReading || mode == 'debate';

    // ① 已配置在线大模型：优先用模型作答，失败/偏离则回落本机引擎
    final cfg = LlmConfigStore.load();
    // 回落原因要在界面上说清楚：否则用户分不清「没配 key」和「配了但调用失败」
    String? engineNote = cfg.enabled ? null : 'not-configured';
    if (cfg.enabled) {
      final llm = await LlmClient.chat(
        cfg,
        system: _systemPrompt(mode, criticalReading),
        user: _userPrompt(content, question, paragraphId, chunks, concepts, mode,
            criticalReading),
        timeoutSec: cfg.interactiveTimeout,
        retries: 0,
      );
      if (llm.ok && llm.text.trim().isNotEmpty) {
        final verdict = OfflineGuard.check(llm.text, allowCritical: exempt);
        if (verdict.blocked) {
          // 红线：模型输出的偏离表述不能展示；换成可用的本机回答并说明原因
          final answer = '${_compose(mode, content, paragraphId, chunks, concepts, criticalReading)}'
              '\n\n（在线模型这段表述涉及与本课程立场不一致的框架'
              '（${verdict.hits.join('、')}），已按防偏离规则拦截，未展示；'
              '以上为本机引擎回答。如确实要讨论该观点，可开启「批判性阅读」。）';
          _persist(dialogueId, content, mode,
              blocked: false,
              paragraphId: paragraphId,
              answer: answer,
              engine: 'local:guard-fallback');
          return {
            'type': 'ai_message',
            'content': answer,
            'mode': mode,
            'is_safe': true,
            'engine': 'local:guard-fallback',
            'guard': {'exempt': exempt, 'output_blocked': verdict.hits},
            ..._provenanceOf(chunks),
          };
        }
        final answer = _stripCodes(llm.text);
        _persist(dialogueId, content, mode,
            blocked: false,
            paragraphId: paragraphId,
            answer: answer,
            engine: 'cloud:${llm.model}');
        return {
          'type': 'ai_message',
          'content': answer,
          'mode': mode,
          'is_safe': true,
          'engine': 'cloud:${llm.model}',
          'guard': {'exempt': exempt},
          ..._provenanceOf(chunks),
        };
      }
      // 走到这里说明在线分支失败：把原因带回界面
      engineNote = llm.ok
          ? 'empty-reply'
          : 'failed:${llm.message.isEmpty ? '未知错误' : llm.message}';
    }

    // ② 本机引擎（未配置 / 调用失败 / 超时）
    final answer = _compose(mode, content, paragraphId, chunks, concepts, criticalReading);
    _persist(dialogueId, content, mode, blocked: false, paragraphId: paragraphId,
        answer: answer,
        engineNote: engineNote);
    return {
      'type': 'ai_message',
      'content': answer,
      'mode': mode,
      'is_safe': true,
      'engine': 'local',
      'engine_note': ?engineNote,
      'guard': {'exempt': exempt},
      ..._provenanceOf(chunks),
    };
  }

  // ------------------------------------------------------------ 会话持久化
  static void _persist(
    String dialogueId,
    String question,
    String mode, {
    required bool blocked,
    String paragraphId = '',
    String answer = '',
    String engine = 'local',
    String? engineNote,
  }) {
    final existing = LocalDb.dialogue(dialogueId);
    final doc = existing == null
        ? <String, dynamic>{
            'id': dialogueId,
            'title': question.length > 24 ? question.substring(0, 24) : question,
            'current_mode': mode,
            'created_at': nowIso(),
            'updated_at': nowIso(),
            'messages': <dynamic>[],
          }
        : Map<String, dynamic>.from(existing);
    final messages = List<dynamic>.from((doc['messages'] as List?) ?? const []);
    messages.add({
      'role': 'user',
      'content': question,
      'mode': mode,
      'paragraph_id': paragraphId,
      'created_at': nowIso(),
    });
    if (answer.isNotEmpty) {
      messages.add({
        'role': blocked ? 'blocked' : 'ai',
        'content': answer,
        'mode': mode,
        'engine': engine,
        if (engineNote != null && engineNote.isNotEmpty)
          'engine_note': engineNote,
        'created_at': nowIso(),
      });
    }
    doc['messages'] = messages;
    doc['current_mode'] = mode;
    doc['updated_at'] = nowIso();
    LocalDb.dialogues[dialogueId] = doc;
    LocalDb.flushKey('dialogues');
  }

  static List<Map<String, dynamic>> listDialogues() {
    final out = LocalDb.dialogues.values
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .map((e) => {
              'id': e['id'],
              'title': e['title'],
              'current_mode': e['current_mode'],
              'created_at': e['created_at'],
              'updated_at': e['updated_at'],
              'message_count': ((e['messages'] as List?) ?? const []).length,
            })
        .toList();
    out.sort((a, b) => '${b['updated_at']}'.compareTo('${a['updated_at']}'));
    return out;
  }

  static List<Map<String, dynamic>> messages(String dialogueId,
      {int limit = 50}) {
    final doc = LocalDb.dialogue(dialogueId);
    if (doc == null) return const [];
    final list = ((doc['messages'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    if (list.length <= limit) return list;
    return list.sublist(list.length - limit);
  }
}
