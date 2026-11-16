# API Contract: 路线与导航 (routes-api)

Base: `/api/routes`　鉴权：Bearer token（复用既有 auth）。响应统一 JSON。

## GET /api/routes
列出全部路线（含共享地基标记）。
```json
{
  "routes": [
    {"id": "route_A", "name": "纯理论研究", "goal": "...", "est_duration": "约4-6个月",
     "shares_foundation": true, "section_count": 18}
  ]
}
```

## GET /api/routes/{route_id}/sections
返回路线章节序列 + 用户解锁/进度状态。
```json
{
  "route_id": "route_A",
  "sections": [
    {"id": "sec_A_00", "order_index": 0, "stage_no": 0, "title": "建坐标系",
     "work": "大众哲学", "is_foundation": true,
     "status": "completed", "mastery_score": 0.86, "unlock_threshold": 0.8}
  ]
}
```

## POST /api/routes/{route_id}/select
用户选择/切换路线。切换保留已有学情。
- Request: `{ "user_id": "u1" }`
- Response: `{ "selected": "route_A", "carried_over": ["sec_A_00"], "recomputed_start": "sec_A_02" }`

## POST /api/routes/{route_id}/diagnostic
提交摸底测作答，返回起点推荐。
- Request: `{ "answers": [{"item_id":"q1","answer":"B"}] }`
- Response:
```json
{
  "diag_id": "d_123",
  "recommended_start": "sec_A_02",
  "order": ["sec_A_02","sec_A_03"],
  "skippable": ["sec_A_00","sec_A_01"],
  "to_reinforce": [{"node_id":"kn_practice","reason":"实践观基础薄弱"}]
}
```

## GET /api/routes/{route_id}/sections/{section_id}/gating
查询某章是否解锁。
- Response: `{ "section_id":"sec_A_03", "unlocked": false, "reason":"需先补强 kn_contradiction（掌握度0.42<0.8）", "blocking_nodes":["kn_contradiction"] }`

**错误码**：401 未认证；404 路线/章节不存在；409 前置未满足尝试进入（附 gating 详情）。
