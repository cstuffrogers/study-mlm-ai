"""混合召回器 — 向量 + 图 + 关键词三路

三路召回 + 合并去重 + FiveLayerFilter 精排 → RAGContext。

实现策略（可切换）：
  - 向量召回：默认 InMemoryVectorStore（字符 n-gram 哈希 + 余弦）；
    Docker 起来后注入 PgvectorStore（embed API + pgvector）
  - 图召回：默认 InMemoryGraphStore（概念→关联 chunk 的邻接表）；
    Docker 起来后注入 Neo4jGraphStore
  - 关键词召回：ConceptDictionary 子串/分词匹配（已有，fallback）

接口 stable：dialogue_service 只调 retrieve()，不感知底层 store。
切真实实现只需替换构造参数。
"""
from __future__ import annotations

import hashlib
import logging
import math
import re
from array import array
from dataclasses import dataclass
from typing import Any, Optional

from core.rag.concept_dict import ConceptDictionary
from core.rag.filter import FiveLayerFilter, TextChunk as FilterChunk, UserQuery
from core.prompt.renderer import RAGContext, TextChunk, TermDefinition, Proposition

logger = logging.getLogger(__name__)


# ============================================================
# 向量存储抽象 + 两个实现
# ============================================================
class VectorStore:
    """向量召回接口"""
    def upsert(self, chunk_id: str, text: str) -> None: ...
    def search(self, query: str, top_k: int = 10) -> list[tuple[str, float]]:
        """返回 [(chunk_id, score)]"""
        raise NotImplementedError


def _hash_vec(text: str, dim: int = 256) -> list[float]:
    """字符 3-gram 哈希向量（in-memory 近似语义召回，无需 embedding API）"""
    vec = [0.0] * dim
    cleaned = re.sub(r"\s+", "", text)
    for i in range(len(cleaned) - 2):
        gram = cleaned[i:i+3]
        h = int(hashlib.md5(gram.encode()).hexdigest(), 16) % dim
        sign = 1.0 if (h % 2 == 0) else -1.0
        vec[h] += sign
    norm = math.sqrt(sum(v*v for v in vec)) or 1.0
    return [v / norm for v in vec]


def _cosine(a: list[float], b: list[float]) -> float:
    return sum(x*y for x, y in zip(a, b))


def _trigrams(text: str) -> set[str]:
    """去空白后的字符 3-gram 集合（书名召回的重合度用）"""
    cleaned = re.sub(r"\s+", "", text or "")
    return {cleaned[i:i+3] for i in range(len(cleaned) - 2)}


def _bigrams(text: str) -> list[str]:
    """去空白后的字符 2-gram 序列（词法召回用；保留重复以算词频）"""
    cleaned = re.sub(r"[\s\u3000]+", "", text or "")
    return [cleaned[i:i+2] for i in range(len(cleaned) - 1)]


