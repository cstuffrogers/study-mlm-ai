# Research: 三路线学习路径与掌握度闭环

**Feature**: `specs/003-learning-routes-closed-loop/spec.md`
**Date**: 2026-07-18
**Purpose**: 解决 `plan.md` Technical Context 中的全部未知项，为 Phase 1 设计提供已决策依据。

---

## D1. 三条路线的组织方式：共享图谱 + 路线 profile

- **Decision**: 三条路线编译为同一知识图谱上的"profile"（必读节点集、概念权重、题型配比、默认起点、立场档位），不复制内容。
- **Rationale**: `路径.txt` 的三段划分（革命前/革命中/建国）与 `学习顺序2.md` 的六阶段高度重叠但顺序不同。若各写一套内容，内容生产量 ×3（`spec.md` R-102 已是首要风险），且立场红线会出现多份副本导致防偏离不一致。
- **Alternatives considered**:
  - 三套独立课程：内容与题目无法复用，放弃。
  - 只做一份线性课程 + 标签过滤：无法表达"组织革命"必须先读《怎么办？》这类前置换序，放弃。
- **Consequence**: 需要 `KnowledgeNode` 可被多路线引用，且节点必须声明前置依赖（FR-101/105）。

## D2. 掌握度模型：加权证据 + 简化贝叶斯置信，不用深度知识追踪

- **Decision**: 每个 `(learner, node)` 维护五级状态 + 置信度；由证据事件按"来源权重 × 结果 × 质量"加权更新，显式测试权重最高，对话证据仅在置信度 ≥ 阈值时小幅上调且不跨两级。
- **Rationale**: 现有 MVP 只有《提纲》11 条与 40 个苏格拉底问题，标注数据量不足以训练 DKT/AKT；轻量模型可解释（NFR-105）、可撤销（NFR-104）、可校准（SC-104）。
- **Alternatives considered**:
  - BKT 标准实现（4 参数 EM 拟合）：需要每节点足够作答样本，冷启动不可用。
  - IRT / Elo：适合题库规模大的自适应测试，当前题库不足以稳定估计难度。
  - 纯规则阈值（答对 3 次=熟悉）：无法处理证据冲突（R-101），放弃。
- **Consequence**: 需要 `EvidenceEvent` 表 + 可版本化的算法参数（NFR-112）。

## D3. 对话证据抽取：会话结束后一次结构化抽取

- **Decision**: 会话结束（或每 N 轮，默认 5 轮）触发一次后处理：用既有 LLM 路由做一次结构化抽取，输出 `{node_id, judgement, confidence, error_type, quote}` 数组；不逐轮调用。
- **Rationale**: 逐轮抽取 token 成本高（`specs/001` R-3 已提示成本风险），且单轮信息量不足以判定掌握；结束后汇总可看到完整推理链。
- **Alternatives considered**:
  - 逐轮抽取：成本 ×轮数，且噪声大。
  - 规则匹配术语表：只能发现术语错误，无法判定推理质量（但作为零成本兜底保留）。
- **Consequence**: 抽取结果必须经过防偏离校验（FR-135），并对低置信结果不写入（FR-116）；抽取失败不得阻断会话（NFR-107）。

## D4. 推荐算法：前沿集合 + 欠账 + 杠杆值

- **Decision**: 候选 = 前置依赖已满足的未掌握节点（前沿集合）；排序 = `欠账优先 > 到期复习 > 杠杆值（下游解锁数）> 路线内顺序 > 近期偏好`。
- **Rationale**: 纯拓扑顺序会反复回炉第一章；纯杠杆值会推荐空洞的高层节点。两因子组合已被 R-104 限定为"先两因子、杠杆值作次级"。
- **Alternatives considered**:
  - 多臂老虎机/强化学习：数据量与工程成本不匹配当前阶段。
  - 纯协同过滤：无同类用户数据，冷启动不可行。
- **Consequence**: 杠杆值需在路线导入时静态计算并缓存；推荐必须可解释（FR-110/NFR-105）。

## D5. 门禁：软门禁（欠账制），硬门禁仅留给未来考试路线

