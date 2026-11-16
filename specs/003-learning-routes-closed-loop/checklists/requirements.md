# Requirements Quality Checklist: 三路线学习路径与掌握度闭环

**Purpose**: 验证 `spec.md` 的需求质量（可测试性、完整性、一致性），在进入实现前发现"看起来清楚实际含糊"的条目。
**Feature**: `specs/003-learning-routes-closed-loop`
**Scope**: spec.md 全部 FR/SC/NFR/UX Brief（不含 plan/tasks 的工程决策）
**Created**: 2026-07-18

---

## A. 需求可测试性（Requirement Testability）

- [x] CHK001 每条 FR 都有可观察的验收方式（接口返回、状态变化或报告字段），无"应当友好/智能"类措辞
- [x] CHK002 FR-107/108 的起点建议有明确输入（定位测结果）与输出（章节 + 理由 + 可跳过清单）
- [x] CHK003 FR-120 的错误类型限定为 6 个枚举值，可做一致性抽检（SC-110）
- [x] CHK004 FR-123 的"7 天"为硬阈值，可实现为查询条件而非主观判断
- [x] CHK005 FR-127 的"可执行动作"定义为带跳转目标的结构化字段，可用脚本检查覆盖率（SC-106）
- [x] CHK006 NFR-102 幂等性有可验证载体（`dedupe_key` 唯一约束），非口号
- [x] CHK007 SC-104 的校准口径（标记"熟悉+"的节点 14 天内后续测试正确率 ≥80%）可查询计算

## B. 完整性与边界（Completeness & Boundaries）

- [x] CHK008 路线切换（FR-104）、人工覆盖起点（FR-108）、内容未上线（FR-110/Edge）三种非主路径均有需求覆盖
- [x] CHK009 缺数据路径有定义：题库不足（NFR-111）、AI 不可用（Edge + NFR-107）、内容未上线（Edge）
- [x] CHK010 撤销与冲突（FR-115/117）定义了状态回退与记录保留，不只是"允许修改"
- [x] CHK011 三条路线的"共享图谱、不复制定义"是硬约束（FR-102），并有校验要求（FR-106）
- [x] CHK012 立场档位（Clarifications 1）与既有防偏离机制的衔接有明确规则（FR-135 + Edge）
- [x] CHK013 交付边界明确：In/Out of Scope 各 10+ 条，含"教师视图""真题库""UGC"等易蔓延项

## C. 一致性（Consistency）

- [x] CHK014 `specs/001` 与本规格的编号不冲突（001 用 FR-001..、本规格用 FR-101..）
- [x] CHK015 术语统一：知识节点 = `KnowledgeNode`；证据 = `EvidenceEvent`；报告 = `FeedbackReport`（spec/data-model/contracts 一致）
- [x] CHK016 五级状态命名在 spec、data-model、API 契约中一致（未接触/初学/熟悉/精通/贯通 ↔ 0..4）
- [x] CHK017 六类题型命名在 spec（中文）、data-model（`item_type` 枚举）、契约（同枚举）一一对应
- [x] CHK018 优先级顺序（P1/P2/P3/P4）与 tasks.md 阶段顺序一致（US1→US2→US3→US4→US5→US6→US7）
- [x] CHK019 软门禁（Clarifications 2）与 FR-111 表述一致，无残留"拒绝解锁"措辞
- [x] CHK020 定位测题量在三处一致（spec US1 / FR-107 / quickstart 场景 2）——**已修订为 8–15**

## D. 可度量性（Measurability）

- [x] CHK021 每条 SC 都有阈值与测量方式（时长/比例/条数/抽检样本量）
- [x] CHK022 SC-101..SC-112 均可由服务端埋点或脚本统计，不依赖主观评分（除 SC-112 问卷，已注明样本 ≥30）
- [x] CHK023 NFR-101..NFR-112 的性能/降级/版本化要求可写成自动化测试（plan 的 `test_learning_perf.py`、`test_learning_db_toggle.py`）

## E. 风险与假设（Risks & Assumptions）

- [x] CHK024 首要风险（R-101 掌握度虚高、R-102 内容瓶颈）都有对应缓解需求（FR-115/116/117、FR-106/124）
- [x] CHK025 假设被显式声明（8 条），其中"轻量模式仍可验收"有 NFR 与 plan 落点
- [x] CHK026 Open Questions 保留 4 条（教师视图/评分要点作者/定位题来源/周报周期），未伪装成已决策

## F. 待确认（需要产品方拍板，不阻塞实现）

- [ ] CHK027 机构/校园场景是否进入本规格（当前 Out of Scope，影响 +1 迭代）
- [ ] CHK028 迁移题评分要点由编辑还是学科专家撰写（依赖 `specs/001` 专家工作台进度）
- [ ] CHK029 周报周期取自然周还是滚动 7 天（当前默认自然周）

---

**结论**：26/29 项通过，3 项待产品方拍板（不影响 Phase 1–2 开工）。规格可进入 `/speckit-implement`。
