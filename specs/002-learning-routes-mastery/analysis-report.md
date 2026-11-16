# Analyze Report: 三路线学习与学情闭环

**Date**: 2026-11-04 | **Artifacts**: spec.md / plan.md / tasks.md / data-model.md / contracts/ / research.md
**Mode**: 只读交叉一致性检查（speckit-analyze）

## 结论摘要

- 总体一致性：**PASS（修复后）**。发现 1 个 High 缺口、2 个 Low 漂移，已就地修复（tasks.md / plan.md）。
- 宪章：`.specify/memory/constitution.md` 不存在，按 001 事实宪章（正统性红线）比对——**无违规**。
- 无悬空引用、无破坏性重复、无用户故事无任务覆盖。

## 覆盖矩阵（Spec → Tasks）

| 用户故事 | 优先级 | 任务 | 独立测试任务 | 状态 |
|---|---|---|---|---|
| US1 路线与起点 | P1 | T011–T018（8） | T018 | ✅ |
| US2 逐章学习闭环 | P1 | T019–T026（8） | T026 | ✅ |
| US3 章节测试与掌握度 | P1 | T027–T036 + T028B（11） | T035/T036 | ✅ |
| US4 学情档案与反馈 | P2 | T037–T044（8） | T044 | ✅ |
| US5 推荐与门控 | P2 | T045–T050（6） | T050 | ✅ |

## 需求覆盖（FR-001…FR-024）

- 全部 24 条 FR 均有对应任务或契约落点 ✅
- **修复项（High）**：原 FR-014（主观题/费曼三维批改）在 tasks 中无显式任务 → 已补 **T028B**（quiz_service 批改）并在 T036 增补批改测试断言。现 FR-014 闭环。
- FR-022/023/024（正统性红线）→ T030/T022/T035 显式覆盖 ✅

## 成功标准可测性（SC-001…SC-008）

- 均可映射到 E2E 或指标：SC-001→US1、SC-002/005→mastery gating（T029/T047）、SC-003→T044、SC-004→T050、SC-006→总结（T038）、SC-007→T030、SC-008→quickstart 6 步。✅

## 实体 / 契约一致性

- data-model.md 14 实体 ⇄ T004 ORM 表名逐项匹配（数：14 vs 14）✅
- contracts 四组 API（routes/quiz/mastery/recommendation）⇄ 任务路由文件（route_routes/quiz_routes/mastery_routes/recommendation_routes）逐项匹配 ✅
- WS `progression`/`struggle_detected` 在契约与 T020/T025 对齐 ✅

## 漂移 / 提示（Low，已处理）

- **L1（已修）**：plan.md 源码树未列 route_service / knowledge_graph_service / sync_service（但 tasks 使用）→ 已补入 plan 源码树，命名对齐。
- **L2（保留）**：NFR-001/002/003 性能指标未设专门性能测试任务，仅有 NFR-004 在 T051/T052 落地。属可接受（P0 以功能验收为先），建议在 Polish 阶段补一次时延抽测；不阻塞。

## 遗留 [NEEDS CLARIFICATION]

- **无**。spec Clarifications 段已以推荐答案落定 5 项关键决策。

## 建议下一步

- 可执行 `/speckit-implement`：按 **MVP 最小集 T001–T036** 先在提纲单章上跑通「选路线→摸底→学一章→测一章」闭环，再补 US4/US5 与 Polish。
