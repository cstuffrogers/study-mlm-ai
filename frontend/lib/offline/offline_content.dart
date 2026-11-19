// 单机版离线内容层：把后端编译好的资产（assets/offline/）读进内存并建索引。
//
// 设计要点：
//   · meta / knowledge 很小，首次用到时同步解析；
//   · chunks（约 15MB）与 quiz 按需懒加载，避免启动即卡；
//   · 全部按 chunk_id / work / paragraph / section 建 Map 索引，查询 O(1)；
//   · 只做读取，不写任何数据（用户学情在 LocalDb）。
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

Map<String, dynamic> _decodeMap(String s) =>
    (jsonDecode(s) as Map).cast<String, dynamic>();

class OfflineContent {
  OfflineContent._();

  static const String _dir = 'assets/offline';

  static Map<String, dynamic> _meta = const {};
  static Map<String, dynamic> _knowledge = const {};
  static Map<String, List<Map<String, dynamic>>> _workSections = const {};
  static List<Map<String, dynamic>> _chunks = const [];
  static Map<String, List<Map<String, dynamic>>> _quiz = const {};

  static final Map<String, Map<String, dynamic>> _chunkById = {};
  static final Map<String, List<Map<String, dynamic>>> _chunksByWork = {};
  static final Map<String, List<Map<String, dynamic>>> _chunksByParagraph = {};
  static final Map<String, Map<String, dynamic>> _sectionCache = {};
  static final Map<String, Map<String, dynamic>> _sectionMetaById = {};
  static final Map<String, List<Map<String, dynamic>>> _nodesBySection = {};
  /// 节点 id → 节点定义。`node()` 是作答归属解析、错题回填、复习队列的
  /// 热路径（每条作答都可能查一次），用 Map 索引把 O(节点数) 的线性扫描
  /// 降为 O(1)，避免大数据量下分析页整链被拖慢。
  static final Map<String, Map<String, dynamic>> _nodeById = {};

  static bool _metaReady = false;
  static bool _chunksReady = false;
  static bool _quizReady = false;
  static Future<void>? _metaLoading;
  static Future<void>? _chunksLoading;
  static Future<void>? _quizLoading;

