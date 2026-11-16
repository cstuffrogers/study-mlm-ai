# Tasks: 三路线学习与学情闭环

**Feature**: `002-learning-routes-mastery` | **Plan**: [plan.md](./plan.md) | **Spec**: [spec.md](./spec.md)
**Created**: 2026-11-04

> 格式：`- [ ] Txxx [P] [USx] 描述 — 文件路径`。`[P]`=可并行（不同文件、无未完成依赖）。路径相对 repo 根。
> 交付策略：**MVP = P0 单章（提纲）闭环**，即 Setup + Foundational + US1 + US2 + US3 的最小集；US4/US5 为 P2 增量。

---

## Phase 1: Setup（项目初始化 / 配置）

- [ ] T001 在 `backend/core/config.py` 增加学情闭环配置项（unlock_threshold=0.8、quiz_size_min=8、quiz_size_max=12、mastery 权重、五级阈值），均可覆盖 — backend/core/config.py
- [ ] T002 [P] 前端新增 API 基址与鉴权复用配置 — frontend/lib/services/api_config.dart
- [ ] T003 [P] 建立 `backend/content/quiz_bank/` 目录与题库 JSON schema 说明（含 source_chunk_id/authority_status/exempt_marked 字段） — backend/content/quiz_bank/README.md

## Phase 2: Foundational（阻塞所有故事的先决条件）

- [ ] T004 扩展 ORM：新增 learning_routes / route_sections / knowledge_nodes / node_prerequisites / mastery_records / quiz_items / quiz_attempts / section_tests / diagnostic_tests / learning_progress / struggle_signals / learning_profiles / recommendations / feedback_reports 表（字段见 data-model.md） — backend/model/models.py
- [ ] T005 [P] 编写建表迁移/初始化脚本（AUTO_CREATE_TABLES 路径 + 索引 + 唯一约束） — backend/core/db.py
- [ ] T006 [P] 定义 `backend/content/routes.py`：三路线（A/B/C）+ 章节映射（公共地基=学习顺序2.md 阶段0–2；支线占位）+ 门槛参数 — backend/content/routes.py
- [ ] T007 [P] 定义 `backend/content/knowledge_graph.py`：提纲知识点树（约12概念）+ 依赖边 DAG（含环检测）；提供 `KnowledgeGraphService` 抽象（Neo4j / in-memory 双实现） — backend/content/knowledge_graph.py
- [ ] T008 [P] 迁移并扩写提纲题库：8–12 题、四类题型、每题标 source_chunk_id + authority_status + exempt_marked — backend/content/quiz_bank/outline_chapter.json
- [ ] T009 [P] 前端新增模型类 Route/RouteSection/KnowledgeNode/QuizItem/MasteryRecord/Profile/Recommendation（对齐 data-model.md） — frontend/lib/models/learning_models.dart
- [ ] T010 定义 `KnowledgeGraphService` 接口与 in-memory 实现（供 mastery/recommendation 复用），并接入现有 retriever 降级范式 — backend/services/knowledge_graph_service.py

## Phase 3: US1 — 选择路线并从正确起点开始 (P1) 🎯 MVP

**Goal**: 用户选路线、做摸底测、拿到推荐起点与顺序。**独立测试**：新用户选 B 路线 + 摸底测 → 得到"建议从《怎么办？》第1章起步，可跳过《宣言》基础节"。

- [ ] T011 [US1] 实现 `route_routes.py`：GET /api/routes、GET /routes/{id}/sections、POST /routes/{id}/select（含切换保留学情/重算起点）、含 gating 查询 — backend/api/route_routes.py
- [ ] T012 [US1] 实现 `diagnostic` 服务：摸底测组题 + 起点/可跳过/需补强计算（依赖 T007/T008） — backend/services/route_service.py
- [ ] T013 [US1] 实现 POST /api/routes/{id}/diagnostic 路由与请求/响应模型 — backend/api/route_routes.py
- [ ] T014 [P] [US1] 前端路线选择页（三卡+共享地基说明+展开章节目录） — frontend/lib/screens/route_picker.dart
- [ ] T015 [P] [US1] 前端摸底测页（进度条+单题卡+跳过入口+结果页推荐起点） — frontend/lib/screens/diagnostic_test.dart
- [ ] T016 [P] [US1] 前端路线导航/章节列表页（阶段分组+🔒/▶/✓徽章+今日推荐横幅） — frontend/lib/screens/route_map.dart
- [ ] T017 [P] [US1] 前端 routes API 服务封装 — frontend/lib/services/routes_service.dart
- [ ] T018 [US1] 后端测试：路线选择/切换保留学情/摸底测起点计算/gating — backend/tests/test_route_flow.py

## Phase 4: US2 — 逐章学习闭环（精读+对话+即时小结）(P1) 🎯 MVP

**Goal**: 章内复用精读与五模式会话，每轮出即时小结，章末出小结+待巩固清单，隐式学情上报。**独立测试**：在《提纲》第6条用【追问】3轮 → 每轮要点小结 + 章末"市民社会概念层次混淆"待巩固清单。

