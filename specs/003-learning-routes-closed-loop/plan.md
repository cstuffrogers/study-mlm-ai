# Implementation Plan: 三路线学习路径与掌握度闭环

**Branch**: `003-learning-routes-closed-loop` | **Date**: 2026-07-18 | **Spec**: `specs/003-learning-routes-closed-loop/spec.md`
**Input**: User description: "根据路径.txt 的三条学习路线…按最佳方案产出详细开发计划"

---

## Summary

在既有「正统马哲深度学习系统」MVP（`specs/001`，阅读器 + 五模式会话 + 防偏离三重机制已验收）**及已交付的 `specs/002`（三路线 + 摸底测 + 章节测试 + 学情档案 + 基础推荐/复习）**之上，增量交付一条**更严格的掌握度闭环**：

> 三条路线配置化（YAML） → 定位测给起点 → 读章节 → 章节诊断出掌握度与错误类型 → 对话中隐式积累可撤销的证据 → 欠账优先推荐 → 三档反馈 + 仪表盘 + 间隔重复。

**与 002 的关系**：002 已实现的能力（`route_*` / `mastery_*` / `quiz_*` / `recommendation_*` / `review_*` 路由与服务）零破坏保留；003 补的是证据事件模型、六类题型、配置化路线、欠账软门禁、审核工作台与统一 `/api/learning` 契约（逐项对照见 `spec.md` §0）。

技术路径：**新建 6 张表 + 扩列 8 张既有表 + 7 个领域模块 + 1 个编排服务 + 1 组路由 + 6 个前端页面**，全部为增量，不改已上线表结构与既有会话协议语义；轻量模式（`LEARNING_DB_MODE=memory`，aiosqlite）下全链路可验收。

---

## Technical Context

**Language/Version**
- Backend: Python 3.11+（现网 `python -m uvicorn`；`requirements.txt` 已含 fastapi/sqlalchemy/asyncpg/pgvector/pydantic/httpx/numpy）
- Frontend: Dart / Flutter（`frontend/pubspec.yaml`，`provider` 状态管理，无路由框架）

**Primary Dependencies（不新增重依赖）**
- Backend: FastAPI、SQLAlchemy 2.x async、asyncpg、pgvector、Pydantic v2、httpx
- 新增（纯 Python，无服务依赖）: `pyyaml`（curriculum 解析）、`jsonschema`（配置校验）——**唯一新增依赖**
- Frontend: `provider`、`web_socket_channel`（已有）

**Storage**
- PostgreSQL 16 + pgvector（既有）；新增表见 `data-model.md`
- 轻量模式：内存仓库（`InMemoryLearningRepository`）+ 可选 JSON 快照（`data/learning_snapshot.json`）

**Testing**
- Backend: `pytest` + `httpx.AsyncClient`（既有 `backend/tests/`），新增 SC 级测试
- Frontend: `flutter test`（既有 `frontend/test/`），新增 widget 测试
- 端到端: 扩展现有 `backend/demo_e2e.py`（WebSocket 闭环脚本）

**Target Platform**
- 后端：Linux/Windows（`core/db.py` 已处理 Windows event loop）
- 前端：Android / iOS / Web（`flutter run -d chrome` 已可跑）

**Project Type**: 单仓双端（backend + frontend），沿用现有结构，不引入 monorepo 工具

**Performance Goals**
- 定位测/诊断/推荐计算 ≤10s（不含主观题 LLM 判分），其中推荐与学情读路径 ≤300ms（NFR-101）
- 章节诊断出报告 ≤10s（SC-103），题目抽取 ≤1.5s
- 会话小结卡：会话结束后 ≤8s 内到达，超时降级（ws contract §3）

**Constraints**
- 不修改 `specs/001` 已上线表结构与消息语义；只加新表 + 新消息类型
- 所有 AI 生成的题目/解析/批改/反馈必须过既有 `OrthodoxyGuard` + 三重校验（FR-135）
- 单学习者 4 周数据量 ≈2,000 条 evidence，单表查询需有索引（`data-model.md` §4）
- 题目 7 天重复不计分（FR-123），必须服务端强制而非前端
- 学习记录加密与导出沿用 `specs/001` NFR-009 / NFR-010：新增证据表不含 PII，部署层加密方案不变；导出能力见 T101

**Scale/Scope**
- 首期节点数：纯理论路线 42 节点（含 5 个 planned），组织/建国路线各 8–12 节点（骨架）
- 首期题库：≥120 题（人工 + AI 辅助），覆盖 6 类题型
- 用户规模目标：MVP 阶段 ≤1,000 学习者；10 万级需 evidence 分区（v2）

