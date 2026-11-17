# -*- coding: utf-8 -*-
"""D140 门禁：立场正则的「正统限定语豁免」+ 数据管线章节正则修复。

背景（为什么要有这组门禁）：
  - 旧规则把 **恩格斯本人的原话** 判成偏离——1890 年致布洛赫「并非只有经济状况
    才是原因……决定性因素归根到底是现实生活的生产和再生产」命中 mutual_determination
    的 `并非.*经济.*决定`；毛泽东《实践论》「机械反映论是错误的，马克思主义的
    反映论是能动的革命的反映论」命中 reject_reflection 的 `反映论是机械的`。
  - 豁免若无否决词，会变成绕过口子：只要塞一个「最终」就能把「相互决定」洗白。
  - text_loader 的章节正则 `.*?` 被 `$` 顶成整行，把 9 段正文当标题丢掉，
    并让 256 片 source_location 膨胀成整段正文。
"""
from __future__ import annotations

import pytest

from core.guard.orthodoxy import OrthodoxyGuard, EXEMPT_VETO_WORDS


@pytest.fixture(scope="module")
def guard() -> OrthodoxyGuard:
    return OrthodoxyGuard()


def _blocked(result: dict) -> bool:
    return result["action"] == "block"


# --------------------------------------------------------------- 正向：正统原话放行
ORT_ECON = (
    "根据唯物史观，历史过程中的决定性因素归根到底是现实生活的生产和再生产。"
    "经济状况是基础，但是对历史斗争的进程发生影响并且在许多情况下主要决定着"
    "这一斗争形式的，还有上层建筑的各种因素。"
)
# 恩格斯 1890 致布洛赫的原始表述：先「归根到底」再「不是唯一决定性的因素」。
# 注意：**裸**说「经济基础不是唯一决定因素」（无「归根到底/决定性的因素」这类
# 正统限定语）仍判偏离——那是标准的修正主义句式，`guard_critical_context_test`
# 已锁住这一条，不能为了放行恩格斯而给它开口子。
ORT_NOT_UNIQUE = (
    "历史过程中的决定性因素归根到底是现实生活的生产和再生产。"
    "经济不是唯一决定性的因素，但归根到底还是经济决定历史。"
)
ORT_REFLECTION = (
    "机械反映论是错误的，马克思主义的反映论是能动的革命的反映论，"
    "认识是主体对客体的能动反映。"
)


@pytest.mark.parametrize("text", [ORT_ECON, ORT_NOT_UNIQUE, ORT_REFLECTION])
def test_orthodox_quotes_not_blocked(guard: OrthodoxyGuard, text: str) -> None:
    """恩格斯 1890 致布洛赫、毛《实践论》的原话不能被判偏离。"""
    assert not _blocked(guard.check(text)), guard.check(text)


def test_exempt_recorded_as_citation(guard: OrthodoxyGuard) -> None:
    """豁免不是「看不见」，而是记录成 citation，便于事后审计。"""
    r = guard.check(ORT_NOT_UNIQUE)
    types = [f["type"] for f in r["flags"]]
    assert "stance_pattern_orthodox_exempt" in types, types


# --------------------------------------------------------------- 反向：真偏离照拦
DEVIATIONS = [
    "经济基础与上层建筑相互决定，二者互为决定。",
    "社会存在与社会意识是相互决定的。",
    "多种因素共同决定历史进程。",
    "经济基础不是唯一决定，文化同样决定历史进程。",
    "反映论是被动的。",
    "认识不是反映，只是主体建构。",
]


@pytest.mark.parametrize("text", DEVIATIONS)
def test_real_deviation_still_blocked(guard: OrthodoxyGuard, text: str) -> None:
    assert _blocked(guard.check(text)), guard.check(text)


def test_veto_words_block_exemption(guard: OrthodoxyGuard) -> None:
    """塞一个「归根到底」来给「相互决定」洗白 → 否决词拦下。"""
    text = "经济基础与上层建筑相互决定，归根到底两者共同决定历史。"
    assert _blocked(guard.check(text)), guard.check(text)
    assert "共同决定" in EXEMPT_VETO_WORDS


def test_reflection_deviation_without_critical_word(guard: OrthodoxyGuard) -> None:
    """『反对反映论』自带「反对」这个批判词，会被同句豁免放行（已知保守边界，
    属漏拦不属误拦）。这里钉住「同一规则的另一句式仍能拦」，防止整条规则失效。"""
    r = guard.check("反映论是被动的，认识不是反映。")
    rules = [f.get("rule") for f in r["flags"]]
    assert "reject_reflection" in rules, r


# --------------------------------------------------------------- 数据管线：章节正则
CH_HEAD_OK = [
    "第一章 商品",
    "第二篇 货币转化为资本",
    "第三章 国家与革命。1848—1851年的经验",
]
CH_HEAD_BAD = [
    # 曾经被 `.*?` 吃成标题的正文（真实数据）
    "第一章第一节更加科学而严密地从表现每个交换价值的等式的分析中引出了价值，"
    "而且只是在限定的形式中才引出价值。",
    "第一篇宣言曾经预言，如果德国反对路易·波拿巴的防御战争蜕变为反对法国人民的"
    "掠夺战争，德国在所谓解放战争之后所遭到的那一切不幸，将会变本加厉地重新落到"
    "它的头上。",
]


def test_chapter_head_accepts_real_titles() -> None:
    from content.text_loader import _is_chapter_head
    for t in CH_HEAD_OK:
        assert _is_chapter_head(t), t


def test_chapter_head_rejects_long_paragraphs() -> None:
    from content.text_loader import _is_chapter_head
    for t in CH_HEAD_BAD:
        assert not _is_chapter_head(t), t


def test_chapter_head_rejects_comma() -> None:
    from content.text_loader import _is_chapter_head
    assert not _is_chapter_head("第一章 商品，是用于交换的劳动产品")


# 修复前被当标题丢掉、从未进分片的 9 段正文（逐条对照真实数据）
RECOVERED = [
    ("法兰西内战", "第一篇宣言曾经预言，如果德国反对路易·波拿巴的防御战争"),
    ("资本论（第一卷节选）", "第一章第一节更加科学而严密地从表现每个交换价值的等式的分析中引出了价值"),
    ("反对党八股", "今天会场上散发了一个题名《宣传指南》的小册子"),
    ("资本论（第二卷）", "第二十章：第一节（第435—438页）采自第Ⅱ稿"),
    ("资本论（第三卷）", "第一篇所阐述的关于利润率提高和降低的一切规律"),
    ("马克思的经济学说", "第一篇谈的主要是商品市场的问题"),
]


def test_previously_dropped_paragraphs_are_indexed() -> None:
    """收文不漏：这 9 段是正文，必须出现在分片里（旧正则把它们当章标题 continue 掉了）。"""
    from content.book_chunks import all_book_chunks
    chunks = all_book_chunks()
    for work, head in RECOVERED:
        blob = "".join(c["text"] for c in chunks if c.get("source") == work)
        assert head in blob, f"{work} 缺正文：{head[:20]}"


def test_source_location_never_long() -> None:
    """source_location 是「第N段」短标签，>50 字即为正文串行（旧正则的后果）。"""
    from content.book_chunks import all_book_chunks
    longs = [(c["id"], c["source_location"]) for c in all_book_chunks()
             if c.get("source_location") and len(c["source_location"]) > 50]
    assert not longs, f"{len(longs)} 片 source_location 过长，例：{longs[:3]}"
