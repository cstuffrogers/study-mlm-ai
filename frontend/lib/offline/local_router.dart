// 单机版本地路由器：把前端原来打到 FastAPI 的 /api/* 请求改由本机处理。
// 返回值形状与后端保持一致，因此各 *Api 类与界面无需改动。
import '../offline/local_db.dart';
import '../offline/offline_content.dart';
import '../services/llm_client.dart';
import '../services/llm_config_store.dart';
import 'local_api_exception.dart';
import 'local_dialogue.dart';
import 'local_insight.dart';
import 'local_mastery.dart';
import 'local_quiz.dart';

export 'local_api_exception.dart';

class LocalRouter {
  LocalRouter._();

  static Future<Map<String, dynamic>> get(
          String path, Map<String, String> query) =>
      _dispatch('GET', path, query, const {});

  static Future<Map<String, dynamic>> post(
          String path, Map<String, dynamic> body) =>
      _dispatch('POST', path, const {}, body);

  static Future<Map<String, dynamic>> _dispatch(
    String method,
    String path,
    Map<String, String> query,
    Map<String, dynamic> body,
  ) async {
    await OfflineContent.ensureMeta();
    await LocalDb.ensure();
    final segs = Uri.parse(path).pathSegments.where((e) => e.isNotEmpty).toList();
    if (segs.isEmpty || segs.first != 'api') {
      throw LocalApiException(404, '未知接口: $path');
    }
    final rest = segs.sublist(1);
    final routeId = query['route_id'] ??
        (body['route_id'] as String?) ??
        LocalDb.routeId;
    final userId = query['user_id'] ?? (body['user_id'] as String?) ?? LocalDb.userId;

    switch (rest.first) {
      case 'routes':
        return _routes(method, rest, query, body, routeId, userId);
      case 'chunks':
        return _chunks(rest);
      case 'guide':
        return _guide(rest, routeId);
      case 'quiz':
        return _quiz(method, rest, query, body, routeId, userId);
      case 'mastery':
        return _mastery(method, rest, query, body, routeId, userId);
      case 'recommendation':
        return _recommendation(method, rest, query, body, routeId);
      case 'review':
        return _review(method, rest, query, body, routeId);
      case 'motivation':
        return LocalInsight.motivation(routeId);
      case 'analytics':
        return rest.length > 1 && rest[1] == 'calibration'
            ? LocalInsight.calibration(routeId)
            : LocalInsight.overview(routeId);
      case 'dialogue':
        return _dialogue(method, rest, query, body, userId);
      case 'sync':
        return _sync(method, rest, body, routeId);
      case 'profile':
        return LocalInsight.profile(routeId);
      case 'llm-config':
        return _llmConfig(method, rest, body);
      case 'auth':
        return _auth(method, rest, body);
      default:
        throw LocalApiException(404, '单机版未实现该接口: $path');
    }
  }

  // ------------------------------------------------------------ llm-config
  /// 「功能中心 → AI 对话引擎」：配置在线大模型（OpenAI 兼容）
  static Future<Map<String, dynamic>> _llmConfig(
    String method,
    List<String> rest,
    Map<String, dynamic> body,
  ) async {
    if (rest.length > 1 && rest[1] == 'test') {
      final cfg = LlmConfigStore.load();
      final result = await LlmClient.test(cfg);
      return {
        ...result.toJson(),
        if (!cfg.enabled) 'mode': 'local',
      };
    }
    if (method == 'POST') {
      try {
        if (body['__action__'] == 'clear') return await LlmConfigStore.clear();
        return await LlmConfigStore.save(body);
      } on LlmConfigError catch (e) {
        throw LocalApiException(400, e.message);
      }
    }
    return LlmConfigStore.status();
  }

  // ------------------------------------------------------------ routes
  static Future<Map<String, dynamic>> _routes(
    String method,
    List<String> rest,
    Map<String, String> query,
    Map<String, dynamic> body,
    String routeId,
    String userId,
  ) async {
    // /api/routes
    if (rest.length == 1) return LocalMastery.listRoutes();
    final rid = rest[1];
    // /api/routes/diagnostic/{id}/submit
    if (rid == 'diagnostic') {
      // 与后端同口径：按逐章正确率算起点 / 可跳过 / 需补强，不再只回一句「已记录」。
      final answers = (body['answers'] as List?) ?? const [];
      return LocalQuiz.submitDiagnostic(
        rest.length > 2 ? rest[2] : '',
        answers.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      );
    }
    // /api/routes/{rid}/sections
    if (rest.length == 3 && rest[2] == 'sections') {
      return LocalMastery.routesSections(rid);
    }
    // /api/routes/{rid}/diagnostic
    if (rest.length == 3 && rest[2] == 'diagnostic' && method == 'POST') {
      // 单机版原先直接回空 items（界面点进去空页）；题库随包发，按后端口径出题。
      return LocalQuiz.startDiagnostic(rid);
    }
    // /api/routes/{rid}/select
    if (rest.length == 3 && rest[2] == 'select') {
      LocalDb.routeId = rid;
      return {'route_id': rid, 'selected': true};
    }
    // /api/routes/{rid}/sections/{sid}[/guide|/gating]
    if (rest.length >= 4 && rest[2] == 'sections') {
      final sid = rest[3];
      if (rest.length > 4 && rest[4] == 'gating') {
        return LocalMastery.computeGating(
            LocalMastery.masteryMap(rid), rid, sid);
      }
      return LocalMastery.guide(rid, sid);
    }
    throw LocalApiException(404, '未知 routes 接口: /${rest.join('/')}');
  }

