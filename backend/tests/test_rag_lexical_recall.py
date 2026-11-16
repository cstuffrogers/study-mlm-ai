"""RAG 召回质量回归（D127 检索修复批）

锁的四件事，都是「实测出过问题」的：
  1. `LexicalIndex`（字符 2-gram 倒排 + BM25）能把「问句里的稀有词」顶上来，
     而不是让长分片靠堆常见二元组取胜；
  2. 五层过滤 L3 在「用户没指定在读哪本书」时不给任何书语境加分
     （旧行为：current_work 硬编码成《关于费尔巴哈的提纲》，该书白得 +0.105）；
  3. L1 概念锁定只用「提问里抽出的概念」，不再把候选分片自己的概念并进 query
     （旧行为等于让候选自己发准入证，L1 退化成摆设）；
  4. 前五条同书限席，避免一本书把结果占满。
"""
from __future__ import annotations

from content.theses_annotations import build_chunks
from core.rag.filter import FiveLayerFilter, TextChunk, UserQuery
from core.rag.retriever import HybridRetriever, LexicalIndex
from websocket.protocol import UserMessageIn


def _tc(cid: str, source: str, text: str, concepts=()) -> TextChunk:
    """过滤层输入（TextChunk）——不经 retriever，直接测五层打分"""
    return TextChunk(
        chunk_id=cid, text=text, source=source, source_location="第1段",
        layer=3, orthodoxy_tag="经典原著", authority_score=1.0,
        concept_mentions=list(concepts), logical_type="proposition",
    )


def _chunk(cid: str, source: str, text: str, concepts=(), tag="经典原著", score=1.0) -> dict:
    return {
        "id": cid,
        "layer": 3,
        "source": source,
        "source_location": "第1段",
        "paragraph_id": "p" + cid,
        "text": text,
        "orthodoxy_tag": tag,
        "authority_score": score,
        "logical_type": "proposition",
        "concept_mentions": list(concepts),
        "book_author": "测试",
        "strictly_not": [],
    }


# ============================================================
# 1) 词法召回：稀有词压过常见字串堆叠
# ============================================================
class TestLexicalIndex:
    def test_rare_term_wins_over_common_boilerplate(self) -> None:
        """语料里 6 条都在讲「革命」，只有 1 条含「工会」——问「工会」必须命中那条。"""
        idx = LexicalIndex()
        common = "无产阶级革命要团结一切可以团结的力量共同奋斗革命到底革命必胜"
        idx.add(0, common)
        idx.add(1, common + "革命的组织形式问题")
        idx.add(2, common + "革命的策略问题")
        idx.add(3, "党怎样领导工会开展经济斗争，工会是工人的群众组织")
        idx.add(4, common + "革命的领导权问题")
        idx.add(5, common + "革命的道路问题")
        idx.finalize()

        hits = idx.search("工会", top_k=3)
        assert hits, "词法召回对「工会」没有任何命中"
        assert hits[0][0] == 3, f"含「工会」的分片未排第一，实际 {hits}"

    def test_high_df_gram_is_pruned(self) -> None:
        """每条都有的二元组（此处「革命」）没有区分度，不该留在倒排表里。"""
        idx = LexicalIndex()
        for i in range(6):
            idx.add(i, f"革命第{i}条不同内容的不同记录")
        idx.finalize()
        assert "革命" not in idx._rank, "高 DF 二元组未剪除，会主导所有查询"

    def test_shorter_chunk_beats_long_one(self) -> None:
        """同样命中「工会」：短分片命中密度高，长分片不该靠体量赢。"""
        idx = LexicalIndex()
        idx.add(0, "工会是工人的群众组织，党要领导工会")
        idx.add(1, "工会" + "无关的叙述" * 400)
        idx.add(2, "别的书讲农业合作化")
        idx.finalize()
        hits = idx.search("工会", top_k=2)
        assert hits[0][0] == 0, f"长分片压过了短分片：{hits}"

    def test_empty_query_returns_nothing(self) -> None:
        idx = LexicalIndex()
        idx.add(0, "实践是检验真理的唯一标准")
        idx.finalize()
        assert idx.search("") == []


# ============================================================
# 2) L3 语境：没指定在读哪本书 → 一律中性
# ============================================================
class TestContextPrior:
    def test_no_current_work_gives_neutral_context(self) -> None:
        f = FiveLayerFilter()
        chunks = [_tc("a", "甲书", "实践的观点", ["实践"]), _tc("b", "乙书", "实践的观点", ["实践"])]
        q = UserQuery(raw_text="什么是实践", current_work="", current_chapter="",
                      mode="explain", user_question="什么是实践", key_concepts=["实践"])
        out = f.filter(q, chunks, top_k=2)
        l3 = {r.chunk.source: r.filter_scores["l3"] for r in out["final_results"]}
        assert l3["甲书"] == l3["乙书"] == 0.6, f"未指定著作时仍给了语境加分：{l3}"

    def test_current_work_still_boosted_when_known(self) -> None:
        f = FiveLayerFilter()
        chunks = [_tc("a", "甲书", "实践的观点", ["实践"]), _tc("b", "乙书", "实践的观点", ["实践"])]
        q = UserQuery(raw_text="什么是实践", current_work="甲书", current_chapter="",
                      mode="explain", user_question="什么是实践", key_concepts=["实践"])
        out = f.filter(q, chunks, top_k=2)
        l3 = {r.chunk.source: r.filter_scores["l3"] for r in out["final_results"]}
        assert l3["甲书"] == 1.0 and l3["乙书"] < 1.0, f"指定了在读著作却没加分：{l3}"


