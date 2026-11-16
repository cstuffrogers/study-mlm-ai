# Data Model: 三路线学习与学情闭环

> Phase 1 产物。落表建议在 `backend/model/models.py` 扩展。与既有表（users/dialogues/text_chunks/concepts/propositions/conversation_threads）通过 user_id / chunk_id 关联。

## 实体总览

| 实体 | 表名 | 用途 | 关键关联 |
|------|------|------|----------|
| LearningRoute | learning_routes | 三路线定义 | 1-N RouteSection |
| RouteSection | route_sections | 路线×章节映射/顺序/门槛 | N-1 route, 1-N KnowledgeNode |
| KnowledgeNode | knowledge_nodes | 知识点节点+依赖 | N-1 section, 自关联依赖 |
| NodePrerequisite | node_prerequisites | 知识点依赖边 | node→prereq |
| MasteryRecord | mastery_records | 学情掌握度 | user×node×route |
| QuizItem | quiz_items | 测验题（溯源+校验态） | chunk_id, node |
| QuizAttempt | quiz_attempts | 作答记录 | user×quiz, test |
| SectionTest | section_tests | 章节测试会话 | user×section |
| DiagnosticTest | diagnostic_tests | 摸底测会话 | user×route |
| LearningProgress | learning_progress | 进度/锚点/解锁 | user×route×section |
| StruggleSignal | struggle_signals | 学情信号 | user×node, 来源 |
| LearningProfile | learning_profiles | 学情档案聚合 | 1-1 user（或 user×route） |
| Recommendation | recommendations | 推荐 | user×route |
| FeedbackReport | feedback_reports | AI 总结反馈 | user×route |

## 实体字段

### LearningRoute（学习路线）
- `id` PK（如 `route_A`）
- `name` : "纯理论研究" / "组织革命" / "建设社会主义国家"
- `goal` : 目标说明
- `est_duration` : 预计时长
- `shares_foundation` : bool（是否共享公共地基）
- `foundation_ref` : 公共地基引用（指向共享 section 集合）

### RouteSection（路线章节）
- `id` PK
- `route_id` FK→LearningRoute
- `order_index` : 路线内顺序
- `stage_no` : 对应学习顺序2.md 阶段号（0–6）
- `work` : 所属著作
- `title` : 章节标题
- `unlock_threshold` : float 默认 0.8
- `is_foundation` : bool 是否公共地基
- validation: order_index 在 route 内唯一

### KnowledgeNode（知识点节点）
- `id` PK（如 `kn_th6_shiminshehui`）
- `section_id` FK→RouteSection
- `name` / `definition`
- `ability_dim` : enum（materialism/dialectics/epistemology/historical_materialism/political_economy）
- `exam_weight` : float（考频/重要性）
- `source_chunk_id` : 溯源锚点

### NodePrerequisite（依赖边）
- `node_id` FK→KnowledgeNode
- `prereq_id` FK→KnowledgeNode
- `strength` : float
- validation: node_id != prereq_id；禁止环（依赖图必须 DAG）

### MasteryRecord（掌握度记录）
- `id` PK
- `user_id` / `node_id` / `route_id`
- `level` : enum（unseen/beginner/familiar/proficient/mastered）
- `score` : float 0–1
- `basis` : JSON（{accuracy, difficulty, stability, dialogue, feynman} 分项）
- `source_flags` : JSON（哪些来源贡献）
- `updated_at`
- validation: (user_id,node_id,route_id) 唯一；score 与 level 映射一致

### QuizItem（测验题）
- `id` PK
- `section_id` FK / `node_id` FK
- `type` : enum（concept_discrimination/text_location/logical_deduction/error_diagnosis）
- `stem` / `options`(JSON) / `answer` / `explanation`
- `difficulty` : float
- `source_chunk_id` : 溯源（必填，FR-022）
- `authority_status` : enum（pending/reviewed）默认 pending
- `exempt_marked` : bool（错误诊断题故意错误项，FR-023）
- `trial_only` : bool（未审题仅练习，不计正式掌握度）

### QuizAttempt（作答记录）
- `id` PK
- `user_id` / `quiz_id` / `test_id`
- `answer` / `is_correct` / `score`
- `duration_ms`
- `error_category` : enum（real_unknown/term_misuse/concept_layer_confusion/stance_deviation/null）

### SectionTest（章节测试）
- `id` PK
- `user_id` / `section_id` / `route_id`
- `item_ids` : JSON 题组
- `total_score` / `mastery_snapshot`(JSON)
- `status` : enum（in_progress/submitted/appealed/reviewed）
- `created_at` / `submitted_at`

### DiagnosticTest（摸底测）
- `id` PK / `user_id` / `route_id`
- `item_ids` / `result`(JSON: 推荐起点/可跳过/需补强)
- `skipped` : bool

### LearningProgress（学习进度）
- `id` PK
- `user_id` / `route_id` / `section_id`
- `status` : enum（locked/unlocked/in_progress/completed）
- `current_anchor` : 段落锚点（paragraph_id）
- `updated_at`
- validation: (user_id,route_id,section_id) 唯一

### StruggleSignal（学情信号）
- `id` PK
- `user_id` / `node_id`
- `signal_type` : enum（repeated_question/stuck_after_dig/rejected_answer/connect_fail/quiz_error）
- `intensity` : float
- `source` : enum（dialogue/quiz/feynman）
- `created_at`（用于时间衰减）

### LearningProfile（学情档案）
- `id` PK / `user_id` / `route_id`
- `ability_radar` : JSON（五维分数）
- `weak_points` : JSON（TOP-N 排序结果 + 阻塞章节数）
- `summary_text` : 最近 AI 总结
- `updated_at`

### Recommendation（推荐）
- `id` PK
- `user_id` / `route_id`
- `rec_type` : enum（start/next_section/review/reinforce）
- `target_section_id` / `target_node_id`
- `reason` : str（一句话理由）
- `created_at` / `consumed` : bool

### FeedbackReport（学习总结反馈）
- `id` PK / `user_id` / `route_id`
- `period`（week/all）
- `mastered` / `to_reinforce` / `next_step`（JSON/文本）
- `source_tags` : JSON（每条结论数据来源）
- `created_at`

## 状态流转
- SectionTest：in_progress → submitted →（可选）appealed → reviewed
- LearningProgress：locked → unlocked → in_progress → completed；未达门槛从 in_progress 可回退 reinforce
- MasteryRecord：随作答/信号/费曼多次更新，基于 D1 加权公式重算 level

## 与既有实体关系
- `QuizItem.source_chunk_id` → 既有 `text_chunks.id`（溯源）
- `KnowledgeNode.source_chunk_id` → `text_chunks.id`
- `StruggleSignal` 可由既有 `dialogue_messages` / `conversation_threads` 触发
- 申诉回写复用既有专家审核（US5 001）队列
