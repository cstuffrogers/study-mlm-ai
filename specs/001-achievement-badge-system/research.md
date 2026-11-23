# Research：学习勋章系统

## D1：勋章目录的承载形式

- **Decision**：`backend/content/badges.py` 纯数据模块（BadgeDef 列表，含 id/名称/描述/分类/条件类型/阈值/进度指标/图标/排序/启用）。
- **Rationale**：与 `content/routes.py` 同风格，类型明确、可被前后端共用的快照接口直接序列化；FR-07「改配置即生效」满足。
- **Alternatives considered**：JSON 文件（与 quiz_bank 一致，但条件类型/阈值结构需要额外 schema 说明，类型弱）；数据库表存目录（需要管理界面，超范围）。

## D2：授予记录存储与幂等

- **Decision**：新增表 `user_badges`（user_id、badge_id、awarded_at、source_event、read_flag），(user_id, badge_id) 唯一约束；插入用 ON CONFLICT 忽略实现幂等。
- **Rationale**：唯一约束天然保证「每勋章每人一次」（SC-02）；现有学习表均在同一 learning DB，AUTO_CREATE_TABLES 可自动建表。
- **Alternatives considered**：JSON 存用户档案（无法可靠去重、查询难）；redis 计数（重启丢失，不适合持久荣誉）。

## D3：评估引擎形态

- **Decision**：`backend/services/badge_service.py`：`collect_metrics(user_id)` 汇总 7 项指标；`evaluate(user_id, source_event)` 对未获得的启用勋章逐条判定，命中即插入授予，返回新授予列表。
- **Rationale**：指标采集复用 motivation/mastery/quiz/route/dialogue 既有逻辑，评估器本身无业务副作用；单函数可被多事件挂接。
- **Alternatives considered**：WebSocket 推送事件后由前端请求评估（多一跳、离线不友好）；定时批量评估（延迟感强，违背 SC-01）。

## D4：检测挂接点

- **Decision**：在 5 类事件完成处调用 `badge_service.evaluate`：答题提交（quiz_service）、掌握度更新（mastery_service.upsert_mastery）、路线完成（route_service 完成判定处）、对话完成（dialogue_service）、每日动机结算（motivation_state 调用处或登录/同步入口的日切处理）。
- **Rationale**：覆盖全部指标来源；事件后立即检测满足 SC-01；幂等保证重复调用安全。
- **Alternatives considered**：仅在前端事件后调接口（服务端无法保证离线与一致性）；集中在单一入口轮询（延迟与成本）。

## D5：新勋章通知前端的方式

- **Decision**：事件处理响应体附带 `badges_awarded` 列表（前端收到即触发动画）；同时提供 `GET /api/badges/unseen` 作为冷启动/离线补发兜底（首页提醒数据源）。
- **Rationale**：即时触发动画无需额外轮询；unseen 接口解决「离线期间达成、回联网才看到」的场景。
- **Alternatives considered**：WebSocket 推送（项目已有 WS 但仅用于对话，引入广播通道超范围）；前端每次事件后轮询 mine（浪费）。

## D6：离线支持策略（推荐默认，待用户确认）

- **Decision**：客户端本地评估。`frontend/lib/offline/local_badges.dart` 复用本地指标（local_mastery/local_insight 同模式）对照同一目录快照判定，授予记录存本地库；联网后经 sync_service 合并到服务端，服务端为最终权威，冲突按「已授予优先」合并。
- **Rationale**：本项目离线是一等能力，纯服务端判定会让离线学习无激励反馈；本地评估保证即时正反馈（动画），同步保证持久。
- **Alternatives considered**：仅在线（离线时勋章功能不可用，违背激励目标）；纯本地不同步（授予记录可能丢失，不满足荣誉持久性）。

## D7：获得动画实现

- **Decision**：Flutter 自绘：礼盒（CustomPainter）+ 开盖动画（内置 AnimationController/Curves）+ 粒子光效；动画结束展示勋章信息并提供「标记已读」。不新增第三方动画依赖。
- **Rationale**：零依赖、包体不增大、离线可用；礼物开箱效果用自绘完全可控。
- **Alternatives considered**：lottie/gif 资源（需要美术资源与打包，自绘更轻且风格可控）；纯文字弹窗（不满足「像抽中礼物」的诉求）。

## D8：路线完成与贯通数口径

- **Decision**：路线完成 = 路线内全部节点达到掌握 或 对应测验通过（复用 route_service 进度聚合）；贯通数 = 存在掌握度记录或测验作答记录的去重知识点数。
- **Rationale**：两者都基于既有数据聚合，无需新增埋点。
- **Alternatives considered**：新增「进入章节」埋点（需要改动阅读器，超范围）。
