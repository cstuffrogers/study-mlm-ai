# Quickstart: 三路线学习与学情闭环 — 端到端验证

> 目标：不读实现细节即可验证 P0 单章闭环（提纲）跑通。实现细节见 tasks.md。

## 前置
- 后端可启动（轻量模式：`AUTO_CREATE_TABLES=0 python -m uvicorn app:app --port 8190`）
- 已入库：提纲 11 条内容 + 知识点树 + 题库（P0 CLI 脚本导入）
- 前端 Flutter 可 `flutter run -d web`

## 验证场景（6 步闭环）

1. **选路线**
   - 打开前端 → 路线选择页可见 A/B/C 三卡 + "共享地基"说明。
   - 选"纯理论研究" → 调 `POST /api/routes/route_A/select` 成功，返回 `recomputed_start`。

2. **摸底测**
   - 完成约 10 题 → `POST /api/routes/route_A/diagnostic` 返回 `recommended_start / order / skippable / to_reinforce`。
   - 期望：推荐起点非空，skippable/to_reinforce 合理。

3. **学一章（对话+即时小结）**
   - 进入推荐章节 → 复用阅读器，选中"市民社会" → 五模式对话。
   - 期望：每轮问答后前端出现"即时小结卡"（要点 + 1 检验问题）；WS 收到 `struggle_detected`（如反复追问）。

4. **章节测试 + 掌握度**
   - `POST /api/quiz/section/{sec}/start` 得题组（含溯源）；作答 `POST /api/quiz/submit`。
   - 期望：返回知识点五级掌握度 + 错因归类 + 错题正统解析与溯源；`gating.next_section_unlocked` 按 0.8 门槛正确。

5. **看档案与反馈**
   - `GET /api/mastery/profile?route_id=route_A` → 五维雷达 + 薄弱点 TOP-N（含 blocking_sections）。
   - `POST /api/mastery/summary` → AI 总结含"已掌握/待巩固/下一步"且带 source_tags。

6. **按推荐进入下一章**
   - `GET /api/recommendation/today` / `POST /api/recommendation/next` → 返回带一句话理由的推荐；点击"一键进入"跳转目标章节。

## 关键断言（正统性红线）
- 任一 `QuizItem` 无 `source_chunk_id` 或 `authority_status=pending` 时，`trial_only=true` 且不计正式掌握度（契约级约束）。
- 错误诊断题"故意错误项" `exempt_marked=true`，不被防偏离拦截。
- 对话中判为"偏离"的内容进入批判对象/双轨制引导，不记为普通错题。

## 通过标准
- 6 步全部可完成且无阻断；第 4 步掌握度与门控、第 5 步薄弱点排序、第 6 步推荐理由均符合预期。