- [ ] T019 [US2] 在 `dialogue_service.py` 增加"即时小结 + 检验问题"生成（每轮问答后，复用 LLM 但独立轻量 prompt；不阻断主回答） — backend/services/dialogue_service.py
- [ ] T020 [US2] 在 `dialogue_service.py` 埋点上报 StruggleSignal（反复追问/答错被驳回/关联失败），并推送 WS `struggle_detected` — backend/services/dialogue_service.py
- [ ] T021 [US2] 章节结束时聚合本章要点 + 待巩固清单（结合 struggling signals 与已判掌握度） — backend/services/dialogue_service.py
- [ ] T022 [US2] 明确防偏离与学情协作：被判偏离内容标注为"需批判对象引导"，不计普通人错题 — backend/services/dialogue_service.py
- [ ] T023 [P] [US2] 前端在章节学习页加"即时小结卡"（折叠不打断，复用 reader/chat 形态） — frontend/lib/widgets/instant_summary_card.dart
- [ ] T024 [P] [US2] 前端章末"章节小结+待巩固清单"卡（附"去测试"按钮） — frontend/lib/widgets/chapter_summary_sheet.dart
- [ ] T025 [US2] 前端 chat_service 接入 progression/struggle WS 事件与小结渲染 — frontend/lib/services/chat_service.dart
- [ ] T026 [US2] 后端测试：即时小结产出/信号上报/偏离不误判为普通错题 — backend/tests/test_dialogue_closure.py

## Phase 5: US3 — 章节测试与掌握度诊断 (P1) 🎯 MVP 核心

**Goal**: 四类题型测试、五级掌握度、错因归类、正统解析+溯源、申诉。**独立测试**：完成提纲章测，答错"市民社会"辨析 → 标记"初学"+错因"概念层次混淆"+溯源解析。

- [ ] T027 [US3] 实现 `quiz_service.py`：自适应出题（按知识点规模 8–12）、四类题型、下发改题不含答案 — backend/services/quiz_service.py
- [ ] T028 [US3] 实现判分逻辑 + 错因归类（real_unknown/term_misuse/concept_layer_confusion/stance_deviation） + 溯源回填 — backend/services/quiz_service.py
- [ ] T028B [US3] 实现主观题/费曼三维度批改（术语正统性/逻辑自洽/概念层次），给修改建议不代写，复用既有 TripleCheck 立场校验 — backend/services/quiz_service.py
- [ ] T029 [US3] 实现 `mastery_service.py`：D1 加权公式计算 score→五级 level，写 MasteryRecord（融合 T020 信号） — backend/services/mastery_service.py
- [ ] T030 [US3] 正统性门禁：入题库/判分前校验 source_chunk_id + TripleCheck；未审题 trial_only 不计正式掌握度；错误诊断题豁免标记 — backend/services/quiz_service.py
- [ ] T031 [US3] 实现 `quiz_routes.py`：POST /section/{id}/start、/submit、/appeal（申诉入既有审核队列） — backend/api/quiz_routes.py
- [ ] T032 [P] [US3] 前端章节测试页（四类题型混合+主观题区+判分结果+错题解析+溯源卡+申诉入口） — frontend/lib/screens/chapter_test.dart
- [ ] T033 [P] [US3] 前端掌握度徽章组件（五级统一色阶，复用 UX Brief 色板） — frontend/lib/widgets/mastery_badge.dart
- [ ] T034 [P] [US3] 前端 quiz API 服务封装 — frontend/lib/services/quiz_service_api.dart
- [ ] T035 [US3] 后端测试：出题不含答案/判分正确/掌握度五级映射/未审题不计分/防偏离与错误诊断豁免 — backend/tests/test_quiz_orthodoxy.py
- [ ] T036 [US3] 后端测试：掌握度算法分项与阈值（含对话信号平滑降权）+ 主观题三维批改输出（FR-014） — backend/tests/test_mastery.py

## Phase 6: US4 — 学情档案与薄弱点反馈 (P2)

**Goal**: 汇总学情→薄弱点 TOP-N（含阻塞章节数）+五维雷达+AI 总结反馈。**独立测试**：学习两周后打开档案见雷达+TOP5+自动总结。

