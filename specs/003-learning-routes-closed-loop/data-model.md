# Data Model: 三路线学习路径与掌握度闭环

**Feature**: `specs/003-learning-routes-closed-loop/spec.md`
**Date**: 2026-07-18
**Stack**: PostgreSQL 16 + pgvector（既有）；SQLAlchemy 2.x async ORM（既有）；**轻量模式**：`LEARNING_DB_MODE=memory` 的 aiosqlite 内存库（既有 `core/db_learning.py`）
**Base module**: `backend/model/models_learning.py`（`LearningBase`，`lr_` 前缀，独立 metadata）；**不得**写入主 `backend/model/models_learning.py`

> 命名沿用既有约定：`String(32)` 十六进制 uuid 主键、`JSON` 存半结构化、`DateTime server_default=func.now()`。

---

## 0. 与已实现 `specs/002` 表的关系（扩列 vs 新建）

`specs/002` 已交付 15 张 `lr_*` 表（`backend/model/models_learning.py`）。本规格**复用为主、只新建立体缺口**，避免“新旧双写”。

| 本规格实体 | 002 已存在 | 处理方式 |
|------------|-----------|----------|
| `learning_routes` | `lr_routes` | **扩列**：`route_code`、`standpoint_tier`、`quiz_mix`(JSON)、`concept_weights`(JSON)、`version`、`content_status` |
| `route_stages` | `lr_route_sections`（已有 `stage_no`/`order_index`） | **复用**，仅增 `objective`、`entry_condition` |
| `route_modules` | — | **新建** `lr_route_modules`（002 只有 section 层，无 module 层） |
| `knowledge_nodes` | `lr_knowledge_nodes` | **扩列**：`anchor`(JSON)、`weight`、`is_required`、`concept_id`、`difficulty` |
| `route_module_nodes` | `lr_node_prerequisites`（拓扑边） | **新建** `lr_route_module_nodes`（模块↔节点+权重），前置仍用 `lr_node_prerequisites` |
| `learning_plans` | —（仅 `lr_learning_progress`） | **新建** `lr_learning_plans`（主路线、tier、start 覆盖、settings、route_version） |
| `evidence_events` | `lr_struggle_signals`（弱信号） | **新建** `lr_evidence_events`（强证据 + 可撤销 + 幂等键）；旧信号保留为写入源的 `source=dialogue_signal` |
| `knowledge_states` | `lr_mastery_records` | **扩列**：`confidence`、`algorithm_version`、`last_evidence_at`、`conflict_flag`、`debt` |
| `quiz_items` | `lr_quiz_items` | **扩列**：`item_type` 加 `provenance`/`transfer`、`rubric`(JSON)、`review_status`、`check_result`(JSON) |
| `quiz_sessions` | `lr_section_tests` + `lr_diagnostic_tests` | **新建统一** `lr_quiz_sessions`（`kind` 区分），旧两表保留为兼容视图/只读 |
| `quiz_attempts` | `lr_quiz_attempts` | **扩列**：`error_type`、`counts_toward_mastery`、`session_id` |
| `feedback_reports` | `lr_feedback_reports` | **扩列**：`level`(turn/chapter/week)、`action_items`(JSON)、`degraded` |
| `review_schedules` | `lr_review_logs` | **扩列**：换个方向——新表 `lr_review_schedules`（`due_at`/`ease`/`interval_days`/`forced_relearn`），作答历史仍入 `lr_review_logs` |
| `recommendation_impressions` | `lr_recommendations` | **扩列**：`reason_type`、`impression_key`、`event`；CTR 统计仍走视图 |

> 结论：**新建 6 张、扩列 8 张**；迁移脚本只做 `ALTER TABLE ADD COLUMN` + 6 个 `CREATE TABLE`，对 002 已有数据零破坏。

---

## 1. 实体总览

