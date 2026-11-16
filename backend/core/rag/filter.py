"""五层过滤漏斗 — RAG 检索结果精排

重构自原型 retrieval_filter_pipeline.py 的 FiveLayerFilter。
接入：
  - ConceptDictionary（新，修 P1-2）
  - OrthodoxyGuard.check_chunk（新，修 P0-2：区分批判引用 vs 宣扬）

向量召回（vector_search）依赖 pgvector，当前留接口；
  生产环境注入真实 embedding 后启用。MVP 阶段可先用关键词+图召回。
"""
from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any, Optional

from core.rag.concept_dict import ConceptDictionary
from core.guard.orthodoxy import OrthodoxyGuard

logger = logging.getLogger(__name__)


@dataclass
class TextChunk:
    """文本块（与 ORM model/models.py TextChunk 对齐的轻量版）"""
    chunk_id: str
    text: str
    source: str
    source_location: str
    layer: int                       # 1词条/2命题/3论证/4语境
    orthodoxy_tag: str               # 正统/经典原著/非正统/待审
    authority_score: float
    concept_mentions: list[str] = field(default_factory=list)
    logical_type: str = ""
    recall_score: float = 0.0        # 召回阶段给的相关性分（0—1，见 L5 说明）


@dataclass
class UserQuery:
    raw_text: str
    current_work: str
    current_chapter: str
    mode: str
    user_question: str
    key_concepts: list[str] = field(default_factory=list)
    logical_type_hint: Optional[str] = None


@dataclass
class FilterResult:
    chunk: TextChunk
    filter_scores: dict[str, float]
    final_score: float


LAYER_WEIGHTS = {
    "l1_concept": 0.20,
    "l2_orthodoxy": 0.30,   # 最重要
    "l3_context": 0.15,
    "l4_logic": 0.15,
    "l5_authority": 0.20,
}

# 召回相关性加分（D105 起，D127 上调 0.15→0.25）：五层只衡量「概念/立场/语境/逻辑/权威」，
# 完全不含「这段话是不是真的和问题相关」——于是「权威=1.0 的无关段落」
# 会压住「权威=0.85 但正是用户点名要查的那本书」。这里把召回分作为
# 第六项加分（权重 0.15，够压过 0.15 的权威差，又不至于翻盘高度相关的高权威段）。
RECALL_WEIGHT = 0.25


