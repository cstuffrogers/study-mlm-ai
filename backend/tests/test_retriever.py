"""HybridRetriever 单元测试

验证三路召回 + 合并去重 + 五层过滤串联 + 锚点优先。
in-memory 实现（无 Docker 依赖）；Docker 起来后 PgvectorStore/Neo4jGraphStore
的测试在 tests_integration/ 单独跑。
"""
from __future__ import annotations

import pytest

from content.theses_annotations import build_chunks, chunks_for_paragraph
from content.theses_concepts import CONCEPTS
from core.rag.retriever import (
    HybridRetriever,
    InMemoryVectorStore,
    InMemoryGraphStore,
    RetrievalConfig,
    _hash_vec,
    _cosine,
)
from websocket.protocol import UserMessageIn


@pytest.fixture(scope="module")
def retriever() -> HybridRetriever:
    r = HybridRetriever()
    r.index_chunks(build_chunks())
    # 注册概念间关联（图召回用）——实践 ↔ 对象性活动 ↔ 人的本质
    r.add_concept_relation("实践", "对象性活动")
    r.add_concept_relation("对象性活动", "人的本质")
    return r


def _msg(content: str = "请解释实践", selected: str = "", pid: str = "", mode: str = "explain") -> UserMessageIn:
    return UserMessageIn(
        dialogue_id="test", content=content, selected_text=selected,
        paragraph_id=pid, mode=mode,
    )


# ============================================================
# 向量召回（InMemoryVectorStore）
# ============================================================
class TestVectorRecall:
    def test_hash_vec_unit_norm(self) -> None:
        v = _hash_vec("实践的检验真理", dim=128)
        norm = sum(x*x for x in v) ** 0.5
        assert abs(norm - 1.0) < 1e-6, "hash_vec 应归一化"

    def test_cosine_identical(self) -> None:
        v = _hash_vec("实践是检验真理的唯一标准", dim=128)
        assert _cosine(v, v) > 0.999

    def test_vector_store_search_returns_relevant(self) -> None:
        store = InMemoryVectorStore()
        for c in build_chunks():
            store.upsert(c["id"], c["text"])
        hits = store.search("实践对象性活动", top_k=5)
        assert len(hits) <= 5 and len(hits) > 0
        # 含"实践"概念的 th1 原文应排前列
        top_ids = [cid for cid, _ in hits[:3]]
        assert any("TH-01" in cid for cid in top_ids), f"th1 相关 chunk 应排前: {top_ids}"


# ============================================================
# 图召回
# ============================================================
class TestGraphRecall:
    def test_neighbors_returns_related_chunks(self, retriever: HybridRetriever) -> None:
        # 实践 → 对象性活动 → 人的本质（depth=2 应跨概念召回）
        n1 = retriever.graph_store.neighbors("实践", depth=1)
        n2 = retriever.graph_store.neighbors("实践", depth=2)
        assert len(n2) >= len(n1), "depth=2 应召回不少于 depth=1"


# ============================================================
# 锚点优先召回
# ============================================================
class TestAnchorRetrieval:
    def test_paragraph_id_recalls_all_layers(self, retriever: HybridRetriever) -> None:
        """选中 th1 → 召回该条 L1-L4 全分块"""
        ctx = retriever.retrieve(_msg(pid="th1"))
        layers = {c.chunk_id.split("-")[-1] for c in ctx.text_chunks}
        assert layers == {"1", "2", "3", "4"}, f"应召回 4 层: {layers}"

    def test_anchor_overrides_query(self, retriever: HybridRetriever) -> None:
        """有 paragraph_id 时，content 不影响召回范围"""
        ctx = retriever.retrieve(_msg(content="无关问题", pid="th6"))
        for c in ctx.text_chunks:
            assert "TH-06" in c.chunk_id, f"应只召回 th6: {c.chunk_id}"


# ============================================================
# 三路混合召回 + 合并去重
# ============================================================
class TestHybridMerge:
    def test_keyword_query_recalls_concept_chunks(self, retriever: HybridRetriever) -> None:
        """无锚点时，关键词/向量/图三路召回合并"""
        ctx = retriever.retrieve(_msg(content="请解释实践和对象性活动", selected="实践"))
        assert len(ctx.text_chunks) > 0, "应召回至少一个 chunk"

    def test_no_duplicate_chunks(self, retriever: HybridRetriever) -> None:
        """三路合并后无重复 chunk_id"""
        ctx = retriever.retrieve(_msg(content="实践 人的本质 市民社会"))
        ids = [c.chunk_id for c in ctx.text_chunks]
        assert len(ids) == len(set(ids)), f"召回结果有重复: {ids}"

    def test_empty_query_fallback(self, retriever: HybridRetriever) -> None:
        """全空查询 → fallback 取前 8 chunk（保持链路可联调）"""
        ctx = retriever.retrieve(_msg(content="zzzznomatch", selected=""))
        assert len(ctx.text_chunks) > 0, "fallback 应保证非空"


# ============================================================
# RAGContext 组装
# ============================================================
class TestRagContextAssembly:
    def test_context_has_term_definitions(self, retriever: HybridRetriever) -> None:
        ctx = retriever.retrieve(_msg(content="什么是实践", selected="实践", pid="th1"))
        assert len(ctx.term_definitions) > 0, "应含概念定义"
        terms = [t.term for t in ctx.term_definitions]
        assert any("实践" in t or "对象" in t for t in terms), f"应含实践相关概念: {terms}"

    def test_context_has_propositions_from_l2(self, retriever: HybridRetriever) -> None:
        """命题层只取 layer=2 的 chunk"""
        ctx = retriever.retrieve(_msg(pid="th1"))
        for p in ctx.propositions:
            assert p.id.endswith("-2"), f"命题应来自 L2: {p.id}"

    def test_context_has_meta_rules(self, retriever: HybridRetriever) -> None:
        ctx = retriever.retrieve(_msg(pid="th1"))
        assert len(ctx.meta_rules) >= 2, "应含至少 2 条元规则（红线）"


# ============================================================
# 可插拔 store（Docker 切换接口验证）
# ============================================================
class TestStoreSwap:
    def test_custom_vector_store_used(self) -> None:
        """注入自定义 VectorStore——验证可插拔"""
        class CountingStore(InMemoryVectorStore):
            def __init__(self):
                super().__init__()
                self.search_count = 0
            def search(self, query, top_k=10):
                self.search_count += 1
                return super().search(query, top_k)

        store = CountingStore()
        r = HybridRetriever(vector_store=store)
        r.index_chunks(build_chunks())
        r.retrieve(_msg(content="实践"))
        assert store.search_count >= 1, "应调用注入的 vector_store"

    def test_pgvector_store_without_deps_returns_empty(self) -> None:
        """PgvectorStore 未配齐 → search 返回空（不崩）"""
        from core.rag.retriever import PgvectorStore
        store = PgvectorStore()  # 无 session/embed
        import asyncio
        result = asyncio.run(store.search("test"))
        assert result == []
