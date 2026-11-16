"""D107 溯源门禁：《关于费尔巴哈的提纲》入库 + 全库溯源可解析

D107 修的是「路线里的溯源到底指不指得到东西」这一件事，三类历史问题：

1. **原著缺位** —— sec_A_02 / sec_B_00 / sec_C_00 三章的 local_work 一直是
   《关于费尔巴哈的提纲》，但这本书从没入库：路线说要读原文，库里没有。
   本轮整篇入库（35 个分片，id 前缀 CH-MLTH-）。
2. **占位 id** —— 早期知识点/题目写的是 `CH-ME-TH-{条}-{层}`，库内从来不存在
   这些分片；点「溯源」只会弹「未找到该分片」。本轮按「条号 → 真实分片」重指。
3. **导读锚** —— 部分题目溯源写成 `GUIDE-<section_id>`。凡题干/解析里有 ≥14 字
   逐字引文、且能在本章主文里逐字找到的，升级为真实分片；找不到逐字证据的
   保持 GUIDE-（宁可标「导读溯源」，不拿关键词检索冒充权威溯源）。

门禁四件事：书在库、章节溯源可解析、题库无死链、提纲章逐题锚到真实条文。
"""
import glob
import io
import json
import os
import re
import sys

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BASE)

from content.book_chunks import all_book_chunks  # noqa: E402
from content.chapter_content import nodes_for_section  # noqa: E402
from content.routes import SECTIONS  # noqa: E402

BANK_DIR = os.path.join(BASE, "content", "quiz_bank")
THESES_WORK = "关于费尔巴哈的提纲"


def _chunks():
    return all_book_chunks()


def _items():
    out = []
    for path in sorted(glob.glob(os.path.join(BANK_DIR, "*.json"))):
        with io.open(path, encoding="utf-8") as f:
            doc = json.load(f)
        for it in doc.get("items", []):
            it.setdefault("section_id", doc.get("section_id"))
            out.append(it)
    return out


def test_theses_are_in_library():
    """《关于费尔巴哈的提纲》必须真的在库内，且 11 条逐条可检索到。"""
    books = {c["source"] for c in _chunks()}
    assert THESES_WORK in books, sorted(books)
    theses = [c for c in _chunks() if c["source"] == THESES_WORK]
    assert len(theses) >= 15, f"提纲分片过少：{len(theses)}"
    joined = "".join(c["text"] for c in theses)
    for needle in ("一切社会关系的总和", "革命的实践", "改变", "市民", "实践"):
        assert needle in joined, needle


def test_theses_sections_local_work_resolves():
    """三章共享地基的 local_work 必须在库内有正文（不能只写在 content 表里）。"""
    books = {c["source"] for c in _chunks()}
    for sid in ("sec_A_02", "sec_B_00", "sec_C_00"):
        sec = next(s for s in SECTIONS if s["id"] == sid)
        assert sec["local_work"] in books, (sid, sec["local_work"])


def test_all_sections_local_work_in_library():
    """全路线：32 章的 local_work 一律要在库内有正文，杜绝「路线指了本没入库的书」。"""
    books = {c["source"] for c in _chunks()}
    missing = [
        (s["id"], s["local_work"])
        for s in SECTIONS
        if s.get("local_work") and s["local_work"] not in books
    ]
    assert not missing, missing


def _guide_section(cid: str) -> str:
    """`GUIDE-<section_id>` 或 `GUIDE-<section_id>-<块号>` → section_id。"""
    m = re.match(r"GUIDE-(sec_[ABC]_\d+)(?:-\d+)?$", cid)
    return m.group(1) if m else cid


def test_no_dangling_chunk_ids_in_quiz_bank():
    """题库溯源只能是「库内真实分片」或 `GUIDE-<章节>` 导读锚，不许出现假 id。"""
    ids = {c["id"] for c in _chunks()}
    section_ids = {s["id"] for s in SECTIONS}
    bad = []
    for it in _items():
        cid = str(it.get("source_chunk_id") or "")
        assert cid, f"{it['id']} 无溯源（正统性门禁要求每题带溯源）"
        if cid.startswith("GUIDE-"):
            if _guide_section(cid) not in section_ids:
                bad.append((it["id"], cid))
        elif cid not in ids:
            bad.append((it["id"], cid))
    assert not bad, bad


def test_no_dangling_chunk_ids_in_nodes():
    """知识点溯源同理：空串=导读型（允许），非空则必须真实存在。"""
    ids = {c["id"] for c in _chunks()}
    bad = []
    for sec in SECTIONS:
        for n in nodes_for_section(sec["id"]):
            cid = str(n.get("source_chunk_id") or "")
            if cid and cid not in ids:
                bad.append((sec["id"], n["id"], cid))
    assert not bad, bad


def test_theses_chapter_items_anchor_real_articles():
    """sec_A_02 的每道题都要锚在提纲真实分片上（不是 GUIDE-，也不是旧占位 id）。"""
    theses_ids = {c["id"] for c in _chunks() if c["source"] == THESES_WORK}
    items = [it for it in _items() if it.get("section_id") == "sec_A_02"]
    assert len(items) >= 15, len(items)
    for it in items:
        assert it["source_chunk_id"] in theses_ids, (it["id"], it["source_chunk_id"])


def test_theses_nodes_anchor_real_articles():
    """sec_A_02 的 12 个知识点必须逐条指到提纲真实分片。"""
    theses_ids = {c["id"] for c in _chunks() if c["source"] == THESES_WORK}
    nodes = nodes_for_section("sec_A_02")
    assert len(nodes) == 12, len(nodes)
    for n in nodes:
        assert n["source_chunk_id"] in theses_ids, (n["id"], n["source_chunk_id"])


def test_no_legacy_placeholders_left():
    """`CH-ME-TH-{条}-{层}` 是历史占位 id，不得再出现在节点/题库/概念锚点里。"""
    offenders = []
    for it in _items():
        if "CH-ME-TH-" in str(it.get("source_chunk_id") or ""):
            offenders.append((it["id"], it["source_chunk_id"]))
    for sec in SECTIONS:
        for n in nodes_for_section(sec["id"]):
            if "CH-ME-TH-" in str(n.get("source_chunk_id") or ""):
                offenders.append((n["id"], n["source_chunk_id"]))
    from content.theses_concepts import CONCEPTS

    for c in CONCEPTS:
        if "CH-ME-TH-" in str(c.get("source_id") or ""):
            offenders.append((c.get("name"), c.get("source_id")))
    assert not offenders, offenders