---

## Constitution Check

项目未提供 `.specify/memory/constitution.md`（`find .specify` 仅 `feature.json`），因此以本仓既有约束作为代理宪法，逐条对照：

| 代理原则（来源） | 本计划是否满足 | 说明 |
|------------------|----------------|------|
| 防偏离优先，宁可不出也不出错（`specs/001` FR-005/006/007, NFR 熔断） | ✅ | FR-135 要求题目/解析/批改/反馈全部过三重校验；失败即不展示（`NFR-106`） |
| 溯源可查，精确到句子级（`specs/001` FR-017） | ✅ | `knowledge_nodes.anchor`、`quiz_items.anchor` 必填（FR-125） |
| 轻量模式无 Docker 可验收（`README.md` / `core/db_learning.py`） | ✅ | `LEARNING_DB_MODE=memory`（aiosqlite）下全链路可跑（D10），契约不变 |
| 学习数据独立 metadata 与 `lr_` 前缀（002 已建立） | ✅ | 新表/扩列全部落在 `model/models_learning.py`，不污染主 PG 模型 |
| 零破坏性变更（已上线对话链路） | ✅ | 只新增表与新消息类型；`ENABLE_LEARNING_DIGEST=0` 可整体回退 |
| 教材体系一致：概念定义只有一份（`specs/001` 双轨制） | ✅ | FR-102 禁止路线携带定义副本；curriculum 校验器直接拒绝定义字段 |
| 不用未经验证的 ML 替代可解释规则（`findings.md` 3-Strike 教训） | ✅ | D2 拒绝 DKT；D6 题目必审；算法版本化（NFR-112） |

**结论**：无违规项，无需 Complexity Tracking 例外。**且必须不破坏 `specs/002` 已交付行为**（除 spec §0 声明的两处有意变更）。

---

## Project Structure

### Documentation（本规格产物）

```
specs/003-learning-routes-closed-loop/
├── spec.md                       # 需求（含 UX Brief，628 行）
├── plan.md                       # 本文件
├── research.md                   # D1–D15 决策与替代方案
├── data-model.md                 # 14 实体 + 状态迁移 + 不变量
├── quickstart.md                 # 可执行验收脚本
├── tasks.md                      # 任务清单（按用户故事分阶段）
├── contracts/
│   ├── learning-api.md           # REST 契约
│   ├── ws-events.md              # WebSocket 增补（向后兼容）
│   └── curriculum-schema.md      # 路线 YAML 格式与校验规则
└── checklists/
    └── requirements.md           # 需求质量检查表
```

### Source Code（新增 / 修改）