# ============================================================
# 3) 同书限席
# ============================================================
class TestSourceDiversity:
    def test_same_work_capped_in_top_k(self) -> None:
        f = FiveLayerFilter(max_per_source=2)
        chunks = []
        for i in range(6):
            chunks.append(_tc(f"a{i}", "甲书", f"实践的观点第{i}段", ["实践"]))
        for i in range(3):
            chunks.append(_tc(f"b{i}", "乙书", f"实践的观点第{i}段", ["实践"]))
        q = UserQuery(raw_text="实践", current_work="", current_chapter="",
                      mode="explain", user_question="实践", key_concepts=["实践"])
        out = f.filter(q, chunks, top_k=5)
        sources = [r.chunk.source for r in out["final_results"]]
        assert sources.count("甲书") <= 2, f"同一本书占席过多：{sources}"
        assert sources.count("乙书") == 2, f"限席后没把别的书补满：{sources}"


# ============================================================
# 4) L1 概念锁定不被候选自证
# ============================================================
class TestConceptLock:
    def test_candidates_cannot_vouch_for_themselves(self) -> None:
        """问「工会」时，只有自己带「工会」概念的分片能过 L1。"""
        r = HybridRetriever()
        r.index_chunks([
            _chunk("w1", "工会书", "党怎样领导工会，工会是工人的群众组织", ["工会"]),
            _chunk("x1", "哲学书", "实践是检验真理的唯一标准，实践的观点", ["实践"]),
            _chunk("y1", "军事书", "革命战争的战略战术问题，革命战争", ["革命"]),
        ])
        ctx = r.retrieve(UserMessageIn(dialogue_id="t", content="工会怎么领导",
                                       selected_text="", paragraph_id="", mode="explain"))
        assert ctx.text_chunks, "问「工会」没有召回任何分片"
        blob = "".join(c.text for c in ctx.text_chunks)
        assert "工会" in blob, f"召回内容与提问不对口：{blob[:80]}"
        assert "实践是检验真理" not in blob, "不相关的哲学分片混进了结果"


# ============================================================
# 5) 书名近似召回
# ============================================================
class TestTitleRecall:
    def test_title_inside_question_resolves_work(self) -> None:
        r = HybridRetriever()
        r.index_chunks([
            _chunk("p1", "论持久战", "战争的伟力之最深厚的根源，存在于民众之中", ["战争"]),
            _chunk("q1", "别的书", "关于合作社的若干问题", ["合作社"]),
        ])
        hits = r._title_recall("论持久战为什么能赢")
        assert hits and hits[0][0] == "p1", f"书名近似召回没认出提问里的书名：{hits}"

    def test_short_partial_title_not_matched(self) -> None:
        r = HybridRetriever()
        r.index_chunks([_chunk("p1", "法德农民问题", "农民问题要具体分析", [])])
        assert r._title_recall("农民问题在中国革命中的地位") == [], \
            "书名只对上一部分就当成点名，会误召回《法德农民问题》"


# ============================================================
# 6) 原有锚点路径不受影响
# ============================================================
class TestAnchorStillWorks:
    def test_paragraph_anchor_returns_its_own_chunks(self) -> None:
        r = HybridRetriever()
        r.index_chunks(build_chunks())
        ctx = r.retrieve(UserMessageIn(dialogue_id="t", content="解释一下",
                                       selected_text="实践", paragraph_id="th1", mode="explain"))
        assert ctx.text_chunks
        # 锚点路径 = 该条分块 + 它的正典注释/解析（相邻层），不该跑题到别的著作
        assert ctx.text_chunks[0].source == "关于费尔巴哈的提纲", "锚点路径没回该条所在著作"


# ============================================================
# 7) 只作导览的条目：书目里可见，检索里不见
# ============================================================
class TestGuideOnlyWorks:
    def test_toc_catalogued_but_not_indexed(self) -> None:
        """选集目录这类非正文条目：`all_book_chunks()` 仍收，检索入口剔除。"""
        from content.book_chunks import (
            BOOKS,
            GUIDE_ONLY_WORKS,
            all_book_chunks,
            retrievable_chunks,
        )

        works = {b["work"] for b in BOOKS}
        assert GUIDE_ONLY_WORKS <= works, "导览专用条目不在书目里，读者就看不到它了"

        every = all_book_chunks()
        feed = retrievable_chunks()
        toc = [c for c in every if c["source"] in GUIDE_ONLY_WORKS]
        assert toc, "目录序言的分片丢了——它还要在书目录里给读者看"
        assert not any(c["source"] in GUIDE_ONLY_WORKS for c in feed), \
            "选集目录仍被喂进检索索引，会继续抢占提问前排"
        assert len(feed) == len(every) - len(toc), "剔除量对不上，说明还漏了别的条目"

    def test_dialogue_retriever_has_no_guide_only_source(self) -> None:
        """真实装配路径（对话服务）用的是 retrievable_chunks，不是全量。"""
        from content.book_chunks import GUIDE_ONLY_WORKS
        from services.dialogue_service import _build_retriever

        r = _build_retriever()
        bad = {c["source"] for c in r._chunks.values()} & GUIDE_ONLY_WORKS
        assert not bad, f"对话检索索引里仍有导览专用条目：{bad}"
