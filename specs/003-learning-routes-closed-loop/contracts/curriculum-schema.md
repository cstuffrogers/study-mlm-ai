# Contract: `curriculum.yaml` 配置格式

**Feature**: `specs/003-learning-routes-closed-loop/spec.md`
**位置**: `backend/content/curriculum/{route_code}.yaml`
**用途**: 三条路线的唯一权威来源；导入时编译为 `learning_routes / route_stages / route_modules / knowledge_nodes / route_module_nodes`（研究 D11）
**校验**: `POST /api/learning/admin/curriculum/validate` 与导入脚本共用同一校验器

---

## 1. 顶层结构

```yaml
schema_version: 1
route:
  code: theory                        # theory | organization | state_building
  name: 纯理论研究
  goal: 能独立判定一种理论是真发展还是假发展
  description: 沿马恩奠基→辩证法与认识论→体系化→政治经济学→当代判据推进
  standpoint_tier: orthodox           # orthodox | critical
  estimated_minutes: 5400
  content_status: partial             # skeleton | partial | complete
  default_start_node_keys:
    - th1-practice
  quiz_mix:
    concept: 0.30
    locate: 0.15
    logic: 0.20
    error_diag: 0.20
    provenance: 0.10
    transfer: 0.05
  concept_weights:
    C-实践: 1.5
    C-对象性活动: 1.2

stages:
  - seq: 1
    name: 理论奠基
    objective: 建立实践观与唯物史观
    entry_condition: {}               # 软条件，仅影响推荐权重
    estimated_minutes: 900
    modules:
      - seq: 1
        id: m_theses                  # 稳定业务键，供引用
        name: 《提纲》精读
        work_id: ME-THESES
        chapter_range: { from: th1, to: th11 }
        status: content_ready         # planned | content_ready
        estimated_minutes: 180
        nodes:
          - node_key: th1-practice
            title: 实践是对象性活动
            concept_id: C-实践
            description: 实践是感性的、对象性的物质活动，非日常行为
            work_id: ME-THESES
            anchor: { chunk_id: CH-ME-TH-01-1, quote: "从前的一切唯物主义…", paragraph: 1 }
            prerequisites: []
            difficulty: 2
            content_status: ready
            weight: 1.0
            is_required: true
```

---

## 2. 字段规则

| 字段 | 规则 |
|------|------|
| `schema_version` | 必填，当前仅 `1`；不匹配则拒绝导入 |
| `route.code` | 三选一；全局唯一 |
| `route.standpoint_tier` | `critical` 时该路线所有节点 MUST 至少有 1 条批判标记语料，否则校验失败（spec Edge Cases） |
| `route.quiz_mix` | 六类键齐全，`sum ≈ 1.0`（±0.001），每项 ≥0 |
| `route.default_start_node_keys` | 必须是本文件内 `node_key` |
| `stages[].seq` / `modules[].seq` | 同父级内连续且唯一（允许跳号但需 ≥1 递增） |
| `modules[].id` | 全局唯一（跨路线也不得重复） |
| `modules[].status=planned` | 允许 `nodes` 为空；推荐命中时提示"尚未开放" |
| `nodes[].node_key` | 全局唯一（跨路线共享同一 key = 共享同一节点） |
| `nodes[].concept_id` | 必须存在于 `backend/content/theses_concepts.py` 的 `CONCEPTS[].id`（或后续概念库）；不存在则校验 error |
| `nodes[].anchor.chunk_id` | 必须能在 `text_chunks`（或 `theses_raw` 的 chunk 映射）中解析；解析不到为 error |
| `nodes[].prerequisites` | 引用 `node_key`，必须存在于**任一**路线文件；缺失为 error，成环为 error |
| `nodes[].weight` | 0.1–3.0，影响模块诊断题量分配 |
| `nodes[].is_required=false` | 可选补充节点，不计入"章节完整率"（SC-108） |
| 禁止字段 | 不允许出现 `canonical_definition` / `near_synonyms` / `strictly_not` 等概念定义字段（FR-102，定义只能来自 concepts） |

---

## 3. 校验输出（与 API 契约一致）

```json
{
  "ok": false,
  "issues": [
    {"severity":"error","type":"orphan_node","node_key":"th9-new"},
    {"severity":"error","type":"broken_prerequisite","node_key":"th2-truth","missing":"th1-x"},
    {"severity":"error","type":"cycle","path":["a","b","a"]},
    {"severity":"error","type":"unknown_concept","node_key":"th3-env","concept_id":"C-不存在"},
    {"severity":"error","type":"unresolvable_anchor","node_key":"th3-env","chunk_id":"CH-X-9"},
    {"severity":"error","type":"tier_content_missing","route":"theory","missing_marked_nodes":["th6-x"]},
    {"severity":"warn","type":"no_quiz","node_key":"th7-essence"},
    {"severity":"warn","type":"empty_module","module_id":"m_planned"}
  ],
  "stats": {"nodes":42,"with_quiz":39,"planned":5,"max_depth":6}
}
```

`severity=error` 阻断导入；`warn` 只提示（`no_quiz` 会导致该节点诊断题量不足，见 NFR-111）。

---

## 4. 导入与版本

- 导入 = `INSERT ... ON CONFLICT (node_key/module_id) DO UPDATE`，并 `learning_routes.version += 1`
- 已存在的 `learning_plans` 保留 `route_version`，不自动升级（避免学习中途路径突变）
- 提供 `--dry-run` 输出 diff 摘要（新增/修改/删除节点数）
- 删除节点时若有学习者状态引用 → 降级为 `content_status=deprecated` 而非物理删除