```text
backend/
├── model/
│   └── models.py                       [修改] 追加 14 个 ORM 实体
├── content/
│   ├── curriculum/
│   │   ├── theory.yaml                 [新增] 纯理论研究路线（首期完整）
│   │   ├── organization.yaml           [新增] 组织革命（骨架 + 首模块）
│   │   └── state_building.yaml         [新增] 建国路线（骨架 + 首节）
│   ├── curriculum_loader.py            [新增] YAML → 领域对象 + 校验
│   └── quiz_bank/                      [新增] 首期人工题库（JSON，按节点分文件）
│       └── th*.json
├── core/learning/
│   ├── repository.py                   [新增] LearningRepository 协议
│   ├── repo_pg.py                      [新增] PostgreSQL 实现
│   ├── repo_memory.py                  [新增] 内存实现（轻量模式）
│   ├── mastery.py                      [新增] 证据加权 + 五级状态迁移 + 重算
│   ├── recommender.py                  [新增] 前沿集合 + 欠账 + 杠杆
│   ├── quiz_engine.py                  [新增] 抽题/判分/错误标签/防刷分
│   ├── feedback.py                     [新增] 模板化报告 + LLM 润色 + 校验
│   ├── evidence_extractor.py           [新增] 会话后结构化抽取
│   ├── review_scheduler.py             [新增] SM-2 简化 + 强制回炉
│   └── validator.py                    [新增] curriculum/quiz 校验（立场/事实/术语）
├── services/
│   └── learning_service.py             [新增] 编排层（路由/权限/降级/埋点）
├── api/
│   └── learning_routes.py              [新增] /api/learning/*（见 contracts/learning-api.md）
├── websocket/
│   ├── protocol.py                     [修改] 追加 3 个 S→C 类型 + 2 个可选字段
│   └── server.py                       [修改] 会话结束时触发 digest
├── scripts/
│   └── import_curriculum.py            [新增] 导入 + --dry-run
├── tests/
│   ├── test_learning_mastery.py        [新增] 状态迁移/撤销重算/防刷分
│   ├── test_learning_recommender.py    [新增] 前沿/欠账/杠杆/忽略降级
│   ├── test_learning_quiz.py           [新增] 抽题/判分/标签/幂等
│   ├── test_learning_feedback.py       [新增] 可执行动作/降级/防偏离
│   ├── test_learning_api.py            [新增] 契约测试（全部端点）
│   ├── test_learning_curriculum.py     [新增] 孤儿/断链/成环/定义副本拒绝
│   └── test_learning_digest_ws.py      [新增] 小结卡 + 降级 + 幂等
└── demo_e2e.py                         [修改] 追加闭环演示（定位→诊断→推荐）

frontend/lib/
├── services/
│   ├── learning_service.dart           [新增] ChangeNotifier：路线/推荐/学情/报告
│   └── quiz_service.dart               [新增] 测试会话与作答
├── screens/
│   ├── learning_home_screen.dart       [新增] 路线地图 + 今日推荐 + 欠账
│   ├── placement_screen.dart           [新增] 定位测 + 起点建议
│   ├── quiz_screen.dart                [新增] 六类题型作答 + 即时反馈
│   ├── report_screen.dart              [新增] 章节报告 / 周报 / 小结卡详情
│   ├── dashboard_screen.dart           [新增] 雷达 + 热力 + Top5 + 欠账
│   └── review_screen.dart              [新增] 复习队列
├── widgets/
│   ├── route_map.dart                  [新增] 阶段-模块-节点树（含状态色 + 未开放态）
│   ├── reason_chip.dart                [新增] 推荐理由徽标（依赖/杠杆/欠账/到期）
│   ├── digest_card.dart                [新增] 回合级小结卡（含"我不认同"）
│   ├── error_type_tag.dart             [新增] 错误类型标签（图形+文字，非纯色彩）
│   └── radar_chart.dart                [新增] 自绘雷达（无新依赖，含替代文本）
├── screens/
│   ├── reader_screen.dart              [修改] 增加进度条/章节诊断入口/批注轨
│   └── chat_sheet.dart                 [修改] 接入 digest 消息与降级提示
├── main.dart                           [修改] 命名路由 + LearningService 注入
└── models/                             [新增] learning_models.dart（手写 fromJson，不引代码生成）

frontend/test/
├── learning_service_test.dart          [新增]
└── digest_card_test.dart               [新增]
```

**Structure Decision**：后端沿用「`core/` 领域算法 + `services/` 编排 + `api/` 契约」三层（与 `core/guard`、`services/dialogue_service.py` 同构）；前端沿用「`services/` ChangeNotifier + `screens/` + `widgets/`」扁平结构（与 `ChatService` 同构），不引入 go_router/Riverpod/代码生成。

---

## Phase 0 — Research（已完成）

见 `research.md`，关键决策：D1 共享图谱 profile、D2 简化贝叶斯 + 证据加权、D3 会话后单次抽取、D4 欠账优先推荐、D5 软门禁、D6 题目三校验 + 抽检、D7 六类错误标签、D8 rubric 判分、D9 SM-2 简化、D10 内存仓库兼容轻量模式、D11 YAML 配置、D12 首期内容边界、D13 模板 + LLM 反馈、D14 Provider 前端、D15 SQL 视图埋点。

## Phase 1 — Design（已完成）

- `data-model.md`：14 实体、状态迁移矩阵、派生视图、不变量
- `contracts/learning-api.md`、`contracts/ws-events.md`、`contracts/curriculum-schema.md`
- `quickstart.md`：6 条可执行验收场景
- `checklists/requirements.md`

---

## Phase 2 — 交付计划（详细）

> 按"每个迭代结束都可独立演示 + 可回归"切片。`tasks.md` 是同源任务清单（T001–T078）。

### 迭代 A（P0）：内容骨架 + 学情地基（对应 US1 前置）

**目标**：三条路线可导入、可校验、可展示；证据/状态模型可用。

| 交付物 | 验收 |
|--------|------|
| 6 新建表 + 8 扩列表 + 迁移脚本 | `LEARNING_DB_MODE=memory` 与 `postgres` 两种模式下建表/扩列均成功，既有 `lr_*` 数据不丢 |
| `curriculum.yaml` ×3 + `curriculum_loader.py` | `POST /api/learning/admin/curriculum/validate` 对三份文件 `ok=true`；故意删前置 → `broken_prerequisite`；节点塞 `canonical_definition` → 拒绝 |
| 仓库抽象（PG + 内存） | 同一套 pytest 对两个实现全过（参数化 fixture） |
| `mastery.py` 状态迁移 | 单测覆盖：对话证据不跨级、测试可 +2、撤销后重算等于"重放剩余证据" |
| 幂等 | 同一 `dedupe_key` 提交 2 次 → 只 1 条 evidence |