  /// 读取失败时降级为空数据（例如未绑定 WidgetsBinding 的纯单元测试）。
  static Future<String?> _load(String name) async {
    try {
      return await rootBundle.loadString('$_dir/$name');
    } catch (e) {
      // ignore: avoid_print
      print('OfflineContent 资源缺失 $name: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------- 元数据
  static Future<void> ensureMeta() {
    if (_metaReady) return Future.value();
    return _metaLoading ??= () async {
      final metaRaw = await _load('meta.json');
      final knowledgeRaw = await _load('knowledge.json');
      final indexRaw = await _load('work_sections.json');
      _meta = metaRaw == null ? const {} : _decodeMap(metaRaw);
      _knowledge = knowledgeRaw == null ? const {} : _decodeMap(knowledgeRaw);
      if (indexRaw != null) {
        _workSections = _decodeMap(indexRaw).map(
            (work, rows) => MapEntry(work, _list(rows)));
      }
      for (final s in _list(_meta['sections'])) {
        _sectionMetaById[s['id'] as String] = s;
      }
      for (final n in _list(_meta['nodes'])) {
        final sid = n['section_id'] as String? ?? '';
        (_nodesBySection[sid] ??= <Map<String, dynamic>>[]).add(n);
        _nodeById['${n['id']}'] = n;
      }
      _metaReady = true;
    }();
  }

  static Future<void> ensureChunks() {
    if (_chunksReady) return Future.value();
    return _chunksLoading ??= () async {
      await ensureMeta();
      final rawText = await _load('chunks.json');
      final raw = rawText == null ? const [] : (jsonDecode(rawText) as List);
      final list = <Map<String, dynamic>>[];
      for (final e in raw) {
        final c = (e as Map).cast<String, dynamic>();
        list.add(c);
        final id = c['id'] as String? ?? '';
        if (id.isEmpty) continue;
        _chunkById[id] = c;
        final work = c['source'] as String? ?? '';
        (_chunksByWork[work] ??= <Map<String, dynamic>>[]).add(c);
        final pid = c['paragraph_id'] as String? ?? '';
        if (pid.isNotEmpty) {
          (_chunksByParagraph[pid] ??= <Map<String, dynamic>>[]).add(c);
        }
      }
      _chunks = list;
      _chunksReady = true;
    }();
  }

  static Future<void> ensureQuiz() {
    if (_quizReady) return Future.value();
    return _quizLoading ??= () async {
      await ensureMeta();
      final rawText = await _load('quiz.json');
      final root = rawText == null ? const <String, dynamic>{} : _decodeMap(rawText);
      final secs = (root['sections'] as Map?)?.cast<String, dynamic>() ?? const {};
      _quiz = secs.map(
          (k, v) => MapEntry(k, _list(v).map((e) => (e as Map).cast<String, dynamic>()).toList()));
      _quizById = null; // 重建 id 索引
      _quizReady = true;
    }();
  }

  static Future<void> ensureAll() async {
    await ensureMeta();
    await Future.wait([ensureChunks(), ensureQuiz()]);
  }

  static List<Map<String, dynamic>> _list(dynamic v) =>
      ((v as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();

  // ---------------------------------------------------------------- 查询
  static List<Map<String, dynamic>> get routes =>
      _list(_meta['routes']).toList(growable: false);

  static Map<String, dynamic> get knowledge => _knowledge;

  static Map<String, dynamic> get config =>
      (_knowledge['config'] as Map?)?.cast<String, dynamic>() ?? const {};

  static List<Map<String, dynamic>> get allSections =>
      _list(_meta['sections']).toList(growable: false);

  static List<Map<String, dynamic>> get allNodes =>
      _list(_meta['nodes']).toList(growable: false);

  static List<Map<String, dynamic>> get works => _list(_meta['works']);

  static Map<String, dynamic>? sectionMeta(String sectionId) => _sectionMetaById[sectionId];

  /// 某部原著在学习路线里出现在哪些章（主线主书在前，延伸阅读在后）。
  /// 无索引数据时返回空列表（旧资产兼容）。
  static List<Map<String, dynamic>> sectionsOfWork(String work) =>
      _workSections[work] ?? const <Map<String, dynamic>>[];

  static List<Map<String, dynamic>> sectionsOf(String routeId) {
    final out = allSections.where((s) => s['route_id'] == routeId).toList();
    out.sort((a, b) => (a['order_index'] as num).compareTo(b['order_index'] as num));
    return out;
  }

  static List<Map<String, dynamic>> nodesOf(String sectionId) =>
      List<Map<String, dynamic>>.from(_nodesBySection[sectionId] ?? const []);

  static Map<String, dynamic>? node(String nodeId) => _nodeById[nodeId];

  static double thresholdOf(String sectionId) {
    final t = sectionMeta(sectionId)?['unlock_threshold'];
    return (t as num?)?.toDouble() ?? (config['unlock_threshold'] as num?)?.toDouble() ?? 0.8;
  }

  /// 章节导读包（与后端 /guide 接口同构，构建期已算好 source_links）
  static Future<Map<String, dynamic>> sectionPayload(String sectionId) async {
    final cached = _sectionCache[sectionId];
    if (cached != null) return cached;
    await ensureMeta();
    Map<String, dynamic> out;
    try {
      out = _decodeMap(await rootBundle.loadString('$_dir/sections/$sectionId.json'));
    } catch (_) {
      out = <String, dynamic>{'section_id': sectionId, 'guide': {}, 'nodes': [], 'extensions': []};
    }
    return _sectionCache[sectionId] = out;
  }

  static Map<String, dynamic>? chunk(String chunkId) {
    final c = _chunkById[chunkId];
    if (c != null) return c;
    // 允许传入带括号/前缀的残留标记，如 "[CH-...]"
    final trimmed = chunkId.replaceAll(RegExp(r'[\[\]\s]'), '');
    return _chunkById[trimmed] ?? _chunkById[trimmed.toUpperCase()];
  }

  static List<Map<String, dynamic>> chunksOfWork(String work) {
    if (work == 'all' || work == '' || work == '_') {
      return List<Map<String, dynamic>>.from(_chunks);
    }
    return List<Map<String, dynamic>>.from(_chunksByWork[work] ?? const []);
  }

  /// 只读视图：不做 List.from 拷贝。检索热路径（全库 2 万多段扫描）用它，
  /// 调用方**不得修改**返回的 list 或其中的 map。
  static List<Map<String, dynamic>> get allChunksView => _chunks;

  static List<Map<String, dynamic>> chunksOfWorkView(String work) {
    if (work == 'all' || work == '' || work == '_') return _chunks;
    return _chunksByWork[work] ?? const [];
  }

  static String workOfChunk(String chunkId) => chunk(chunkId)?['source'] as String? ?? '';

  static List<Map<String, dynamic>> chunksForParagraph(String paragraphId) =>
      List<Map<String, dynamic>>.from(_chunksByParagraph[paragraphId] ?? const []);

  static List<Map<String, dynamic>> quizItems(String sectionId) =>
      List<Map<String, dynamic>>.from(_quiz[sectionId] ?? const []);

  /// 按题目 id 取回题目（含 answer/explanation）。用于「错题本」「作答历史」
  /// 补全题面与解析——那边只有 attempt 记录，没有题面。
  static Map<String, Map<String, dynamic>>? _quizById;

  static Map<String, dynamic>? quiz(String quizId) {
    if (quizId.isEmpty || !_quizReady) return null;
    final idx = _quizById ??= () {
      final m = <String, Map<String, dynamic>>{};
      _quiz.forEach((_, items) {
        for (final it in items) {
          final id = '${it['id'] ?? ''}';
          if (id.isNotEmpty) m[id] = it;
        }
      });
      return m;
    }();
    return idx[quizId];
  }

  static Map<String, List<Map<String, dynamic>>> get concepts {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final c in _list(_knowledge['concepts'])) {
      final id = c['id'] as String? ?? '';
      out[id] = [c];
    }
    return out;
  }

  static List<Map<String, dynamic>> get conceptList => _list(_knowledge['concepts']);

  static Map<String, dynamic> nodeTerms(String nodeId) =>
      ((_knowledge['node_terms'] as Map?)?[nodeId] as Map?)?.cast<String, dynamic>() ?? const {};

  static Map<String, dynamic> get guard =>
      (_knowledge['guard'] as Map?)?.cast<String, dynamic>() ?? const {};

  static String get stageLabelOfAuto => '';
}