```
                    ┌──────────────┐
                    │ learning_routes│
                    └──────┬───────┘
                 ┌─────────┴─────────┐
          ┌──────▼──────┐     ┌──────▼──────────┐
          │ route_stages│     │learning_plans   │
          └──────┬──────┘     └──────┬──────────┘
          ┌──────▼────────┐          │ user_id
          │ route_modules │          │
          └──────┬────────┘          │
                 │ module_nodes      │
          ┌──────▼─────────┐         │
          │ knowledge_nodes│◄────────┼──────────┐
          └──────┬─────────┘         │          │
                 │ concept_id        │          │
          ┌──────▼──────┐    ┌───────▼────────┐ │
          │  concepts   │    │knowledge_states│ │
          │  (既有)     │    └───────┬────────┘ │
          └─────────────┘            │          │
                                     │  evidence_events
                            ┌────────┴───────┐  │
                            │ feedback_reports│ │
                            └────────────────┘ │
     ┌──────────────┐   ┌────────────────┐    │
     │  quiz_items  │◄──┤  quiz_attempts │────┘
     └──────┬───────┘   └────────┬───────┘
            │                    │ session_id
            │            ┌───────▼───────┐   ┌──────────────────┐
            └───────────►│ quiz_sessions │   │ review_schedules │
                         └───────────────┘   └──────────────────┘
                         ┌──────────────────────────┐
                         │ recommendation_impressions│
                         └──────────────────────────┘
```

---

## 2. 实体定义

### 2.1 `learning_routes`（学习路线）

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | String(32) | PK | |
| code | String(32) | UNIQUE, NOT NULL | `theory` / `organization` / `state_building` |
| name | String(64) | NOT NULL | 纯理论研究 / 组织革命 / 建设社会主义国家 |
| goal | Text | NOT NULL | 路线目标（一句话，展示在路线卡） |
| description | Text | | 展开说明 |
| standpoint_tier | String(16) | NOT NULL, default `orthodox` | `orthodox` / `critical`（见 spec Clarifications 1） |
| default_start_node_ids | JSON | NOT NULL, default `[]` | 默认起点候选（冷启动无定位测时） |
| quiz_mix | JSON | NOT NULL | 题型配比，如 `{"concept":0.3,"locate":0.15,"logic":0.2,"error_diag":0.2,"provenance":0.1,"transfer":0.05}`，各项和 = 1.0 |
| concept_weights | JSON | | `{concept_id: weight}`，缺省 1.0 |
| estimated_minutes | Integer | NOT NULL | 全路线预计投入（分钟） |
| content_status | String(16) | NOT NULL, default `skeleton` | `skeleton` / `partial` / `complete` |
| version | Integer | NOT NULL, default 1 | |
| is_active | Boolean | default true | |
| created_at / updated_at | DateTime | | |

**Validation**
- `quiz_mix` 六类键齐全且 sum≈1.0（±0.001）
- `code` 唯一；`is_active=false` 的路线不出现在选择页，但已选用户不受影响
- 同一 `code` 有多版本时，`learning_plans.route_version` 固定学习者使用的版本

### 2.2 `route_stages`（路线阶段）

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | String(32) | PK | |
| route_id | String(32) | FK learning_routes, NOT NULL | |
| seq | Integer | NOT NULL | 阶段顺序，同路线内唯一 |
| name | String(64) | NOT NULL | 如「理论奠基」「建党与夺权」 |
| objective | Text | | 本阶段应达到的能力 |
| entry_condition | JSON | default `{}` | 软进入条件 `{"min_level": 2, "node_ids": [...]}`，仅用于推荐加权，不阻断 |
| estimated_minutes | Integer | | |

UNIQUE(route_id, seq)

### 2.3 `route_modules`（路线模块）

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | String(32) | PK | |
| stage_id | String(32) | FK route_stages, NOT NULL | |
| seq | Integer | NOT NULL | |
| name | String(64) | NOT NULL | 如「《提纲》精读」 |
| work_id | String(64) | | 对应 `sources/texts` 或 `theses_raw.WORK_ID` |
| chapter_range | JSON | | `{"from":"th1","to":"th3"}` 或 `{"chapters":[1,2]}` |
| status | String(16) | NOT NULL, default `planned` | `planned` / `content_ready`（推荐命中 planned 时提示未开放，US4 场景 4） |
| estimated_minutes | Integer | | |

UNIQUE(stage_id, seq)

### 2.4 `knowledge_nodes`（知识节点）

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | String(32) | PK | |
| node_key | String(64) | UNIQUE, NOT NULL | 稳定业务键，如 `th1-practice`，供 curriculum.yaml 引用 |
| concept_id | String(32) | FK concepts.id, NULL | 一个节点聚合一个主概念；跨概念命题节点可空 |
| title | String(128) | NOT NULL | 展示名，如「实践是对象性活动」 |
| description | Text | | 一句话说明（用于报告/推荐理由） |
| work_id | String(64) | | 所属原著 |
| anchor | JSON | NOT NULL | 原文锚点 `{"chunk_id":"CH-ME-TH-01-1","quote":"...","paragraph":1}` |
| prerequisites | JSON | NOT NULL, default `[]` | 前置 `node_key` 列表（同图谱内） |
| leverage_value | Integer | NOT NULL, default 0 | 下游可解锁节点数（导入时静态计算，D4） |
| difficulty | Integer | NOT NULL, default 3 | 1–5，供定位测与诊断抽题 |
| content_status | String(16) | NOT NULL, default `ready` | `ready` / `planned` |
| created_at | DateTime | | |

