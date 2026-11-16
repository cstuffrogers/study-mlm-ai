# Tasks: 三路线学习路径与掌握度闭环

**Feature**: `specs/003-learning-routes-closed-loop/spec.md`
**Plan**: `specs/003-learning-routes-closed-loop/plan.md`
**Input**: spec.md（US1–US7）+ plan.md（迭代 A–F）+ data-model.md + contracts/*

**格式**: `- [ ] Txxx [P?] [US?] 描述 + 文件路径`
`[P]` = 可与同阶段其他任务并行（不同文件、无未完成依赖）；`[US?]` = 归属用户故事。

---

## Phase 1: Setup（项目初始化，无故事）

- [ ] T001 在 `backend/requirements.txt` 追加 `pyyaml>=6.0`、`jsonschema>=4.21`，并安装验证
- [ ] T002 [P] 新建 `backend/content/curriculum/` 目录与三份空骨架 `theory.yaml` / `organization.yaml` / `state_building.yaml`（含 `schema_version: 1` 与 route 头）
- [ ] T003 [P] 新建 `backend/content/quiz_bank/` 目录与 `README.md`（题目文件命名与字段约定，指向 `contracts/curriculum-schema.md` 的题型定义）
- [ ] T004 [P] 新建 `backend/core/learning/__init__.py`，导出 `repository / mastery / recommender / quiz_engine / feedback / evidence_extractor / review_scheduler / validator` 模块占位
- [ ] T005 [P] 在 `backend/core/config.py` 追加开关：`ENABLE_LEARNING`、`ENABLE_LEARNING_DIGEST`、`LEARNING_DIGEST_TIMEOUT_S=8`、`LEARNING_SNAPSHOT_PATH`、`LEARNING_ALGO_VERSION=1`
- [ ] T006 [P] 在 `frontend/lib/models/learning_models.dart` 建立手写模型（Route/Stage/Module/NodeState/QuizItem/Report/Recommendation/Progress），不引代码生成

---

## Phase 2: Foundational（阻塞所有用户故事）

### 数据层

- [ ] T007 在 `backend/model/models_learning.py` **新建 6 张**：`RouteModule` / `RouteModuleNode` / `LearningPlan` / `EvidenceEvent` / `QuizSession` / `ReviewSchedule`（字段见 data-model.md §0 与 §2）
- [ ] T008 在 `backend/model/models_learning.py` **扩列 8 张既有表**：`lr_routes`、`lr_route_sections`、`lr_knowledge_nodes`、`lr_mastery_records`、`lr_quiz_items`、`lr_quiz_attempts`、`lr_feedback_reports`、`lr_recommendations`（仅 `ALTER ADD COLUMN` 语义，可空默认值）
- [ ] T009 在 `backend/model/models_learning.py` 补唯一约束与索引：`evidence_events.dedupe_key` 全局唯一、`quiz_sessions(session_id, quiz_item_id)` 唯一
- [ ] T010 [P] 在 `backend/model/models_learning.py` 补查询索引（data-model.md §4：`evidence_events(user_id, created_at desc)`、`mastery_records(user_id, level)`、`review_schedules(user_id, due_at)`、`quiz_items(review_status, item_type, difficulty)`）
- [ ] T011 [P] 确认 `services/learning_startup.py` 能在 `LEARNING_DB_MODE=memory`（aiosqlite）与 `postgres` 两种模式下建出新表并种子导入；补断言测试 `backend/tests/test_learning_db_toggle.py`；**不得**修改主 `model/models.py` 与主 DB 连接

### 仓库抽象

- [ ] T012 在 `backend/core/learning/repository.py` 定义 `LearningRepository` 协议（路线/计划/状态/证据/题目/会话/报告/复习的读写方法，全部 async）
- [ ] T013 在 `backend/core/learning/repo_pg.py` 实现 PostgreSQL 版本（依赖 T007–T010）
- [ ] T014 在 `backend/core/learning/repo_memory.py` 实现内存版本，支持 `LEARNING_SNAPSHOT_PATH` 的 JSON 落盘/恢复
- [ ] T015 在 `backend/core/learning/repository.py` 追加工厂 `get_repository()`，按 `LEARNING_DB_MODE`/`ENABLE_LEARNING` 选择实现；若既有服务层已足够，可直接复用 `services/learning_db.py` 而不新建仓库层
- [ ] T016 [P] 在 `backend/tests/conftest.py` 追加 `repo` 参数化 fixture（pg 用临时事务回滚、memory 每次新建），供后续测试复用

### 领域核心

- [ ] T017 在 `backend/core/learning/mastery.py` 实现来源权重表（quiz 1.0 / feynman 0.8 / dialogue 0.4 / reading 0.1 / manual 1.0）与证据→状态迁移（data-model.md §2.8 迁移矩阵）
- [ ] T018 在 `backend/core/learning/mastery.py` 实现 `recompute_from_evidence(user, node)`：撤销后按剩余有效证据重放，结果必须与顺序无关（不变量 6）
- [ ] T019 在 `backend/core/learning/mastery.py` 实现派生查询：欠账清单、前沿集合、能力雷达五维、掌握增量
- [ ] T020 在 `backend/core/learning/validator.py` 实现 `validate_curriculum(doc) -> issues`（孤儿/断链/成环/未知概念/锚点不可解析/定义副本拒绝/档位内容缺失，见 contracts/curriculum-schema.md §2–3）
- [ ] T021 在 `backend/core/learning/validator.py` 实现 `check_item(item)`：立场/事实/术语三类离线校验，复用 `backend/core/guard/orthodoxy.py` 与 `backend/core/verify/triple_check.py`
- [ ] T022 在 `backend/content/curriculum_loader.py` 实现 YAML → 领域对象解析 + 编译（stage/module/node 展开、`leverage_value` 反向闭包计算、`route_module_nodes` 生成）
- [ ] T023 在 `backend/scripts/import_curriculum.py` 实现导入（`ON CONFLICT DO UPDATE`、`version += 1`、`--dry-run` diff 摘要、删除节点降级为 `deprecated`）
- [ ] T024 在 `backend/services/learning_service.py` 建立骨架：依赖注入仓库、开关判断、统一错误码映射（contracts/learning-api.md 通用错误码）
- [ ] T025 在 `backend/api/learning_routes.py` 注册 `/api/learning` 前缀并在 `backend/app.py` `include_router`（`ENABLE_LEARNING=0` 时不注册）

### 基础测试

- [ ] T026 [P] `backend/tests/test_learning_mastery.py`：对话证据不跨级、测试可 +2、连续 3 错降级 + `conflict_flag`、7 天同题不计分、撤销重算等价
- [ ] T027 [P] `backend/tests/test_learning_curriculum.py`：三份 YAML `ok=true`；删前置 → `broken_prerequisite`；成环 → `cycle`；塞 `canonical_definition` → 拒绝；`critical` 缺内容 → `tier_content_missing`
- [ ] T028 [P] `backend/tests/test_learning_repository.py`：同一套语义测试对 pg/memory 两实现全绿；`dedupe_key` 重复写只 1 条

**Gate**：`pytest backend/tests/test_learning_mastery.py test_learning_curriculum.py test_learning_repository.py -q` 全绿；**002 回归**：`test_route_flow.py`、`test_mastery.py`、`test_quiz_orthodoxy.py`、`test_recommendation.py`、`test_review.py`、`test_profile.py`、`test_analytics_interleaved.py` 全绿；`python demo_e2e.py` 无回归。

---

## Phase 3: US1 — 选路线与起点定位（P1）🎯 MVP 第一切片

**独立验收**：新用户选"组织革命"→ 12 题定位测 → 得到起点章节与理由；可人工覆盖起点；切换路线保留学情。

- [ ] T029 [US1] `backend/services/learning_service.py` 实现 `list_routes()` / `get_route_tree(code, user)`（含节点状态与欠账标记，`GET /routes`、`GET /routes/{code}`）
- [ ] T030 [US1] 实现 `create_or_switch_plan()`：单主路线、切换保留状态、`route_version` 锁定、`standpoint_tier` 校验（`TIER_NOT_AVAILABLE`）
- [ ] T031 [US1] 实现 `patch_plan()`：`manual_start_node_key`（写 `manual` 证据，不删除定位测结果）+ `settings` 合并
- [ ] T032 [US1] `backend/core/learning/quiz_engine.py` 实现定位测抽题：按路线各阶段抽样、题量 8–15、题库不足降级并在响应标 `placement_degraded`
- [ ] T033 [US1] `backend/core/learning/quiz_engine.py` 实现 `suggest_start_node()`：前沿集合按 stage seq 取最小，并列取 `leverage_value` 最大（确定性）
- [ ] T034 [US1] `backend/api/learning_routes.py` 实现 `POST /plan`、`PATCH /plan`、`GET /plan`（`PLAN_MISSING`）
- [ ] T035 [US1] 实现 `POST /quiz/sessions`（kind=placement）与 `GET /quiz/sessions/{id}`（不下发 answer/rubric）
- [ ] T036 [US1] 实现 `POST /quiz/sessions/{id}/answers` 的客观题判分路径（含 `counts_toward_mastery` 计算）
- [ ] T037 [US1] 实现 `POST /quiz/sessions/{id}/finish` 生成定位报告（`action_items` 含 `start_here`，`reason_text` 说明依赖/杠杆）
- [ ] T038 [P] [US1] `frontend/lib/services/learning_service.dart`：路线列表/切换/计划/定位测状态机（ChangeNotifier）
- [ ] T039 [P] [US1] `frontend/lib/widgets/route_map.dart`：阶段-模块-节点树，6 状态（空/加载/正常/部分失败/离线/未上线）
- [ ] T040 [P] [US1] `frontend/lib/screens/learning_home_screen.dart`：路线卡（目标/投入/首站推荐）+ 进入路线地图
- [ ] T041 [P] [US1] `frontend/lib/screens/placement_screen.dart`：定位测作答 + 起点建议卡 + "我要从更早处开始"
- [ ] T042 [US1] `frontend/lib/main.dart`：加命名路由（`/learning`、`/placement`、`/quiz`、`/report`、`/dashboard`、`/review`）并注入 `LearningService`
- [ ] T043 [P] [US1] `backend/tests/test_learning_api.py`：`POST /plan` → 切换路线保留状态；`manual_start` 不被丢弃；`TIER_NOT_AVAILABLE`
- [ ] T044 [P] [US1] `backend/tests/test_learning_placement.py`：题量 8–15、降级标记、起点建议确定性（固定快照）
- [ ] T045 [P] [US1] `frontend/test/learning_service_test.dart`：切换路线不清空已掌握节点；定位测状态机

**Gate**：US1 独立可用；SC-101 ≤5 分钟、SC-102 ≥80%（5 人内测）。

---

## Phase 4: US2 — 章节诊断与六类题型（P1）

**独立验收**：学完《提纲》1–3 条 → 触发诊断 → 8–20 题 → 报告含五级状态、错误类型、3 条可执行下一步。

- [ ] T046 [US2] `backend/content/quiz_bank/` 生产首批 120 题（含 12 溯源、10 迁移），按 `th*.json` 分文件，字段遵循 data-model.md §2.9
- [ ] T047 [US2] `backend/core/learning/quiz_engine.py` 实现诊断抽题：按 `route_module_nodes.weight` 分配题量（8–20）、按 `quiz_mix` 保型、难度 1–5 自适应
- [ ] T048 [US2] 实现判分：客观题精确匹配、迁移题 rubric 分项（术语/逻辑链/原文依据/实践指向）、低置信 → `pending`
- [ ] T049 [US2] 实现错误类型标签映射：6 类 + 每类一句话解释 + 推荐动作模板（`backend/core/learning/quiz_engine.py`）
- [ ] T050 [US2] 实现 7 天重复不计分：抽题时过滤近 7 天已作答题目；不足时降级并标 `counts_toward_mastery=false`
- [ ] T051 [US2] 实现断点续答与幂等：`UNIQUE(session_id, quiz_item_id)`，重复提交返回首次结果；`finish` 重复调用返回同一报告（`X-Report-Id`）；`POST /quiz/sessions/{id}/abandon` 为幂等 `204`
- [ ] T052 [US2] 实现 `POST /quiz/sessions`（kind=chapter_diagnostic/patch）与 `finish` 生成章节报告（`X-Report-Id`）
- [ ] T053 [US2] 实现 `GET /reports/{id}`、`POST /reports/{id}/read`、`POST /reports/{id}/actions/{key}/clicked`
- [ ] T054 [P] [US2] `frontend/lib/services/quiz_service.dart`：会话/作答/续答/提交
- [ ] T055 [P] [US2] `frontend/lib/screens/quiz_screen.dart`：六类题型渲染、即时判分反馈、待确认态
- [ ] T056 [P] [US2] `frontend/lib/screens/report_screen.dart`：掌握度分布、错误类型分布、薄弱点 Top3、可跳转 action_items
- [ ] T057 [P] [US2] `frontend/lib/widgets/error_type_tag.dart`：图形 + 文字（非纯色彩）+ 一句话解释
- [ ] T058 [US2] `frontend/lib/screens/reader_screen.dart`：加章节进度条 + "本章学完，开始诊断"入口（阅读完成后才可触发）
- [ ] T059 [P] [US2] `backend/tests/test_learning_quiz.py`：六类判分、标签一致性（20 题样本）、7 天重复、断点续答、题量边界
- [ ] T060 [P] [US2] `backend/tests/test_learning_report_latency.py`：SC-103，诊断 finish ≤10s（打桩 LLM）

**Gate**：SC-103、SC-110 达标；题库 `with_quiz` 覆盖 ≥90% 节点。

---

## Phase 5: US3 — 对话证据与回合小结卡（P2）

**独立验收**：会话结束 ≤8s 收到 `learning_digest`；低置信不入库；可撤销；LLM 关闭时降级但不阻塞。

- [ ] T061 [US3] `backend/core/learning/evidence_extractor.py`：会话后单次结构化抽取（复用 `core/llm/router.py`，输出 `{node_key, judgement, confidence, error_type, quote}[]`）
- [ ] T062 [US3] 抽取结果过滤：confidence < 0.6 丢弃并计数；术语误用（命中 `near_synonyms`）单独标记
- [ ] T063 [US3] 抽取结果过防偏离校验（`core/guard/orthodoxy.py`），失败则整条丢弃并记 `guard_rejected`
- [ ] T064 [US3] `backend/websocket/protocol.py` 追加 `learning_digest` / `evidence_updated` / `learning_degraded` 三个 S→C 类型与 `state_transition.node_keys`、`progression.mastery` 两个可选字段
- [ ] T065 [US3] `backend/websocket/server.py`：`action=end` 时触发 digest（8s 超时→先发 degraded 再发 ended），幂等返回同一 `report_id`
- [ ] T066 [US3] 实现 `POST /dialogue/{id}/digest`（REST 兜底）与 `POST /evidence/{id}/revoke`（含 5s 内重算）
- [ ] T067 [US3] 实现 `GET /state?node_keys=` 与 `GET /state/{node_key}/evidence`
- [ ] T068 [P] [US3] `frontend/lib/widgets/digest_card.dart`：小结卡（理解/待纠正/下一问三栏 + "我不认同"→revoke）
- [ ] T069 [US3] `frontend/lib/screens/chat_sheet.dart`：接入 digest/evidence_updated/degraded，degraded 时不展示 `to_fix`
- [ ] T070 [P] [US3] `backend/tests/test_learning_digest_ws.py`：正常/超时/幂等/LLM 关闭降级/guard 拦截 5 条路径
- [ ] T071 [P] [US3] `frontend/test/digest_card_test.dart`：三栏渲染、撤销交互、degraded 态
- [ ] T072 [US3] `backend/demo_e2e.py` 追加 `--scenario learning-digest`（5 轮对话 → 断言小结卡与证据置信度）

**Gate**：SC-105（纠正率 ≤10%）内测达标；`ENABLE_LEARNING_DIGEST=0` 时行为与现状一致。

---

## Phase 6: US4 — 推荐与欠账补丁（P2）

**独立验收**：欠账优先于新内容；推荐 1 主 + ≤2 备选并带理由；连续忽略 3 次降级为单概念。

- [ ] T073 [US4] `backend/core/learning/recommender.py`：候选生成（前沿集合）+ 排序（欠账 > 到期 > 杠杆 > 顺序 > 偏好）
- [ ] T074 [US4] 实现 `ignored_streak` 计数与降级策略（模块→节→单概念），并避免重复同一推荐
- [ ] T075 [US4] 实现 `content_status=planned` 的替代推荐与"尚未开放"提示（US4 场景 4）
- [ ] T076 [US4] 实现 `GET /recommendation` 与 `POST /recommendation/events`（shown/clicked/dismissed 埋点）
- [ ] T077 [US4] 实现 `GET /dashboard`、`GET /dashboard/ability/{dimension}`（含证据下钻）
- [ ] T078 [P] [US4] `frontend/lib/widgets/reason_chip.dart` + `learning_home_screen.dart` 的"今日推荐 + 欠账"区
- [ ] T079 [P] [US4] `frontend/lib/screens/review_screen.dart`：队列、"只做 5 项"降级、到期排序展示
- [ ] T080 [P] [US4] `backend/tests/test_learning_recommender.py`：30 组固定状态快照输出、忽略降级、未上线替代、欠账优先
- [ ] T081 [US4] 建 SQL 视图 `v_recommendation_ctr` / `v_mastery_delta` 供 SC-107/SC-111 统计

**Gate**：SC-107 内测达标；推荐响应 ≤300ms。

---

## Phase 7: US5 — 三档反馈与仪表盘（P3）

- [ ] T082 [US5] `backend/core/learning/feedback.py`：结构化模板（掌握分布/错误分布/薄弱点/动作项）→ LLM 润色 → 三重校验 → 不可用时返回模板版
- [ ] T083 [US5] 实现周报生成（自然周）：掌握增量、雷达变化、欠账、到期、路线偏离；`GET /reports/weekly/latest`
- [ ] T084 [US5] 实现推送开关与低频策略（7 天无学习最多 1 次提醒）
- [ ] T085 [P] [US5] `frontend/lib/screens/dashboard_screen.dart`：雷达 + 热力 + Top5 + 欠账，各维度可下钻
- [ ] T086 [P] [US5] `frontend/lib/widgets/radar_chart.dart`：自绘雷达（无新依赖）+ 屏幕阅读器替代文本 + 键盘可达
- [ ] T087 [P] [US5] `backend/tests/test_learning_feedback.py`：50 条报告抽检脚本、可执行动作覆盖 100%、校验失败不展示、模板降级
- [ ] T088 [US5] `frontend/lib/screens/report_screen.dart` 扩展到周报视图（含"路线偏离提醒"）

**Gate**：SC-106、SC-112 达标。

---

## Phase 8: US6 — 间隔重复与复习（P3）

- [ ] T089 [US6] `backend/core/learning/review_scheduler.py`：SM-2 简化（3 档评级、ease 2.5 起、间隔上限 60 天）；实现 `GET /review/today`（含 `capped` 标记）
- [ ] T090 [US6] 加两条硬约束：单日队列 ≤20（`settings.max_daily_review`）、章节诊断未过 → `forced_relearn=true`
- [ ] T091 [US6] 实现 `POST /review/{node_key}/answer`（评级 → 下次到期 → 生成 `review` 证据）
- [ ] T092 [P] [US6] `backend/tests/test_learning_review.py`：间隔推进、上限、强制回炉、批量跳过后的降级
- [ ] T093 [P] [US6] `frontend/test/review_screen_test.dart`：20 项上限与"只做 5 项"

**Gate**：SC-111（7 日完成率 ≥50%）内测达标。

---

## Phase 9: US7 — 内容与题目审核（P4）

- [ ] T094 [US7] 实现 `POST /admin/curriculum/validate`（`route_code` 或草稿 `yaml` 两种入参）
- [ ] T095 [US7] 实现 `POST /admin/quiz/items`（创建草稿 + 自动三类校验 + 置 `check_failed`/`pending_review`）
- [ ] T096 [US7] 实现 `POST /admin/quiz/items/{id}/review`（approved 才写 `published_at`/`reviewed_by`）与 `/recheck`（内容修订后重跑三类校验）
- [ ] T097 [US7] 在 `quiz_engine.py` 抽题处强制过滤 `review_status != approved`（防绕过）
- [ ] T098 [P] [US7] `backend/tests/test_learning_audit.py`：`check_failed` 不可发布、未审题不进 `item_plan`、版本追溯、`critical` 档位内容缺失拦截
- [ ] T099 [P] [US7] `backend/tests/test_learning_guard.py`：AI 反馈/解析被 guard 拦下时不展示（FR-135），且返回 `GUARD_REJECTED`

**Gate**：SC-109（立场/事实错误率 0）抽检 200 题通过。

---

## Phase 10: Polish & 横切关注

- [ ] T100 [P] `backend/core/learning/learning_algo_version.py`：算法版本常量 + 数据标注（NFR-112），旧数据展示"旧算法生成"
- [ ] T101 [P] 实现学习者数据导出 `GET /learning/export?format=json|csv`（evidence/attempts/reports，NFR-108 / `specs/001` NFR-010）
- [ ] T102 [P] 埋点补齐：`FeedbackRead` / 诊断触发与完成 / 推荐曝光，供 SC-101..SC-112 统计
- [ ] T103 [P] 降级矩阵测试：pg 掉线 / LLM 掉线 / guard 掉线 / 题库不足 / 内容未上线 五种场景下学习者路径不中断（NFR-107）
- [ ] T104 [P] 性能测试：`test_learning_perf.py`（推荐 ≤300ms、抽题 ≤1.5s、诊断 finish ≤10s）
- [ ] T105 更新 `README.md`（学情模块启动、开关、验收命令）与 `demo_e2e.py` 全链路脚本
- [ ] T106 [P] 可访问性抽查：雷达图替代文本、错误标签非纯色彩、字号 200% 不截断
- [ ] T107 全量回归：`pytest tests -q`（含 002 的 `test_route_flow / test_mastery / test_quiz_orthodoxy / test_recommendation / test_review / test_profile`）、`flutter analyze && flutter test`、`demo_e2e.py`、`import_curriculum.py --dry-run`
- [ ] T108 内测指标收集：SC-101..SC-112 的度量脚本与首轮报告（5–10 人）

---

## Dependencies（故事完成顺序）

```
Phase 1 Setup
   └─► Phase 2 Foundational（T007–T028，阻塞全部）
         ├─► US1（T029–T045）── 定位测 + 起点
         │      └─► US2（T046–T060）── 章节诊断
         │             ├─► US3（T061–T072）── 对话证据 + 小结卡
         │             │      └─► US4（T073–T081）── 推荐 + 仪表盘数据
         │             │             └─► US5（T082–T088）── 三档反馈 + 仪表盘 UI
         │             │                    └─► US6（T089–T093）── 复习
         │             └─► US7（T094–T099）── 审核（可提前到 US2 后并行，但发布门禁在 US2）
         └─► Phase 10 Polish（T100–T108）收尾
```

**可并行**：T046（题库生产，内容侧）可与 T047–T051 并行；US7 的 T094–T096 可与 US3 并行；前端 T038–T041 可与后端 T029–T033 并行（契约已冻结）。

---

## Parallel Execution Examples

**US1 并行组**（3 人）：
```text
A: T029–T037（后端 API）
B: T038–T041（前端页面，按 contracts/learning-api.md 打桩）
C: T043–T045（测试）
```

**US2 并行组**（4 人）：
```text
A: T046（题库 120 题，内容侧）
B: T047–T053（抽题/判分/报告 API）
C: T054–T057（前端答题与报告）
D: T059–T060（测试与压测）
```

**US3+US7 并行组**：
```text
A: T061–T067（抽取 + WS + REST）
B: T068–T072（前端小结卡 + demo）
C: T094–T099（审核链路）
```

---

## Implementation Strategy

**MVP 优先**：Phase 1 → Phase 2 → US1 → US2 即构成"能定位起点 + 能诊断掌握度"的最小可验证产品。此时尚未有对话证据与推荐，但已可对内测验证 SC-101/102/103/110。

**增量交付**：
1. 切片 1（MVP）：T001–T060 — 路线 + 定位 + 诊断
2. 切片 2：T061–T081 — 对话证据 + 推荐 + 仪表盘数据
3. 切片 3：T082–T099 — 反馈/复习/审核
4. 切片 4：T100–T108 — 收尾与指标

**每切片必过的门禁**：
```bash
cd backend && python -m pytest tests -q
cd backend && python demo_e2e.py
cd frontend && flutter analyze && flutter test
python backend/scripts/import_curriculum.py --dry-run
```

**内容与开发的关系**：T046 题库生产是唯一可提前启动且决定进度的外部依赖；建议在 Phase 2 期间即启动，避免成为切片 1 的瓶颈。
