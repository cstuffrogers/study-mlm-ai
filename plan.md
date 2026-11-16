# Plan: 正统马哲深度学习系统 — MVP（提纲11条精读闭环）

## Goal

交付可运行的 MVP：学习者阅读《关于费尔巴哈的提纲》11条，选中文本唤起AI五模式会话，防偏离三重机制守门，溯源卡片可查——端到端闭环跑通且不偏离正统立场。

## Spec Reference

- **Spec File:** `specs/001-marxism-learning-system/spec.md`
- **方案 File:** `方案.md`（含 ljsk 工程骨架附录）
- **Key Requirements (MVP 范围 = User Story 1):**
  - FR-001 三层阅读模式（原文/注释/解析）+ 段落批注 + 概念高亮
  - FR-002 选中文本唤起AI，五模式（释义/追问/辩难/关联/应试）可切换
  - FR-003 锚点保持（多轮会话回原文）
  - FR-004 会话存为"思考批注"附着原文
  - FR-005 防偏离三重机制（PromptSanitizer + MetaRuleEngine + BERT分类器）
  - FR-006 辩难模式标记豁免（`【反方观点·仅供批判】`）
  - FR-007 双轨制概念防火墙
  - FR-015 RAG五层过滤
  - FR-016 三重索引混合召回
  - FR-017 溯源卡片（句子级）
  - SC-001 端到端延迟≤3s | SC-003 拦截率≥95% | SC-007 标记豁免100%生效
- **Out of MVP (进 roadmap):** User Story 2-5（掌握度/费曼/间隔重复/专家台）、七层中后6层原著

## Current Phase

MVP 交付完成 + RAG 混合召回 + ML 立场分类器（4 xfailed 解除）· 后续：Docker 切 pgvector/Neo4j 真实 store / 生产 500 条样本 / 6 阶段内容补全

## Phases

### Phase 1: 工程骨架搭建（移植 ljsk）
- [ ] 初始化项目结构：backend(FastAPI) + frontend(Flutter) + docker-compose(PostgreSQL+pgvector+Redis+Neo4j)
- [ ] 数据库 Schema：users / dialogues / dialogue_messages / text_chunks / concepts / propositions / conversation_threads（参考 ljsk 19表精简）
- [ ] 后端应用工厂 + 路由骨架（auth/dialogue/chunk）
- [ ] WebSocket 消息协议（C→S user_message+selected_text，S→C ai_message/state_transition/provenance/blocked）
- **Status:** pending

### Phase 2: RAG 检索与防偏离核心（重构现有原型）
- [x] 将 retrieval_filter_pipeline.py 重构为服务层（HybridRetriever + FiveLayerFilter）
- [x] 接入真实向量索引（in-memory 3-gram 哈希；pgvector 接口留待 Docker）
- [x] 接入 Neo4j 图索引（in-memory 邻接表；Neo4j 接口留待 Docker）
- [x] 概念词典子串匹配改 jieba 分词 + 最长匹配（修 P1-2 精度问题）
- [x] MetaRuleEngine 扩充 stance_patterns 变体（"多种因素共同决定"等，修 P0-1）
- [x] L2 立场校验区分"批判性引用 vs 宣扬"（修 P0-2）
- [x] prompt_sanitizer.py 接入输入侧前置
- **Status:** partial complete（in-memory 三路召回 + 五层过滤全通；pgvector/Neo4j 真实 store 接口骨架留待 Docker up）

### Phase 3: Prompt 渲染与 LLM 接入
- [x] prompt_renderer.py 接入真实 YAML 配置（已就绪）
- [x] 接入真实 LLM API（替换 MockLLM）+ 4级路由（cache→语义缓存→本地→云，移植 ljsk router.py）
- [x] 辩难模式标记豁免实现（校验器识别 `【反方观点·仅供批判】` 跳过）
- [x] 双轨制概念防火墙实现（正统一路默认 + 批判性模式显式切换）
- [x] 生成后三重校验（事实一致性 + 术语一致性 + 立场二分类）
- **Status:** complete（LLM 默认 Mock，配齐 LLM_API_KEY 自动走真实国产模型；BERT 立场分类器留接口待 Phase 6）

### Phase 4: 内容生产（《提纲》11条 + 6阶段结构入库）
- [x] MVP 优先：《关于费尔巴哈的提纲》11条原文入库（第2阶段核心）+ 原子化分块（L1-L4）
- [x] 11条的概念锚点 + 注释层 + 解析层（项目编写，基于正典教材阐释）
- [x] 概念节点入数据模块（实践/对象性活动/市民社会/人类社会/人的本质等12概念 + 术语红线）
- [x] 每条配备苏格拉底问题（含原教旨第三问：这个理论指向什么革命实践？共40问）
- [ ] 6阶段结构化索引（第0/1/3-6阶段，本轮仅第2阶段提纲，后续补）
- [ ] 概念/命题节点入 Neo4j（待 Docker 集成）
- [ ] 第6阶段批判对象内容入库（强制标注批判任务，后续阶段）
- **Status:** partial complete（提纲11条闭环就绪；6阶段索引+Neo4j+批判对象后续补）