- **Decision**: 未达标节点不锁定后续章节，只记为"欠账"并提升其在推荐中的优先级；补丁为"定向段落 + 专项题"组合，不要求整章重读。
- **Rationale**: 自学者遇到硬门槛会流失；`specs/001` 原"<80% 不解锁"与本产品定位冲突。见 `spec.md` Clarifications 2。
- **Alternatives considered**: 硬门禁（`specs/001` 原文）——保留为可选策略，考试路线复用。
- **Consequence**: 需要在 `KnowledgeState` 上派生"欠账"标记，并进入仪表盘与推荐（FR-111/FR-131）。

## D6. 题目生产：题库优先 + AI 生成补足 + 三类离线校验 + 人工抽检

- **Decision**: 章节诊断优先从已审核题库按知识点+难度抽样；不足时用 AI 生成（模板 + 概念锚点 + 原文分块）补足；生成题必须过立场/事实/术语校验，并进入抽检队列。题量保底 8 题（NFR-111）。
- **Rationale**: 全人工写题无法覆盖三条路线；全自动生成会引入错误题目（SC-109 要求 0 立场/事实错误）。
- **Alternatives considered**: 只用人工题库（产量不足）；完全 AI 生成（不可控）。
- **Consequence**: 需要 `QuizItem.version` 与 `review_status`，以及"题库不足则提示延迟诊断"的降级路径。

## D7. 错误类型标签：6 类固定分类法

- **Decision**: 机械唯物 / 唯心 / 概念层次混淆 / 术语混用 / 立场偏离 / 记忆性失误。每类配一句人话解释与一条推荐动作模板。
- **Rationale**: 标签的价值在于驱动推荐，不在于精确诊断学理。6 类是 `路径.txt`「基本原则清单 + 合规性判据」与 `学习顺序2.md` 常见错误的交集，足以映射到补丁动作。
- **Alternatives considered**: 更细的 12+ 类（学习者不理解、标注一致性差）；只分对错（无法驱动推荐）。
- **Consequence**: 判分环节必须输出标签（FR-120），标签准确率由 SC-110 抽检保证。

## D8. 主观迁移题判分：评分要点 + 低置信转待确认

- **Decision**: 迁移题用固定评分要点（术语命中/逻辑链/原文依据/实践指向）逐项判分，总分阈值决定结果；模型自评置信度低或两次判分不一致时进入"待确认"，不计入掌握度。
- **Rationale**: 单一总分判分不稳定（R-105）；分项 rubric 可解释、可人工复核。
- **Alternatives considered**: 纯 LLM 打分（不稳定）；人工批改（不可规模化）。
- **Consequence**: 评分要点必须随题目版本化（FR-134）。

## D9. 复习调度：SM-2 简化版 + 强制回炉约束

- **Decision**: 采用 SM-2 简化（评级 3 档 → 间隔 ×1.2/×2.5/重置），并加两条硬约束：单日队列 ≤20、章节诊断未通过则对应节点强制回炉。
- **Rationale**: SM-2 简单、可解释、无需训练；FSRS 需要大量复习记录才能拟合。
- **Alternatives considered**: FSRS（数据不足）；固定间隔（不适应个体）。
- **Consequence**: `ReviewSchedule` 需存连续评级序列，便于后续升级到 FSRS。

## D10. 存储与轻量模式兼容

- **Decision**: 学情/证据/题目/报告落既有学习引擎 `core/db_learning.py`（`LearningBase`，`lr_` 前缀）；`LEARNING_DB_MODE=memory`（无 Docker 轻量模式）走 aiosqlite 内存库 + 可选 JSON 快照（`LEARNING_SNAPSHOT_PATH`），保证 `demo_e2e.py` 与前端联调可用。**沿用 002 已建立的双模式，不新造仓库抽象层。**
- **Rationale**: 现有项目明确支持"无 Docker 也能跑核心闭环"（`README.md` / `core/db.py` 注释），新增功能不能破坏这条验收路径。
- **Alternatives considered**: 强制依赖 PG（破坏轻量验收）；全部内存（重启丢学情）。
- **Consequence**: 学情服务需要仓库抽象（`repository` 协议 + PG/内存两个实现），测试用内存实现。

## D11. 路线配置格式：YAML + 导入校验

