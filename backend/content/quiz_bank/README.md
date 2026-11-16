# 题库 JSON Schema 说明（P0 提纲章）

> 文件：`outline_chapter.json`。所有题必须满足正统性门禁（见下），否则后端拒绝出题。

## 顶层结构
```json
{ "section_id": "sec_A_02", "items": [ { ...题... } ] }
```

## 题字段
| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | 题号，`q_*` |
| `type` | string | 四类：`concept_discrimination` 概念辨析 / `text_location` 原文定位 / `logical_deduction` 逻辑推演 / `error_diagnosis` 错误诊断 |
| `stem` | string | 题干 |
| `options` | string[] | 客观题选项（主观题可空） |
| `answer` | string | 正确项字母（A/B/C/D）；主观题留空 |
| `explanation` | string | 正统解析（须可从 source_chunk 溯源） |
| `node_id` | string | 对应知识点 `kn_*` |
| `difficulty` | number | 0~1，参与掌握度 D1 难度分量 |
| `subjective` | bool | 是否主观/费曼题（三维度批改） |
| `source_chunk_id` | string | **必填**。溯源 chunk（`CH-ME-TH-NN-L`）；缺则拒绝出题（FR-022） |
| `authority_status` | string | `reviewed`（已审，计正式掌握度）/ `pending`（待审，`trial_only` 不计分，D2） |
| `trial_only` | bool | 可选覆盖；true 表示仅练习不计正式掌握度 |
| `exempt_marked` | bool | 错误诊断题的“故意错误项”须置 true，判分豁免，不被防偏离误杀（FR-023） |

## 正统性门禁（后端强制）
1. 每道题 `source_chunk_id` 非空，且指向 `content/theses_annotations.py` 中的合法 chunk。
2. 入题库前经 TripleCheck（事实/术语/立场）；`authority_status != reviewed` 的题 `trial_only=true`，不计正式掌握度。
3. 错误诊断题的“故意错误项” `exempt_marked=true`，走豁免判定。
4. 对话中判为“偏离”的内容标 `not_a_normal_error`，不计普通错题。

## P0 现状
- 10 题覆盖四类题型；2 道错误诊断题 `exempt_marked=true`；1 道费曼主观题。
- 全部 `authority_status=reviewed`，均带 `source_chunk_id`。
