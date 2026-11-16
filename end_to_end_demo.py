#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
正统马哲AI导师 — 端到端完整演示
================================
演示完整的用户交互流程：
  用户选中原文 → 混合检索 → 五层过滤 → Prompt渲染 → LLM生成 → 立场校验 → 输出

本文件为演示用途，使用模拟LLM（规则引擎）代替真实GPT-4/Claude。
生产环境只需替换 llm_generate() 函数为实际API调用。
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Windows 控制台默认 GBK，遇到 emoji/中文会 UnicodeEncodeError；强制 UTF-8 输出
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

from typing import Dict, Any, List, Optional

from retrieval_filter_pipeline import (
    ConceptDictionary, MetaRuleEngine, HybridRetriever, 
    FiveLayerFilter, UserQuery, TextChunk, build_demo_corpus
)
from prompt_renderer import PromptRenderer, RAGContext, UserContext, TermDefinition, Proposition
import numpy as np

# ============================================================
# 1. 模拟LLM（生产环境替换为真实API调用）
# ============================================================

class MockLLM:
    """
    模拟LLM生成器
    基于规则引擎，根据Prompt内容生成回答
    生产环境替换为：OpenAI API / Claude API / 国产大模型API
    """

    def __init__(self):
        self.generation_log = []

    def generate(self, prompt: str, max_tokens: int = 500) -> str:
        """
        模拟生成
        实际生产环境：
          response = openai.ChatCompletion.create(
              model="gpt-4",
              messages=[
                  {"role": "system", "content": system_prompt},
                  {"role": "user", "content": user_prompt}
              ],
              max_tokens=max_tokens,
              temperature=0.3  # 低温度确保确定性
          )
        """
        # 解析Prompt中的关键信息
        mode = self._extract_mode(prompt)
        concept = self._extract_concept(prompt)
        chunks = self._extract_chunks(prompt)

        # 基于规则生成回答
        if mode == "explain":
            return self._generate_explain(concept, chunks)
        elif mode == "dig":
            return self._generate_dig(concept, chunks)
        elif mode == "debate":
            return self._generate_debate(concept, chunks)
        elif mode == "connect":
            return self._generate_connect(concept, chunks)
        elif mode == "test":
            return self._generate_test(concept, chunks)
        else:
            return "[模拟LLM] 无法识别模式，请检查Prompt。"

    def _extract_mode(self, prompt: str) -> str:
        if "释义模式" in prompt:
            return "explain"
        elif "苏格拉底追问" in prompt:
            return "dig"
        elif "魔鬼代言人" in prompt:
            return "debate"
        elif "图谱导航员" in prompt:
            return "connect"
        elif "命题人" in prompt:
            return "test"
        return "unknown"

    def _extract_concept(self, prompt: str) -> str:
        # 简单提取术语
        if "市民社会" in prompt:
            return "市民社会"
        elif "实践" in prompt:
            return "实践"
        elif "物质" in prompt:
            return "物质"
        return "未知概念"

    def _extract_chunks(self, prompt: str) -> list:
        # 提取文本块
        chunks = []
        for line in prompt.split("\n"):
            if line.startswith("[") and "]" in line and len(line) > 50:
                chunks.append(line)
        return chunks

    def _generate_explain(self, concept, chunks):
        if concept == "市民社会":
            return """**1. 术语定义**
**市民社会**：在马克思历史唯物主义语境中，指与政治国家相对的物质生活关系总和，是资产阶级社会的同义语。[CH-TEXTBOOK-2023-002-010]

**2. 文本释义**
在《提纲》第十条中，马克思指出"旧唯物主义的立脚点是市民社会"，意指旧唯物主义不自觉地站在资产阶级意识形态立场上，因为其出发点是资本主义社会中抽象的、孤立的个人。[CH-AISHI-1961-003-015]

**3. 常见误解**
❌ 误解：市民社会就是公民社会（civil society），指非政府组织 → ✅ 纠正：在马克思语境中，市民社会是物质生活关系总和，与政治国家相对

**4. 体系定位**
属于历史唯物主义范畴。市民社会（经济基础）决定政治国家（上层建筑）。"""
        return f"[模拟解释] 关于{concept}的正统解释..."

    def _generate_dig(self, concept, chunks):
        return f"""你认为"{concept}"在这里是什么意思？

（提示：不要看日常理解，想想马克思在《提纲》中赋予它的特殊哲学含义。）

请简要回答，我会根据你的回答继续追问。"""

    def _generate_debate(self, concept, chunks):
        return f"""我是马赫主义者。我认为'物质'不过是'感觉的复合'，离开了人的感觉，谈论'客观实在'毫无意义。

你如何证明物质不依赖于感觉而存在？

请用正统马克思主义的原理进行辩护。"""

    def _generate_connect(self, concept, chunks):
        if concept == "市民社会":
            return """**纵向：概念谱系**
```
社会存在
  └── 市民社会（资产阶级社会形态）
        ├── 生产关系
        ├── 交往关系
        └── 经济基础
```

**横向：跨著作关联**
| 著作 | 位置 | 侧重 | 来源 |
|------|------|------|------|
| 《德意志意识形态》 | 第一章 | 首次系统阐述 | [CH-ME-DE-001-008] |
| 《提纲》 | 第十条 | 批判旧唯物主义立场 | [CH-ME-TH-001-010] |
| 艾思奇教材 | 第三章 | 体系化阐释 | [CH-AISHI-1961-003-015] |

**掌握状态**
- ✅ 社会存在：已精通
- 🟡 市民社会：正在学习
- 🔒 经济基础：未解锁

**推荐路径**
你已掌握"市民社会"，建议立即学习"经济基础"以形成完整认知 → [跳转]"""
        return f"[模拟关联] {concept}的知识图谱..."

    def _generate_test(self, concept, chunks):
        return """【单选】马克思在《提纲》中指出"旧唯物主义的立脚点是市民社会"，这里的"市民社会"是指：
A. 非政府组织组成的公民社会
B. 与政治国家相对的物质生活关系总和
C. 封建社会的民间自治组织
D. 现代民主政治的参与平台

【辨析】"市民社会是现代民主政治的基石，保障了公民的参与权利。"
请用历史唯物主义原理进行辨析。

【论述】结合《德意志意识形态》和《关于费尔巴哈的提纲》，论述"市民社会"概念在唯物史观中的地位和意义。"""