**Rules**
- 节点**不存概念定义副本**（FR-102）；定义一律从 `concepts` 取
- `prerequisites` 引用的 `node_key` 必须存在（导入校验 FR-106），且依赖图必须无环
- `leverage_value` 由导入脚本按反向依赖闭包计算

### 2.5 `route_module_nodes`（模块-节点关联，多路线共享）

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| module_id | String(32) | FK route_modules | |
| node_id | String(32) | FK knowledge_nodes | |
| seq | Integer | NOT NULL | 模块内顺序 |
| is_required | Boolean | NOT NULL, default true | 必读 vs 可选补充 |
| weight | Float | NOT NULL, default 1.0 | 该节点在本模块诊断中的题量权重 |

PK(module_id, node_id)；UNIQUE(module_id, seq)

### 2.6 `learning_plans`（学习计划）

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | String(32) | PK | |
| user_id | String(32) | FK users, UNIQUE, NOT NULL | 单用户单主路线（Clarifications 3） |
| route_id | String(32) | FK learning_routes, NOT NULL | |
| route_version | Integer | NOT NULL | 锁定版本，路线升级不影响进行中的计划 |
| manual_start_node_id | String(32) | FK knowledge_nodes, NULL | 人工起点（FR-108） |
| placement_session_id | String(32) | FK quiz_sessions, NULL | 定位测结果 |
| current_recommendation | JSON | default `{}` | 缓存 `{primary:{node_key,reason_type,minutes},alternates:[...],computed_at}` |
| settings | JSON | default `{}` | `{weekly_report_day:1, push_enabled:true, max_daily_review:20, allow_cross_route:true}` |
| created_at / updated_at | DateTime | | |

### 2.7 `evidence_events`（证据事件 — 学情唯一写入源）

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | String(32) | PK | |
| user_id | String(32) | FK users, NOT NULL, index | |
| node_id | String(32) | FK knowledge_nodes, NOT NULL, index | |
| source | String(16) | NOT NULL | `quiz` / `dialogue` / `feynman` / `reading` / `manual` |
| source_ref | String(64) | | 题目作答 id / 会话 id / 报告 id |
| judgement | String(16) | NOT NULL | `correct` / `partial` / `incorrect` / `quality`（费曼质量分） |
| score | Float | | 0–1；`quality` 时必填 |
| error_type | String(24) | NULL | 六类标签之一（FR-120） |
| confidence | Float | NOT NULL | 0–1；对话证据 ≤0.6 |
| weight | Float | NOT NULL | 按来源：quiz 1.0 / feynman 0.8 / dialogue 0.4 / reading 0.1 / manual 1.0 |
| dedupe_key | String(128) | UNIQUE | 幂等键（NFR-102），如 `quiz:{attempt_id}` |
| revoked_at | DateTime | NULL | 学习者纠正（FR-117） |
| revoke_reason | String(32) | NULL | `learner_disagree` / `conflict_with_test` |
| created_at | DateTime | NOT NULL, index | |

**Rules**
- 只增不改；撤销通过 `revoked_at` 标记，再触发状态重算
- 显式测试冲突时插入两条记录：新证据 + 旧对话证据 `revoke_reason=conflict_with_test`（FR-115）
- `dedupe_key` 唯一约束保证重复提交幂等

### 2.8 `knowledge_states`（知识状态）

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | String(32) | PK | |
| user_id | String(32) | FK users, NOT NULL | |
| node_id | String(32) | FK knowledge_nodes, NOT NULL | |
| level | Integer | NOT NULL, default 0 | 0 未接触 / 1 初学 / 2 熟悉 / 3 精通 / 4 贯通 |
| confidence | Float | NOT NULL, default 0.0 | 0–1 |
| last_evidence_id | String(32) | FK evidence_events, NULL | |
| conflict_flag | Boolean | default false | 证据冲突待复盘（Edge Cases） |
| algorithm_version | Integer | NOT NULL | 算法版本（NFR-112） |
| updated_at | DateTime | | |

UNIQUE(user_id, node_id)

**State transitions（来自 D2）**