class LexicalIndex:
    """字符 2-gram 倒排 + BM25——无 embedding 时的词法召回

    为什么要这一层：`InMemoryVectorStore` 用 3-gram 哈希向量，把 256 维里的
    碰撞当相似度，余弦只反映「共享了多少常见字串」——长分片（手稿、教科书）
    天然占便宜，问「九月来信讲了什么」会召回《无政府主义还是社会主义？》。
    向量层在没接真 embedding 之前无法区分「字串常见」与「内容相关」。

    BM25 把这补上：按 **逆文档频率** 加权（「什么」「必须」这类高 DF 二元组
    直接剔除）、按 **分片长度** 归一（短分片命中同等的词不被长分片压住）。
    这是标准检索做法，不针对任何具体问句写规则。
    """

    def __init__(self, max_df_ratio: float = 0.02, k1: float = 1.2, b: float = 0.75) -> None:
        self.max_df_ratio = max_df_ratio
        self.k1 = k1
        self.b = b
        self._raw: dict[str, array] = {}      # gram → 分片序号（含重复，算 tf）
        self._lens: list[int] = []            # 分片序号 → 词数（去空白字符数）
        self._rank: dict[str, tuple[array, float]] = {}  # gram → (去重升序序号, idf)
        self._avgdl = 0.0
        self._n = 0

    def add(self, idx: int, text: str) -> None:
        grams = _bigrams(text)
        self._lens.append(len(grams))
        for g in grams:
            self._raw.setdefault(g, array("i")).append(idx)

    def finalize(self) -> None:
        """剪掉高 DF 二元组（无区分度）并预算 idf"""
        self._n = len(self._lens)
        if not self._n:
            return
        self._avgdl = sum(self._lens) / self._n or 1.0
        max_df = max(2, int(self.max_df_ratio * self._n))
        for g, arr in self._raw.items():
            uniq = array("i")
            prev = -1
            for v in arr:
                if v != prev:
                    uniq.append(v)
                    prev = v
            df = len(uniq)
            # 按「出现在几个分片」剪，不按出现次数剪：某本书把某个词重复五百遍，
            # 按次数算会把它当高频停用词剪掉，恰恰丢掉最能定位这本书的那个词。
            if df > max_df:
                continue
            idf = math.log(1.0 + (self._n - df + 0.5) / (df + 0.5))
            self._rank[g] = (uniq, idf)
        # 保留原始倒排：允许调 max_df_ratio 后重新 finalize（内存约 20MB）

    def search(self, query: str, top_k: int = 10) -> list[tuple[int, float]]:
        """→ [(分片序号, BM25 分)]，分未归一化"""
        if not self._rank:
            return []
        scores: dict[int, float] = {}
        lens = self._lens
        avgdl = self._avgdl or 1.0
        k1, b = self.k1, self.b
        for g in set(_bigrams(query)):
            entry = self._rank.get(g)
            if entry is None:
                continue
            arr, idf = entry
            for idx in arr:
                dl = lens[idx] or 1
                tf = 1.0  # 分片级出现即算一次（多次出现在短分片里已由长度归一体现）
                scores[idx] = scores.get(idx, 0.0) + idf * tf * (k1 + 1.0) / (
                    tf + k1 * (1.0 - b + b * dl / avgdl)
                )
        if not scores:
            return []
        ranked = sorted(scores.items(), key=lambda x: -x[1])[:top_k]
        return ranked


_PAREN_TAIL = re.compile(r"[（(][^）)]*[）)]\s*$")


def _work_aliases(work: str) -> set[str]:
    """著作名 → 可被 query 直接命中的别名

    只收全名与「去掉末尾括注」的短名（如 `金融资本（节选）` → `金融资本`），
    且要求短名 ≥4 字：`资本论（第一卷节选）` 的短名只有 3 字，故不参与书名召回，
    避免「资本论」三个字把第二、三卷全部拽进候选池。
    """
    out = {work}
    short = _PAREN_TAIL.sub("", work).strip()
    if len(short) >= 4:
        out.add(short)
    return {a for a in out if len(a) >= 4}


class InMemoryVectorStore(VectorStore):
    """内存向量召回——3-gram 哈希 + 余弦相似。

    无外部依赖，单测/轻量模式用。语义近似度有限（字符级），
    生产替换 PgvectorStore + embedding API。
    """
    def __init__(self, dim: int = 256) -> None:
        self.dim = dim
        self._vecs: dict[str, list[float]] = {}

    def upsert(self, chunk_id: str, text: str) -> None:
        self._vecs[chunk_id] = _hash_vec(text, self.dim)

    def search(self, query: str, top_k: int = 10) -> list[tuple[str, float]]:
        if not self._vecs:
            return []
        qv = _hash_vec(query, self.dim)
        scored = [(cid, _cosine(qv, v)) for cid, v in self._vecs.items()]
        scored.sort(key=lambda x: x[1], reverse=True)
        return scored[:top_k]


