# API Contract: 推荐与门控 (recommendation-api)

Base: `/api/recommendation`

## GET /api/recommendation/today?route_id=route_A
今日推荐（首页/导航横幅）。
```json
{ "recommendation":{
    "rec_type":"reinforce","target_section_id":"sec_A_03","target_node_id":"kn_contradiction",
    "reason":"你在'对立统一规律'连续出错，建议先回补《矛盾论》专项",
    "cta":{"primary":"一键进入","secondary":"先补强前置"} } }
```

## POST /api/recommendation/next
请求"下一步该学/复习什么"。综合门控与薄弱点。
- Request: `{ "user_id":"u1","route_id":"route_A","current_section_id":"sec_A_02" }`
- Response:
```json
{ "rec_type":"next_section","target_section_id":"sec_A_03","reason":"第2章已达标(0.83)，可进入第3章",
  "alternatives":[{"rec_type":"review","target_node_id":"kn_contradiction","reason":"..."}] }
```

## GET /api/recommendation/weak-top?route_id=route_A&n=5
薄弱点 TOP-N（与 mastery 档案一致，供推荐卡/档案卡复用）。
```json
{ "weak_points":[{"node_id":"kn_contradiction","statement":"存在3处依赖，阻塞后续3章"}] }
```

**规则（对应 research D4）**：达标(≥0.8)解锁下一章；未达标返回 reinforce 推荐 + blocking_nodes；薄弱排序 = (1-score)×依赖出度×考频。所有推荐必带 `reason` 一句话。