| 触发 | 允许的最大变化 | 条件 |
|------|----------------|------|
| `dialogue` 证据 | +1 级 | confidence ≥ 0.6 且累计 ≥3 条同向证据；单条不升级 |
| `quiz` 证据 | +1 级 / 正确率 100% 且连续 2 次不同题型可 +2 | 题量 ≥ 章节保底 |
| `quiz` 失败 3 次 | -1 级 + `conflict_flag=true` | 进入补丁队列 |
| 撤销证据 | 按剩余有效证据重算（可能 -1～-3） | NFR-104，5 秒内完成 |
| 7 天内同题重复 | 0 级 | FR-123 |

### 2.9 `quiz_items`（题目）

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | String(32) | PK | |
| node_keys | JSON | NOT NULL | 关联知识点（≥1；迁移题 ≥2，FR-125） |
| item_type | String(16) | NOT NULL | `concept` / `locate` / `logic` / `error_diag` / `provenance` / `transfer` |
| stem | Text | NOT NULL | 题干 |
| options | JSON | | 客观题选项（迁移题为空） |
| answer | JSON | NOT NULL | `{"correct":"B"}` 或 `{"key_points":[...]}` |
| rubric | JSON | | 评分要点（迁移题必填，D8） |
| explain_correct | Text | | 正确项解释（判分后展示） |
| explain_distractors | JSON | | `{option_key: 差异说明}`（FR-120） |
| anchor | JSON | NOT NULL | 原文锚点 |
| difficulty | Integer | NOT NULL, default 3 | 1–5 |
| source | String(16) | NOT NULL | `manual` / `ai_assisted` |
| checks | JSON | | 三类离线校验结果 `{stance,fact,term}` 各含 pass/reasons |
| review_status | String(16) | NOT NULL, default `draft` | `draft` / `check_failed` / `pending_review` / `approved` / `rejected` |
| version | Integer | NOT NULL, default 1 | |
| created_by | String(32) | FK users, NULL | |
| reviewed_by | String(32) | FK users, NULL | |
| published_at | DateTime | NULL | 未 `approved` 不得发布（FR-124） |

**Rules**
- `review_status != approved` 的题不进入正式抽题池
- 任意 `checks.*.pass == false` 自动置 `check_failed`，不可跳过人工审（FR-124/FR-135）

### 2.10 `quiz_sessions`（测试会话）

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | String(32) | PK | |
| user_id | String(32) | FK users, NOT NULL | |
| kind | String(24) | NOT NULL | `placement` / `chapter_diagnostic` / `patch` / `review` |
| scope | JSON | NOT NULL | `{"route_code":"organization","module_id":"...","node_keys":[...]}` |
| status | String(16) | NOT NULL | `in_progress` / `finished` / `abandoned` |
| item_plan | JSON | NOT NULL | 抽题计划 `[{item_id,version}]`（快照，防题目改动） |
| item_count | Integer | NOT NULL | |
| started_at / finished_at | DateTime | | |
| report_id | String(32) | FK feedback_reports, NULL | |

### 2.11 `quiz_attempts`（作答记录）

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | String(32) | PK | |
| session_id | String(32) | FK quiz_sessions, NOT NULL, index | |
| user_id | String(32) | NOT NULL | |
| quiz_item_id | String(32) | FK quiz_items, NOT NULL | |
| item_version | Integer | NOT NULL | 固定作答时的版本 |
| answer | JSON | NOT NULL | |
| verdict | String(16) | NOT NULL | `correct` / `partial` / `incorrect` / `pending`（FR-121） |
| error_type | String(24) | NULL | |
| rubric_scores | JSON | NULL | 迁移题分项 |
| counts_toward_mastery | Boolean | NOT NULL, default true | 7 天重复 / 待确认 → false（FR-123） |
| duration_ms | Integer | | |
| created_at | DateTime | | |

UNIQUE(session_id, quiz_item_id)

### 2.12 `feedback_reports`（反馈报告）

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | String(32) | PK | |
| user_id | String(32) | NOT NULL, index | |
| level | String(16) | NOT NULL | `turn`（小结卡）/ `chapter` / `period`（周报） |
| scope_ref | JSON | NOT NULL | `{"session_id":...}` / `{"module_id":...}` / `{"week":"2026-W30"}` |
| content | JSON | NOT NULL | 结构化内容 `{mastery_dist, error_dist, weak_points:[{node_key,label,evidence_refs}], understood:[], to_fix:[], next_questions:[]}` |
| action_items | JSON | NOT NULL | 可执行动作 `[{key,label,target:{type,id},estimated_minutes}]`（FR-127） |
| generated_by | String(24) | NOT NULL | `template` / `template+llm`（D13） |
| algorithm_version | Integer | NOT NULL | |
| created_at | DateTime | | |
| read_at | DateTime | NULL | |

