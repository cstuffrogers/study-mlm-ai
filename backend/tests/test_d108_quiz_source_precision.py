# -*- coding: utf-8 -*-
"""D108 门禁：题库/知识点的溯源不许「跨书」，导读锚保持诚实。

背景：D107 把占位 id 与可逐字证的导读锚都修了，D108 把剩下能人工挑出原句的
导读锚也升级为真实分片。这条链路上最容易犯的错是**跨书锚定**——题干考的是
《矛盾论》，却把溯源指到本章 `local_work`（《实践论》）里的分片，看起来分片真实、
其实考据错位。本文件把「溯源分片必须属于本章点名的著作」钉死。
"""

from __future__ import annotations

import glob
import json
import re
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

from content.book_chunks import all_book_chunks  # noqa: E402
from content.routes import SECTIONS  # noqa: E402
from content.reading_extensions import extensions_for  # noqa: E402

BANK = BACKEND / "content" / "quiz_bank"
CJK = re.compile(r"[\u4e00-\u9fff]")
MIN_QUOTE = 12


def _chunks():
    return all_book_chunks()


def _items():
    out = []
    for path in sorted(glob.glob(str(BANK / "*.json"))):
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        for it in data.get("items", []):
            out.append(it)
    return out


def _sections():
    return {s["id"]: s for s in SECTIONS}


def _norm(s: str) -> str:
    return re.sub(r"\s+", "", s or "")


def test_no_cross_book_source_in_quiz_bank():
    """真实分片溯源的著作必须属于本章考点范围（不许拿别章的原文项上）。

    本章考点范围 = `local_work`（主书）∪ 本章延伸阅读所挂的著作。
    背景：有些章节标题就跨两部书（如 sec_A_03「实践的辩证法：从《实践论》到《矛盾论》」），
    该类章节的知识点本就考第二部书的内容，把溯源锚到延伸阅读里的《矛盾论》分片是
    正确的考据；若只认 `local_work`，就会把这些合法溯源误判成「跨书」。
    """
    chunks = {c["id"]: c for c in _chunks()}
    sec = _sections()
    # 章节 id → 允许的著作集合（主书 + 延伸阅读挂接的著作）
    allowed: dict[str, set[str]] = {}
    for sid, s in sec.items():
        works = {s.get("local_work", "")}
        for ext in extensions_for(sid):
            w = str(ext.get("local_work") or "")
            if w:
                works.add(w)
        works.discard("")
        allowed[sid] = works
    bad = []
    for it in _items():
        cid = str(it.get("source_chunk_id") or "")
        if cid.startswith("GUIDE-"):
            continue
        c = chunks.get(cid)
        if c is None:
            bad.append((it["id"], cid, "分片不存在"))
            continue
        sid = it.get("section_id") or ""
        want = allowed.get(sid, set())
        if want and c["source"] not in want:
            bad.append((it["id"], cid,
                        f"属《{c['source']}》，本章允许 {sorted(want)}"))
    assert not bad, bad


def test_guide_anchors_are_minority_and_honest():
    """导读锚（GUIDE-）只允许出现在「本章正文确实没有对应原句」的题上，且占比应持续下降。"""
    items = _items()
    guide = [it for it in items if str(it.get("source_chunk_id") or "").startswith("GUIDE-")]
    # D107 51 条 → D108 29 条；给出上限而不是精确值，便于后续继续收敛
    assert len(guide) <= 29, f"导读锚反弹到 {len(guide)} 条（D108 基线 29）"
    assert len(guide) < len(items) * 0.3, f"导读锚占比过高：{len(guide)}/{len(items)}"
    for it in guide:
        assert re.match(r"GUIDE-sec_[ABC]_\d{2}(-\d+)?$", it["source_chunk_id"]), it


def test_d108_upgraded_sources_quote_verbatim():
    """D108 升级的每条溯源都必须能在该分片里逐字找到原句（证据回放）。"""
    report = BACKEND.parent / ".local" / "d108_fix_sources.json"
    chunks = {c["id"]: c for c in _chunks()}
    if not report.exists():
        return  # 报告是运行脚本的产物，不入库时不阻塞
    data = json.loads(report.read_text(encoding="utf-8"))
    assert not data.get("errors"), data.get("errors")
    for row in data["upgraded"]:
        c = chunks.get(row["to"])
        assert c is not None, f"{row['id']} 指向不存在的分片 {row['to']}"
        assert _norm(row["quote"]) in _norm(c["text"]), \
            f"{row['id']} 证据不再逐字命中 {row['to']}"
        assert len(CJK.findall(row["quote"])) >= MIN_QUOTE, row["id"]
        assert c["source"] == row["work"], (row["id"], c["source"], row["work"])


def test_upgraded_items_point_to_reported_chunk():
    """落库后的题库与报告一致：升级过的题确实指向报告里的新分片。"""
    report = BACKEND.parent / ".local" / "d108_fix_sources.json"
    if not report.exists():
        return
    data = json.loads(report.read_text(encoding="utf-8"))
    want = {r["id"]: r["to"] for r in data["upgraded"]}
    got = {it["id"]: it["source_chunk_id"] for it in _items() if it["id"] in want}
    assert got == want, {k: (want[k], got.get(k)) for k in want if got.get(k) != want[k]}

# 依赖 sources/texts/ 原著正文；无正文时由 conftest.py 自动跳过。
import pytest

pytestmark = pytest.mark.needs_texts
