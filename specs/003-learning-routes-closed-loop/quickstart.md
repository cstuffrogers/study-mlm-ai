# Quickstart: 三路线学习路径与掌握度闭环（验收脚本）

**Feature**: `specs/003-learning-routes-closed-loop/spec.md`
**前置**: 已完成 `specs/001` MVP（阅读器 + 五模式会话可跑通）
**两种模式**: 轻量（无 Docker，内存仓库）/ 完整（Docker + PostgreSQL）

---

## 0. 环境准备

```bash
cd backend
pip install -r requirements.txt          # 新增 pyyaml / jsonschema 后需重装

# 轻量模式（默认，推荐用于验收）
export LEARNING_DB_MODE=memory
export ENABLE_LEARNING=1
export ENABLE_LEARNING_DIGEST=1
python -m uvicorn app:app --host 0.0.0.0 --port 8190

# 完整模式
docker compose up -d          # postgres + redis + neo4j
export LEARNING_DB_MODE=postgres
python backend/scripts/import_curriculum.py --dry-run
python backend/scripts/import_curriculum.py
python -m uvicorn app:app --host 0.0.0.0 --port 8190
```

前端：

```bash
cd frontend
flutter pub get
flutter run -d chrome      # 或 windows / android
```

> 轻量模式下学情存内存，重启即清空；如需跨重启保留，设 `LEARNING_SNAPSHOT_PATH=data/learning_snapshot.json`。

---

## 验收场景 1 — 路线导入校验（FR-101/102/106）

```bash
curl -s -X POST localhost:8190/api/learning/admin/curriculum/validate \
  -H 'Authorization: Bearer <expert_token>' -H 'Content-Type: application/json' \
  -d '{"route_code":"theory"}'
```

**预期**：`{"ok": true, "stats": {"nodes": 42, "with_quiz": 39, "planned": 5}}`

反例（把某节点 `prerequisites` 改成不存在值后重跑）：
**预期**：`ok=false`，`issues` 含 `{"type":"broken_prerequisite", ...}`

---

## 验收场景 2 — 选路线 → 定位测 → 起点建议（US1 / SC-101 / SC-102）

```bash
# 2.1 选路线（不跳过定位测）
curl -s -X POST localhost:8190/api/learning/plan \
  -H 'Authorization: Bearer <token>' -H 'Content-Type: application/json' \
  -d '{"route_code":"organization","standpoint_tier":"orthodox"}'
# → 201, next_action.type = placement_test

# 2.2 开始定位测
curl -s -X POST localhost:8190/api/learning/quiz/sessions \
  -H 'Authorization: Bearer <token>' -H 'Content-Type: application/json' \
  -d '{"kind":"placement"}'
# → item_count 在 8..15

# 2.3 取题（确认不含 answer/rubric）
curl -s localhost:8190/api/learning/quiz/sessions/<sid> -H 'Authorization: Bearer <token>'

# 2.4 作答（客观题即时判分）
curl -s -X POST localhost:8190/api/learning/quiz/sessions/<sid>/answers \
  -H 'Authorization: Bearer <token>' -H 'Content-Type: application/json' \
  -d '{"item_id":"q_1","answer":{"choice":"B"},"duration_ms":18000}'

# 2.5 结束 → 报告含起点建议
curl -s -X POST localhost:8190/api/learning/quiz/sessions/<sid>/finish -H 'Authorization: Bearer <token>'
```

**预期**：报告 `action_items` 含 `{"key":"start_here","target":{"type":"module","id":"..."}}`，且 `reason_text` 说明"前置依赖未满足/杠杆值最高"。
**计时**：2.1→2.5 全程 ≤5 分钟（人工操作），服务端计算耗时在响应头 `X-Compute-Ms` ≤3000。

---

## 验收场景 3 — 章节诊断 + 错误标签 + 补丁（US2 / SC-103 / SC-110）

```bash
curl -s -X POST localhost:8190/api/learning/quiz/sessions \
  -H 'Authorization: Bearer <token>' -H 'Content-Type: application/json' \
  -d '{"kind":"chapter_diagnostic","module_id":"m_theses"}'
```

**预期**
- `item_count` ∈ 8..20，且 `scope.node_keys` 覆盖该模块必读节点
- 故意答错一道"实践=日常行为"的辨析题 → 返回 `error_type: "term_misuse"` + `distractor_note` + `anchor`
- 同一知识点连续错 3 次 → 报告 `weak_points` 含该节点，`action_items` 含 `{"key":"patch_quiz"}`