  // ------------------------------------------------------------ chunks
  static Future<Map<String, dynamic>> _chunks(List<String> rest) async {
    // /api/chunks/works
    if (rest.length > 1 && rest[1] == 'works') {
      // works：旧口径（纯名字数组，保持兼容）
      // items：带作者与分片数，供原著浏览页搜索/分组（作者未知就留空，不猜）
      final items = OfflineContent.works
          .map((w) => {
                'work': '${w['work'] ?? w}',
                'author': '${w['author'] ?? ''}',
                'chunk_count':
                    (w['chunk_count'] as num?)?.toInt() ?? 0,
                'first_chunk_id': '${w['first_chunk_id'] ?? ''}',
                // 旧资产没有 is_book 字段：缺省按「是著作」处理（不误伤）
                'is_book': w['is_book'] ?? true,
              })
          .toList();
      return {
        'works': items.map((e) => e['work']).toList(),
        'items': items,
        'total': items.length,
        'source': 'offline',
      };
    }
    // /api/chunks/by_work/{work}
    if (rest.length > 2 && rest[1] == 'by_work') {
      await OfflineContent.ensureChunks();
      final work = rest[2];
      final list = OfflineContent.chunksOfWork(work);
      // 同时给 items / chunks：不同页面历史上取过不同键名。
      return {
        'work': work,
        'work_name': work,
        'items': list,
        'chunks': list,
        'count': list.length,
        'total': list.length,
      };
    }
    // /api/chunks/{chunkId}
    if (rest.length == 2) {
      await OfflineContent.ensureChunks();
      final c = OfflineContent.chunk(rest[1]);
      // D135：后端 `chunk_routes.get_chunk()` 对不存在的分片回 200 +
      // `{error: 'not_found', chunk_id}`，而 `widgets/chunk_tag.dart` 正是按
      // `error == 'not_found'` 显示「未找到该分片」——单机抛 404 会让同一句提示
      // 变成「Exception: 分片不存在」。按后端形状给。
      if (c == null) {
        return {'error': 'not_found', 'chunk_id': rest[1]};
      }
      return c;
    }
    throw LocalApiException(404, '未知 chunks 接口');
  }

  static Future<Map<String, dynamic>> _guide(
      List<String> rest, String routeId) async {
    // /api/guide/{sectionId}
    if (rest.length >= 2) return LocalMastery.guide(routeId, rest[1]);
    throw LocalApiException(404, '未知 guide 接口');
  }