class PgvectorStore(VectorStore):
    """pgvector 向量召回——Docker 集成后启用。

    依赖：embedding API（EMBED_API_KEY）+ pgvector 扩展。
    当前留接口骨架，注入 session + embed client 后实现。
    """
    def __init__(self, session_factory=None, embed_client=None) -> None:
        self.session_factory = session_factory
        self.embed_client = embed_client
        if not (session_factory and embed_client):
            logger.warning("PgvectorStore 未配齐 session/embed_client，召回返回空")

    async def upsert(self, chunk_id: str, text: str) -> None:  # type: ignore[override]
        if not (self.session_factory and self.embed_client):
            return
        # 生产实现：embed_client.embed(text) → INSERT INTO text_chunks(embedding) ...
        raise NotImplementedError("Docker 集成后实现 pgvector upsert")

    async def search(self, query: str, top_k: int = 10) -> list[tuple[str, float]]:  # type: ignore[override]
        if not (self.session_factory and self.embed_client):
            return []
        raise NotImplementedError("Docker 集成后实现 pgvector search")


# ============================================================
# 图存储抽象 + 两个实现
# ============================================================
class GraphStore:
    """图召回接口——概念→关联 chunk"""
    def add_edge(self, concept: str, chunk_id: str) -> None: ...
    def neighbors(self, concept: str, depth: int = 1) -> list[str]:
        """返回概念关联的 chunk_id 列表"""
        raise NotImplementedError


class InMemoryGraphStore(GraphStore):
    """内存图——概念→chunk 邻接表 + 概念间关联"""
    def __init__(self) -> None:
        self._concept_to_chunks: dict[str, set[str]] = {}
        self._concept_relations: dict[str, set[str]] = {}

    def add_edge(self, concept: str, chunk_id: str) -> None:
        self._concept_to_chunks.setdefault(concept, set()).add(chunk_id)

    def add_concept_relation(self, c1: str, c2: str) -> None:
        self._concept_relations.setdefault(c1, set()).add(c2)
        self._concept_relations.setdefault(c2, set()).add(c1)

    def neighbors(self, concept: str, depth: int = 1) -> list[str]:
        visited_concepts: set[str] = {concept}
        frontier = {concept}
        for _ in range(depth):
            nxt: set[str] = set()
            for c in frontier:
                nxt |= self._concept_relations.get(c, set())
            nxt -= visited_concepts
            visited_concepts |= nxt
            frontier = nxt
            if not frontier:
                break
        chunk_ids: set[str] = set()
        for c in visited_concepts:
            chunk_ids |= self._concept_to_chunks.get(c, set())
        return list(chunk_ids)


class Neo4jGraphStore(GraphStore):
    """Neo4j 图召回——Docker 集成后启用"""
    def __init__(self, driver=None) -> None:
        self.driver = driver
        if driver is None:
            logger.warning("Neo4jGraphStore 未配 driver，图召回返回空")

    def add_edge(self, concept: str, chunk_id: str) -> None:
        if self.driver is None:
            return
        raise NotImplementedError("Docker 集成后实现 Neo4j MERGE")

    def neighbors(self, concept: str, depth: int = 1) -> list[str]:
        if self.driver is None:
            return []
        raise NotImplementedError("Docker 集成后实现 Neo4j Cypher 邻居查询")


# ============================================================
# 混合召回器
# ============================================================
@dataclass
class RetrievalConfig:
    top_k_vector: int = 10
    top_k_lexical: int = 20
    top_k_graph: int = 10
    top_k_keyword: int = 8
    top_k_work: int = 6
    final_top_k: int = 5
    graph_depth: int = 1


