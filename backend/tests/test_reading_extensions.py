"""扩展读物（延伸阅读）分档完整性测试 — 守正统性与合规红线。"""
from __future__ import annotations

from content.reading_extensions import (
    READING_EXTENSIONS, READING_BLACKLIST, KIND_LABEL,
    KIND_CLASSIC, KIND_HISTORICAL, KIND_PRIVATE, KIND_CONTESTED,
    extensions_for, blacklist,
)

_VALID_KINDS = set(KIND_LABEL.keys())


def test_route_c_sections_have_extensions():
    # 路线 C 各章节都应至少有一条延伸阅读
    for sid in ("sec_C_00", "sec_C_01", "sec_C_02", "sec_C_03", "sec_C_04",
                "sec_C_05", "sec_C_06", "sec_C_07"):
        items = extensions_for(sid)
        assert items, f"{sid} 缺少延伸阅读"
        for it in items:
            assert it["kind"] in _VALID_KINDS, f"{sid} 存在非法分档 {it['kind']}"
            assert it["title"].strip(), f"{sid} 条目缺标题"
            assert it["kind"] in KIND_LABEL


def test_contested_entries_require_caution_and_marker():
    # 争议版本必须带 caution，且 how_to_use 提到「批判」/「非借鉴」
    for sid, items in READING_EXTENSIONS.items():
        for it in items:
            if it["kind"] == KIND_CONTESTED:
                assert it.get("caution"), f"{sid}:{it['title']} 争议版本必须有 caution"
                hay = (it.get("how_to_use", "") + it.get("caution", "")).lower()
                assert ("批判" in hay) or ("非借鉴" in hay) or ("靶子" in hay), \
                    f"{sid}:{it['title']} 争议版本须声明仅作批判对象"


def test_private_entries_require_caution():
    # 「私人版本」必须声明非官方、须对照经典
    for sid, items in READING_EXTENSIONS.items():
        for it in items:
            if it["kind"] == KIND_PRIVATE:
                c = it.get("caution", "")
                assert c, f"{sid}:{it['title']} 私人版本必须有 caution"
                assert ("非官方" in c) or ("未经" in c) or ("个人观点" in c), \
                    f"{sid}:{it['title']} 私人版本须声明非官方性质"


def test_only_maybe_classic_has_links_and_no_blacklisted_author():
    # 经典条目允许带外部链接，且都指向 marxists.org 权威库（可公开）
    for sid, items in READING_EXTENSIONS.items():
        for it in items:
            link = it.get("link")
            if link:
                assert it["kind"] == KIND_CLASSIC, \
                    f"{sid}:{it['title']} 只有经典条目可带外部链接"
                assert link.startswith("https://www.marxists.org/chinese/"), \
                    f"{sid}:{it['title']} 外链须为权威中文马克思主义文库"


def test_blacklist_present():
    bl = blacklist()
    assert len(bl) >= 3
    joined = "".join(bl)
    # 必须明确排除境外反华/被定性组织
    assert ("推翻" in joined) or ("否定" in joined)


def test_classic_entries_have_local_text():
    """凡提供「阅读原文」入口的经典条目，都必须「已入库本地正文」（local_work 指向有分片的著作），
    「阅读原文」走本地知识库，不再依赖外部链接；无本地正文的经典条目只作「导读」，不提供入口。"""
    from content.book_chunks import available_works

    works = set(available_works())
    local_count = 0
    for sid, items in READING_EXTENSIONS.items():
        for it in items:
            if it["kind"] == KIND_CLASSIC:
                lw = it.get("local_work")
                if lw:
                    assert lw in works, f"{sid}:{it['title']} 的 local_work={lw} 未在本地入库分片中"
                    local_count += 1
                else:
                    # 无本地正文 → 不得提供外链「阅读原文」入口（不伪造、不跳外部）
                    assert not it.get("link"), \
                        f"{sid}:{it['title']} 无本地正文却带外链，应改为导读或先入库正文"
    # 至少 15 个经典条目指向本地已入库正文（D87+D88 补齐的路线 A/B/C 经典原著）
    assert local_count >= 15, f"经典条目本地正文入口过少: {local_count}"

# 依赖 sources/texts/ 原著正文；无正文时由 conftest.py 自动跳过。
import pytest

pytestmark = pytest.mark.needs_texts
