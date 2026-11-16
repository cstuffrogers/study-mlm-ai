"""D99 门禁：A 组（周恩来章补实）+ B 组（谱系补环）落地校验。

红线（原）：全部为导读型延伸阅读 —— 无 local_work、无外链、caution 明示仅导读。
更新（D 盘镜像补录 22 部原文后）：D99 大部分条目已由 `content.mirror_upgrades`
升级为「可阅读原文」——挂 local_work、caution 改为版本/节选声明；
仍无正文的条目保持导读。两种状态都不得带外链、不得伪造正文。
另守「不膨胀」：章节数不变（32 章），只向既有章节追加条目。
"""
from __future__ import annotations

import pytest

from content.reading_extensions import READING_EXTENSIONS, extensions_for, KIND_CLASSIC
from content.routes import SECTIONS

EXPECTED_SECTION_COUNT = 32

# A 组：sec_B_04「怎样做一个好的领导者」——精简后保留 4 条核心
ZHOU_KEEP = [
    "在白色恐怖下如何健全党的组织工作",
    "怎样做一个好的领导者",
    "反对官僚主义",
    "关于领导方法的若干问题",
]

# B 组：(章节, 关键词) —— 精简后 6 条
B_GROUP = [
    ("sec_A_02", "在马克思墓前的讲话"),
    ("sec_A_08", "1857-1858"),
    ("sec_A_14", "思想起源论"),
    ("sec_B_01", "论列宁主义基础"),
    ("sec_B_01", "论权威"),
    ("sec_B_05", "星星之火"),
    ("sec_C_04", "苏联社会主义经济问题"),
]


def _hay(sid: str) -> str:
    return "".join(f"{it['title']}{it.get('author', '')}" for it in extensions_for(sid))


def test_section_count_not_inflated():
    assert len(SECTIONS) == EXPECTED_SECTION_COUNT, "D99 不应新增章节，只向既有章节追加条目"


def test_b04_no_longer_empty():
    """sec_B_04 此前是唯一的空壳章（local_work 为空且零延伸阅读）。"""
    items = extensions_for("sec_B_04")
    assert len(items) >= 4, f"sec_B_04 延伸阅读不足: {len(items)}"
    hay = _hay("sec_B_04")
    for kw in ZHOU_KEEP:
        assert kw in hay, f"sec_B_04 缺《{kw}》"


@pytest.mark.parametrize("sid,keyword", B_GROUP)
def test_b_group_entries_present(sid: str, keyword: str):
    assert keyword in _hay(sid), f"{sid} 缺 B 组条目: {keyword}"


def test_all_d99_entries_are_guide_only():
    """D99 条目结构门禁：导读型 / 已入库型二选一，均不得外链或冒充原文。

    原「一律导读」断言已随 D 盘镜像补录升级：确有原文的条目挂 local_work，
    caution 改为版本与节选声明；仍无正文的保留『仅导读』措辞。
    """
    from content.book_chunks import available_works

    works = set(available_works())
    d99_sids = {"sec_B_04", "sec_A_02", "sec_A_08", "sec_A_14", "sec_B_01", "sec_B_05", "sec_C_04"}
    d99_titles = {kw for kw in ZHOU_KEEP} | {kw for _, kw in B_GROUP}
    checked = 0
    ingested = 0
    for sid in d99_sids:
        for it in extensions_for(sid):
            if not any(kw in it["title"] for kw in d99_titles):
                continue
            checked += 1
            assert it["kind"] == KIND_CLASSIC, f"{sid}:{it['title']} 应为经典档"
            assert not it.get("link"), f"{sid}:{it['title']} 不得外链跳转"
            caution = it.get("caution", "")
            lw = it.get("local_work")
            if lw:
                ingested += 1
                assert lw in works, f"{sid}:{it['title']} local_work={lw} 未真实入库"
                # 已入库 → 不得再向用户声明「无正文 / 仅导读」
                assert "仅导读" not in caution, \
                    f"{sid}:{it['title']} 已入库仍声明仅导读"
                assert "本篇为" in caution or "节选" in caution, \
                    f"{sid}:{it['title']} 缺版本/节选声明"
                for word in ("本机", "知识库", "入库", "镜像", "分片"):
                    assert word not in caution, \
                        f"{sid}:{it['title']} caution 仍含内部术语「{word}」"
            else:
                assert "导读" in caution, f"{sid}:{it['title']} 导读条目 caution 须声明仅导读"
            assert it.get("points"), f"{sid}:{it['title']} 缺要点"
            assert it.get("how_to_use"), f"{sid}:{it['title']} 缺怎么用"
    assert checked >= 10, f"D99 条目数异常: {checked}"
    assert ingested >= 8, f"镜像补录后已入库的 D99 条目过少: {ingested}"


def test_no_trotsky_or_critique_targets_leaked_in():
    """托洛茨基系列与第 6 阶段批判对象不得进入正面学习路径（红线）。"""
    banned = ["托洛茨基", "不断革命论", "被背叛的革命", "卢卡奇", "葛兰西", "阿尔都塞", "哈耶克", "波普尔"]
    for sid, items in READING_EXTENSIONS.items():
        for it in items:
            hay = f"{it['title']}{it.get('author', '')}"
            for b in banned:
                assert b not in hay, f"{sid}:{it['title']} 触碰红线（{b}）"

# 依赖 sources/texts/ 原著正文；无正文时由 conftest.py 自动跳过。
pytestmark = pytest.mark.needs_texts
