#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
正统马哲AI导师 — Prompt渲染引擎
================================
将YAML配置的Prompt模板与动态数据（RAG检索结果、用户上下文）结合，
生成可直接送入LLM的最终Prompt。

核心功能：
1. 模板渲染（Handlebars风格变量替换）
2. 上下文窗口管理（Token预算分配）
3. 多轮会话历史注入
4. 模式切换时的Prompt热切换
5. 生成后自检触发
"""

import os
import re
import yaml
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass, field
from collections import deque
import json

# ============================================================
# 1. 数据模型
# ============================================================

@dataclass
class TermDefinition:
    """术语定义"""
    term: str
    definition: str
    source_id: str
    equivalents: List[str] = field(default_factory=list)
    misreadings: List[str] = field(default_factory=list)

@dataclass
class Proposition:
    """哲学命题"""
    id: str
    text: str
    source: str
    location: str
    logical_type: str

@dataclass
class TextChunk:
    """文本块"""
    chunk_id: str
    text: str
    source: str
    source_location: str
    authority_score: float

@dataclass
class RAGContext:
    """RAG检索返回的完整上下文"""
    term_definitions: List[TermDefinition]
    propositions: List[Proposition]
    text_chunks: List[TextChunk]
    meta_rules: List[Dict[str, str]]

@dataclass
class UserContext:
    """用户会话上下文"""
    current_work: str
    current_chapter: str
    selected_text: str
    user_question: str
    current_mode: str  # explain/dig/debate/connect/test
    session_history: List[Dict[str, str]] = field(default_factory=list)

@dataclass
class RenderedPrompt:
    """渲染后的最终Prompt"""
    system_prompt: str
    user_prompt: str
    full_prompt: str
    token_estimate: int
    context_injection_summary: Dict[str, Any]


# ============================================================
# 2. Prompt渲染引擎
# ============================================================

class PromptRenderer:
    """
    Prompt渲染引擎
    负责将模板 + 数据 → 最终LLM输入
    """

    def __init__(self, prompt_yaml_path: str):
        """
        初始化渲染引擎

        Args:
            prompt_yaml_path: prompt_engineering.yaml 文件路径
        """
        with open(prompt_yaml_path, 'r', encoding='utf-8') as f:
            self.config = yaml.safe_load(f)

        self.system_prompt_template = self.config['system_prompt']
        self.modes = self.config['modes']
        self.context_assembly_template = self.config['context_assembly']['template']
        self.guard_prompt = self.config['guard_prompt']
        self.self_check_prompt = self.config['self_check_prompt']
        self.fallback_prompts = self.config['fallback_prompts']
        self.special_scenarios = self.config['special_scenarios']

        # Token预算配置（基于GPT-4的8K上下文）
        self.token_budget = {
            "system": 800,           # 系统Prompt
            "context_layer1": 400,   # 术语层
            "context_layer2": 600,   # 命题层
            "context_layer3": 1200,  # 阐释层
            "context_layer5": 300,   # 元规则层
            "user_context": 200,     # 用户上下文
            "history": 1000,         # 多轮历史
            "response": 800,         # AI回复预留
            "buffer": 200,           # 缓冲
        }
        self.max_total_tokens = 8000

        # 多轮会话历史（滑动窗口）
        self.session_history = deque(maxlen=10)

    # --------------------------------------------------
    # 2.1 基础模板渲染（Handlebars风格）
    # --------------------------------------------------
    def _render_template(self, template: str, variables: Dict[str, Any]) -> str:
        """
        简单的模板渲染器
        支持 {{variable}} 和 {{#each}} 语法
        """
        result = template

        # 处理 {{#each}} 循环
        def render_each(match):
            full_match = match.group(0)
            var_name = match.group(1).strip()
            inner_template = match.group(2)

            if var_name not in variables or not variables[var_name]:
                return ""

            items = variables[var_name]
            rendered_items = []
            for item in items:
                item_str = inner_template
                # 替换 this.field
                if isinstance(item, dict):
                    for key, value in item.items():
                        placeholder = f"{{{{this.{key}}}}}"
                        item_str = item_str.replace(placeholder, str(value))
                rendered_items.append(item_str)

            return "\n".join(rendered_items)

        # 匹配 {{#each var}} ... {{/each}}
        result = re.sub(
            r'\{\{#each\s+(\w+)\}\}(.*?)\{\{/each\}\}',
            render_each,
            result,
            flags=re.DOTALL
        )

        # 处理简单变量 {{variable}}
        for key, value in variables.items():
            if isinstance(value, str):
                result = result.replace(f"{{{{{key}}}}}", value)
            elif isinstance(value, list):
                # 跳过列表（已在each中处理）
                pass

        # 清理未替换的变量
        result = re.sub(r'\{\{[^}]+\}\}', '', result)

        return result

    # --------------------------------------------------
    # 2.2 Token估算（中文字符特殊处理）
    # --------------------------------------------------
    def _estimate_tokens(self, text: str) -> int:
        """
        估算Token数
        中文：1字 ≈ 1.5 tokens
        英文：1词 ≈ 1.3 tokens
        """
        chinese_chars = len(re.findall(r'[\u4e00-\u9fff]', text))
        english_words = len(re.findall(r'[a-zA-Z]+', text))
        other_chars = len(text) - chinese_chars - sum(len(w) for w in re.findall(r'[a-zA-Z]+', text))

        return int(chinese_chars * 1.5 + english_words * 1.3 + other_chars * 0.5)

    # --------------------------------------------------
    # 2.3 上下文截断（按优先级）
    # --------------------------------------------------
    def _truncate_context(self, rag_context: RAGContext, budget: int) -> RAGContext:
        """
        当上下文超出Token预算时，按优先级截断

        优先级：
        1. 术语定义（Layer 1）— 绝不截断
        2. 命题（Layer 2）— 尽量不截断
        3. 阐释文本（Layer 3-4）— 按authority_score排序截断
        4. 元规则（Layer 5）— 压缩为摘要
        """
        current_tokens = 0

        # Layer 1: 术语定义（全保留）
        layer1_tokens = sum(self._estimate_tokens(t.definition) for t in rag_context.term_definitions)
        current_tokens += layer1_tokens

        # Layer 2: 命题（全保留）
        layer2_tokens = sum(self._estimate_tokens(p.text) for p in rag_context.propositions)
        current_tokens += layer2_tokens

        # Layer 5: 元规则（压缩为摘要）
        if current_tokens + 200 > budget:
            # 紧急压缩：只保留最关键的红线
            rag_context.meta_rules = [r for r in rag_context.meta_rules if r.get('critical', False)]
            if not rag_context.meta_rules:
                rag_context.meta_rules = [{"rule": "坚持正统立场", "description": "所有回答必须符合辩证唯物主义与历史唯物主义"}]

        layer5_tokens = sum(self._estimate_tokens(r['rule'] + r['description']) for r in rag_context.meta_rules)
        current_tokens += layer5_tokens

        # Layer 3-4: 阐释文本（按authority_score排序，保留高分）
        remaining_budget = budget - current_tokens
        sorted_chunks = sorted(rag_context.text_chunks, key=lambda x: x.authority_score, reverse=True)

        kept_chunks = []
        for chunk in sorted_chunks:
            chunk_tokens = self._estimate_tokens(chunk.text)
            if remaining_budget - chunk_tokens >= 0:
                kept_chunks.append(chunk)
                remaining_budget -= chunk_tokens
            else:
                break

        return RAGContext(
            term_definitions=rag_context.term_definitions,
            propositions=rag_context.propositions,
            text_chunks=kept_chunks,
            meta_rules=rag_context.meta_rules
        )

    # --------------------------------------------------
    # 2.4 系统Prompt渲染
    # --------------------------------------------------
    def _render_system_prompt(self, user_context: UserContext) -> str:
        """渲染系统Prompt"""
        variables = {
            "current_work": user_context.current_work,
            "current_chapter": user_context.current_chapter,
            "current_mode": user_context.current_mode,
        }
        return self._render_template(self.system_prompt_template, variables)

    # --------------------------------------------------
    # 2.5 模式Prompt叠加
    # --------------------------------------------------
    def _render_mode_prompt(self, mode: str) -> str:
        """渲染模式级Prompt叠加"""
        if mode not in self.modes:
            return ""
        return self.modes[mode]['prompt_addition']

    # --------------------------------------------------
    # 2.6 上下文组装渲染
    # --------------------------------------------------
    def _render_context_assembly(self, rag_context: RAGContext) -> str:
        """渲染RAG检索上下文"""
        variables = {
            "term_definitions": [
                {
                    "term": t.term,
                    "definition": t.definition,
                    "source_id": t.source_id,
                    "equivalents": ", ".join(t.equivalents) if t.equivalents else "无",
                    "misreadings": "; ".join(t.misreadings) if t.misreadings else "无"
                }
                for t in rag_context.term_definitions
            ],
            "propositions": [
                {
                    "id": p.id,
                    "text": p.text,
                    "source": p.source,
                    "location": p.location,
                    "logical_type": p.logical_type
                }
                for p in rag_context.propositions
            ],
            "text_chunks": [
                {
                    "chunk_id": c.chunk_id,
                    "text": c.text,
                    "source": c.source,
                    "source_location": c.source_location,
                    "authority_score": c.authority_score
                }
                for c in rag_context.text_chunks
            ],
            "meta_rules": rag_context.meta_rules
        }
        return self._render_template(self.context_assembly_template, variables)

    # --------------------------------------------------
    # 2.7 多轮历史渲染
    # --------------------------------------------------
    def _render_history(self, history: List[Dict[str, str]], max_tokens: int = 1000) -> str:
        """
        渲染多轮会话历史
        采用"摘要+最近3轮完整"策略
        """
        if not history:
            return ""

        # 最近3轮完整保留
        recent = history[-3:]

        # 更早的轮次压缩为摘要
        older = history[:-3] if len(history) > 3 else []

        parts = []

        if older:
            parts.append("【前文摘要】")
            for i, turn in enumerate(older):
                parts.append(f"  轮{i+1}: 用户问{turn['user'][:30]}... → AI答{turn['assistant'][:30]}...")

        if recent:
            parts.append("【最近对话】")
            for turn in recent:
                parts.append(f"用户: {turn['user']}")
                parts.append(f"AI: {turn['assistant']}")

        history_text = "\n".join(parts)

        # 如果仍超预算，只保留最近1轮
        if self._estimate_tokens(history_text) > max_tokens:
            if recent:
                history_text = f"【最近对话】\n用户: {recent[-1]['user']}\nAI: {recent[-1]['assistant']}"
            else:
                history_text = ""

        return history_text

    # --------------------------------------------------
    # 2.8 主渲染函数
    # --------------------------------------------------
    def render(self, user_context: UserContext, rag_context: RAGContext) -> RenderedPrompt:
        """
        主渲染入口

        Args:
            user_context: 用户会话上下文
            rag_context: RAG检索结果

        Returns:
            RenderedPrompt: 渲染后的完整Prompt
        """
        # Step 1: 计算可用Token预算
        available_budget = self.max_total_tokens - self.token_budget["response"] - self.token_budget["buffer"]

        # Step 2: 渲染系统Prompt
        system_prompt = self._render_system_prompt(user_context)
        system_tokens = self._estimate_tokens(system_prompt)

        # Step 3: 叠加模式Prompt
        mode_prompt = self._render_mode_prompt(user_context.current_mode)
        if mode_prompt:
            system_prompt += "\n\n" + mode_prompt
            system_tokens = self._estimate_tokens(system_prompt)

        # Step 4: 计算上下文预算
        context_budget = available_budget - system_tokens - self.token_budget["user_context"] - self.token_budget["history"]

        # Step 5: 截断上下文（如果需要）
        if context_budget < 1000:
            # 紧急：压缩系统Prompt
            system_prompt = system_prompt[:500] + "...[系统指令压缩]"
            system_tokens = self._estimate_tokens(system_prompt)
            context_budget = available_budget - system_tokens - self.token_budget["user_context"] - self.token_budget["history"]

        truncated_rag = self._truncate_context(rag_context, context_budget)

        # Step 6: 渲染上下文
        context_text = self._render_context_assembly(truncated_rag)

        # Step 7: 渲染用户上下文
        user_context_text = f"""
当前阅读著作：{user_context.current_work}
当前章节：{user_context.current_chapter}
选中原文：{user_context.selected_text}
用户问题：{user_context.user_question}
会话模式：{user_context.current_mode}
"""

        # Step 8: 渲染历史
        history_text = self._render_history(user_context.session_history)

        # Step 9: 组装完整Prompt
        full_prompt = f"""{system_prompt}

{context_text}

{history_text}

{user_context_text}

【自检指令】
{self.self_check_prompt}

请回答用户问题。"""

        # Step 10: 计算总Token
        total_tokens = self._estimate_tokens(full_prompt)

        # Step 11: 生成摘要
        injection_summary = {
            "system_tokens": system_tokens,
            "context_tokens": self._estimate_tokens(context_text),
            "history_tokens": self._estimate_tokens(history_text),
            "user_context_tokens": self._estimate_tokens(user_context_text),
            "total_tokens": total_tokens,
            "term_definitions_count": len(truncated_rag.term_definitions),
            "propositions_count": len(truncated_rag.propositions),
            "text_chunks_count": len(truncated_rag.text_chunks),
            "truncated": len(rag_context.text_chunks) != len(truncated_rag.text_chunks)
        }

        return RenderedPrompt(
            system_prompt=system_prompt,
            user_prompt=user_context_text,
            full_prompt=full_prompt,
            token_estimate=total_tokens,
            context_injection_summary=injection_summary
        )

    # --------------------------------------------------
    # 2.9 生成后校验Prompt渲染
    # --------------------------------------------------
    def render_guard_prompt(self, generated_text: str, retrieved_context: str) -> str:
        """
        渲染生成后校验Prompt
        用于第二层防线
        """
        variables = {
            "generated_text": generated_text,
            "retrieved_context": retrieved_context
        }
        return self._render_template(self.guard_prompt, variables)

    # --------------------------------------------------
    # 2.10 Fallback Prompt渲染
    # --------------------------------------------------
    def render_fallback(self, scenario: str, **kwargs) -> str:
        """
        渲染错误恢复Prompt

        Args:
            scenario: fallback场景名称
            **kwargs: 场景特定变量
        """
        if scenario in self.fallback_prompts:
            return self._render_template(self.fallback_prompts[scenario], kwargs)
        elif scenario in self.special_scenarios:
            return self._render_template(self.special_scenarios[scenario], kwargs)
        else:
            return "系统遇到未知错误，请重新提问。"

    # --------------------------------------------------
    # 2.11 会话历史管理
    # --------------------------------------------------
    def add_to_history(self, user_message: str, assistant_message: str):
        """添加一轮对话到历史"""
        self.session_history.append({
            "user": user_message,
            "assistant": assistant_message
        })

    def clear_history(self):
        """清空历史"""
        self.session_history.clear()


# ============================================================
# 3. 使用示例
# ============================================================

def demo_render():
    """渲染引擎演示"""

    # 初始化渲染器
    renderer = PromptRenderer("./prompt_engineering.yaml")

    # 构建RAG上下文（模拟检索结果）
    rag_context = RAGContext(
        term_definitions=[
            TermDefinition(
                term="市民社会",
                definition="在马克思历史唯物主义语境中，指与政治国家相对的物质生活关系总和，是资产阶级社会的同义语。",
                source_id="CH-TEXTBOOK-2023-002-010",
                equivalents=["资产阶级社会", "经济基础"],
                misreadings=["民间社会", "非政府组织", "公民社会（现代政治学含义）"]
            ),
            TermDefinition(
                term="旧唯物主义",
                definition="指马克思主义产生之前的唯物主义，包括古代朴素唯物主义和近代形而上学唯物主义（机械唯物主义），其代表人物有费尔巴哈等。",
                source_id="CH-TEXTBOOK-2023-001-002",
                equivalents=["形而上学唯物主义", "机械唯物主义"],
                misreadings=["所有唯物主义", "包括辩证唯物主义"]
            )
        ],
        propositions=[
            Proposition(
                id="PROP-ME-TH-001-010",
                text="旧唯物主义的立脚点是市民社会，新唯物主义的立脚点则是人类社会或社会的人类。",
                source="关于费尔巴哈的提纲",
                location="第十条",
                logical_type="determination"
            )
        ],
        text_chunks=[
            TextChunk(
                chunk_id="CH-AISHI-1961-003-015",
                text="马克思在《提纲》第十条中指出，旧唯物主义的立脚点是市民社会。这就是说，旧唯物主义不自觉地站在了资产阶级意识形态的立场上，因为他们把抽象的、孤立的个人作为出发点，而这个个人正是资本主义市民社会的产物。",
                source="辩证唯物主义历史唯物主义",
                source_location="第三章",
                authority_score=0.95
            ),
            TextChunk(
                chunk_id="CH-ME-DE-001-008",
                text="市民社会这一名称始终标志着直接从生产和交往中发展起来的社会组织，这种社会组织在一切时代都构成国家的基础以及任何其他的观念的上层建筑的基础。",
                source="德意志意识形态",
                source_location="第一章",
                authority_score=1.0
            )
        ],
        meta_rules=[
            {"rule": "坚持唯物史观", "description": "社会存在决定社会意识，经济基础决定上层建筑"},
            {"rule": "术语红线", "description": "市民社会不等于公民社会或民间社会"}
        ]
    )

    # 构建用户上下文
    user_context = UserContext(
        current_work="关于费尔巴哈的提纲",
        current_chapter="全文",
        selected_text="旧唯物主义的立脚点是市民社会",
        user_question="为什么说旧唯物主义的立脚点是市民社会？",
        current_mode="explain",
        session_history=[]
    )

    # 执行渲染
    rendered = renderer.render(user_context, rag_context)

    # 输出结果
    print("="*70)
    print("Prompt渲染引擎 — 输出演示")
    print("="*70)

    print("\n【Token预算分配】")
    for key, value in rendered.context_injection_summary.items():
        print(f"  {key}: {value}")

    print(f"\n【系统Prompt预览】（前500字）")
    print("-"*50)
    print(rendered.system_prompt[:500])

    print(f"\n\n【完整Prompt预览】（前1500字）")
    print("-"*50)
    print(rendered.full_prompt[:1500])
    print("...")

    print(f"\n\n【总Token估算】: {rendered.token_estimate}")
    print(f"【是否截断】: {rendered.context_injection_summary['truncated']}")

    # 演示生成后校验
    print("\n" + "="*70)
    print("生成后校验Prompt演示")
    print("="*70)

    sample_generation = "市民社会就是公民社会，是现代民主政治的基础。"
    guard = renderer.render_guard_prompt(sample_generation, "")
    print(f"\n【待校验文本】: {sample_generation}")
    print(f"\n【校验Prompt】（前800字）:")
    print(guard[:800])

    # 演示Fallback
    print("\n" + "="*70)
    print("Fallback Prompt演示")
    print("="*70)

    fallback = renderer.render_fallback("non_orthodox_concept", concept="多元决定", orthodox_equivalent="经济基础决定上层建筑")
    print(fallback)


if __name__ == "__main__":
    demo_render()
