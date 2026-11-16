// 学习闭环数据模型（对齐 specs/002 data-model.md 契约）

class LearningRoute {
  final String id;
  final String name;
  final String goal;
  final String estDuration;
  final bool sharesFoundation;

  LearningRoute({
    required this.id,
    required this.name,
    required this.goal,
    required this.estDuration,
    required this.sharesFoundation,
  });

  factory LearningRoute.fromJson(Map<String, dynamic> j) => LearningRoute(
        id: j['id'] ?? '',
        name: j['name'] ?? '',
        goal: j['goal'] ?? '',
        estDuration: j['est_duration'] ?? '',
        sharesFoundation: j['shares_foundation'] ?? false,
      );
}

class RouteSection {
  final String id;
  final int orderIndex;
  final int stageNo;
  final String work;
  final String title;
  final bool isFoundation;
  final String status; // locked / unlocked / in_progress / completed
  final double masteryScore;
  final double unlockThreshold;
  final bool hasBank; // 是否挂载题库（无题库章＝按段落学习）
  final bool prevCompleted; // 理想顺序上，前一章是否已完成（仅作建议/展示，不构成硬门禁）
  final String? localWork; // 本章对应的本机知识库原著名（有则可「查看原文」）

  RouteSection({
    required this.id,
    required this.orderIndex,
    required this.stageNo,
    required this.work,
    required this.title,
    required this.isFoundation,
    required this.status,
    required this.masteryScore,
    required this.unlockThreshold,
    this.hasBank = true,
    this.prevCompleted = true,
    this.localWork,
  });

  factory RouteSection.fromJson(Map<String, dynamic> j) => RouteSection(
        id: j['id'] ?? '',
        orderIndex: j['order_index'] ?? 0,
        stageNo: j['stage_no'] ?? 0,
        work: j['work'] ?? '',
        title: j['title'] ?? '',
        isFoundation: j['is_foundation'] ?? false,
        status: j['status'] ?? 'locked',
        masteryScore: (j['mastery_score'] ?? 0).toDouble(),
        unlockThreshold: (j['unlock_threshold'] ?? 0.8).toDouble(),
        hasBank: j['has_bank'] ?? true,
        prevCompleted: j['prev_completed'] ?? true,
        localWork: (j['local_work'] as String?)?.isNotEmpty == true ? j['local_work'] as String : null,
      );
}

class QuizItem {
  final String id;
  final String type;
  final String stem;
  final List<dynamic> options;
  final double difficulty;
  final bool subjective;
  final bool application;
  final String sourceChunkId;
  final String authorityStatus;
  final bool exemptMarked;
  final bool trialOnly;

  QuizItem({
    required this.id,
    required this.type,
    required this.stem,
    required this.options,
    required this.difficulty,
    required this.subjective,
    this.application = false,
    required this.sourceChunkId,
    required this.authorityStatus,
    required this.exemptMarked,
    required this.trialOnly,
  });

  factory QuizItem.fromJson(Map<String, dynamic> j) => QuizItem(
        id: j['id'] ?? '',
        type: j['type'] ?? '',
        stem: j['stem'] ?? '',
        options: (j['options'] as List?) ?? const [],
        difficulty: (j['difficulty'] ?? 0.5).toDouble(),
        subjective: j['subjective'] ?? false,
        application: j['application'] ?? (j['type'] == 'application'),
        sourceChunkId: j['source_chunk_id'] ?? '',
        authorityStatus: j['authority_status'] ?? 'reviewed',
        exemptMarked: j['exempt_marked'] ?? false,
        trialOnly: j['trial_only'] ?? false,
      );
}

class MasteryEntry {
  final String nodeId;
  final String level;
  final double score;
  MasteryEntry({required this.nodeId, required this.level, required this.score});
  factory MasteryEntry.fromJson(Map<String, dynamic> j) => MasteryEntry(
        nodeId: j['node_id'] ?? '',
        level: j['level'] ?? 'unseen',
        score: (j['score'] ?? 0).toDouble(),
      );
}

class WeakPoint {
  final String nodeId;
  final String name;
  final double score;
  final String level;
  final int blockingSections;
  final String sectionId;
  WeakPoint({
    required this.nodeId,
    required this.name,
    required this.score,
    required this.level,
    required this.blockingSections,
    this.sectionId = '',
  });
  factory WeakPoint.fromJson(Map<String, dynamic> j) => WeakPoint(
        nodeId: j['node_id'] ?? '',
        name: j['name'] ?? '',
        score: (j['score'] ?? 0).toDouble(),
        level: j['level'] ?? 'unseen',
        blockingSections: j['blocking_sections'] ?? 0,
        sectionId: j['section_id'] ?? '',
      );
}

class Profile {
  final String routeId;
  final Map<String, dynamic> abilityRadar;
  final List<WeakPoint> weakPoints;
  final Map<String, dynamic> masteryDistribution;
  final String summary;
  Profile({
    required this.routeId,
    required this.abilityRadar,
    required this.weakPoints,
    required this.masteryDistribution,
    required this.summary,
  });
  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        routeId: j['route_id'] ?? '',
        abilityRadar: (j['ability_radar'] as Map?)?.cast<String, dynamic>() ?? {},
        weakPoints: ((j['weak_points'] as List?) ?? const [])
            .map((e) => WeakPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        masteryDistribution:
            (j['mastery_distribution'] as Map?)?.cast<String, dynamic>() ?? {},
        summary: j['summary'] ?? '',
      );
}

class ReviewItem {
  final String nodeId;
  final String name;
  final String sectionId;
  final double score;
  final double stability;
  final double retention;
  final double elapsedDays;
  final String kind; // '' | 'due' | 'interleave'
  ReviewItem({
    required this.nodeId,
    required this.name,
    required this.sectionId,
    required this.score,
    required this.stability,
    required this.retention,
    required this.elapsedDays,
    this.kind = '',
  });
  factory ReviewItem.fromJson(Map<String, dynamic> j) => ReviewItem(
        nodeId: j['node_id'] ?? '',
        name: j['name'] ?? '',
        sectionId: j['section_id'] ?? '',
        score: (j['score'] ?? 0).toDouble(),
        stability: (j['stability'] ?? 0).toDouble(),
        retention: (j['retention'] ?? 0).toDouble(),
        elapsedDays: (j['elapsed_days'] ?? 0).toDouble(),
        kind: j['kind'] ?? '',
      );
}

class Recommendation {
  final String recType;
  final String targetSectionId;
  final String targetNodeId;
  final String reason;
  Recommendation({
    required this.recType,
    required this.targetSectionId,
    required this.targetNodeId,
    required this.reason,
  });
  factory Recommendation.fromJson(Map<String, dynamic> j) => Recommendation(
        recType: j['rec_type'] ?? '',
        targetSectionId: j['target_section_id'] ?? '',
        targetNodeId: j['target_node_id'] ?? '',
        reason: j['reason'] ?? '',
      );
}
