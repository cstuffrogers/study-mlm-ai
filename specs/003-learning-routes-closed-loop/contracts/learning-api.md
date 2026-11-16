# Contract: 学情与路线 REST API

**Feature**: `specs/003-learning-routes-closed-loop/spec.md`
**Base path**: `/api/learning`（沿用既有 `/api/*` 前缀风格，见 `backend/app.py`）
**Auth**: 既有 JWT（`Authorization: Bearer <token>`）；除标注 `public` 外均需登录
**Content-Type**: `application/json; charset=utf-8`
**Error envelope**（与既有路由保持一致）:

```json
{ "detail": "human readable message", "code": "LEARNING_PLAN_MISSING" }
```

**通用错误码**

| code | HTTP | 含义 |
|------|------|------|
| `ROUTE_NOT_FOUND` | 404 | 路线 code 不存在或已下线 |
| `PLAN_MISSING` | 409 | 未选路线，需先 `POST /plan` |
| `NODE_NOT_READY` | 409 | 节点内容未上线（`content_status=planned`） |
| `TIER_NOT_AVAILABLE` | 409 | 该节点/路线无对应立场档位内容（spec Edge Cases） |
| `SESSION_CLOSED` | 409 | 测试会话已结束 |
| `ITEM_NOT_IN_PLAN` | 400 | 题目不在本会话抽题计划内 |
| `EVIDENCE_REVOKED` | 409 | 证据已撤销，不可重复撤销 |
| `QUIZ_POOL_INSUFFICIENT` | 409 | 题库不足且生成失败（NFR-111） |
| `GUARD_REJECTED` | 422 | 内容未通过防偏离校验（FR-135） |

---

## 1. 路线

### `GET /api/learning/routes`
public（登录后返回个人进度）

**200**

```json
{
  "routes": [
    {
      "code": "theory",
      "name": "纯理论研究",
      "goal": "能独立判定一种理论是真发展还是假发展",
      "content_status": "partial",
      "estimated_minutes": 5400,
      "standpoint_tiers": ["orthodox", "critical"],
      "stages": [{ "seq": 1, "name": "理论奠基", "module_count": 3 }],
      "selected": true
    }
  ]
}
```

### `GET /api/learning/routes/{code}`
**200**：完整阶段-模块-节点树 + 该用户各节点状态（未选路线也可预览，`progress` 为空）

```json
{
  "code": "theory",
  "route_version": 3,
  "stages": [
    { "seq": 1, "name": "理论奠基",
      "modules": [
        { "id": "m_theses", "seq": 1, "name": "《提纲》精读", "status": "content_ready",
          "estimated_minutes": 180,
          "nodes": [
            { "node_key": "th1-practice", "title": "实践是对象性活动", "level": 2,
              "confidence": 0.72, "debt": false, "content_status": "ready",
              "prerequisites": [] }
          ] } ] } ]
}
```

**404** `ROUTE_NOT_FOUND`

---

## 2. 学习计划 / 起点

### `POST /api/learning/plan`
```json
{ "route_code": "organization", "standpoint_tier": "orthodox", "skip_placement": false }
```
**201**
```json
{ "plan_id": "…", "route_code": "organization", "route_version": 2,
  "next_action": { "type": "placement_test", "session_id": null, "item_count": 12 } }
```
**规则**：已存在计划时视为切换路线（FR-104），返回 `201` 且 `switched=true`；`standpoint_tier=critical` 而路线无 critical 内容 → `TIER_NOT_AVAILABLE`

### `PATCH /api/learning/plan`
```json
{ "manual_start_node_key": "th1-practice", "settings": { "weekly_report_day": 1, "max_daily_review": 20 } }
```
**200**：返回更新后的计划摘要。`manual_start_node_key` 不影响已有证据（FR-108）

### `GET /api/learning/plan`
**200**：计划 + 当前推荐 + 欠账数。**409** `PLAN_MISSING`

---

## 3. 定位测 / 章节诊断（同一会话模型）

### `POST /api/learning/quiz/sessions`
```json
{ "kind": "chapter_diagnostic", "module_id": "m_theses" }
```
`kind` ∈ `placement` | `chapter_diagnostic` | `patch` | `review`；`placement` 无需 `module_id`（用当前路线）
**201**
```json
{ "session_id": "s_…", "kind": "chapter_diagnostic", "item_count": 12,
  "estimated_minutes": 8, "scope": { "module_id": "m_theses", "node_keys": ["th1-practice"] },
  "placement_degraded": false }
```
**409** `QUIZ_POOL_INSUFFICIENT` | `NODE_NOT_READY`

