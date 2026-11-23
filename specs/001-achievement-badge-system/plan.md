---
feature: achievement-badge-system
spec_version: 1.0
plan_version: 1.0
created: 2026-11-22
status: draft
---

# 实施计划：学习勋章系统（achievement-badge-system）

> 说明：项目本地 `.specify/` 未提供 plan 模板与 setup 脚本，本计划采用 spec-kit 标准结构（Technical Context / Constitution Check / Research / Data Model / Contracts / Quickstart）。

## Technical Context

**现有技术栈与可复用设施**

- 后端：Python FastAPI + uvicorn；SQLAlchemy 2.0 async + asyncpg（学习域表在 `backend/model/models_learning.py`，15 表）；redis、neo4j。
- 前端：Flutter/Dart（`frontend/lib/`：screens / services / widgets / offline）。
- 可复用的既有能力：
  - `motivation_service.motivation_state()`：已返回掌握数、连续学习天数、作答统计与里程碑列表（`_milestones`），是多项指标的直接来源。
  - `mastery_service.get_mastery_map()` / `progress_map()`：掌握度与路线进度。
  - `quiz_service`：作答记录（含 `is_correct`），可汇总答对题数。
  - `route_service` + `content/routes.py`：路线与完成判定。
  - `dialogue_service` / `dialogue_store`：对话学习记录。
  - `sync_service`：既有离线数据同步通道（离线授予记录可走此通道）。
  - 前端离线：`frontend/lib/offline/`（local db、`local_mastery.dart`、`local_insight.dart`）已实现本地指标计算，勋章本地评估沿用同模式。
- 内容配置模式：`backend/content/routes.py`、`content/quiz_bank/*.json` —— 勋章目录采用同风格的配置模块。

**关键决策（详见 research.md）**

1. 勋章目录为 `backend/content/badges.py` 的纯数据模块（D1）。
2. 授予记录落新表 `user_badges`（`backend/model/models_learning.py`），(user_id, badge_id) 唯一保证幂等（D2）。
3. 评估引擎 `backend/services/badge_service.py`：采集 7 项指标 → 对照目录 → 插入新授予（D3）。
4. 检测挂接点：答题提交、掌握度更新、路线完成、对话完成、每日动机结算（D4）。
5. 事件响应中直接返回 `badges_awarded`，前端即时触发动画；另有 `unseen` 查询兜底（D5）。
6. 离线：客户端本地评估 + 本地授予记录，联网经 sync 通道合并（D6，采用推荐默认，待用户确认）。
7. 动画用 Flutter 内置动画 + CustomPainter 自绘礼盒开箱效果，不新增依赖（D7）。

## Constitution Check

项目本地无 `.specify/memory/constitution.md`，以项目既有红线与约定为准：

- 内容红线（不伪造原文、批判对象标注等）：本功能不涉及内容生成，无冲突。
- 测试基线：后端 `pytest tests/ -q`（必须用 `backend/.venv/Scripts/python.exe`）、前端 `flutter test` / `flutter analyze`，本计划任务包含对应测试。
- 前端底栏高度不随功能开关变化：勋章页为独立页面，不涉及底栏布局，无冲突。

**结论**：无宪法冲突。

## Research（摘要）

完整记录见 [research.md](research.md)。要点：

- 指标采集全部复用既有服务，不引入新的统计口径；贯通数 = 有掌握度记录或测验记录的去重知识点数。
- 路线完成判定复用 `route_service` 进度聚合（全部节点掌握或测验通过）。
- 动画方案评估：引入第三方动画库（成本高、离线包体增大）vs 自绘（可控、零依赖）→ 自绘。
- 离线方案评估：服务端单点判定（离线不可用，违背激励目标）vs 客户端本地评估 + 服务端权威合并 → 后者。

## Data Model

详见 [data-model.md](data-model.md)。新增实体：`BadgeDefinition`（配置，非表）、`BadgeAward`（表 `user_badges`）。派生实体：`LearningMetrics`（实时汇总，不落表）。

## Interface Contracts

REST 接口契约见 [contracts/badges-api.md](contracts/badges-api.md)：

- `GET /api/badges/mine`：全部勋章 + 授予状态 + 进度（「我的勋章」页面数据源）。
- `GET /api/badges/unseen`：未查看的新勋章（首页提醒 / 动画触发兜底）。
- `POST /api/badges/read`：标记已查看。
- 事件响应扩展：答题/掌握/路线/对话等事件响应中附带 `badges_awarded`。

## Quickstart

验证指南见 [quickstart.md](quickstart.md)：后端接口验证（curl）+ 前端测试 + 端到端手工流程。

## Implementation Notes

- 阶段顺序：目录/表/服务骨架 → 评估引擎与事件挂接 → 后端接口 → 动画 → 勋章页 → 首页提醒 → 离线与收尾。
- 任务分解见 [tasks.md](tasks.md)。
- 项目无 CLAUDE.md 文件，spec-kit 的 agent 上下文更新步骤（SPECKIT 标记区间）跳过；如后续创建 CLAUDE.md，需将本计划路径写入该文件。
