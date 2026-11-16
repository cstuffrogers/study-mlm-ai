# Findings: 正统马哲深度学习系统 MVP

## Research Summary

通过对比 ljsk 项目（E:\ljsk，已落地的 AI 学习教练）与 xxmz 现有原型，确认 xxmz 的工程化路径：复用 ljsk 的 FastAPI+Flutter+状态机+LLM路由骨架，嫁接 xxmz 的七层马哲知识图谱+立场校验垂直深度。已识别 xxmz 原型的 7 个精度/架构问题（P0-2 个、P1-3 个、P2-2 个），其中 P0-1（防偏离层漏判"共同决定"变体）和 P0-2（L2 误杀批判性教科书文本）是产品命门。

## Key Discoveries

### ljsk 工程骨架可复用
- **Found:** ljsk 提供完整的 6步认知状态机（state_machine.py）、LLM 4级路由（router.py: cache→语义缓存→蒸馏→本地→云）、Prompt注入防护（sanitizer.py: NFKC+12正则+关键词）、评分机制、管理面板、WebSocket协议
- **Source:** E:/ljsk/backend/，方案.md 附录
- **Relevance:** xxmz 工程骨架不必从零搭，Phase 1-3 可直接移植适配
- **Timestamp:** 2026-07-16

### xxmz 防偏离体系原漏洞已识别
- **Found:** MetaRuleEngine 按字面 `in` 匹配黑名单术语，对"多种因素共同决定"（阿尔都塞话术变体）漏判；L2 对所有 chunk 跑内容检测会误杀引用西马概念做批判的正统教科书文本
- **Source:** retrieval_filter_pipeline.py:218,335
- **Relevance:** Phase 2 必修，否则动摇"正统纯粹"核心卖点
- **Timestamp:** 2026-07-16

### Prompt注入防护已移植
- **Found:** prompt_sanitizer.py 已创建，6/6 自测通过（越狱/角色切换/系统提示探测/全角绕过/立场解锁诱导均拦截）
- **Source:** E:/xxmz/prompt_sanitizer.py（从 ljsk sanitizer.py 移植+马哲场景适配）
- **Relevance:** 补齐 xxmz 防偏离的输入侧漏洞，FR-005 输入侧已就绪
- **Timestamp:** 2026-07-16

### 精度指标已降级为可验证形式
- **Found:** 方案.md 原"正统性合规>99.9%"无 ground truth 不可验证，已拆为"黑名单术语拦截率"+"立场分类器F1"两个可测子指标
- **Source:** 方案.md §九（已优化）
- **Relevance:** SC-003/SC-004 可量化，Phase 6 可验收
- **Timestamp:** 2026-07-16

### 待研究问题
- pgvector vs Milvus：MVP规模（500-800节点）倾向 pgvector，Phase 1 确认
- BERT 立场分类器训练数据标注：可能阻塞 Phase 6，考虑规则引擎+少量标注启动
- 《提纲》解析层内容：专家撰写 vs AI生成+专家审，影响 Phase 4 工期

### Phase 6 测试暴露的规则版立场校验边界（2026-07-18）
- **Found:** 规则版 OrthodoxyGuard 对"批判对象攻击正统" vs "批判对象被批判"两类句式无法区分——
  "鲍德里亚的生产之镜批判了马克思的劳动价值论"（deviation，应 block）
  "鲍德里亚的生产之镜是对劳动价值论的后现代歪曲"（orthodox 批判引用，应 pass）
  句式同构，"批判/歪曲"等词共现，规则版无法判定语义方向。
- **Source:** backend/tests/deviation_dataset.py（2 条 bert_only 标注）+ backend/tests/test_sc004_stance_f1.py（xfailed）
- **Relevance:** 确认 spec 设计——规则版只做基线兜底，SC-004 生产 F1 由 BERT 立场分类器达成；
  BERT 训练数据必须含此类困难正/负样本，否则会退化为关键词匹配（与 P0-2 同病）
- **3-Strike 教训:** 两次试图加规则细化（_attacks_orthodoxy 语义方向检测）都引入回归，
  按 planning-with-files §3-Strike 协议停止改规则，改测试预期 + xfail 诚实标注边界
- **Timestamp:** 2026-07-18

### Phase 6 暴露并修复的两类真实话术漏判（2026-07-18）
- **Found:** 原 STANCE_PATTERNS 漏两类高频反马话术：
  ① 哈耶克"计划经济是通往奴役之路"（新自由主义）
  ② "劳动价值论已经过时，知识经济超越了它"（修正主义/后现代）
  测试集暴露后才补 `deny_planned_economy` + `deny_labor_value_theory` 两条 pattern。
- **Relevance:** Phase 6 测试集的价值实证——数据集驱动发现产品命门漏洞，非纯回归测试。
  生产 500 条样本集应继续扩充此类话术覆盖（哈耶克/米塞斯/熊彼特/后劳动价值论批判）
- **Timestamp:** 2026-07-18
