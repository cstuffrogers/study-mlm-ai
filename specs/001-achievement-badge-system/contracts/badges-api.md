# 接口契约：勋章系统 REST API

基础路径：`/api/badges`。响应均为 JSON（`application/json`）。用户标识沿用项目既有体系（固定 demo_user），无需额外鉴权变更。

## 1. GET /api/badges/mine —— 我的勋章总览

「我的勋章」页面数据源（FR-05）。返回全部启用勋章 + 当前用户的授予状态 + 进度。

**响应**

```json
{
  "metrics": {
    "mastered_count": 3,
    "journey_count": 8,
    "milestones_achieved": 1,
    "quiz_correct_total": 12,
    "quiz_attempt_total": 20,
    "routes_completed": 0,
    "streak_days": 5,
    "dialogues_completed": 2
  },
  "badges": [
    {
      "badge_id": "mastery_10",
      "name": "知识学人",
      "description": "掌握 10 个知识点",
      "category": "知识掌握",
      "condition_text": "掌握 10 个知识点",
      "icon_key": "mastery",
      "earned": false,
      "awarded_at": null,
      "source_event": null,
      "read": false,
      "progress": {"current": 3, "target": 10, "display": "3/10"}
    },
    {
      "badge_id": "mastery_1",
      "name": "初窥门径",
      "category": "知识掌握",
      "condition_text": "掌握 1 个知识点",
      "icon_key": "mastery",
      "earned": true,
      "awarded_at": "2026-11-22T10:00:00Z",
      "source_event": "mastery_update",
      "read": true,
      "progress": {"current": 1, "target": 1, "display": "1/1"}
    }
  ],
  "summary": {"total": 29, "earned": 2, "unearned": 27}
}
```

**约定**

- `progress.current` 为该勋章进度指标当前值；`completion` 型（route_all）返回 `{"current": N, "target": N, "display": "N/N"}`（N 为已开放路线总数，0 时显示「暂不可达」）。
- 比率型复合条件勋章（如 `quiz_acc_50`：作答≥50 且正确率≥90%）的进度按主指标展示并附正确率：`{"current": 已作答数, "target": 50, "accuracy": 0.8, "display": "作答 30/50，正确率 80%"}`（规则见 data-model.md「进度展示规则」）。
- `enabled=false` 的勋章不参与新授予；已授予的停用勋章仍在响应中展示并标记 `disabled: true`。

## 2. GET /api/badges/unseen —— 未查看的新勋章

首页提醒（FR-06）与动画触发兜底（D5）的数据源。

**响应**

```json
{
  "awards": [
    {
      "badge_id": "streak_7",
      "name": "七日坚持",
      "description": "连续学习 7 天",
      "category": "连续学习",
      "condition_text": "连续学习 7 天",
      "icon_key": "streak",
      "awarded_at": "2026-11-22T10:00:00Z",
      "source_event": "daily_settle"
    }
  ],
  "count": 1
}
```

仅返回 `read_flag=false` 的授予记录，按授予时间倒序。

## 3. POST /api/badges/read —— 标记已查看

**请求**

```json
{ "award_ids": ["<award_id_1>", "<award_id_2>"] }
```

**响应**

```json
{ "updated": 2 }
```

效果：对应记录 `read_flag=true`，此后不再出现在 `unseen` 与首页提醒。动画播放完成时客户端调用；中途退出未播放的，用户可在勋章详情中手动标记或再次触发。

## 4. 事件响应扩展：badges_awarded

答题提交、掌握度更新、路线完成、对话完成等事件接口的响应体中追加 `badges_awarded` 字段，内容同 `unseen` 中单条结构：

```json
{
  "...原有响应字段...",
  "badges_awarded": [
    {
      "badge_id": "quiz_10",
      "name": "初次答对",
      "description": "累计答对 10 题",
      "category": "答题",
      "condition_text": "累计答对 10 题",
      "icon_key": "quiz",
      "awarded_at": "2026-11-22T10:00:00Z",
      "source_event": "quiz_submit"
    }
  ]
}
```

- 无新勋章时该字段为 `[]`（始终存在，便于前端统一处理）。
- 前端收到非空列表即触发获得动画（US2）。

## 错误处理

- 统一沿用项目现有错误约定（业务错误返回结构化错误信息）。
- `POST /api/badges/read` 中不存在的 award_id 静默忽略，返回实际更新数。