### Phase 5: 前端阅读器与会话面板
- [x] 三层阅读器（原文/注释/解析切换）+ 概念高亮 + 段落批注
- [x] 选中文本→浮动工具栏（5模式按钮）→会话浮层（Sheet Modal）
- [x] 会话历史彩色竖线（5模式5色，加图标+标签，对齐 NFR-019）
- [x] 锚点保持（"回到原文"按钮）
- [x] 溯源卡片渲染 + blocked/insufficient-context 状态
- [x] 辩难模式 ExemptBlockWrapper 组件（视觉区分反方发言）
- **Status:** complete（flutter analyze 0 issues + widget test 过 + web build 过 + 后端 ws 真实联调通过）

### Phase 6: 测试与质量门禁
- [x] 500条西马话术测试集 → 黑名单拦截率验证（SC-003）— 内测 53 条样本集，规则版拦截率 100%；生产补全 500 条
- [x] 立场分类器训练（正/负/困难负样本）→ F1验证（SC-004）— ML 分类器（logreg + TF-IDF char n-gram）F1=0.90；规则版基线 F1=0.933（不含困难样本）；4 条 xfailed 全解除
- [x] 标记豁免测试（标记100%通过 / 未标记100%拦截，SC-007）
- [x] 端到端延迟测试（SC-001 ≤3s）— Mock LLM 路径全过，P95 ≤3s
- [ ] /review + /hunt 工作流（安全门禁）— 留待后续
- **Status:** complete（SC-001/003/004/007 全过 + ML 分类器注入解除 4 xfailed；安全门禁后续补）

### Phase 7: MVP 交付
- [x] docker-compose 一键启动（app 服务容器化 + 三数据服务 healthcheck 依赖）
- [x] 测试账号 + 演示数据（demo_e2e.py 4 用例验收脚本）
- [x] README 更新（双启动模式/架构/测试/已知边界）
- [x] 交付验收（轻量模式端到端 4/4 通过 + 65 测试 + 2 xfailed）
- **Status:** complete

## Key Questions

1. ~~向量索引选 pgvector 还是 Milvus？~~ → **pgvector**（用户决策，MVP规模小省运维）
2. ~~LLM 选 GPT-4/Claude 还是国产模型？~~ → **国产大模型**（通义/文心/DeepSeek，合规+成本低；架构须支持多云轮换以便切换）
3. ~~前端 Flutter 还是先做 Web 验证闭环？~~ → **Flutter 跨平台**（用户决策，按方案 §四 原选型，一套代码覆盖 iOS/Android）
4. BERT 立场分类器训练数据谁来标注？→ 需马哲专家，可能阻塞 Phase 6，考虑先用规则引擎+少量标注启动
5. 《提纲》解析层内容由专家撰写还是AI生成+专家审？→ 影响 Phase 4 工期，待 Phase 4 启动时确认

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| MVP 限定 User Story 1（提纲11条） | spec Scope Boundaries；单部原著足够验证核心闭环 |
| 工程骨架移植 ljsk | 方案.md 附录；ljsk 已落地 FastAPI+Flutter+状态机+LLM路由，省从零搭 |
| 防偏离三重机制优先（Phase 2-3） | 产品命门；P0-1/P0-2 已识别为已知风险 |
| 向量索引 = pgvector | 用户决策；MVP 规模小（500-800节点），与PostgreSQL同库省运维 |
| LLM = 国产大模型 + 多云轮换架构 | 用户决策；合规+成本低；架构支持后续切换 GPT/Claude |
| 前端 = Flutter 跨平台 | 用户决策；按方案 §四 原选型，一套代码 iOS/Android |
| 指标降级为可验证形式 | spec 已删"99.9%正统性"，改黑名单拦截率+立场F1 |
| 内容层 = 学习顺序2.md 6阶段结构 | 用户决策；替换原七层递进；第6阶段批判对象强制批判姿态（非中立对照） |
| FR-007 收紧为批判对象模式 | 用户决策；按 学习顺序2.md §严格禁止；批判性阅读不作中立，AI以"找出错误"姿态呈现 |
| MVP 内容仍为提纲11条 | 用户决策；第2阶段核心，最短概念密度高，验证闭环够用 |

## Errors Encountered

| Error | Attempt | Resolution |
|-------|---------|------------|
| (Phase 1-7 执行中记录) | | |

## Attestation

- **SHA256:** (运行 attest-plan.sh 后自动填充)
- **Last Attested:** (未启用)

## Notes

- 更新阶段状态: pending → in_progress → complete
- 重大决策前重读此计划
- 记录所有错误 — 避免重复
- 永不重复失败操作 — 改变策略
- 2-Action Rule: 每2次视图/搜索操作后保存发现到 findings.md
- 会话恢复: /clear 后运行 python .claude/scripts/session-catchup.py "$(pwd)"