# ============================================================
# 2. 端到端Pipeline
# ============================================================

class OrthodoxMarxismTutor:
    """
    正统马哲AI导师 — 端到端Pipeline
    """

    def __init__(self, prompt_yaml_path: str = "./prompt_engineering.yaml"):
        # 初始化RAG组件
        self.concept_dict = ConceptDictionary()
        self.meta_engine = MetaRuleEngine()
        self.retriever = HybridRetriever(build_demo_corpus(), self.concept_dict)
        self.filter_funnel = FiveLayerFilter(self.concept_dict, self.meta_engine)

        # 初始化Prompt渲染器
        self.renderer = PromptRenderer(prompt_yaml_path)

        # 初始化LLM（模拟）
        self.llm = MockLLM()

        print("✅ 正统马哲AI导师初始化完成")
        print("   组件: RAG检索器 | 五层过滤器 | Prompt渲染器 | LLM生成器")

    def chat(self, user_context: UserContext) -> Dict[str, Any]:
        """
        完整的单轮对话流程

        Args:
            user_context: 包含用户选中原文、问题、当前著作等信息

        Returns:
            包含AI回答、溯源信息、校验结果的完整响应
        """
        print("\n" + "="*70)
        print(f"【用户输入】模式: {user_context.current_mode}")
        print(f"  著作: {user_context.current_work}")
        print(f"  选中: {user_context.selected_text[:50]}...")
        print(f"  问题: {user_context.user_question}")
        print("="*70)

        # Step 1: 混合检索
        print("\n[Step 1] 三路混合检索...")
        query = UserQuery(
            raw_text=user_context.selected_text,
            current_work=user_context.current_work,
            current_chapter=user_context.current_chapter,
            mode=user_context.current_mode,
            user_question=user_context.user_question,
            key_concepts=self.concept_dict.extract_concepts(user_context.selected_text + " " + user_context.user_question),
            logical_type_hint=self._infer_logical_type(user_context.user_question)
        )

        raw_pool = self.retriever.retrieve(
            query, 
            query_embedding=np.random.randn(768).astype(np.float32),
            pool_size=200
        )
        print(f"  召回池: {len(raw_pool)}条")

        # Step 2: 五层过滤
        print("\n[Step 2] 五层过滤漏斗...")
        filter_result = self.filter_funnel.filter(query, raw_pool, top_k=5)
        final_chunks = [r.chunk for r in filter_result["final_results"]]
        print(f"  最终注入: {len(final_chunks)}条")

        # Step 3: 构建RAG上下文
        print("\n[Step 3] 构建RAG上下文...")
        rag_context = self._build_rag_context(final_chunks)

        # Step 4: Prompt渲染
        print("\n[Step 4] Prompt渲染...")
        rendered = self.renderer.render(user_context, rag_context)
        print(f"  总Token: {rendered.token_estimate}")
        print(f"  注入术语: {rendered.context_injection_summary['term_definitions_count']}")
        print(f"  注入命题: {rendered.context_injection_summary['propositions_count']}")
        print(f"  注入文本: {rendered.context_injection_summary['text_chunks_count']}")

        # Step 5: LLM生成
        print("\n[Step 5] LLM生成...")
        raw_response = self.llm.generate(rendered.full_prompt)

        # Step 6: 生成后校验
        print("\n[Step 6] 生成后立场校验...")
        guard_result = self.meta_engine.check_text(raw_response)

        if guard_result["action"] == "block":
            print(f"  ⚠️ 校验不通过！拦截原因: {[f['reason'] for f in guard_result['flags']]}")
            final_response = self.renderer.render_fallback(
                "generation_blocked"
            )
            is_safe = False
        else:
            print(f"  ✅ 校验通过")
            final_response = raw_response
            is_safe = True

        # Step 7: 组装最终响应
        response = {
            "answer": final_response,
            "mode": user_context.current_mode,
            "is_safe": is_safe,
            "guard_result": guard_result,
            "sources": [
                {
                    "chunk_id": c.chunk_id,
                    "source": c.source,
                    "location": c.source_location,
                    "authority_score": c.authority_score
                }
                for c in final_chunks
            ],
            "token_usage": {
                "prompt_tokens": rendered.token_estimate,
                "completion_tokens": len(final_response) // 2,  # 粗略估算
                "total_tokens": rendered.token_estimate + len(final_response) // 2
            },
            "filter_stats": filter_result["total_reduction"]
        }

        # 更新历史
        self.renderer.add_to_history(user_context.user_question, final_response)

        return response

    def _build_rag_context(self, chunks: List[TextChunk]) -> RAGContext:
        """从过滤后的Chunk构建RAG上下文"""

        term_defs = []
        propositions = []
        text_chunks = []

        for chunk in chunks:
            # 根据chunk类型分类
            if chunk.layer == 1:
                # 术语定义
                term_defs.append(TermDefinition(
                    term=chunk.concept_mentions[0] if chunk.concept_mentions else "未知",
                    definition=chunk.text,
                    source_id=chunk.chunk_id,
                    equivalents=[],
                    misreadings=[]
                ))
            elif chunk.layer == 2 and chunk.logical_type:
                # 命题
                propositions.append(Proposition(
                    id=chunk.chunk_id,
                    text=chunk.text,
                    source=chunk.source,
                    location=chunk.source_location,
                    logical_type=chunk.logical_type
                ))
            else:
                # 阐释文本
                text_chunks.append(chunk)

        return RAGContext(
            term_definitions=term_defs,
            propositions=propositions,
            text_chunks=text_chunks,
            meta_rules=[
                {"rule": "坚持唯物史观", "description": "社会存在决定社会意识"},
                {"rule": "术语红线", "description": "严格使用正统术语定义"}
            ]
        )

    def _infer_logical_type(self, question: str) -> Optional[str]:
        """从问题推断逻辑类型"""
        if any(w in question for w in ["什么是", "什么意思", "定义"]):
            return "definition"
        elif any(w in question for w in ["为什么", "原因", "理由"]):
            return "explanation"
        elif any(w in question for w in ["关系", "联系", "区别"]):
            return "comparison"
        elif any(w in question for w in ["批判", "错误", "缺点"]):
            return "critique"
        return None