- [ ] T037 [US4] 实现 `profile_service.py`：聚合 mastery/signals→ability_radar、weak_points 排序 key=(1-score)×依赖出度×考频、blocking_sections 计算 — backend/services/profile_service.py
- [ ] T038 [US4] 实现 AI 学习总结生成（已掌握/待巩固/下一步 + source_tags 标注数据来源） — backend/services/profile_service.py
- [ ] T039 [US4] 实现 `mastery_routes.py`：GET /profile、GET /node/{id}、POST /summary，含隐私鉴权（本人/专家/管理员） — backend/api/mastery_routes.py
- [ ] T040 [P] [US4] 前端学情档案/仪表盘页（能力雷达+热力图+薄弱点TOP-N卡+总结卡+时间筛选+空态引导） — frontend/lib/screens/profile_dashboard.dart
- [ ] T041 [P] [US4] 前端雷达图组件（五维） — frontend/lib/widgets/radar_chart.dart
- [ ] T042 [P] [US4] 前端薄弱点卡组件（含"阻塞后续N章"标签+回补快捷） — frontend/lib/widgets/weak_point_card.dart
- [ ] T043 [US4] 前端 mastery API 服务封装 — frontend/lib/services/mastery_service_api.dart
- [ ] T044 [US4] 后端测试：薄弱点排序/阻塞章节数/隐私403/总结来源标注 — backend/tests/test_profile.py

## Phase 7: US5 — 智能路径推荐与解锁门控 (P2)

**Goal**: 门控解锁 + 今日推荐 + 回补推荐 + 一键进入，附一句话理由。**独立测试**：某知识点连续3次错 → 推荐"先完成《矛盾论》第3节专项"并锁定下一章入口。

- [ ] T045 [US5] 实现 `recommendation_service.py`（D4 规则）：门控判定、next/today/weak-top 推荐 + 一句话理由模板 — backend/services/recommendation_service.py
- [ ] T046 [US5] 实现 `recommendation_routes.py`：GET /today、POST /next、GET /weak-top — backend/api/recommendation_routes.py
- [ ] T047 [US5] 门控与解锁联动 LearningProgress（达 0.8 解锁下一章；未达返回 blocking_nodes） — backend/services/recommendation_service.py
- [ ] T048 [P] [US5] 前端推荐卡组件（一句话理由+一键进入+先补强前置，跨页复用：首页/导航/档案） — frontend/lib/widgets/recommendation_card.dart
- [ ] T049 [P] [US5] 前端 recommendation API 服务封装 — frontend/lib/services/recommendation_service_api.dart
- [ ] T050 [US5] 后端测试：门控0.8边界/推荐理由生成/回补优先 — backend/tests/test_recommendation.py

## Phase 8: Polish & 跨切面

- [ ] T051 [P] 跨设备同步与断点续学：进度/作答增量同步、离线暂存后批量合并（NFR-004） — backend/services/sync_service.py
- [ ] T052 [P] 前端跨设备续学提示 + 加载骨架屏 + 网络异常离线暂存提示 — frontend/lib/widgets/sync_notice.dart
- [ ] T053 [P] 端到端 demo：按 quickstart.md 6 步跑通脚本 — backend/demo_routes_flow.py
- [ ] T054 [P] 回归：既有 001 全量测试 + 新增测试全绿（`pytest -q` / `flutter test`） — backend/tests/ , frontend/test/
- [ ] T055 更新 README 状态表与本功能 spec/plan/tasks 索引 — README.md

---

## 依赖图（故事完成顺序）

```
Setup(T001-T003)
  └─ Foundational(T004-T010)
       ├─ US1(T011-T018) ──┐
       ├─ US2(T019-T026) ──┤ (P1 可并行开发，均依赖 Foundational)
       └─ US3(T027-T036) ──┘ ← MVP 关键路径（T029掌握度依赖T007知识点树；T030依赖既有TripleCheck）
                 │
                 ├─ US4(T037-T044) 依赖 US3 产出的 mastery/signals 数据
                 └─ US5(T045-T050) 依赖 US4 的 weak_points 排序 & US3 的 mastery
                           │
                        Polish(T051-T055) 收尾
```

**关键路径**：T004→T007→T029→T037→T045（数据模型→知识点树→掌握度→档案→推荐）。

**MVP 最小集**：T001–T036（Setup+Foundational+US1/US2/US3）在提纲单章上形成"选路线→摸底→学一章→测一章"闭环，即可交付验证。

## 并行执行示例

- **Foundational 并行组**：T005/T006/T007/T008/T009 可同时进行（不同文件）。
- **US1 前端并行**：T014/T015/T016/T017 可并行（页面与服务互不依赖），后端 T011-T013 并行。
- **US3 前端并行**：T032/T033/T034 并行；后端 T027-T031 顺序（同文件依赖）。
- **US4/US5 组件并行**：T040-T042 与 T048 均可在各自后端就绪后并行。

## 实现策略

1. 先打地基（T004-T010），尤其知识点树(T007)与题库(T008)是内容中枢。
2. 按 P1 顺序或并行推进 US1/US2/US3，尽快形成单章闭环 MVP（T001-T036）。
3. 用 quickstart.md 6 步验收 MVP，再补 US4/US5（P2）与 Polish。
4. 全程守正统性红线：T030/T022/T035 为验收前置门槛。

## Task 完整性自检
- 每个用户故事均含独立测试任务（T018/T026/T035/T044/T050）✅
- 每故事含前端+后端+服务+测试 ✅
- Foundational 无未被后续消费的孤立任务 ✅
- 正统性红线任务（T022/T030/T035）显式存在 ✅
