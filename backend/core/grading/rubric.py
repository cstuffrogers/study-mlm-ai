"""评分基准卡 — 按题预生成、缓存复用。

基准卡锚定权威数据（原文分片 + 核心术语 + 常见误用 + 标准解析 + 踩分点），
供 LLM 评分对照打分，保证评分口径与马列毛权威表述零偏差。
基准卡内容不随作答变化，按题缓存：同题多次作答（重做、不同用户）复用，
省 prompt 组装与 token 消耗。
"""
from __future__ import annotations

import re
from functools import lru_cache

from content.book_chunks import retrievable_chunks
from content.concept_keywords import terms_for, misconceptions_for


@lru_cache(maxsize=1)
def _chunk_index() -> dict[str, dict]:
    """chunk_id -> chunk dict，进程内只构建一次（22377 分片，避免逐题遍历）。"""
    return {c["id"]: c for c in retrievable_chunks()}


def _extract_rubric_points(
    source_text: str, explanation: str, terms: list[str]
) -> list[str]:
    """从原文与解析中提取踩分点清单。

    取包含核心术语的句子作为要点，让 LLM 对照逐条判断覆盖/准确/遗漏，
    从"凭感觉打分"变"对照清单打分"，精度提升且可解释。
    """
    points: list[str] = []
    # 原文中含核心术语的句子
    if source_text:
        for sent in re.split(r"[。；\n]", source_text):
            sent = sent.strip()
            if sent and any(t in sent for t in terms):
                points.append(f"原文要点：{sent[:80]}")
    # 解析中的关键句（≥8 字，非空）
    for sent in re.split(r"[。；\n]", explanation or ""):
        sent = sent.strip()
        if sent and len(sent) >= 8:
            points.append(f"解析要点：{sent[:80]}")
    # 去重（按前 20 字），限 6 条
    seen: set[str] = set()
    unique: list[str] = []
    for p in points:
        key = p[:20]
        if key not in seen:
            seen.add(key)
            unique.append(p)
        if len(unique) >= 6:
            break
    return unique or ["对照标准解析判断要点覆盖"]


@lru_cache(maxsize=256)
def build_rubric_card(
    node_id: str, source_chunk_id: str, explanation: str
) -> dict:
    """生成评分基准卡，按题缓存（不随作答变化）。

    原文分片取自 source_chunk_id（CH-XXX 对应原著，GUIDE-XXX 导读题取不到
    原文则留空，以 explanation 为参照）。
    """
    terms = terms_for([node_id])
    misconceptions = misconceptions_for([node_id])
    chunk_idx = _chunk_index()
    chunk = chunk_idx.get(source_chunk_id or "")
    source_text = (chunk or {}).get("text", "") or ""
    rubric_points = _extract_rubric_points(source_text, explanation, terms)
    return {
        "node_id": node_id,
        "source_chunk_id": source_chunk_id,
        "source_text": source_text,
        "terms": terms,
        "misconceptions": misconceptions,
        "explanation": explanation,
        "rubric_points": rubric_points,
    }