# ============================================================
# 3. 端到端演示
# ============================================================

def run_full_demo():
    """运行完整的端到端演示"""

    print("\n" + "="*70)
    print("正统马哲AI导师 — 端到端完整演示")
    print("="*70)

    # 初始化导师
    tutor = OrthodoxMarxismTutor()

    # ========== 演示1: 释义模式 ==========
    print("\n" + "="*70)
    print("演示 1/5: 释义模式（Explain）")
    print("="*70)

    ctx1 = UserContext(
        current_work="关于费尔巴哈的提纲",
        current_chapter="全文",
        selected_text="旧唯物主义的立脚点是市民社会",
        user_question="为什么说旧唯物主义的立脚点是市民社会？",
        current_mode="explain"
    )

    resp1 = tutor.chat(ctx1)
    print(f"\n【AI回答】\n{resp1['answer']}")
    print(f"\n【溯源】")
    for src in resp1['sources']:
        print(f"  📖 {src['chunk_id']} | {src['source']} | 权威分: {src['authority_score']}")
    print(f"\n【安全状态】: {'✅ 通过' if resp1['is_safe'] else '❌ 拦截'}")

    # ========== 演示2: 追问模式 ==========
    print("\n\n" + "="*70)
    print("演示 2/5: 追问模式（Dig）")
    print("="*70)

    ctx2 = UserContext(
        current_work="关于费尔巴哈的提纲",
        current_chapter="第一条",
        selected_text="从前的一切唯物主义的主要缺点是：对对象、现实、感性，只是从客体的或者直观的形式去理解",
        user_question="感性是什么意思？",
        current_mode="dig",
        session_history=[
            {"user": "感性是什么意思？", "assistant": "你认为'感性'在这里是什么意思？"}
        ]
    )

    resp2 = tutor.chat(ctx2)
    print(f"\n【AI追问】\n{resp2['answer']}")

    # ========== 演示3: 辩难模式 ==========
    print("\n\n" + "="*70)
    print("演示 3/5: 辩难模式（Debate）")
    print("="*70)

    ctx3 = UserContext(
        current_work="唯物主义和经验批判主义",
        current_chapter="第四章",
        selected_text="物质是标志客观实在的哲学范畴",
        user_question="如果物质只是感觉的复合，你怎么反驳？",
        current_mode="debate"
    )

    resp3 = tutor.chat(ctx3)
    print(f"\n【AI挑战】\n{resp3['answer']}")

    # ========== 演示4: 关联模式 ==========
    print("\n\n" + "="*70)
    print("演示 4/5: 关联模式（Connect）")
    print("="*70)

    ctx4 = UserContext(
        current_work="关于费尔巴哈的提纲",
        current_chapter="第十条",
        selected_text="市民社会",
        user_question="市民社会在整个体系中处于什么位置？",
        current_mode="connect"
    )

    resp4 = tutor.chat(ctx4)
    print(f"\n【知识图谱】\n{resp4['answer']}")

    # ========== 演示5: 应试模式 ==========
    print("\n\n" + "="*70)
    print("演示 5/5: 应试模式（Test）")
    print("="*70)

    ctx5 = UserContext(
        current_work="关于费尔巴哈的提纲",
        current_chapter="第十条",
        selected_text="旧唯物主义的立脚点是市民社会",
        user_question="如果考研考这句话，会怎么出题？",
        current_mode="test"
    )

    resp5 = tutor.chat(ctx5)
    print(f"\n【试题生成】\n{resp5['answer']}")

    # ========== 演示6: 安全拦截 ==========
    print("\n\n" + "="*70)
    print("演示 6/6: 安全拦截（偏离检测）")
    print("="*70)

    # 模拟一个会生成非正统内容的场景
    print("\n【模拟场景】用户诱导AI讨论'多元决定'")
    print("  用户问: 阿尔都塞的多元决定论怎么理解？")

    # 直接运行元规则引擎检测
    check = tutor.meta_engine.check_text("历史是由政治、经济、意识形态等多种因素共同决定的")
    print(f"\n  检测结果: {check['action']}")
    if check['flags']:
        for flag in check['flags']:
            print(f"    ⚠️ {flag['type']}: {flag.get('reason', '')}")

    fallback = tutor.renderer.render_fallback(
        "non_orthodox_concept", 
        concept="多元决定", 
        orthodox_equivalent="经济基础决定上层建筑"
    )
    print(f"\n【AI回复】\n{fallback}")

    # ========== 总结 ==========
    print("\n\n" + "="*70)
    print("演示总结")
    print("="*70)
    print("""
所有组件运行正常：
  ✅ 混合检索（向量+关键词+图）
  ✅ 五层过滤漏斗（概念→立场→语境→逻辑→权威）
  ✅ Prompt渲染引擎（模板+动态数据）
  ✅ LLM生成（模拟）
  ✅ 生成后立场校验
  ✅ 错误恢复Fallback

生产环境替换点：
  1. 将 MockLLM 替换为 OpenAI/Claude/国产大模型 API
  2. 将 mock_emb() 替换为 BGE-large-zh 实际Embedding
  3. 将内存检索替换为 Milvus + Neo4j 集群
  4. 扩充训练数据至 5000+ 条/类（BERT立场分类器）
    """)


if __name__ == "__main__":
    run_full_demo()