**退出条件**：`pytest backend/tests/test_learning_mastery.py test_learning_curriculum.py` 全绿；`demo_e2e.py` 仍通过（无回归）。

### 迭代 B（P0）：定位测 + 起点建议（US1）

| 交付物 | 验收 |
|--------|------|
| `POST /plan` + 路线树接口 | 切换路线保留状态（FR-104）测例通过 |
| `quiz_engine.py` 抽题（定位测 8–15 题，按路线各阶段抽样） | 题库不足 8 题 → 降级抽样 + `placement_degraded=true` |
| 起点算法（前沿集合最小 seq，杠杆值次排序） | 固定输入 → 稳定输出（确定性单测） |
| `placement_screen.dart` + `route_map.dart` | 3 分钟可完成定位到进入阅读的路径；空/加载/离线/未上线四态有截图验收 |

**退出条件**：SC-101（≤5 分钟）、SC-102（≥80% 接受或微调）在 5 人内测中达成。

### 迭代 C（P1）：章节诊断 + 六类题型 + 错误标签（US2）

| 交付物 | 验收 |
|--------|------|
| 题库 120 题（含 12 道溯源、10 道迁移） | 每题有 `anchor` + `rubric`（迁移题）；`test_learning_quiz.py` 覆盖 6 类判分 |
| 抽题：题量按 `weight` 自适应（8–20），连续对错调难度 | 单章诊断出报告 ≤10s（SC-103 压测脚本） |
| 错误标签 6 类 + 干扰项差异说明 | 20 道样例题人工核对标签一致 |
| 7 天重复不计分 | 单测：同题同日两次作答，第二次 `counts_toward_mastery=false` |
| `quiz_screen.dart` + `report_screen.dart` | 断点续答；待确认态可见；每条 `action_item` 可跳转 |

**退出条件**：SC-103/SC-110 达标；`pytest backend/tests/test_learning_quiz.py` 全绿。

### 迭代 D（P1）：对话证据 + 三档反馈 + 推荐（US3/US4/US5 的反馈与推荐部分）

| 交付物 | 验收 |
|--------|------|
| `evidence_extractor.py` + WS `learning_digest` | 会话结束 ≤8s 出小结卡；LLM 关掉 → `degraded=true` 且不展示 `to_fix` |
| 低置信不写入 + 可撤销 | 单测：confidence<0.6 不产生 evidence；撤销后 5s 内回退（NFR-104） |
| `recommender.py`（欠账 > 到期 > 杠杆 > 顺序） | 30 组固定状态快照的输出快照测试；连续忽略 3 次降级为单概念 |
| `feedback.py` 模板 + 润色 + 三重校验 | 50 条报告抽检：可执行动作覆盖 100%（SC-106）；校验失败不展示 |
| `learning_home_screen.dart` / `digest_card.dart` / `reason_chip.dart` | 推荐 1 主 + ≤2 备选；理由徽标四类齐全 |

**退出条件**：SC-104（校准 ≥80%）、SC-105（纠正率 ≤10%）、SC-107（采纳率 ≥60%）在 10 人内测中达成。

### 迭代 E（P2）：仪表盘 + 复习队列 + 审核（US5 仪表盘 / US6 / US7）

| 交付物 | 验收 |
|--------|------|
| `dashboard` API + `dashboard_screen.dart`（雷达/热力/Top5/欠账） | 每个维度可下钻到节点与证据；雷达图有屏幕阅读器替代文本 |
| `review_scheduler.py` + `review_screen.dart` | 到期排序正确；单日 ≤20；"只做 5 项"降级；诊断未过 → `forced_relearn` |
| 审核 API + 抽检队列 | AI 题 `check_failed` 无法发布；`approved` 才能进抽题池（FR-124） |
| 周报 | 自然周生成，含掌握增量/雷达变化/欠账/到期/偏离；可关闭推送 |

**退出条件**：SC-108（首个已开放模块完整率 100%）、SC-109、SC-111 达标。

### 迭代 F（收尾）：回退开关、导出、文档