### `GET /api/learning/quiz/sessions/{session_id}`
返回抽题计划与已作答状态（断点续答，UX 流程 B）
```json
{ "session_id": "s_…", "status": "in_progress", "answered": 3, "item_count": 12,
  "items": [ { "attempt_index": 4,
     "item_id": "q_…", "item_version": 2, "item_type": "concept",
     "stem": "…", "options": [{"key":"A","text":"…"}], "difficulty": 3,
     "node_keys": ["th1-practice"], "is_subjective": false } ] }
```
**注意**：`answer` / `rubric` / `explain_*` 绝不出现在未作答题目中

### `POST /api/learning/quiz/sessions/{session_id}/answers`
```json
{ "item_id": "q_…", "answer": { "choice": "B" }, "duration_ms": 24000 }
```
**200**（客观题即时判分）
```json
{ "verdict": "incorrect", "error_type": "term_misuse",
  "explain_correct": "实践是对象性活动，不是日常行为。",
  "distractor_note": "你选了“日常行为”——这是 near_synonym 陷阱，见 concepts.strictly_not。",
  "anchor": { "chunk_id": "CH-ME-TH-01-1", "quote": "…" },
  "counts_toward_mastery": true }
```
主观题返回 `{"verdict":"pending","reason":"low_confidence"}`（FR-121），或 `{"verdict":"partial","rubric_scores":{...}}`
**400** `ITEM_NOT_IN_PLAN`；**409** `SESSION_CLOSED`

### `POST /api/learning/quiz/sessions/{session_id}/finish`
**200**：返回报告（同 `GET /reports/{id}`），并在响应头 `X-Report-Id` 给出 id
**409** `SESSION_CLOSED`（幂等：重复调用返回同一报告）

### `POST /api/learning/quiz/sessions/{session_id}/abandon`
学情不更新，仅保留已产生证据（按 `counts_toward_mastery`）；重复调用幂等，返回 `204`

---

## 4. 报告与反馈

### `GET /api/learning/reports/{report_id}`
```json
{
  "id": "r_…", "level": "chapter", "generated_by": "template+llm", "read": false,
  "mastery_dist": { "untouched": 1, "beginner": 2, "familiar": 5, "proficient": 1, "mastered": 0 },
  "error_dist": { "term_misuse": 2, "concept_level_confusion": 1 },
  "weak_points": [
    { "node_key": "th1-practice", "title": "实践是对象性活动", "label": "把实践理解成日常行为",
      "evidence_refs": ["e_123", "e_130"] }
  ],
  "understood": ["已能区分对象性活动与直观"],
  "action_items": [
    { "key": "read_anchor", "label": "回看第 1 条解析层「实践≠道德践履」",
      "target": { "type": "anchor", "chunk_id": "CH-ME-TH-01-1" }, "estimated_minutes": 4 },
    { "key": "patch_quiz", "label": "做 2 道专项题", "target": { "type": "quiz", "session_kind": "patch" },
      "estimated_minutes": 3 }
  ],
  "algorithm_version": 2
}
```

### `POST /api/learning/reports/{report_id}/read`
**204**

### `GET /api/learning/reports/weekly/latest`
周报（level=`period`），结构同上，另含 `mastery_delta`、`ability_delta`、`review_due_count`、`debt_count`、`route_drift`
**404** 无周报

### `POST /api/learning/reports/{report_id}/actions/{action_key}/clicked`
轻量埋点，用于 SC-106 / SC-107

---

## 5. 学情

### `GET /api/learning/state?node_keys=a,b,c`
```json
{ "states": [ { "node_key": "th1-practice", "level": 2, "confidence": 0.72,
  "last_evidence": { "id": "e_130", "source": "quiz", "created_at": "…" },
  "conflict": false, "debt": false } ] }
```

### `GET /api/learning/state/{node_key}/evidence?limit=20`
证据链下钻（FR-118/NFR-105）

### `POST /api/learning/evidence/{evidence_id}/revoke`
```json
{ "reason": "learner_disagree", "note": "我确实还没掌握" }
```
**200**：返回重算后的 state（NFR-104，≤5s）
**409** `EVIDENCE_REVOKED`

### `POST /api/learning/dialogue/{dialogue_id}/digest`
会话结束触发抽取 + 小结卡（FR-116/FR-126）
```json
{ "turns": 7, "last_message_seq": 14 }
```
**200**
```json
{ "report_id": "r_…", "level": "turn",
  "understood": ["你能说出实践的对象性"],
  "to_fix": ["“实践就是人做事情”落入了日常行为的 near_synonym"],
  "next_questions": ["那“道德践履”算不算实践？为什么？"],
  "evidence_written": 2, "evidence_skipped_low_confidence": 1 }
```
**规则**：AI 不可用 → `evidence_written=0` 且返回 `{"degraded": true}`，不报错（NFR-107）

