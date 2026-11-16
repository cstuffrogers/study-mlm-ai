"""读者可见文案里不得出现开发期内部术语（章节 id、书单文件名、镜像路径、分片编码等）。

背景：延伸阅读 / 导读 / 知识点说明都是给学习者看的。曾经的示例：

    「路线 B、《路径.txt》 sec_C_03、说辞」

这类内容属于知识开发期的内部逻辑，展示出来会引起误解，必须换成读者向表述。
本用例遍历所有会被前端展示的字符串（导读、知识点、延伸阅读、题库解析），
一旦再次出现内部术语就失败，防止回潮。
"""
import json
import re
from pathlib import Path

import pytest

from content.chapter_content import guide_for, nodes_for_section
from content.reading_extensions import extensions_for
from content.routes import SECTIONS

# 内部术语：章节 id / 路线编号 / 书单与路径文档 / 入库与镜像口吻 / 分片编码 / 实现细节
JARGON = re.compile(
    r"(路径\.txt|学习顺序\d?\.md|书籍\.md|扩展读物\.md|专读\.md|\.md\b|\.txt\b"
    r"|sec_[A-C]_\d\d|route_[A-C]|路线\s*[ABC]|[ABC]\s?路线"
    r"|(?<![A-Za-z])D\d{2,3}(?![0-9])"
    r"|CH-[A-Z]|GUIDE-|kn_[a-z]|q_[a-c]\d"
    r"|源表|未落地|镜像|本机|知识库|入库|分片"
    r"|PDF|OCR|HTML|D 盘|TRIM|import_mirror|manifest|blacklist|TODO|占位)"
)

# 这些字段是数据/标识，不面向读者，允许出现内部编码
DATA_KEYS = {
    "id", "chunk_id", "source_chunk_id", "first_chunk_id", "paragraph_id",
    "local_work", "work_short", "section_id", "node_id", "route_id", "source",
    "dependents", "prerequisites", "foundation_ref", "source_id",
    "source_location", "work", "link", "kind",
}


def _collect(obj, path=""):
    """递归收集所有面向读者的字符串及其位置。"""
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in DATA_KEYS:
                continue
            yield from _collect(v, f"{path}/{k}")
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            yield from _collect(v, f"{path}[{i}]")
    elif isinstance(obj, str) and obj:
        yield path, obj


def _bad(texts):
    bad = []
    for path, text in texts:
        m = JARGON.search(text)
        if m:
            bad.append(f"{path}: 「{m.group(0)}」 ← {text[:60]}")
    return bad


def test_guide_texts_have_no_internal_jargon():
    bad = []
    for sec in SECTIONS:
        sid = sec["id"]
        g = guide_for(sid) or {}
        bad += _bad(list(_collect(g, f"{sid}/guide")))
        bad += _bad(list(_collect(nodes_for_section(sid) or [], f"{sid}/nodes")))
    assert not bad, "导读/知识点出现内部术语：\n" + "\n".join(bad)


def test_extensions_have_no_internal_jargon():
    bad = []
    for sec in SECTIONS:
        sid = sec["id"]
        bad += _bad(list(_collect(extensions_for(sid), f"{sid}/extensions")))
    assert not bad, "延伸阅读出现内部术语：\n" + "\n".join(bad)


def test_quiz_bank_has_no_internal_jargon():
    bank = Path(__file__).resolve().parents[1] / "content" / "quiz_bank"
    bad = []
    for f in sorted(bank.glob("*.json")):
        data = json.loads(f.read_text(encoding="utf-8"))
        bad += _bad(list(_collect(data.get("items", []), f.name)))
    assert not bad, "题库出现内部术语：\n" + "\n".join(bad)


@pytest.mark.parametrize("section_id", ["sec_B_04", "sec_C_02", "sec_C_04"])
def test_samples_read_like_user_copy(section_id):
    """抽查重点章节：延伸阅读文案里不应再出现「路线 B」「路径.txt」「sec_」等字样。"""
    blob = json.dumps(extensions_for(section_id), ensure_ascii=False)
    for token in ("路径.txt", "sec_", "路线 B", "路线 C", "路线 A", "本机", "镜像"):
        assert token not in blob, f"{section_id} 仍含 {token}"