```bash
# 出报告耗时
time curl -s -X POST .../finish -H 'Authorization: Bearer <token>' >/dev/null
```
**预期**：≤10s（SC-103）

---

## 验收场景 4 — 对话中更新学情 + 小结卡 + 撤销（US3 / SC-105）

WebSocket 脚本（复用 `demo_e2e.py` 的连接方式）：

```bash
cd backend && python demo_e2e.py --scenario learning-digest
```

**预期输出**（脚本断言）
1. 会话 5 轮后收到 `type=learning_digest`
2. `evidence_written ≥ 1`，且该证据 `source=dialogue`、`confidence ≤0.6`
3. 学习者在对话里说"实践就是人做事情" → `to_fix` 含"near_synonym 陷阱"
4. 调 `POST /api/learning/evidence/{id}/revoke` → 200，且 `GET /api/learning/state` 在 5s 内回退
5. 关掉 `LLM_API_KEY` 重跑 → 收到 `type=learning_degraded`，`ai_message` 仍正常（NFR-107）

---

## 验收场景 5 — 推荐与欠账（US4 / SC-107）

```bash
curl -s localhost:8190/api/learning/recommendation -H 'Authorization: Bearer <token>'
```

**预期**
- `primary.reason_type` ∈ `prerequisite|leverage|debt|review_due`，且 `reason_text` 引用了具体证据
- 有欠账节点时，`primary` 必为欠账（除非 `review_due` 且当日到期）
- 连续 3 次 `dismissed` 后，`primary` 的单元从"模块"降为"单概念"

```bash
# 埋点回归（SC-107）
curl -s -X POST localhost:8190/api/learning/recommendation/events \
  -d '{"impression_key":"theory:th1-practice:debt","event":"clicked"}' -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <token>'
# → 204；SQL 视图 v_recommendation_ctr 应计入
```

---

## 验收场景 6 — 仪表盘 + 复习 + 审核（US5/6/7 / SC-109）

```bash
curl -s localhost:8190/api/learning/dashboard -H 'Authorization: Bearer <token>'
curl -s localhost:8190/api/learning/review/today -H 'Authorization: Bearer <token>'

# 审核：AI 生成题必须被拦或进待审
curl -s -X POST localhost:8190/api/learning/admin/quiz/items \
  -H 'Authorization: Bearer <expert_token>' -H 'Content-Type: application/json' \
  -d '{"node_keys":["th1-practice"],"item_type":"provenance","stem":"...","options":[...],"answer":{"correct":"C"},"source":"ai_assisted"}'
# → 201, review_status ∈ {check_failed, pending_review}；绝不会直接 approved
```

**预期**
- 仪表盘 `ability` 五维齐全，`weak_top5` 每条带 `evidence_refs`
- `review/today` `total_due > 20` 时 `capped=true` 且最多 20 项
- 未审核题在任何 `quiz_sessions.item_plan` 中都不出现（可用 SQL 断言）

---

## 回归验收（不破坏既有闭环）

```bash
cd backend && python -m pytest tests -q          # 既有 5 个 SC 测试 + 新增 7 个测试文件
cd backend && python demo_e2e.py                 # specs/001 的 4 用例仍全过
cd frontend && flutter analyze && flutter test
```

**关键回归点**
- `ENABLE_LEARNING=0` 时：无 `/api/learning/*`（或返回 404），阅读器与会话行为与 `specs/001` 完全一致
- `ENABLE_LEARNING_DIGEST=0` 时：WebSocket 不出现新增消息类型，旧客户端无感知
- `LEARNING_DB_MODE=memory` 时：不触碰 asyncpg，服务可启动并跑通场景 2/4（aiosqlite）

---

## 常见问题

| 现象 | 原因 | 处理 |
|------|------|------|
| `QUIZ_POOL_INSUFFICIENT` | 题库不足且生成失败 | 先导入 `content/quiz_bank/`；或降低章节权重 |
| `TIER_NOT_AVAILABLE` | 路线/节点无 `critical` 档位内容 | 保持 `orthodox`；或补齐批判标记语料再开启 |
| 定位测 `placement_degraded=true` | 该路线定位题 <8 | 补齐题库；降级结果置信度较低时前端必须提示 |
| 小结卡一直不出现 | `lesson digest` 超时或 LLM 不可用 | 检查 `learning_degraded` 消息；8s 超时是设计行为 |
| 掌握度不升 | 证据置信度不足或 7 天内同题重复 | 看 `evidence_events.dedupe_key`；换题型或等窗口 |
| 撤销后状态没变 | 剩余有效证据本身就支撑当前等级 | 属正确行为（重放结果一致，data-model 不变量 6） |
