# Tasks：学习勋章系统（achievement-badge-system）

> 基于 spec.md（用户故事 US1–US5）、plan.md、research.md、data-model.md、contracts/badges-api.md、quickstart.md。

## Phase 1: Setup（项目初始化）

- [ ] T001 [P] 定义勋章目录数据模块 `backend/content/badges.py`：BadgeDef 数据结构（badge_id/名称/描述/分类/条件类型/阈值/进度指标/图标 key/排序/启用）与初始 29 枚勋章（口径见 spec.md「勋章目录（初始设计）」），提供目录加载函数
- [ ] T002 [P] 在 `backend/model/models_learning.py` 新增 BadgeAward ORM 模型（表 `user_badges`：user_id、badge_id、awarded_at、source_event、read_flag，(user_id, badge_id) 唯一约束），确认 AUTO_CREATE_TABLES 可自动建表
- [ ] T003 [P] 创建勋章 API 路由骨架 `backend/api/badge_routes.py` 并在应用入口注册（先挂空路由占位，接口实现见 T012/T013）

## Phase 2: Foundational（基础前置）

- [ ] T004 [US1] 实现评估引擎 `backend/services/badge_service.py` 的 `collect_metrics(user_id)`：汇总 7 项指标（mastered_count / journey_count / milestones_achieved / quiz_correct_total / quiz_attempt_total / routes_completed / streak_days / dialogues_completed），分别复用 mastery_service、quiz_service、motivation_service、route_service、dialogue_service 的既有数据
- [ ] T005 [US1] 实现 `badge_service.py` 的 `evaluate(user_id, source_event)`：对照目录中该用户未获得的启用勋章逐条判定，命中即插入授予记录（冲突忽略保证幂等），返回新授予列表（结构见 contracts/badges-api.md 第 4 节）
- [ ] T006 [US1] 实现 `badge_service.py` 的目录序列化与进度计算：生成条件文案（condition_text）、逐勋章进度（current/target/display），供 mine/unseen 接口使用

## Phase 3: US1 —— 学习事件触发达成检测与授予（P1）

**目标**：学习事件后自动检测并授予勋章，幂等，事件响应携带 badges_awarded。
**独立测试标准**：完成 10 次正确答题后响应含 `quiz_10`；重复事件不产生重复授予记录。

- [ ] T007 [US1] 在 `backend/services/quiz_service.py` 答题提交完成处调用 evaluate，并在该事件响应中追加 `badges_awarded` 字段（无新勋章时为空列表）
- [ ] T008 [US1] 在 `backend/services/mastery_service.py` 掌握度更新（upsert_mastery、sync_dialogue_mastery 等写入口）处调用 evaluate 并追加 `badges_awarded`
- [ ] T009 [US1] 在 `backend/services/route_service.py` 路线完成判定处调用 evaluate 并追加 `badges_awarded`
- [ ] T010 [US1] 在 `backend/services/dialogue_service.py` 对话完成处调用 evaluate 并追加 `badges_awarded`
- [ ] T011 [US1] 在每日动机结算入口（motivation_state 的日切/结算调用路径）调用 evaluate，覆盖 streak_days 与 milestones_achieved 类勋章
- [ ] T012 [US1] 在 `backend/api/badge_routes.py` 实现 `GET /api/badges/mine`（返回全部启用勋章 + 授予状态 + 进度 + 指标快照，结构见 contracts/badges-api.md 第 1 节）
- [ ] T013 [US1] 在 `backend/api/badge_routes.py` 实现 `GET /api/badges/unseen` 与 `POST /api/badges/read`（结构见 contracts/badges-api.md 第 2、3 节）
- [ ] T014 [US1] 后端测试：`backend/tests/test_badge_service.py`（指标采集、条件判定、幂等授予、指标波动不回收）与 `backend/tests/test_badge_routes.py`（mine/unseen/read），运行 `backend/.venv/Scripts/python.exe -m pytest tests/ -q` 通过

## Phase 4: US2 —— 新勋章获得动画（P1）

**目标**：首次获得勋章时播放礼物开箱式动画，中途退出可重触发，不重复授予。
**独立测试标准**：收到 badges_awarded 后弹出动画；动画完成自动标记已读；中途退出后再次触发仍正常且仅一条授予记录。

- [ ] T015 [US2] 实现礼物开箱动画组件 `frontend/lib/widgets/badge_award_dialog.dart`：礼盒开盖动画（CustomPainter + AnimationController，不新增依赖）、粒子光效、勋章名称/描述/条件展示、动画结束回调（自动调 read 接口标记已读）
- [ ] T016 [US2] 在前端事件调用处（答题提交、掌握更新、路线完成、对话完成等响应处理）接入动画触发：`badges_awarded` 非空即弹出 dialog；处理中途退出与重复弹窗防抖
- [ ] T017 [US2] 前端测试 `frontend/test/badge_award_dialog_test.dart`：动画触发条件、完成回调、中途退出状态，`flutter test` 通过

## Phase 5: US3 —— 功能中心「我的勋章」页面（P1）

**目标**：功能中心新增「我的勋章」入口，展示已获得（含时间）与未获得（含条件与进度）全部勋章。
**独立测试标准**：新用户见全部勋章未获得态；达成后进入页面见已获得分组与获得时间；进度与真实指标一致。

