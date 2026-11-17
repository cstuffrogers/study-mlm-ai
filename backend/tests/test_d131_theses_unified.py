"""D131 门禁：《关于费尔巴哈的提纲》统一到库内通行本后，别再漂回别的译本。

三件事：
1. 后端 11 条条文必须能在库内原文文件里**逐字**查到（去掉排版空格后）；
2. 提纲知识点/概念的锚点分片必须落在通行本那 11 段（CH-MLTH-001…011）内，
   不能指到文件后半的德文版原稿译本（012…023）——那里讲的不是同一条；
3. 锚点分片必须真实存在。
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from content.book_chunks import all_book_chunks  # noqa: E402
from content.knowledge_graph import KNOWLEDGE_NODES  # noqa: E402
from content.theses_concepts import CONCEPTS  # noqa: E402
from content.theses_raw import THESES_RAW  # noqa: E402

THESES_FILE = ROOT.parent / "sources" / "texts" / "0-关于费尔巴哈的提纲.txt"
KEEP = re.compile(r"[^0-9A-Za-z\u4e00-\u9fff]+")


def _flat(s: str) -> str:
    return KEEP.sub("", s)


def _work_text() -> str:
    raw = THESES_FILE.read_bytes()
    for enc in ("utf-8", "gb18030"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    raise AssertionError("原文文件编码无法识别")


def test_eleven_theses_verbatim_in_library() -> None:
    assert len(THESES_RAW) == 11
    corpus = _flat(_work_text())
    for th in THESES_RAW:
        assert _flat(th["text"]) in corpus, f"{th['paragraph_id']} 已不是库内原文"


def test_theses_have_no_crossed_items() -> None:
    """第六条不能串进第七条（D132 修过的串条，别回来）。"""
    by_id = {th["paragraph_id"]: th["text"] for th in THESES_RAW}
    assert "费尔巴哈没有看到" not in by_id["th6"]
    assert "费尔巴哈没有看到" in by_id["th7"]


def test_old_translation_words_are_gone() -> None:
    """「在其现实性上」「社会的人类」是另一译本用词，库内通行本没有。"""
    joined = "".join(th["text"] for th in THESES_RAW)
    for bad in ("在其现实性上", "社会的人类", "人的社会或"):
        assert bad not in joined, f"11 条里又出现了《{bad}》"


def test_theses_anchors_point_into_versions_block() -> None:
    """提纲知识点/概念的锚点必须落在通行本 11 段内。"""
    present = {c["id"] for c in all_book_chunks()}
    allowed = {f"CH-MLTH-{i:03d}" for i in range(1, 12)}
    for node in KNOWLEDGE_NODES:
        cid = node.get("source_chunk_id")
        if not cid:
            continue
        assert cid in present, f"{node['name']} 锚点分片不存在：{cid}"
        if node["section_id"] == "sec_A_02":
            assert cid in allowed, f"{node['name']} 锚点指到了原稿译本：{cid}"
    for c in CONCEPTS:
        cid = c.get("source_id") or ""
        if cid.startswith("CH-MLTH"):
            assert cid in present, f"{c['name']} 锚点分片不存在：{cid}"
            assert cid in allowed, f"{c['name']} 锚点指到了原稿译本：{cid}"
