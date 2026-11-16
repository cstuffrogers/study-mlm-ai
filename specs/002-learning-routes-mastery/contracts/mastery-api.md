# API Contract: 掌握度与学情档案 (mastery-api)

Base: `/api/mastery`

## GET /api/mastery/profile?route_id=route_A
返回学情档案聚合视图。
```json
{
  "route_id":"route_A",
  "ability_radar":{"materialism":0.8,"dialectics":0.55,"epistemology":0.7,
                   "historical_materialism":0.6,"political_economy":0.5},
  "weak_points":[
    {"node_id":"kn_contradiction","name":"对立统一规律","score":0.42,
     "reason":"掌握度低×依赖出度高×考频高","blocking_sections":3}
  ],
  "mastery_distribution":{"unseen":12,"beginner":8,"familiar":6,"proficient":3,"mastered":1},
  "summary":"本周完成2章，辩证法偏弱，建议优先回补《矛盾论》专项",
  "updated_at":"2026-11-04T10:00:00Z"
}
```

## GET /api/mastery/node/{node_id}
单知识点掌握详情（含分项依据，用于审计/展示）。
```json
{ "node_id":"kn_shiminshehui","level":"beginner","score":0.42,
  "basis":{"accuracy":0.3,"difficulty":0.5,"stability":0.2,"dialogue":0.4,"feynman":null},
  "signals":[{"type":"concept_layer_confusion","source":"quiz","at":"..."}] }
```

## POST /api/mastery/summary
触发生成 AI 学习总结反馈。
- Request: `{ "user_id":"u1","route_id":"route_A","period":"week" }`
- Response:
```json
{ "report_id":"fr_1","mastered":["实践观","物质定义"],"to_reinforce":["对立统一规律"],
  "next_step":"从《矛盾论》第3节开始专项",
  "source_tags":{"mastered":"quiz","to_reinforce":"quiz+dialogue"} }
```

## WS 事件（复用既有 protocol，落地预留消息）
- `progression`：判分后推送 `{step:"mastery", node_id, level, score}`
- `struggle_detected`：对话中检测到卡顿 `{node_id, signal_type, intensity}`

**隐私（NFR-006）**：仅本人或 `role in (expert, admin)` 可读他人档案；越权 403。