- [ ] T018 [US3] 实现勋章 API 封装 `frontend/lib/services/badge_api.dart`（mine / unseen / read 三个接口，含离线本地数据合并读取）
- [ ] T019 [US3] 实现「我的勋章」页面 `frontend/lib/screens/badge_screen.dart`：已获得/未获得分组、勋章图标（icon_key 自绘）、名称、描述、获取条件、获得时间、进度展示、分类筛选、点击进详情
- [ ] T020 [US3] 在 `frontend/lib/screens/home_screen.dart` 功能中心入口区新增「我的勋章」入口并接通到 BadgeScreen 导航
- [ ] T021 [US3] 前端测试 `frontend/test/badge_screen_test.dart`：分组展示、进度渲染、筛选、空态，`flutter test` 通过

## Phase 6: US4 —— 首页新勋章提醒（P2）

**目标**：存在未查看新勋章时首页显示提醒入口，查看后消失。
**独立测试标准**：达成新勋章后回首页见提醒；播放动画或标记已读后提醒消失；无新勋章不显示。

- [ ] T022 [US4] 在 `frontend/lib/screens/home_screen.dart` 实现新勋章提醒入口：数据源为 unseen（启动与学习事件后刷新），点击触发获得动画或跳「我的勋章」，查看后消失
- [ ] T023 [US4] 实现离线本地评估 `frontend/lib/offline/local_badges.dart`：复用本地指标（local_mastery/local_insight 同模式）对照目录快照判定，授予记录存本地库；联网后经 sync_service 合并、服务端权威、已授予优先（若澄清确认仅在线方案，本任务改为「离线仅展示已同步记录」）

## Phase 7: US5 —— 勋章分享（收藏卡）（P2）

**目标**：「我的勋章」页面一键生成勋章收藏卡图片，分享到微信、朋友圈、QQ 等系统分享渠道。
**独立测试标准**：点击分享生成含全部已获得勋章的收藏卡；原生调起系统分享面板；Web 不支持 Web Share API 时复制文案到剪贴板；分享不改变授予/查看状态。

- [ ] T027 [US5] `frontend/pubspec.yaml` 新增 `share_plus` 依赖；实现分享服务 `frontend/lib/services/badge_share.dart`：本地渲染收藏卡图片（RepaintBoundary 转 PNG）、原生端写临时文件调系统分享面板（微信/朋友圈/QQ 等）、Web 端优先 Web Share API（navigator.share 携带图片）、不支持时回退剪贴板复制文案
- [ ] T028 [US5] 在 `frontend/lib/screens/badge_screen.dart` 标题栏新增「分享」按钮：基于已获得勋章生成收藏卡并调起分享；分享流程不改变任何授予记录与查看状态
- [ ] T029 [US5] 前端测试 `frontend/test/badge_share_test.dart`：收藏卡内容与已获得勋章一致（数量/名称）、Web 剪贴板回退路径、分享不改变状态，`flutter test` 通过

## Phase 8: Polish（收尾与横切）

- [ ] T024 按 `specs/001-achievement-badge-system/quickstart.md` 执行 6 个验证场景并修复问题
- [ ] T025 全量回归：后端 `backend/.venv/Scripts/python.exe -m pytest tests/ -q`、前端 `flutter test` 与 `flutter analyze lib test` 全部通过
- [ ] T026 更新 README（勋章功能说明）与项目记忆（勋章系统位置与口径）

## Dependencies（依赖关系）

```
T001, T002, T003 可并行（Setup）
T004, T005 ← T001, T002
T006 ← T001
T007–T011 ← T005
T012, T013 ← T005, T006
T015 独立（可与 T007–T011 并行）
T016 ← T015, T007（响应字段约定）
T018 ← T012, T013
T019 ← T018；T020 ← T019（或并行，先约定 BadgeScreen 类名）
T022 ← T013, T015, T019
T023 ← T005, T018
T027 ← T019（分享服务与页面）；T028 ← T027；T029 ← T027, T028
T024–T026 ← 全部完成
```

## Parallel Execution（并行示例）

- Setup 阶段：T001 + T002 + T003 三人并行。
- 后端事件集成：T007–T011 在 T005 完成后可并行推进（不同文件、同一 evaluate 接口）。
- 接口与动画：T012 + T013 并行；T015 动画开发与 T007–T011 后端集成并行。
- 前端页面：T018 完成后，T019 + T020 可并行；T017 与 T021 可分别跟随各自实现并行编写。

## Implementation Strategy（实施策略）

- **MVP 范围**：Phase 1–3（目录、表、评估引擎、事件挂接、mine/unseen/read 接口）+ T015/T016 最小动画触发，即可满足「达成检测 + 授予 + 动画触发」的核心闭环，此时前端可先用临时页面验证动画。
- **增量交付**：随后按 US3（勋章页）→ US4（首页提醒）→ 离线（T023）逐步交付，每阶段独立可测。
- **风险**：T023 离线方案取决于 Open Questions 的澄清结论，实施前需先确认；若选仅在线方案，T023 降级为本地展示缓存，其余任务不受影响。
