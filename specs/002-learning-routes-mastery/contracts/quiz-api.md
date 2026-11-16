# API Contract: 测验 (quiz-api)

Base: `/api/quiz`

## POST /api/quiz/section/{section_id}/start
为一章生成测试题组（按知识点规模自适应 8–12 题）。
- Request: `{ "user_id":"u1", "route_id":"route_A", "mode":"section_test" }`
- Response:
```json
{ "test_id":"t_1", "section_id":"sec_A_02",
  "items":[
    {"id":"q1","type":"concept_discrimination","stem":"...","options":["A","B","C","D"],
     "difficulty":0.5,"source_chunk_id":"CH-ME-TH-001-010","authority_status":"reviewed"},
    {"id":"q9","type":"error_diagnosis","stem":"...","options":[...],"exempt_marked":true,"trial_only":false}
  ]}
```
说明：`answer`/`explanation`/`error_category` 不在下发给客户端的 start 响应中（判分时返回）。

## POST /api/quiz/submit
提交作答并判分。
- Request: `{ "test_id":"t_1", "answers":[{"item_id":"q1","answer":"B","duration_ms":12000}] }`
- Response:
```json
{
  "test_id":"t_1","total_score":0.75,
  "mastery":[
    {"node_id":"kn_shiminshehui","level":"beginner","score":0.42,
     "error_category":"concept_layer_confusion"}
  ],
  "review":[
    {"item_id":"q1","is_correct":false,"answer":"A","explanation":"...","source_chunk_id":"CH-ME-TH-001-010",
     "provenance":{"source":"关于费尔巴哈的提纲","location":"第10条","authority_score":0.95}}
  ],
  "gating":{"next_section_unlocked":false,"need_reinforce":["kn_shiminshehui"]}
}
```

## POST /api/quiz/appeal
对判分申诉，进入专家审核队列（复用既有审核）。
- Request: `{ "test_id":"t_1", "item_id":"q1", "reason":"..." }`
- Response: `{ "appeal_id":"ap_1", "status":"pending_review" }`

**正统性约束（契约级）**：任何 `items[]` 无 `source_chunk_id` 或 `authority_status=pending` 的题，`trial_only` 必须为 true 且不得计入正式掌握度。
