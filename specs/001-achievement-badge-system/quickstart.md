# Quickstart：勋章系统验证指南

本指南用于在实现完成后端到端验证学习勋章系统。只描述验证步骤与预期结果，不含实现代码。

## 前置条件

- 后端可运行：`cd backend && python -m uvicorn app:app --port 8190`（学习域表随 AUTO_CREATE_TABLES 自动创建，含新增的 `user_badges` 表）。
- 前端可运行：`scripts/serve_frontend.py 8080`（或 `flutter run`）。
- 测试基线命令：后端 `backend/.venv/Scripts/python.exe -m pytest tests/ -q`；前端 `flutter test`、`flutter analyze lib test`。

## 验证场景

### 场景 1：达成检测与授予（US1 / SC-01 / SC-02）

1. 启动后端，确认 `user_badges` 表已建。
2. 通过既有答题流程累计答对 10 题（或直接以测试夹具写入 10 条正确作答记录）。
3. 预期：第 10 题提交响应的 `badges_awarded` 中包含 `quiz_10`（初次答对）。
4. 再次提交任意题目：`badges_awarded` 为 `[]`，`user_badges` 中 `quiz_10` 仍仅一条记录（幂等，SC-02）。

### 场景 2：我的勋章页面数据（US3 / SC-03 / SC-04）

1. `curl http://localhost:8190/api/badges/mine`。
2. 预期：`badges` 含目录全部启用勋章（初始 29 枚）；`summary.total=29`；已达成勋章 `earned=true` 且带 `awarded_at`；未达成勋章 `earned=false` 且 `progress.display` 与 `metrics` 一致（如 `mastered_count=3` 时 `mastery_10` 显示 `3/10`，SC-04）。

### 场景 3：未查看提醒与已读（US4 / SC-06）

1. 达成一枚新勋章后 `curl http://localhost:8190/api/badges/unseen`：返回该勋章。
2. `curl -X POST http://localhost:8190/api/badges/read -H "Content-Type: application/json" -d '{"award_ids":["<id>"]}'`。
3. 再次请求 `unseen`：返回空；首页不再显示提醒（SC-06）。

### 场景 4：获得动画（US2 / SC-05）

1. 在客户端触发一次新勋章达成（完成一次可达成的学习事件）。
2. 预期：立即播放礼物开箱式动画，动画结束展示勋章信息并自动标记已读；中途退出后重新进入，首页提醒仍可再次触发，且授予记录不重复。

### 场景 5：目录可配置（FR-07 / SC-07）

1. 在 `backend/content/badges.py` 中新增一枚测试勋章（如 `mastery_2`），不做任何事件处理代码改动。
2. 重启后端，`/api/badges/mine` 中出现该勋章；掌握 2 个知识点后触发授予。
3. 预期：全程无需改动学习事件代码（SC-07）。

### 场景 6：指标波动不回收（SC-08）

1. 达成 `streak_7` 后，将连续学习天数重置为 0（或使用测试夹具模拟中断）。
2. 预期：`/api/badges/mine` 中 `streak_7` 仍为 `earned=true`，授予记录保留。

## 自动化验证

- 后端：`badge_service` 评估引擎单元测试（指标采集、条件判定、幂等授予）+ 路由测试（mine / unseen / read）纳入 `backend/tests/`。
- 前端：勋章页组件与动画触发逻辑纳入 `frontend/test/`，`flutter test` 全量通过。
- 全量基线：后端 `784 passed + 2 xfailed` 基线不回退；前端 `413` 项测试基线不回退（实现后以实际新增数为新基线）。