- `ENABLE_LEARNING_DIGEST` / `ENABLE_LEARNING` 双开关，可整块回退到 `specs/001` 行为
- 学习者数据导出（NFR-108）：evidence + attempts + reports → JSON/CSV
- `README.md` 增补学情模块启动与验收说明；`demo_e2e.py` 追加闭环演示

---

## 依赖图（迭代顺序）

```
A（内容骨架 + 学情地基）
 └─► B（定位测 + 起点）
      └─► C（章节诊断 + 题型）
           ├─► D（对话证据 + 反馈 + 推荐）
           │    └─► E（仪表盘 + 复习 + 审核）
           │         └─► F（收尾）
           └─► （推荐算法可先于 D 的反馈部分独立开发，二选一并行）
```

**可并行**：C 与 D 的题库/抽取器可并行（不同目录）；E 的仪表盘前端可在 D 的 API 冻结后立即开始（mock 数据）。

---

## 验证门禁（每个迭代必须通过）

```bash
# 后端
cd backend && python -m pytest tests -q
cd backend && LEARNING_DB_MODE=memory python -m uvicorn app:app --port 8190    # 轻量模式启动不报错
cd backend && python demo_e2e.py                                              # 既有闭环无回归

# 002 已交付能力的回归（必须保持全绿）
cd backend && python -m pytest tests/test_route_flow.py tests/test_mastery.py \
    tests/test_quiz_orthodoxy.py tests/test_recommendation.py tests/test_review.py \
    tests/test_profile.py -q

# 前端
cd frontend && flutter analyze && flutter test

# 内容
cd backend && python scripts/import_curriculum.py --dry-run                   # 三份路线 ok=true
```

---

## 风险与缓解（与 spec 对应）

| 风险 | 计划中的落点 |
|------|--------------|
| R-101 掌握度虚高 | 迭代 A 的状态迁移单测 + 迭代 D 的校准测试（SC-104）+ 撤销入口（迭代 D） |
| R-102 内容瓶颈 | 首期只铺一条完整路线（D12）；题库按"每节点 ≥2 题"分批；内容进度作为迭代 D/E 的进入条件 |
| R-103 路线与立场冲突 | curriculum 校验器强制 `standpoint_tier` 内容匹配（迭代 A）；`critical` 档位默认关闭，需配置开启 |
| R-104 推荐过度工程 | 迭代 D 先两因子，杠杆值只作次级；用 SC-107 决定是否继续调参 |
| R-105 主观题判分不稳 | rubric 分项 + 低置信待确认（迭代 C）；判分版本化（NFR-112） |
| R-107 刷题化 | FR-123 服务端强制（迭代 C）+ 诊断在阅读完成后才可触发（迭代 C 前端约束） |
| R-108 复习堆积 | 20 项上限 + 降级模式（迭代 E） |

---

## Complexity Tracking

无违规项，无例外申请。以下为**有意的简化**（避免过度设计）：

| 简化 | 理由 | 何时重新评估 |
|------|------|--------------|
| 不引入 DKT/AKT | 数据量不足，不可解释（D2） | 单路线累计作答 ≥50k 且 SC-104 不达标 |
| 不引入 go_router/Riverpod | 现有 provider 已够用（D14） | 页面数 >10 或出现深链需求 |
| 不引入向量检索做推荐 | 推荐依赖图谱依赖关系，语义相似度会破坏教学顺序（D4） | 出现"跨路线选学"复杂需求 |
| 题目 node_keys 不用 GIN 索引 | 题库 <500，应用层过滤足够 | 题库 >5,000 |
| evidence 不按月分区 | MVP 数据量小 | 学习者 >10 万 |
| 周报用定时任务而非流式 | 只需自然周 | 需要实时看板 |

---

## 估算（1 名后端 + 1 名前端 + 兼职内容）

| 迭代 | 人力（人日） | 说明 |
|------|--------------|------|
| A | 6（后端 5 / 前端 1） | 表 + 校验器 + 状态机 |
| B | 7（后端 3 / 前端 4） | 定位测 + 路线地图 |
| C | 9（后端 5 / 前端 4） | 题库生产是主要成本（内容另计 5 人日） |
| D | 10（后端 6 / 前端 4） | 抽取 + 推荐 + 反馈 + 小结卡 |
| E | 8（后端 4 / 前端 4） | 仪表盘 + 复习 + 审核 |
| F | 3 | 回退开关 + 导出 + 文档 |
| **合计** | **≈43 人日**（不含内容生产 ≈14 人日） | |

**关键路径**：内容生产（题目 + 解析层）> 后端算法 > 前端页面。建议迭代 C 开始前先并行启动题库生产。