class HybridRetriever:
    """三路混合召回 + 五层过滤

    用法：
        retriever = HybridRetriever()  # 默认 in-memory
        retriever.index_chunks(build_chunks())  # 建索引
        ctx = retriever.retrieve(user_msg)  # → RAGContext

    Docker 起来后：
        retriever = HybridRetriever(
            vector_store=PgvectorStore(session, embed),
            graph_store=Neo4jGraphStore(driver),
        )
    """

    def __init__(
        self,
        vector_store: Optional[VectorStore] = None,
        graph_store: Optional[GraphStore] = None,
        concept_dict: Optional[ConceptDictionary] = None,
        filterer: Optional[FiveLayerFilter] = None,
        config: Optional[RetrievalConfig] = None,
    ) -> None:
        self.vector_store = vector_store or InMemoryVectorStore()
        self.graph_store = graph_store or InMemoryGraphStore()
        self.concept_dict = concept_dict or ConceptDictionary()
        self.filterer = filterer or FiveLayerFilter(concept_dict=self.concept_dict)
        self.config = config or RetrievalConfig()
        self._chunks: dict[str, dict] = {}  # chunk_id → chunk dict（content 模块格式）
        # 关键词召回用的概念集合，建索引时一次性算好；否则每轮对话都要对
        # 1.5 万+ 分片重跑一遍 ConceptDictionary.extract_concepts（约 4s/次）。
        self._chunk_concepts: dict[str, frozenset[str]] = {}
        # 书名召回：著作别名 → 著作名；著作名 → 该著作全部分片 id。
        # 见 _work_recall 的说明（概念词典只有提纲概念，点书名时三路全空）。
        self._work_aliases: dict[str, str] = {}
        self._by_work: dict[str, list[str]] = {}
        # 书名近似召回：提问用「国家和革命」指《国家与革命》（差一个字、没带书名号）
        self._work_title_grams: dict[str, set[str]] = {}
        # 词法召回：字符 2-gram 倒排 + BM25（无 embedding 时区分「字串常见」与「内容相关」）
        self._lexical = LexicalIndex()
        self._chunk_ids: list[str] = []  # 词法索引的分片序号 → chunk id

    # --------------------------------------------------
    # 索引
    # --------------------------------------------------
    def index_chunks(self, chunks: list[dict]) -> None:
        """建索引——向量 + 图 + chunk 缓存 + 概念集合

        同一段正文可能被原文登记两次（《唯物主义和经验批判主义》每章末尾都有一个
        「注释：」块，编者注从 [53] 起重排，两次入库文字完全相同；源站就这么排，
        原文一字未改，所以清理点在索引侧而不是正文侧）：这样的分片只索引第一次出现，
        否则召回里同一句原文占两个名额、引用框里刷两遍。id 仍登记进 `_chunks`，
        题库/延伸阅读按 id 溯源照旧可用。
        """
        seen_text: set[str] = set()
        for c in chunks:
            cid = c["id"]
            self._chunks[cid] = c
            key = re.sub(r"\s+", "", c.get("text") or "")
            if key and key in seen_text:
                continue
            seen_text.add(key)
            # 词法索引按「分片序号」存倒排，序号顺序必须与 _chunk_ids 一致
            self._lexical.add(len(self._chunk_ids), c["text"])
            self._chunk_ids.append(cid)
            self.vector_store.upsert(cid, c["text"])
            self._chunk_concepts[cid] = frozenset(
                (c.get("concept_mentions") or [])
            ) | frozenset(self.concept_dict.extract_concepts(c["text"]))
            for concept in (c.get("concept_mentions") or []):
                self.graph_store.add_edge(concept, cid)
            work = (c.get("source") or "").strip()
            if work:
                self._by_work.setdefault(work, []).append(cid)
                if work not in self._work_title_grams and len(work) >= 4:
                    self._work_title_grams[work] = _trigrams(work)
                for alias in _work_aliases(work):
                    self._work_aliases.setdefault(alias, work)
        self._lexical.finalize()

    def add_concept_relation(self, c1: str, c2: str) -> None:
        """注册概念间关联（图召回用）"""
        if isinstance(self.graph_store, InMemoryGraphStore):
            self.graph_store.add_concept_relation(c1, c2)

    # --------------------------------------------------
    # 三路召回
    # --------------------------------------------------
    def _vector_recall(self, query_text: str) -> list[tuple[str, float]]:
        """向量召回——语义近似（3-gram 哈希余弦，接真 embedding 前由词法层兜底）"""
        if isinstance(self.vector_store, InMemoryVectorStore):
            return self.vector_store.search(query_text, self.config.top_k_vector)
        return []  # PgvectorStore 是 async，由 retrieve_async 处理

    def _lexical_recall(self, query_text: str) -> list[tuple[str, float]]:
        """词法召回——BM25，分归一到 0—1（最高分为 1.0）

        与向量层并行：向量层管「共享字串」，词法层管「稀有词命中且不被长度稀释」。
        """
        hits = self._lexical.search(query_text, self.config.top_k_lexical)
        if not hits:
            return []
        ids = self._chunk_ids
        top = hits[0][1] or 1.0
        out: list[tuple[str, float]] = []
        for idx, score in hits:
            if 0 <= idx < len(ids):
                out.append((ids[idx], score / top))
        return out

    def _graph_recall(self, concepts: list[str]) -> list[tuple[str, float]]:
        """图召回——概念关联的 chunk

        旧实现按「概念出现顺序」取前 10 条，等于把候选池交给概念词典里排在前面的
        概念去挑，同一本书（入库最早的那几本）反复入选。现在按「命中几个提问概念」排序。
        """
        if not concepts:
            return []
        overlap: dict[str, int] = {}
        for c in concepts:
            for cid in self.graph_store.neighbors(c, self.config.graph_depth):
                overlap[cid] = overlap.get(cid, 0) + 1
        ranked = sorted(overlap.items(), key=lambda x: -x[1])
        return [(cid, 0.30 + 0.15 * min(n, 2)) for cid, n in ranked[: self.config.top_k_graph]]

    def _title_recall(self, query_text: str) -> list[tuple[str, float]]:
        """书名近似召回——「国家和革命是什么关系」→《国家与革命》

        用户很少带书名号，常把书名写进问句（少一个字、加个「的」、改词序）。
        这里按 3-gram 覆盖率判：书名的 3-gram 有 ≥75% 出现在问句里，
        就认为用户点的是这本书。覆盖率门槛高（书名几乎要整段出现），
        所以不会把「农民问题」误判成《法德农民问题》。
        """
        q_grams = _trigrams(query_text)
        if len(q_grams) < 4:
            return []
        hits: list[tuple[str, float]] = []
        for work, w_grams in self._work_title_grams.items():
            if not w_grams:
                continue
            cover = len(w_grams & q_grams) / len(w_grams)
            if cover >= 0.75:
                hits.append((work, cover))
        if not hits:
            return []
        hits.sort(key=lambda x: -x[1])
        out: list[tuple[str, float]] = []
        for work, cover in hits[:3]:
            for cid in self._by_work.get(work, []):
                out.append((cid, min(1.0, 0.8 + 0.2 * cover)))
        return out[: self.config.top_k_work]

    def _work_recall(self, query_text: str) -> list[str]:
        """书名召回 —— 补住「用户直接点著作名」的召回盲区

        背景：ConceptDictionary 只覆盖提纲概念，`金融资本`／`资本积累论`／
        `世界经济与帝国主义` 这类「著作名 + 主题词」的说法抽不出概念，三路召回
        全空，该书正文永远进不了候选池（实测：问「金融资本 银行 产业资本」
        召不到 CH-JRZB-*）。这里按「query 命中某部著作名 → 取该书与 query 共享
        3-gram 的分片」补齐候选。分数只决定是否进候选池，最终排序仍由五层过滤决定。
        """
        if not self._work_aliases:
            return []
        works = {w for a, w in self._work_aliases.items() if a in query_text}
        if not works:
            return []
        q_grams = _trigrams(query_text)
        if not q_grams:
            return []
        scored: list[tuple[str, int]] = []
        for work in sorted(works):
            for cid in self._by_work.get(work, ()):
                c = self._chunks.get(cid)
                if not c:
                    continue
                overlap = len(q_grams & _trigrams(c["text"]))
                if overlap:
                    scored.append((cid, overlap))
        scored.sort(key=lambda x: -x[1])
        return [cid for cid, _ in scored[: self.config.top_k_work]]

    def _keyword_recall(self, query_text: str) -> list[tuple[str, float]]:
        """关键词召回——ConceptDictionary 匹配（概念集合建索引时已预算）

        与原实现等价：chunk 的 concept_mentions ∪ extract_concepts(text)
        与 query 概念求交。仅把 O(全库 × 词典扫描) 从每轮挪到建索引时。
        """
        concepts = frozenset(self.concept_dict.extract_concepts(query_text))
        if not concepts:
            return []
        hits: list[tuple[str, int]] = []
        for cid in self._chunks:
            cc = self._chunk_concepts.get(cid)
            if cc is None:  # 兼容外部直接改 _chunks 的调用方
                c = self._chunks[cid]
                cc = frozenset(c.get("concept_mentions") or []) | frozenset(
                    self.concept_dict.extract_concepts(c["text"])
                )
                self._chunk_concepts[cid] = cc
            overlap = len(cc & concepts)
            if overlap:
                hits.append((cid, overlap))
        # 按命中概念数取前 N：旧实现按 dict 插入顺序 break，等于偏向最早入库的书，
        # 后入库的分片永远进不了候选池（概念命中再多也排不上）。
        hits.sort(key=lambda x: -x[1])
        n = max(len(concepts), 1)
        return [(cid, 0.35 + 0.25 * (cnt / n)) for cid, cnt in hits[: self.config.top_k_keyword]]

    # --------------------------------------------------
    # 合并 + 过滤
    # --------------------------------------------------
    def retrieve(self, user_msg: Any) -> RAGContext:
        """同步召回（in-memory store）→ RAGContext

        Args:
            user_msg: UserMessageIn（含 content/selected_text/paragraph_id/mode）
        """
        query_text = (getattr(user_msg, "selected_text", "") or "") + getattr(user_msg, "content", "")
        paragraph_id = getattr(user_msg, "paragraph_id", "") or ""

        # 锚点优先：选中某条直接召回该条全部分块
        if paragraph_id.startswith("th"):
            return self._retrieve_by_paragraph(paragraph_id, user_msg)

        # 三路召回
        vec_hits = self._vector_recall(query_text)
        lex_hits = self._lexical_recall(query_text)
        concepts = self.concept_dict.extract_concepts(query_text)
        graph_hits = self._graph_recall(concepts)
        kw_hits = self._keyword_recall(query_text)
        work_hits = self._work_recall(query_text)
        title_hits = self._title_recall(query_text)

        # 合并去重（向量带分，图/关键词带来源标记）
        merged: dict[str, float] = {}
        for cid, score in vec_hits:
            merged[cid] = max(merged.get(cid, 0.0), score)
        for cid, score in lex_hits:
            merged[cid] = max(merged.get(cid, 0.0), score)
        for cid, score in graph_hits:
            merged[cid] = max(merged.get(cid, 0.0), score)
        for cid, score in kw_hits:
            merged[cid] = max(merged.get(cid, 0.0), score)
        for cid in work_hits:
            # 书名命中：用户明确点了这部著作，相关性按满给（见 filter.RECALL_WEIGHT）
            merged[cid] = max(merged.get(cid, 0.0), 1.0)
        for cid, score in title_hits:
            merged[cid] = max(merged.get(cid, 0.0), score)

        if not merged:
            # 全空 → fallback 取前 8 个 chunk（保持链路可联调）
            merged = {cid: 0.0 for cid in list(self._chunks)[:8]}

        # 构 FilterChunk 走五层过滤
        filter_chunks = [self._to_filter_chunk(cid, merged[cid]) for cid in merged if cid in self._chunks]
        # 概念锁定只用「提问里抽出的概念」。旧实现把召回分片的概念并进 query，
        # 等于让候选自己给自己发准入证：任何分片都能凭自己身上的概念通过 L1，
        # L1 于是退化成摆设（实测「党怎样领导工会」召回的 5 条里 4 条不含「工会」）。
        user_query = UserQuery(
            raw_text=query_text,
            current_work=self._current_work(paragraph_id),
            current_chapter="全文",
            mode=getattr(user_msg, "mode", "explain"),
            user_question=getattr(user_msg, "content", ""),
            key_concepts=list(concepts),
        )
        filtered = self.filterer.filter(user_query, filter_chunks, top_k=self.config.final_top_k)

        return self._build_rag_context(filtered["final_results"], user_msg)

    def _retrieve_by_paragraph(self, paragraph_id: str, user_msg: Any) -> RAGContext:
        """锚点召回——选中某条直接取该条 L1-L4 全分块

        锚点路径：把该条所有 chunk 的 concept_mentions 并入 query.key_concepts，
        保证 L1 概念锁定全通过（用户已明确选中该条，不应被概念过滤）。
        """
        from content.theses_annotations import chunks_for_paragraph
        chunk_dicts = chunks_for_paragraph(paragraph_id)
        filter_chunks = [
            FilterChunk(
                chunk_id=c["id"], text=c["text"], source=c["source"],
                source_location=c["source_location"], layer=c["layer"],
                orthodoxy_tag=c["orthodoxy_tag"], authority_score=c["authority_score"],
                concept_mentions=c.get("concept_mentions") or [],
                logical_type=c.get("logical_type", ""),
            )
            for c in chunk_dicts
        ]
        # 锚点：query 概念 = 用户选中概念 + 该条全部 chunk 概念（保证 L1 通过）
        anchor_concepts: set[str] = set(self.concept_dict.extract_concepts(
            getattr(user_msg, "selected_text", "") or ""
        ))
        for fc in filter_chunks:
            anchor_concepts |= set(fc.concept_mentions)
        user_query = UserQuery(
            raw_text=getattr(user_msg, "content", ""),
            current_work=self._current_work(paragraph_id),
            current_chapter="全文",
            mode=getattr(user_msg, "mode", "explain"),
            user_question=getattr(user_msg, "content", ""),
            key_concepts=list(anchor_concepts),
        )
        filtered = self.filterer.filter(user_query, filter_chunks, top_k=self.config.final_top_k)
        return self._build_rag_context(filtered["final_results"], user_msg)

    # --------------------------------------------------
    # 辅助
    # --------------------------------------------------
    def _current_work(self, paragraph_id: str) -> str:
        """用户当前在读的著作名——只有真能定位时才返回，否则空串（L3 不设先验）"""
        if not paragraph_id:
            return ""
        if paragraph_id.startswith("th"):
            return "关于费尔巴哈的提纲"   # 提纲的 11 条正是这本书的分块
        for c in self._chunks.values():
            if c.get("paragraph_id") == paragraph_id:
                return (c.get("source") or "").strip()
        return ""

    def _to_filter_chunk(self, chunk_id: str, recall_score: float = 0.0) -> FilterChunk:
        c = self._chunks[chunk_id]
        return FilterChunk(
            chunk_id=c["id"], text=c["text"], source=c["source"],
            source_location=c["source_location"], layer=c["layer"],
            orthodoxy_tag=c["orthodoxy_tag"], authority_score=c["authority_score"],
            concept_mentions=c.get("concept_mentions") or [],
            logical_type=c.get("logical_type", ""),
            recall_score=recall_score,
        )

    def _build_rag_context(self, results: list, user_msg: Any) -> RAGContext:
        """过滤结果 → RAGContext（含 term/proposition/meta_rules）"""
        text_chunks = [
            TextChunk(
                chunk_id=r.chunk.chunk_id, text=r.chunk.text, source=r.chunk.source,
                source_location=r.chunk.source_location, authority_score=r.chunk.authority_score,
            )
            for r in results
        ]
        # 概念定义层
        from content.theses_concepts import CONCEPTS, concepts_mentioning_term
        hit_concepts = concepts_mentioning_term(
            (getattr(user_msg, "selected_text", "") or "") + getattr(user_msg, "content", "")
        ) or CONCEPTS[:4]
        term_defs = [
            TermDefinition(
                term=c["name"], definition=c["canonical_definition"],
                source_id=c["source_id"],
                equivalents=c.get("equivalent_terms", []),
                misreadings=c.get("strictly_not", []),
            )
            for c in hit_concepts
        ]
        # 命题层（L2 chunks）
        prop_ids = {r.chunk.chunk_id for r in results}
        propositions = [
            Proposition(
                id=c["id"], text=c["text"], source=c["source"],
                location=c["source_location"], logical_type=c.get("logical_type", ""),
            )
            for cid, c in self._chunks.items()
            if cid in prop_ids and c["layer"] == 2
        ]
        meta_rules = [
            {"rule": "坚持唯物史观", "description": "社会存在决定社会意识，经济基础决定上层建筑", "critical": True},
            {"rule": "术语红线", "description": "市民社会≠公民社会/民间社会/NGO；实践≠道德践履；人的本质≠抽象人性", "critical": True},
        ]
        return RAGContext(
            term_definitions=term_defs,
            propositions=propositions,
            text_chunks=text_chunks,
            meta_rules=meta_rules,
        )