### 2.13 `review_schedules`（复习计划）

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | String(32) | PK | |
| user_id | String(32) | NOT NULL | |
| node_id | String(32) | FK knowledge_nodes, NOT NULL | |
| last_grade | Integer | NOT NULL, default 0 | 0 忘 / 1 困难 / 2 一般 / 3 容易 |
| interval_days | Integer | NOT NULL, default 1 | |
| ease | Float | NOT NULL, default 2.5 | SM-2 简化（D9） |
| streak | JSON | NOT NULL, default `[]` | 连续评级序列 |
| due_at | DateTime | NOT NULL, index | |
| forced_relearn | Boolean | default false | 章节诊断未通过强制回炉（FR-132） |
| updated_at | DateTime | | |

UNIQUE(user_id, node_id)

### 2.14 `recommendation_impressions`（推荐曝光，供 SC-107 验证）

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | String(32) | PK | |
| user_id | String(32) | NOT NULL | |
| recommendation_key | String(96) | NOT NULL | 如 `theory:th1-practice:debt` |
| reason_type | String(16) | NOT NULL | `prerequisite` / `leverage` / `debt` / `review_due` |
| shown_at | DateTime | NOT NULL | |
| clicked_at | DateTime | NULL | |
| dismissed_at | DateTime | NULL | |

---

## 3. 派生视图 / 计算字段

| 名称 | 计算方式 | 用途 |
|------|----------|------|
| 欠账清单 | `knowledge_states.level < 2 AND exists(quiz_attempts.verdict=incorrect)` 或 `conflict_flag=true` | 仪表盘、推荐排序（FR-111/131） |
| 前沿集合 | 所有 `prerequisites` 中每个 node 的 state.level ≥ 2 的未掌握节点 | 推荐候选（FR-109） |
| 能力雷达 | 五维度 = 该维度下节点 `level` 的加权平均 × 置信度折扣 | 仪表盘（FR-131） |
| 错误类型分布 | `evidence_events.error_type` 近 30 天计数 | 章节报告（FR-128） |
| 掌握增量 | 周初 vs 周末 `level≥2` 节点数差 | 周报（FR-129） |
| 定位建议起点 | 前沿集合中 route seq 最小者；并列时取 `leverage_value` 最大 | 定位测结果（FR-107） |

---

## 4. 索引与容量

- `evidence_events(user_id, created_at desc)`、`(user_id, node_id, created_at desc)`、UNIQUE(dedupe_key)
- `knowledge_states(user_id, level)`、UNIQUE(user_id, node_id)
- `quiz_items` 抽题：`(review_status, item_type, difficulty)`；node_keys 为 JSON，抽题时按应用层过滤（首期题库 <500 题，无需 GIN 索引）
- `review_schedules(user_id, due_at)`
- 容量假设：单学习者 4 周 ≈ 2,000 条 evidence、100 条 attempts、≤300 条 review；10 万学习者 ≈ 2 亿条 evidence → 需按月分区（v2 再做，先留 `partition_hint`）

---

## 5. 数据迁移与兼容

- 全部为新增表，不改 `dialogues` / `dialogue_messages` / `text_chunks` / `concepts`，零破坏性迁移
- 既有 `dialogue_messages` 通过 `source_ref` 关联到 `evidence_events`，不反向加外键（避免改动已上线表）
- `LEARNING_DB_MODE=memory` 时用 aiosqlite 内存库（不依赖 PG），学情走内存仓库 + 可选 JSON 快照（D10），接口契约不变

---

## 6. 不变量（必须在服务层强制）

1. 一个学习者只有一条主路线（`learning_plans.user_id` UNIQUE）
2. 任何 `knowledge_states` 变化必须能追溯到 `last_evidence_id` 指向的有效证据
3. 未 `approved` 的题目不得出现在任何 `quiz_sessions.item_plan`
4. `route_module_nodes` 不得出现跨路线同一模块内 `node_key` 重复
5. `dialogue` 来源的证据 `confidence` 恒 ≤0.6，且单条不得使 `level` 跨级
6. 撤销证据后重算的结果必须与"从头重放剩余有效证据"一致（可重放性，保证 NFR-103）
