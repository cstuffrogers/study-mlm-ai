# Implementation Plan: 三路线学习与学情闭环

**Feature Branch**: `002-learning-routes-mastery`
**Spec**: [spec.md](./spec.md)
**Created**: 2026-11-04

## Summary

在既有 MVP（FastAPI + Flutter + PG/pgvector + Redis + Neo4j，已跑通《提纲》精读 + 五模式会话 + 防偏离三重机制 + RAG + 溯源）之上，新增「三路线学习 + 学情闭环」能力层。技术上分五块新增：**内容层（路线/章节/知识点树）→ 测验引擎 → 掌握度与学情引擎 → 路径推荐引擎 → 前端导航/测试/档案页面**。核心复用既有 `DialogueService`、`TripleCheck`、`HybridRetriever`、溯源卡片与 `ReaderScreen`/`ChatSheet`。

## Technical Context

- **Language/Version**: Python 3.11（后端）、Dart/Flutter（前端）
- **Primary Dependencies**: FastAPI、SQLAlchemy(asyncpg)、pgvector、Redis、Neo4j driver、pytest；Flutter (Material)
- **Storage**: PostgreSQL(pgvector) 主存储学情/题目/进度；Redis 缓存推荐与判分；Neo4j 知识点依赖图（降级 in-memory 邻接表）
- **Testing**: pytest（后端）、flutter test（前端）、demo 端到端脚本
- **Target Platform**: 移动端优先（Flutter iOS/Android），Web 次要
- **Project Type**: Web 前后端分离（backend/ + frontend/）
- **Performance Goals**: 判分+掌握度 ≤3s（客观题）、档案首屏 ≤1s、推荐生成 ≤2s（NFR-001/002/003）
- **Constraints**: 题库须溯源锚定 + 三重校验；防偏离红线不放松；学情跨设备同步
- **Scale/Scope**: P0 先单章（提纲）闭环；路线/题库分批扩展。知识点节点目标 500–800（spec FR 设计量级，P0 先提纲约 12 概念）

### 未知项与决策（原 NEEDS CLARIFICATION，已在 research.md 解决）

- 掌握度算法选型 → 见 research.md D1（加权贝叶斯式评分 + 五级阈值）
- 题目来源与正统性保障 → 见 research.md D2（专家题库 + AI 辅助 + 三重校验门禁）
- 知识点依赖图存储 → 见 research.md D3（Neo4j 优先，in-memory 降级）
- 推荐算法 → 见 research.md D4（规则优先：掌握度×依赖出度×考频）
- 题库/路线内容规模 P0 → 见 research.md D5（单章先行，可配置）

## Constitution Check

> `.specify/memory/constitution.md` 不存在，跳过正式宪章比对。沿用 001 已确立的项目红线作为事实宪章：

- **正统性不可放松**：题库/解析/批改必须过 TripleCheck + 溯源；错误诊断项走豁免标记。
- **不臆造内容**：AI 不凭空生成无溯源答案；题目须专家定稿。
- **复用优先**：不重建精读/会话/防偏离能力，只在其上叠加。
- **可验证指标**：成功标准均量化可测。

结论：本计划与既有红线一致，无违规。

## Project Structure

### Documentation (this feature)
```
specs/002-learning-routes-mastery/
├── spec.md              # 功能规格（含 UX Brief）
├── plan.md              # 本文件
├── research.md          # Phase 0：技术决策
├── data-model.md        # Phase 1：实体/表结构
├── contracts/           # Phase 1：REST/WS 接口契约
│   ├── routes-api.md
│   ├── quiz-api.md
│   ├── mastery-api.md
│   └── recommendation-api.md
├── quickstart.md        # Phase 1：端到端验证指南
├── tasks.md             # /speckit-tasks 产出
└── checklists/
    └── requirements.md
```

### Source Code (repo root)
```
backend/
├── content/
│   ├── routes.py            # [新] 三路线 + 章节定义（A/B/C + 共享地基）
│   ├── knowledge_graph.py   # [新] 知识点节点 + 依赖关系（提纲为例）
│   └── quiz_bank/           # [新] 题库（提纲章节题，含溯源 chunk_id）
├── services/
│   ├── route_service.py     # [新] 路线/章节/摸底测起点计算
│   ├── knowledge_graph_service.py  # [新] 知识点图查询（前置闭包/依赖出度）
│   ├── quiz_service.py      # [新] 出题/判分/错因归类/主观题三维批改
│   ├── mastery_service.py   # [新] 掌握度计算 + 学情信号融合
│   ├── profile_service.py   # [新] 学情档案聚合 + 薄弱点排序 + AI 总结
│   ├── recommendation_service.py  # [新] 路径推荐 + 门控
│   ├── sync_service.py      # [新] 跨设备同步 + 离线暂存合并
│   └── dialogue_service.py  # [改] 接入即时小结 + 隐式学情信号上报
├── model/models.py          # [改] 新增学情/题目/进度等表
├── api/
│   ├── route_routes.py      # [新] 路线/导航
│   ├── quiz_routes.py       # [新] 测试
│   ├── mastery_routes.py    # [新] 掌握度/档案
│   └── recommendation_routes.py  # [新] 推荐/门控
└── tests/
    ├── test_quiz_orthodoxy.py
    ├── test_mastery.py
    ├── test_recommendation.py
    └── test_route_flow.py

frontend/lib/
├── models/          # [改] 新增 Route/Chapter/Quiz/Mastery/Profile 模型
├── screens/         # [新] route_picker / route_map / chapter_test / profile_dashboard
├── widgets/         # [新] recommendation_card / mastery_badge / radar_chart / weak_point_card
├── services/        # [改] 新增 routes/quiz/mastery 的 API 服务
└── screens/reader_screen.dart  # [改] 章节学习页复用；加即时小结卡
```

**Structure Decision**: 沿用 001 的 backend/frontend 分层与服务化架构。新增能力以 service 层扩展 + 新 API 路由 + 新表实现，前端新增页面并以推荐卡/掌握度徽章等可复用组件叠加到既有阅读器。

## Phase 0: Outline & Research — 见 research.md
决策项：D1 掌握度算法、D2 题目正统性门禁、D3 知识点图存储、D4 推荐算法、D5 P0 内容规模。

## Phase 1: Design & Contracts
- data-model.md：14 个核心实体落表（路线/章节/知识点/掌握度/题目/作答/测试/摸底/进度/信号/档案/推荐/总结）。
- contracts/：4 组 REST 契约 + 复用既有 WS 协议（新增 progression/struggle 消息落地）。
- quickstart.md：端到端 6 步验证（选路线→摸底→学一章→测一章→看档案→按推荐进入）。

## Phase 2: Task Planning Approach
- 按用户故事组织（US1–US5 对应 spec 优先级），P1 先做（US1/US2/US3），P2 后补（US4/US5）。
- 每个故事可独立测试；US3（测试+掌握度）是 P1 核心，作为 P0 单章闭环的关键路径。

## Complexity Tracking
| 决策 | 说明 |
|------|------|
| 复用 vs 重建 | 精读/会话/防偏离直接复用，降低复杂度；仅新增学情侧服务 |
| 知识点图 in-memory 降级 | P0 阶段无需 Neo4j 即可跑，Docker 起来切换 |
| 题库 P0 单章 | 控制内容生产成本，机制先跑通再批量补内容 |
