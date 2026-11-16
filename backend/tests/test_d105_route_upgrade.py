"""D105 之后的路线内容跟进门禁（导读 / 题库 / 召回可发现性）

D105 把《资本论》第一卷 11—13 章与三部历史文献正文补进了库，
但「路线」这一层必须同步跟上，否则新正文读不到、考不到、也搜不到：

1. 导读 —— sec_A_08 的导读要覆盖「相对剩余价值的生产」（协作—分工—机器），
   sec_B_06 的导读要给三部历史文献一个显式入口（先看源头、再看列宁的批评）。
2. 题库 —— sec_A_08 要有锚定新插入分片（CH-ZBL-5xx/6xx）的题，
   且应用题落到有概念关键词表的节点上（否则「概念运用」维度恒为 0）。
3. 召回 —— 用户直接点著作名时（「金融资本 银行 产业资本」），
   这本书的正文必须能进候选池并被排上来。
"""
import io
import json
import os
import sys

import pytest

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BASE)

from content.chapter_content import guide_for  # noqa: E402
from content.book_chunks import all_book_chunks  # noqa: E402
from content.concept_keywords import terms_for  # noqa: E402

BANK = os.path.join(BASE, "content", "quiz_bank", "route_A.json")


def _items():
    with io.open(BANK, encoding="utf-8") as f:
        return json.load(f)["items"]


def test_sec_a08_guide_covers_relative_surplus():
    g = guide_for("sec_A_08")
    assert g, "sec_A_08 必须有导读"
    concepts = [c[0] for c in g["core_concepts"]]
    assert any("相对剩余价值" in c for c in concepts), concepts
    headings = " ".join(s["heading"] + s["body"] for s in g["sections"])
    for kw in ("协作", "分工", "机器"):
        assert kw in headings, f"导读缺「{kw}」这一节内容：{kw} 不在 sections 里"
    # 导读必须给学员指到原文，且不得出现内部开发术语
    assert "查看原文" in g["source_note"]
    for token in ("sec_A_08", "D105", "local_work", "TRIM"):
        assert token not in json.dumps(g, ensure_ascii=False), f"导读里出现内部术语 {token}"


def test_sec_b06_guide_gives_explicit_entry_to_three_sources():
    g = guide_for("sec_B_06")
    body = json.dumps(g, ensure_ascii=False)
    for title in ("金融资本", "世界经济与帝国主义", "资本积累论"):
        assert title in body, f"sec_B_06 导读缺少《{title}》的入口"
    assert "列宁" in body
    # 三部文献只作对照材料，不能写成正面结论依据
    assert "不作正面路径" in body, "必须写明三部历史文献不作正面路径的结论依据"


def test_sec_a08_quiz_anchors_inserted_chapters():
    items = [it for it in _items() if it["section_id"] == "sec_A_08"]
    assert len(items) >= 6, f"sec_A_08 题目偏少：{len(items)}"
    zbl = [it for it in items if it["source_chunk_id"].startswith("CH-ZBL-")]
    assert len(zbl) >= 3, "至少 3 道题锚定《资本论》第一卷真实分片"
    # 应用题必须落到有术语表的节点，否则 rubric「概念运用」维度恒为 0
    apps = [it for it in items if it["type"] == "application"]
    assert apps, "sec_A_08 应有应用题"
    for it in apps:
        assert terms_for([it["node_id"]]), f"{it['id']} 的节点缺概念关键词表"


def test_sec_a08_quiz_chunk_ids_exist():
    ids = {c["id"] for c in all_book_chunks()}
    for it in _items():
        cid = it["source_chunk_id"]
        if cid.startswith("CH-"):
            assert cid in ids, f"{it['id']} 锚定了不存在的分片 {cid}"


def test_work_name_query_recalls_the_named_book():
    """书名召回：query 直接点著作名时，该书正文必须能进候选池并排上来"""
    from core.rag.retriever import HybridRetriever
    from websocket.protocol import UserMessageIn

    works = {
        "金融资本（节选）": "金融资本",
        "资本积累论（节选）": "资本积累论",
        "世界经济与帝国主义": "世界经济与帝国主义",
    }
    chunks = [c for c in all_book_chunks() if c["source"] in works]
    assert chunks, "三部历史文献必须已入库"

    r = HybridRetriever()
    r.index_chunks(chunks)
    for work, query in works.items():
        hits = r._work_recall(query)
        assert hits, f"「{query}」没有召回《{work}》"
        assert all(r._chunks[cid]["source"] == work for cid in hits), "书名召回串到了别的书"
        ctx = r.retrieve(UserMessageIn(dialogue_id="d1", content=query, mode="study"))
        assert any(tc.source == work for tc in ctx.text_chunks), f"「{query}」最终没排上《{work}》"


def test_work_alias_skips_short_generic_names():
    """短名（如「资本论」）不参与书名召回，避免把第二、三卷全部拽进候选池"""
    from core.rag.retriever import _work_aliases

    assert "资本论" not in _work_aliases("资本论（第一卷节选）")
    assert "金融资本" in _work_aliases("金融资本（节选）")
