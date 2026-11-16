# Contract: WebSocket 事件（学情增补）

**Feature**: `specs/003-learning-routes-closed-loop/spec.md`
**Endpoint**: `ws://<host>:8190/ws/dialogue`（既有）
**Base protocol**: `backend/websocket/protocol.py`（`type` 字段驱动，JSON）
**原则**: **只新增消息类型，不改变既有消息结构与语义**（`specs/001` 已上线链路零破坏）

---

## 1. 新增 S→C 消息类型

| type | 触发时机 | 用途 |
|------|----------|------|
| `learning_digest` | 会话结束（`action=end`）或满 N 轮 | 推送小结卡（FR-126） |
| `evidence_updated` | 证据写入且状态发生变化 | 前端刷新节点状态/批注轨 |
| `learning_degraded` | 抽取或学情服务失败 | 提示"本次学情未保存"（NFR-107） |

### 1.1 `learning_digest`

```json
{
  "type": "learning_digest",
  "dialogue_id": "d_…",
  "report_id": "r_…",
  "level": "turn",
  "understood": ["你能说出实践的对象性"],
  "to_fix": ["“实践就是人做事情”落入了日常行为的 near_synonym"],
  "next_questions": ["那“道德践履”算不算实践？为什么？"],
  "evidence_written": 2,
  "evidence_skipped_low_confidence": 1,
  "degraded": false
}
```

**客户端行为**
- 以半屏卡片升起（UX 流程 C），不阻塞会话
- 每条判定带"我不认同"入口 → 调 `POST /api/learning/evidence/{id}/revoke`
- `degraded=true` 时不展示 `to_fix`（防止未校验内容展示，FR-135）

### 1.2 `evidence_updated`

```json
{
  "type": "evidence_updated",
  "dialogue_id": "d_…",
  "states": [
    { "node_key": "th1-practice", "level": 2, "confidence": 0.72,
      "changed": true, "prev_level": 1, "source": "dialogue", "conflict": false }
  ],
  "debt_delta": 0
}
```

**客户端行为**：更新阅读器右侧批注轨与章节进度条；不弹提示（避免打断阅读）

### 1.3 `learning_degraded`

```json
{
  "type": "learning_degraded",
  "dialogue_id": "d_…",
  "reason": "digest_failed",
  "message": "本次学情未保存，可重试",
  "retryable": true
}
```

`reason` ∈ `digest_failed` | `llm_unavailable` | `guard_rejected` | `storage_unavailable`

---

## 2. 既有消息的字段增补（向后兼容，均可缺省）

### `state_transition`（既有）

新增可选字段：
```json
{
  "type": "state_transition",
  "dialogue_id": "d_…",
  "from": "dig", "to": "explain",
  "node_keys": ["th1-practice"],
  "evidence_hint": "low_confidence_correct"
}
```
`node_keys` 由会话锚点映射得到，让前端在模式切换时即可预取节点状态（性能，SC-103 的前置）。

### `progression`（既有）

新增可选字段（与 `specs/001` 费曼评分并存）：
```json
{
  "type": "progression",
  "dialogue_id": "d_…",
  "mastery": { "node_key": "th1-practice", "level": 2, "confidence": 0.72 },
  "counts_toward_mastery": true
}
```
**规则**：`counts_toward_mastery=false` 时前端不得呈现"已掌握"视觉

---

## 3. 时序不变量

1. `learning_digest` MUST 在 `dialogue_ended` 之前或紧随其后到达；若抽取超时（默认 8s）先发 `learning_degraded`，再发 `dialogue_ended`
2. 一次会话最多 1 条 `learning_digest`（重复 end 幂等，返回同一 `report_id`）
3. `evidence_updated` 可多次，但需按 `states[].node_key` 去重合并
4. 任一新增消息缺失时，客户端必须仍可正常使用阅读器与会话（消息为增强，不是必需）

---

## 4. 兼容与回退

- 旧客户端不识别新 `type` → 忽略即可（无必需字段依赖）
- 后端 `ENABLE_LEARNING_DIGEST=0` 时不发任何新增消息，行为退回 `specs/001` 现状（用于回归对比）
- 学情服务不可用时只发 `learning_degraded`，不阻塞 `ai_message`