- **Decision**: `backend/content/curriculum/*.yaml`，每文件一条路线；加载后与 `theses_concepts.py` 的概念 id 对齐；导入时输出孤儿/断链/未映射报告（FR-106）。
- **Rationale**: 内容是编辑与专家维护的，YAML 比 Python 常量更安全（无需跑代码即可改），且便于 diff 与版本化。
- **Alternatives considered**: Python 常量（改内容要动代码）；数据库后台录入（MVP 无工作台）。
- **Consequence**: 需要 `content/curriculum_loader.py` 与一份 JSON Schema 校验。

## D12. 首期内容边界

- **Decision**: 首期完整内容 = 纯理论研究路线第 1–4 模块（《提纲》11 条 + 《费尔巴哈论》节选 + 《共产党宣言》第一章 + 《国家与革命》第一章）；组织革命路线 = 骨架 + 《怎么办？》第一章模块；建国路线 = 骨架 + 《国家与革命》/《论人民民主专政》各一节。
- **Rationale**: 首期要能验证"路线差异真的产生不同推荐"，同时内容量可控；《提纲》已有内容资产（原文/概念/解析/问题池）。
- **Alternatives considered**: 只做纯理论（无法验证路线机制）；三条路线全铺（内容不可交付）。
- **Consequence**: `curriculum.yaml` 必须允许 `status: planned` 的占位节点，推荐命中时提示"该章尚未开放"（US4 场景 4）。

## D13. 反馈生成：结构化模板 + LLM 润色

- **Decision**: 反馈先由服务端按模板生成结构化内容（掌握度分布、错误类型、薄弱点、下一步动作含跳转目标），再由 LLM 做语言润色；LLM 不可用时直接展示结构化版本。
- **Rationale**: FR-127/SC-106 要求"下一步必须可执行"，纯 LLM 生成容易产出"你基础薄弱"式空话；模板保证结构，LLM 只负责可读性。
- **Alternatives considered**: 纯 LLM 生成（不可控）；纯模板（生硬但可用，作为降级）。
- **Consequence**: 模板与润色都需过防偏离校验（FR-135）。

## D14. 前端形态：沿用 Flutter + Provider，新增页面不改造阅读器

- **Decision**: 保留 `reader_screen.dart` 为主界面；新增学习中心（路线地图 + 推荐 + 欠账）、测试页、报告页、仪表盘、复习队列 5 个 screen；学情相关状态用新增 `LearningService extends ChangeNotifier`，与现有 `ChatService` 平级。
- **Rationale**: 现有前端是 `provider` + 单 `ChatService`，无路由框架（`main.dart` 直接 `home: HomeScreen`）。引入 go_router/Riverpod 会牵动已验收代码，收益低。
- **Alternatives considered**: 引入 Riverpod（与 `specs/001` 方案不符，且 MVP 已有 provider）；Web 优先（已确定 Flutter 跨平台）。
- **Consequence**: 需要补一个轻量页面栈（`Navigator` + 命名路由），避免弹层套弹层（UX Brief 会约束）。

## D15. 数据分析与埋点

- **Decision**: 只记录服务端已有事件即可（诊断触发/完成、推荐曝光/点击、反馈已读、复习完成），不引入第三方分析 SDK；指标由 SQL 视图计算。
- **Rationale**: SC-101..SC-112 需要可验证指标，但 MVP 不必自建分析平台。
- **Alternatives considered**: 接入第三方埋点（合规与依赖成本）；不埋点（无法验证 SC-107/SC-111）。
- **Consequence**: `RecommendationImpression` / `FeedbackRead` 两个轻量记录表。

---

## Open Questions Resolved

| 问题 | 结论 |
|------|------|
| 掌握度用 BKT 还是简化模型 | 简化加权 + 置信度（D2） |
| 对话证据实时更新还是会话后批处理 | 会话后一次抽取（D3） |
| 三条路线是否三套内容 | 共享图谱 + profile（D1） |
| 是否硬门禁 | 软门禁 + 欠账（D5） |
| 首期内容铺多宽 | 一条路线完整 + 两条骨架（D12） |
| 轻量模式是否仍可验收 | 是，仓库抽象 + 内存实现（D10） |
| AI 生成题是否可直接上线 | 否，三类校验 + 人工抽检（D6） |