class FiveLayerFilter:
    """五层过滤漏斗：概念锁定→立场校验→语境匹配→逻辑兼容→权威排序"""

    # 同一著作最多占几席：一本书的分片往往连着讲同一件事，不设上限时
    # 前五条常常整段取自同一本书（《论列宁主义基础》能把五席全占），
    # 用户问「农民问题在中国革命中的地位」就只看到一本，看不到《湖南农民运动考察报告》。
    MAX_PER_SOURCE = 2

    def __init__(self, concept_dict: Optional[ConceptDictionary] = None,
                 guard: Optional[OrthodoxyGuard] = None,
                 max_per_source: int = 2) -> None:
        self.concept_dict = concept_dict or ConceptDictionary()
        self.guard = guard or OrthodoxyGuard()
        self.max_per_source = max_per_source

    def filter(self, query: UserQuery, chunks: list[TextChunk], top_k: int = 5) -> dict[str, Any]:
        c1, _ = self._l1_concept_lock(query, chunks)
        c2, s2 = self._l2_orthodoxy_guard(query, c1)
        c3, _ = self._l3_context_match(query, c2)
        c4, _ = self._l4_logic_compat(query, c3)
        final, s5 = self._l5_authority_rank(query, c4, top_k)
        return {
            "final_results": final,
            "layer_stats": {"L1": len(c1), "L2": len(c2), "L3": len(c3), "L4": len(c4), "L5": len(final)},
            "l2_blocked": s2.get("blocked", []),
            "total_reduction": f"{len(chunks)} → {len(final)}",
        }

    # L1: 概念锁定
    def _l1_concept_lock(self, query: UserQuery, chunks: list[TextChunk]) -> tuple[list[TextChunk], dict]:
        qc = set(query.key_concepts)
        if not qc:
            # 问题里抽不出概念（如「金融资本 银行 产业资本」这类纯主题词）：
            # 没有可锁定的概念，L1 不设卡（旧行为是把全部候选概念并进 query 再求交，
            # 分母被撑大、结果是「概念越多越占便宜」，反而压住真正相关的段落）。
            for c in chunks:
                c._l1 = 1.0
            return chunks, {"input": len(chunks), "output": len(chunks), "query_concepts": []}
        kept = []
        for c in chunks:
            cc = set(c.concept_mentions) | set(self.concept_dict.extract_concepts(c.text))
            overlap = qc & cc
            if overlap:
                c._l1 = len(overlap) / max(len(qc), 1)
                kept.append(c)
        return kept, {"input": len(chunks), "output": len(kept), "query_concepts": list(qc)}

    # L2: 立场校验（P0-2 修复：check_chunk 区分批判引用 vs 宣扬）
    def _l2_orthodoxy_guard(self, query: UserQuery, chunks: list[TextChunk]) -> tuple[list[TextChunk], dict]:
        kept = []
        blocked = []
        for c in chunks:
            r = self.guard.check_chunk(c.text, c.orthodoxy_tag)
            if r["action"] == "block":
                blocked.append({"chunk_id": c.chunk_id, "reason": r["reason"]})
                continue
            # demote 的 chunk 保留但降权
            score = c.authority_score
            if c.orthodoxy_tag == "经典原著":
                score = 1.0
            elif c.orthodoxy_tag == "正统":
                score = max(score, 0.9)
            if r["action"] == "demote":
                score *= 0.6  # 批判术语无语境 → 降权
            c._l2 = score
            kept.append(c)
        return kept, {"input": len(chunks), "output": len(kept), "blocked": blocked[:5]}

    # L3: 语境匹配
    def _l3_context_match(self, query: UserQuery, chunks: list[TextChunk]) -> tuple[list[TextChunk], dict]:
        # 简化关联矩阵（生产环境可外置配置）
        relations = {
            "关于费尔巴哈的提纲": {"德意志意识形态": 1.0, "辩证唯物主义历史唯物主义": 0.7},
            "德意志意识形态": {"关于费尔巴哈的提纲": 1.0, "资本论第一卷": 0.7},
        }
        for c in chunks:
            if not query.current_work:
                # 前端没告诉我们在读哪本书（绝大多数提问都是这样）：
                # 不设语境先验。旧行为是把 current_work 硬编码成《关于费尔巴哈的提纲》，
                # 结果该书全部段落白得 +0.105，与问题无关也能挤进前五。
                c._l3 = 0.6
            elif c.source == query.current_work:
                c._l3 = 1.0
            elif query.current_work in relations and c.source in relations[query.current_work]:
                c._l3 = relations[query.current_work][c.source]
            elif "基本原理" in c.source or "教科书" in c.source:
                c._l3 = 0.5
            else:
                c._l3 = 0.3
        return chunks, {"input": len(chunks), "output": len(chunks)}

    # L4: 逻辑兼容
    def _l4_logic_compat(self, query: UserQuery, chunks: list[TextChunk]) -> tuple[list[TextChunk], dict]:
        compat = {
            "definition": ["definition", "proposition", "explanation"],
            "critique": ["critique", "comparison", "analysis"],
            "determination": ["determination", "causation"],
        }
        ql = query.logical_type_hint
        for c in chunks:
            cl = c.logical_type
            if not ql or not cl:
                c._l4 = 0.6
            elif cl == ql:
                c._l4 = 1.0
            elif ql in compat and cl in compat[ql]:
                c._l4 = 0.8
            else:
                c._l4 = 0.4
        return chunks, {"input": len(chunks), "output": len(chunks)}

    # L5: 权威排序
    def _l5_authority_rank(self, query: UserQuery, chunks: list[TextChunk], top_k: int) -> tuple[list[FilterResult], dict]:
        results = []
        for c in chunks:
            l1 = getattr(c, "_l1", 0.5)
            l2 = getattr(c, "_l2", 0.5)
            l3 = getattr(c, "_l3", 0.5)
            l4 = getattr(c, "_l4", 0.5)
            l5 = c.authority_score
            recall = max(0.0, min(1.0, c.recall_score))
            final = (
                LAYER_WEIGHTS["l1_concept"] * l1 +
                LAYER_WEIGHTS["l2_orthodoxy"] * l2 +
                LAYER_WEIGHTS["l3_context"] * l3 +
                LAYER_WEIGHTS["l4_logic"] * l4 +
                LAYER_WEIGHTS["l5_authority"] * l5 +
                RECALL_WEIGHT * recall
            )
            results.append(FilterResult(
                c, {"l1": l1, "l2": l2, "l3": l3, "l4": l4, "l5": l5, "recall": recall}, final))
        # 平手时按召回分再按 chunk_id：sort 是稳定排序，不设次级键等于让
        # 「哪本书先入库」决定名次（最早入库的几本会一直霸榜）。
        results.sort(key=lambda x: (-x.final_score, -x.chunk.recall_score, x.chunk.chunk_id))
        picked: list[FilterResult] = []
        per_source: dict[str, int] = {}
        overflow: list[FilterResult] = []
        for r in results:
            src = (r.chunk.source or "").strip()
            if self.max_per_source > 0 and per_source.get(src, 0) >= self.max_per_source:
                overflow.append(r)
                continue
            per_source[src] = per_source.get(src, 0) + 1
            picked.append(r)
            if len(picked) >= top_k:
                break
        # 候选池几乎全来自同一本书（只有 1—2 条不同来源）时，宁肯少给几条
        # 也要补到 3 条，免得对话拿到「一本书的两个段落」当唯二依据。
        floor = min(top_k, 3)
        while len(picked) < floor and overflow:
            picked.append(overflow.pop(0))
        return picked, {"input": len(chunks), "output": len(picked)}