---

## 6. 推荐

### `GET /api/learning/recommendation`
**200**
```json
{
  "primary": { "node_key": "th1-practice", "title": "实践是对象性活动",
    "module_id": "m_theses", "reason_type": "debt",
    "reason_text": "你在诊断中 3 次把实践理解成日常行为",
    "estimated_minutes": 12, "impression_key": "theory:th1-practice:debt" },
  "alternates": [ { "node_key": "th4-religion", "reason_type": "leverage", "…": "…" } ],
  "ignored_streak": 0,
  "computed_at": "2026-07-18T10:00:00Z",
  "algorithm_version": 2
}
```
`reason_type` ∈ `prerequisite` | `leverage` | `debt` | `review_due`；`ignored_streak ≥3` 时主推荐自动降为"单节/单概念"（FR-112）

**409** `PLAN_MISSING`（此时前端引导选路线）

### `POST /api/learning/recommendation/events`
```json
{ "impression_key": "theory:th1-practice:debt", "event": "clicked" }
```
`event` ∈ `shown` | `clicked` | `dismissed`；**204**

---

## 7. 仪表盘 / 复习

### `GET /api/learning/dashboard`
```json
{
  "ability": { "materialism": 0.61, "dialectics": 0.48, "epistemology": 0.55,
               "historical_materialism": 0.33, "political_economy": 0.12 },
  "heatmap": [ { "date": "2026-07-17", "intensity": 2 } ],
  "weak_top5": [ { "node_key": "th1-practice", "label": "…", "evidence_refs": ["e_123"] } ],
  "debt": [ { "node_key": "th4-religion", "since": "2026-07-10", "attempts": 3 } ],
  "mastered_count": 18, "total_nodes": 42,
  "review_due_today": 6
}
```
每个能力维度可下钻：`GET /api/learning/dashboard/ability/{dimension}` 返回节点与证据（FR-131）

### `GET /api/learning/review/today?limit=20`
```json
{ "items": [ { "node_key": "th10-civil-society", "kind": "concept_card",
  "due_at": "…", "last_grade": 1 } ], "total_due": 12, "capped": true }
```

### `POST /api/learning/review/{node_key}/answer`
```json
{ "grade": 2 }
```
`grade` ∈ 0..3；**200** 返回下次到期时间

---

## 7.5 数据导出

### `GET /api/learning/export?format=json|csv`
学习者导出自己的学情数据（NFR-108，沿用 `specs/001` NFR-010 的导出权）

**200**（`format=json`）
```json
{
  "user_id": "…", "exported_at": "2026-07-18T10:00:00Z", "algorithm_version": 2,
  "plan": { "route_code": "theory", "route_version": 3 },
  "states": [ { "node_key": "th1-practice", "level": 2, "confidence": 0.72 } ],
  "evidence": [ { "id": "e_…", "node_key": "th1-practice", "source": "quiz",
                  "judgement": "correct", "created_at": "…" } ],
  "attempts": [ { "quiz_item_id": "q_…", "verdict": "correct", "created_at": "…" } ],
  "reports": [ { "id": "r_…", "level": "chapter", "created_at": "…" } ]
}
```
**409** `PLAN_MISSING`；`format=csv` 返回 `text/csv`（每行一条 evidence，便于二次分析）

---

## 8. 内容管理（编辑/专家，role ∈ expert|admin）

### `POST /api/learning/admin/curriculum/validate`
body: `{ "route_code": "theory" }` 或 `{ "yaml": "…" }`（草稿校验）
**200**
```json
{ "ok": false,
  "issues": [
    { "severity": "error", "type": "orphan_node", "node_key": "th9-new" },
    { "severity": "error", "type": "broken_prerequisite", "node_key": "th2-truth", "missing": "th1-x" },
    { "severity": "warn", "type": "no_quiz", "node_key": "th7-essence" },
    { "severity": "error", "type": "cycle", "path": ["a","b","a"] }
  ],
  "stats": { "nodes": 42, "with_quiz": 39, "planned": 5 } }
```

### `POST /api/learning/admin/quiz/items`
创建题目草稿（source=`manual`|`ai_assisted`）→ 自动跑三类离线校验
**201** 返回 `review_status`（`check_failed` 或 `pending_review`）与 `checks`

### `POST /api/learning/admin/quiz/items/{id}/review`
```json
{ "decision": "approved", "note": "干扰项表述已修正" }
```
**200**；`decision ∈ approved|rejected`；`approved` 时写 `published_at` 与 `reviewed_by`（FR-134）

### `POST /api/learning/admin/quiz/items/{id}/recheck`
重跑离线校验（内容修订后）