  // ------------------------------------------------------------ quiz
  static Future<Map<String, dynamic>> _quiz(
    String method,
    List<String> rest,
    Map<String, String> query,
    Map<String, dynamic> body,
    String routeId,
    String userId,
  ) async {
    if (rest.length > 1 && rest[1] == 'history') {
      await OfflineContent.ensureQuiz(); // 错题要回填题面与解析
      return LocalQuiz.history(
        onlyWrong: query['only_wrong'] == 'true',
        limit: int.tryParse(query['limit'] ?? '') ?? 100,
        sectionId: query['section_id'],
      );
    }
    if (rest.length > 1 && rest[1] == 'appeal') {
      return LocalInsight.appeal(
        '${body['test_id'] ?? ''}',
        '${body['item_id'] ?? ''}',
        '${body['reason'] ?? ''}',
      );
    }
    if (rest.length > 1 && rest[1] == 'tests') {
      return LocalQuiz.listTests();
    }
    // /api/quiz/section/{sectionId}/start
    if (rest.length > 3 && rest[1] == 'section' && rest[3] == 'start') {
      return LocalQuiz.start(rest[2], routeId);
    }
    // /api/quiz/{testId}/submit
    if (rest.length > 2 && rest[2] == 'submit') {
      final answers = ((body['answers'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      return LocalQuiz.submit(rest[1], answers);
    }
    // /api/quiz/{testId}  取回仍在进行中的测试
    if (rest.length == 2) {
      final t = LocalDb.tests[rest[1]];
      if (t is! Map) throw LocalApiException(404, '测试不存在');
      return t.cast<String, dynamic>();
    }
    throw LocalApiException(404, '未知 quiz 接口');
  }

  // ------------------------------------------------------------ mastery
  static Future<Map<String, dynamic>> _mastery(
    String method,
    List<String> rest,
    Map<String, String> query,
    Map<String, dynamic> body,
    String routeId,
    String userId,
  ) async {
    if (rest.length > 1 && rest[1] == 'profile') {
      return LocalInsight.profile(routeId);
    }
    if (rest.length > 2 && rest[1] == 'node') {
      return LocalInsight.nodeDetail(rest[2], routeId);
    }
    if (rest.length > 1 && rest[1] == 'summary') {
      return LocalInsight.summary(routeId,
          period: '${body['period'] ?? 'week'}');
    }
    if (rest.length > 1 && rest[1] == 'record') {
      // 供阅读页直接记录一次自评
      final nodeId = '${body['node_id'] ?? ''}';
      final rec = await LocalMastery.upsert(
          routeId, nodeId, {'dialogue': (body['value'] as num?)?.toDouble() ?? 0.5}, 'dialogue');
      return rec;
    }
    throw LocalApiException(404, '未知 mastery 接口');
  }

  // ------------------------------------------------------------ 推荐
  static Future<Map<String, dynamic>> _recommendation(
    String method,
    List<String> rest,
    Map<String, String> query,
    Map<String, dynamic> body,
    String routeId,
  ) async {
    if (rest.length > 1 && rest[1] == 'today') return LocalInsight.today(routeId);
    if (rest.length > 1 && rest[1] == 'next') {
      return LocalInsight.nextRecommendation(
        routeId,
        currentSectionId: body['current_section_id'] as String?,
      );
    }
    if (rest.length > 1 && rest[1] == 'weak-top') {
      return LocalInsight.weakTop(routeId,
          n: int.tryParse(query['n'] ?? '') ?? 5);
    }
    throw LocalApiException(404, '未知 recommendation 接口');
  }

  // ------------------------------------------------------------ 复习
  static Future<Map<String, dynamic>> _review(
    String method,
    List<String> rest,
    Map<String, String> query,
    Map<String, dynamic> body,
    String routeId,
  ) async {
    if (rest.length > 1 && rest[1] == 'due') {
      final due = LocalMastery.dueReviews(routeId);
      // `due_count` 与后端 `/api/review/due` 同键（`count` 保留兼容）。
      return {
        'route_id': routeId,
        'due_count': due.length,
        'count': due.length,
        'due': due,
      };
    }
    if (rest.length > 1 && rest[1] == 'interleaved') {
      final n = int.tryParse(query['n'] ?? '') ?? 8;
      final items = LocalMastery.interleaved(routeId, n: n);
      return {'route_id': routeId, 'count': items.length, 'items': items};
    }
    if (rest.length > 1 && rest[1] == 'submit') {
      return LocalMastery.applyReview(
        routeId,
        '${body['node_id'] ?? ''}',
        ((body['correct_ratio'] as num?) ?? 1).toDouble(),
      );
    }
    if (rest.length > 1 && rest[1] == 'fit') {
      return LocalMastery.fitParameters();
    }
    if (rest.length > 1 && rest[1] == 'status') {
      return LocalMastery.reviewStatus(routeId);
    }
    throw LocalApiException(404, '未知 review 接口');
  }

  // ------------------------------------------------------------ 对话
  static Future<Map<String, dynamic>> _dialogue(
    String method,
    List<String> rest,
    Map<String, String> query,
    Map<String, dynamic> body,
    String userId,
  ) async {
    if (rest.length > 1 && rest[1] == 'list') {
      return {'dialogues': LocalDialogue.listDialogues()};
    }
    if (rest.length > 2 && rest[2] == 'messages') {
      final limit = int.tryParse(query['limit'] ?? '') ?? 50;
      return {
        'dialogue_id': rest[1],
        'messages': LocalDialogue.messages(rest[1], limit: limit),
      };
    }
    if (rest.length > 1 && rest[1] == 'send') {
      return LocalDialogue.respond(
        dialogueId: '${body['dialogue_id'] ?? 'local'}',
        content: '${body['content'] ?? ''}',
        selectedText: '${body['selected_text'] ?? ''}',
        paragraphId: '${body['paragraph_id'] ?? ''}',
        mode: '${body['mode'] ?? 'explain'}',
        criticalReading: body['critical_reading'] == true,
      );
    }
    throw LocalApiException(404, '未知 dialogue 接口');
  }

  // ------------------------------------------------------------ 同步（本机即权威）
  static Future<Map<String, dynamic>> _sync(
    String method,
    List<String> rest,
    Map<String, dynamic> body,
    String routeId,
  ) async {
    if (rest.length > 1 && rest[1] == 'push') {
      // 与后端 `sync_service.push()` 同口径（原先是三缺一）：
      //  · 事件自带的 route_id 优先（离线队列可能混着切换路线前的事件）；
      //  · 四种事件都落库，不能只认 progress（quiz_attempt / struggle_signal 原先静默丢，
      //    section_complete 不写 completed）；
      //  · 返回 **applied/skipped/details** 三键（前端 SyncController 读这三个），
      //    原实现只回 accepted，导致单机模式文案永远「已合并 0 条」。
      const approved = {
        'quiz_attempt',
        'progress',
        'struggle_signal',
        'section_complete',
      };
      final events = ((body['events'] as List?) ?? const []).whereType<Map>();
      final applied = <String>[];
      final details = <Map<String, dynamic>>[];
      for (final e in events) {
        final type = '${e['type'] ?? ''}';
        if (!approved.contains(type)) {
          details.add({'event': e, 'reason': 'unknown_type'});
          continue;
        }
        final r = '${e['route_id'] ?? routeId}';
        if (type == 'progress' || type == 'section_complete') {
          LocalMastery.markProgress(
            r,
            '${e['section_id'] ?? ''}',
            status: type == 'section_complete'
                ? 'completed'
                : '${e['status'] ?? 'in_progress'}',
            lastPosition: (e['last_position'] as num?)?.toInt() ?? 0,
          );
        } else if (type == 'quiz_attempt') {
          LocalDb.attempts.add({
            'item_id': '${e['quiz_id'] ?? ''}',
            'test_id': '${e['test_id'] ?? ''}',
            'route_id': r,
            'node_id': '${e['node_id'] ?? ''}',
            'answer': '${e['answer'] ?? ''}',
            'is_correct': e['is_correct'] == true,
            'score': (e['score'] as num?)?.toDouble() ?? 0.0,
            'duration_ms': (e['duration_ms'] as num?)?.toInt() ?? 0,
            'error_category': '${e['error_category'] ?? ''}',
            'created_at': nowIso(),
          });
        } else {
          LocalDb.signals.add({
            'node_id': '${e['node_id'] ?? ''}',
            'signal_type': '${e['signal_type'] ?? 'offline'}',
            'intensity': (e['intensity'] as num?)?.toDouble() ?? 0.3,
            'source': 'offline',
            'created_at': nowIso(),
          });
        }
        applied.add(type);
      }
      await LocalDb.flush();
      return {
        'applied': applied.length,
        'skipped': details.length,
        'details': details,
        'accepted': events.length, // 兼容旧读法
        'snapshot': LocalMastery.pullSnapshot(routeId),
      };
    }
    if (rest.length > 1 && rest[1] == 'pull') {
      return LocalMastery.pullSnapshot(routeId);
    }
    if (rest.length > 1 && rest[1] == 'progress') {
      final map = LocalMastery.markProgress(
        routeId,
        '${body['section_id'] ?? ''}',
        status: '${body['status'] ?? 'in_progress'}',
        lastPosition: (body['last_position'] as num?)?.toInt() ?? 0,
      );
      await LocalDb.flush();
      // D135：后端 `sync_service.save_progress()` 回 `{section_id, last_position,
      // status}`；单机原先只嵌套在 `progress` 里，界面读 `last_position`/`status`
      // 得到的都是 null（续学锚点丢失）。平铺补齐，旧键保留。
      return {
        'saved': true,
        'section_id': body['section_id'],
        'last_position': map['last_position'],
        'status': map['status'],
        'progress': map,
      };
    }
    throw LocalApiException(404, '未知 sync 接口');
  }

  // ------------------------------------------------------------ 认证（单机无账号）
  static Future<Map<String, dynamic>> _auth(
    String method,
    List<String> rest,
    Map<String, dynamic> body,
  ) async {
    return {
      'user_id': LocalDb.userId,
      'nickname': '本机用户',
      'token': 'offline',
      'mode': 'offline',
      'message': '单机版无需登录，学习数据仅保存在本设备。',
    };
  }

  /// 供设置页展示：本机数据规模
  static Map<String, dynamic> stats() {
    return {
      'user_id': LocalDb.userId,
      'route_id': LocalDb.routeId,
      'nodes': OfflineContent.allNodes.length,
      'sections': OfflineContent.allSections.length,
      'mastery_records': LocalMastery.masteryMap(LocalDb.routeId).length,
      'attempts': LocalDb.attempts.length,
      'tests': LocalDb.tests.length,
      'dialogues': LocalDb.dialogues.length,
    };
  }
}

