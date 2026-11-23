# 数据模型：学习勋章系统

## 实体 1：BadgeDefinition（勋章定义，配置型，不建表）

承载于 `backend/content/badges.py`，由 `badge_service` 加载并对外序列化。

| 字段 | 类型 | 说明 |
|------|------|------|
| badge_id | str | 唯一标识（如 `mastery_10`） |
| name | str | 展示名称 |
| description | str | 描述 |
| category | enum | 分类：知识掌握 / 贯通 / 里程碑 / 答题 / 路线 / 连续学习 / 对话 |
| condition_type | enum | `threshold`（阈值型）或 `completion`（完成型，如 route_all） |
| threshold | number | 阈值（threshold 型必填；completion 型忽略） |
| metric_key | str | 进度指标键，对应 LearningMetrics 的键（如 `mastered_count`、`streak_days`、`quiz_correct_total` + `quiz_attempt_total` 组合）；`quiz_acc_50` 类双指标条件用 `metric_keys` 列表 |
| icon_key | str | 展示图标标识（前端按 key 渲染自绘图标，不依赖图片资源） |
| sort_order | int | 展示排序 |
| enabled | bool | 是否参与检测与展示（停用仅影响新授予，历史授予保留） |

约束：

- `badge_id` 全局唯一；目录变更（增删改）不得修改已有 badge_id 的含义（幂等与历史记录依赖标识稳定性）。
- 初始 26 枚，见 spec.md「勋章目录（初始设计）」。

## 实体 2：BadgeAward（勋章授予记录，表 `user_badges`）

落在学习域数据库（`backend/model/models_learning.py` 新增 ORM 模型，随 AUTO_CREATE_TABLES 自动建表）。

| 字段 | 类型 | 说明 |
|------|------|------|
| id | PK | 自增主键 |
| user_id | str | 用户标识（沿用项目固定 demo_user 体系） |
| badge_id | str | 勋章标识，外键语义指向目录 |
| awarded_at | datetime | 授予时间 |
| source_event | str | 触发授予的事件标识（如 `quiz_submit`、`mastery_update`、`route_complete`、`dialogue_complete`、`daily_settle`） |
| read_flag | bool | 是否已查看（动画播放完成或显式标记后置 True） |

约束：

- **唯一约束 `(user_id, badge_id)`**：保证每枚勋章每人至多授予一次（SC-02）。
- 插入采用冲突忽略（ON CONFLICT DO NOTHING / 先查后插），评估幂等。
- 已授予记录永不删除（SC-08）；停用勋章的记录继续展示。

状态流转：`未查看（read_flag=false）→ 已查看（read_flag=true）`，单向。

## 实体 3：LearningMetrics（学习指标快照，派生，不落表）

由 `badge_service.collect_metrics(user_id)` 实时汇总，字段与口径：

| 键 | 含义 | 来源 |
|----|------|------|
| mastered_count | 掌握知识点数（掌握度达 mastered，含费曼通过） | mastery_service.get_mastery_map 计数 |
| journey_count | 贯通知识点数（有掌握度记录或测验记录的去重节点数） | mastery 记录 ∪ 测验作答记录去重计数 |
| milestones_achieved | 已达成里程碑数 | motivation_service._milestones 计数 |
| quiz_correct_total | 累计答对题数 | quiz 作答记录 is_correct 计数 |
| quiz_attempt_total | 累计作答题数 | quiz 作答记录计数 |
| routes_completed | 完成路线数 | route_service 进度聚合（全节点掌握/测验通过） |
| streak_days | 连续学习天数 | motivation_service 连续天数计算 |
| dialogues_completed | 完成对话场次数 | dialogue 完成记录计数 |

用途：条件判定 + 未获得勋章的进度展示（如 3/10）。

## 进度展示规则

未获得勋章的进度（FR-05 / SC-04）按条件类型生成 `display` 文本：

- **阈值型（单指标）**：`"{current}/{target}"`，如「3/10」。
- **比率型（双指标，如 quiz_acc_50）**：主指标为累计作答数，`display` 为 `"作答 {quiz_attempt_total}/{threshold}，正确率 {pct}%"`；已达标子条件用完整度展示，如正确率已达标但作答不足时仍显示作答进度。
- **完成型（如 route_all）**：`"{已完成路线数}/{已开放路线总数}"`；已开放路线总数为 0 时显示「暂不可达」。
- 已获得的勋章进度恒为 `"{target}/{target}"`。

## 关系

- BadgeDefinition 1 : N BadgeAward（按 badge_id 关联，目录可配置故不用数据库外键，应用层校验）。
- BadgeAward N : 1 用户（user_id）。
- LearningMetrics 为 BadgeDefinition 判定与展示的派生输入，无持久化关系。
