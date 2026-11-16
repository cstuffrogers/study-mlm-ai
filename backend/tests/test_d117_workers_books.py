"""D117 门禁：工人运动谱系补环（2 部）+ 概念词典补词

用户口径（2026-11）：「那按你的意见来处理」——即按实测重排后的优先级执行
「① 概念词典补词 → ② 工运线补书 → ③ 六个薄章节补白」。

本测试覆盖五类约束：

  1) **甄别**：2 部全部登记在 BOOKS，前缀/分片 id 唯一；邓中夏为 1930 年党内自述
     史学著作（正统／0.9），刘少奇 1926 年报告收《刘少奇选集》上卷（经典原著／1.0）；
     黑名单组织文献（菲共等）不得混入；
  2) **节选**：邓中夏只收「著者申明＋第五、七、九章」，从
     `sources/_backup_d117_pretrim/` 的裁剪前全文按 `TRIM` 重切必须与现库逐字节一致；
     刘少奇 1926 年报告为全文照录（无 TRIM、无备份）；
  3) **挂接**：3 条延伸阅读挂 sec_B_01 / sec_B_08 / sec_B_04，caution 如实声明保留与删去范围；
     另有 6 条薄章节补白，全部指向库内已有正文（不新增文本）；
  4) **检索**：概念词典标准名必须与分片 `concept_mentions` 用词一致，
     「工会／罢工」一类提问能召回真实分片（补词前为 0 命中）；
  5) **不膨胀**：章节数仍为 32，不新开章节。
"""
from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest

from content.book_chunks import BOOKS, all_book_chunks, available_works
from content.reading_extensions import READING_BLACKLIST, READING_EXTENSIONS
from content.reading_extensions_d117 import D117_EXTENSIONS
from content.routes import SECTIONS

ROOT = Path(__file__).resolve().parents[2]
TEXTS = ROOT / "sources" / "texts"
BACKUP = ROOT / "sources" / "_backup_d117_pretrim"

DENG = "1-中国职工运动简史节选.txt"
LIU = "1-工人阶级在革命中的地位与职工运动方针.txt"
D117_WORKS = (DENG, LIU)

# 新入库 2 部 → 期望挂载章节（同一条目按篇目差异分别挂三处）
EXPECTED_SECTION = {
    "《中国职工运动简史（1919—1926）》节选（1930）": "sec_B_01",
    "《中国职工运动简史》第七章「京汉路大罢工——‘二七’惨杀」（1930）": "sec_B_08",
    "《工人阶级在革命中的地位与职工运动方针》（1926）": "sec_B_04",
}

# 薄章节补白（全部指向库内已有正文，D117 未新增任何文本）
THIN_SECTIONS = {
    "sec_A_00": "《路德维希·费尔巴哈和德国古典哲学的终结》第二章「哲学基本问题」（1886）",
    "sec_A_01": "《唯物主义和经验批判主义》第二章「经验批判主义的认识论和辩证唯物主义的认识论」（1908）",
    "sec_A_12": "《德意志意识形态》第一章「费尔巴哈」（1846，节选）",
    "sec_B_02": "《法兰西内战》（1871）",
    "sec_C_03": "《论联合政府》（1945）",
    "sec_C_06": "《路易·波拿巴的雾月十八日》（1852）",
}

KEEP = {
    DENG: ("著者申明", "第一次全国劳动大会", "劳动立法运动", "京汉路大罢工",
           "没有一个强大的共产党", "不到五十人", "职工运动复兴期"),
    LIU: ("是确凿不移的", "以防备资产阶级骗卖自己", "工会中应有自卫的组织", "小资产阶级"),
}

# 裁去的章节标题必须以「独立成行」判断（正文提及不算残留）
DROP_LINES = {
    DENG: ("第一章 原始的职工运动", "第六章 开滦五矿大罢工",
           "第八章 职工运动消沉期", "第十章 上海日本纱厂大罢工"),
}

# D117 新增的概念词典标准名（必须同时是分片 mention 的原文用词）
NEW_CONCEPTS = (
    "工会", "职工运动", "罢工", "工人俱乐部", "群众路线", "群众组织", "工农联盟",
    "民主集中制", "党内斗争", "先锋队", "统一战线", "整风", "批评与自我批评",
    "调查研究", "妇女解放", "合作社", "白区工作", "领导方法", "阶级分析", "组织起来",
)


def _load_import_module():
    p = ROOT / "scripts" / "import_mirror.py"
    spec = importlib.util.spec_from_file_location("import_mirror_d117", p)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


# ----------------------------------------------------------------------------
# 1) 甄别与登记
# ----------------------------------------------------------------------------
def test_d117_books_registered_and_unique():
    files = {b["file"] for b in BOOKS}
    for f in D117_WORKS:
        assert f in files, f"未在 BOOKS 登记: {f}"
        assert (TEXTS / f).exists(), f"正文文件缺失: {f}"
    prefixes = [b["id_prefix"] for b in BOOKS]
    assert len(prefixes) == len(set(prefixes)), "id_prefix 有重复"
    ids = [c["id"] for c in all_book_chunks()]
    assert len(ids) == len(set(ids)), "分片 id 有重复"
    by_file = {b["file"]: b for b in BOOKS}
    assert by_file[DENG]["author"] == "邓中夏"
    assert by_file[DENG]["orthodoxy_tag"] == "正统"
    assert by_file[DENG]["authority_score"] == 0.9
    assert by_file[LIU]["author"] == "刘少奇"
    assert by_file[LIU]["orthodoxy_tag"] == "经典原著"
    assert by_file[LIU]["authority_score"] == 1.0


def test_d117_works_available():
    works = set(available_works())
    assert "中国职工运动简史（1919—1926）节选" in works
    assert "工人阶级在革命中的地位与职工运动方针" in works


# ----------------------------------------------------------------------------
# 2) 节选：可复现、边界正确
# ----------------------------------------------------------------------------
def test_d117_deng_excerpt_reproducible_from_backup():
    mod = _load_import_module()
    assert {p.name for p in BACKUP.glob("*.txt")} == {DENG}, \
        "裁剪前全文备份应且只应含邓中夏这一部（刘少奇为全文照录）"
    full = (BACKUP / DENG).read_text(encoding="utf-8")
    cur = (TEXTS / DENG).read_text(encoding="utf-8")
    assert len(cur) < len(full), "邓中夏未裁剪"
    ratio = len(cur) / len(full)
    assert 0.10 < ratio < 0.25, f"裁片比例异常: {ratio:.2%}"
    assert mod.apply_trim(DENG, full) == cur, "裁剪结果不可复现（原文被改写？）"


def test_d117_liu_full_text_not_trimmed():
    """刘少奇 1926 年报告为全文照录：不应出现在 TRIM 里，也不应有裁剪备份。"""
    mod = _load_import_module()
    assert LIU not in mod.TRIM, "刘少奇 1926 年报告应全文照录，不应设节选规则"
    assert not (BACKUP / LIU).exists(), "刘少奇为全文照录，不应有裁剪前备份"


def test_d117_kept_and_dropped_sections():
    for f, kws in KEEP.items():
        t = (TEXTS / f).read_text(encoding="utf-8")
        for k in kws:
            assert k in t, f"{f} 误删关键内容: {k}"
        assert "\n\n\n\n" not in t, f"{f} 段落结构被破坏（连续空行）"
    for f, kws in DROP_LINES.items():
        lines = [x.strip() for x in (TEXTS / f).read_text(encoding="utf-8").splitlines()]
        for k in kws:
            assert k not in lines, f"{f} 仍残留应裁章节标题: {k}"


# ----------------------------------------------------------------------------
# 3) 挂接
# ----------------------------------------------------------------------------
def test_d117_extensions_attached_with_local_work():
    works = set(available_works())
    total = 0
    for sid, items in D117_EXTENSIONS.items():
        assert sid in {s["id"] for s in SECTIONS}, f"挂到不存在的章节: {sid}"
        titles = {x["title"] for x in READING_EXTENSIONS[sid]}
        for it in items:
            total += 1
            assert it.get("local_work"), f"{it['title']} 缺 local_work"
            assert it["local_work"] in works, \
                f"{it['title']} local_work 指向不存在的正文: {it['local_work']}"
            assert it["title"] in titles, f"{it['title']} 未挂到 {sid}"
            assert it["kind"] in ("classic", "historical"), f"{it['title']} 分档异常"
            assert not it.get("link"), f"{it['title']} 已有本地正文，不应再跳外部链接"
            c = it.get("caution", "")
            assert c, f"{it['title']} 缺 caution"
            assert "一字未改" in c, f"{it['title']} caution 未声明原文一字未改"
            assert "D117" not in c and "TRIM" not in c, f"{it['title']} caution 暴露开发标记"
    assert total == len(EXPECTED_SECTION) + len(THIN_SECTIONS), f"条目数异常: {total}"


def test_d117_new_books_mounted_in_expected_sections():
    for title, sid in EXPECTED_SECTION.items():
        hits = [it for it in READING_EXTENSIONS[sid] if it["title"] == title]
        assert hits, f"{title} 未挂在 {sid}"
        it = hits[0]
        assert it["local_work"] in ("中国职工运动简史（1919—1926）节选",
                                    "工人阶级在革命中的地位与职工运动方针")
        c = it["caution"]
        if it["local_work"].startswith("中国职工运动简史"):
            # 邓中夏必须是节选，且如实说明只收哪几章
            assert "只收" in c and "章" in c, f"{title} caution 未声明只收哪几章"
            assert ("只删未选章节" in c) or ("节选" in c), \
                f"{title} caution 未如实声明为节选"
        else:
            assert "未作节选" in c, f"{title} 为全文照录，caution 应如实声明"


def test_d117_thin_sections_no_longer_single():
    for sid, title in THIN_SECTIONS.items():
        items = READING_EXTENSIONS[sid]
        assert len(items) >= 2, f"{sid} 仍只有 {len(items)} 条延伸阅读"
        assert title in {it["title"] for it in items}, f"{sid} 未补入: {title}"


# ----------------------------------------------------------------------------
# 4) 概念词典与检索
# ----------------------------------------------------------------------------
def test_d117_concept_dict_matches_chunk_mentions():
    """标准名必须与分片 mention 用词一致，否则图召回连不上（D117 的根因）。"""
    from content.book_chunks import _GENERIC_TERMS
    from core.rag.concept_dict import CONCEPT_MAP

    generic = set(_GENERIC_TERMS)
    for name in NEW_CONCEPTS:
        assert name in CONCEPT_MAP, f"概念词典缺标准名: {name}"
        assert name in generic, f"分片 mention 词表缺标准名: {name}"

    # 分片里确实有这些概念的出现记录（图召回才有边可连）
    mentions: dict[str, int] = {}
    for c in all_book_chunks():
        if not c["id"].startswith(("CH-ZGYD-", "CH-GRJD-")):
            continue
        for m in c.get("concept_mentions") or []:
            mentions[m] = mentions.get(m, 0) + 1
    assert mentions.get("工会", 0) > 0, "邓中夏分片缺「工会」提及"
    assert mentions.get("罢工", 0) > 0, "邓中夏分片缺「罢工」提及"


def test_d117_concept_extraction_works():
    from core.rag.concept_dict import ConceptDictionary

    d = ConceptDictionary()
    cases = {
        "党怎样领导工会？": "工会",
        "黄色工会怎么办": "工会",
        "安源罢工的经验": "罢工",
        "妇女解放怎么理解": "妇女解放",
        "民主集中制是什么": "民主集中制",
        "统一战线怎么搞": "统一战线",
    }
    for text, expect in cases.items():
        got = d.extract_concepts(text)
        assert expect in got, f"「{text}」未抽出概念 {expect}，实际 {got}"


@pytest.fixture(scope="module")
def retriever():
    """建一次索引（23,810 分片，约 15~20s），供召回断言复用。"""
    from core.rag.retriever import HybridRetriever

    r = HybridRetriever()
    r.index_chunks(all_book_chunks())
    return r


def test_d117_recall_reaches_workers_chunks(retriever):
    """补词前「党怎样领导工会」三路全空（n=0）；补词后必须召回真实分片。"""
    from types import SimpleNamespace

    ctx = retriever.retrieve(SimpleNamespace(
        content="党怎样领导工会？", selected_text="", paragraph_id="", mode="learn",
    ))
    assert ctx.text_chunks, "「党怎样领导工会」仍未召回任何分片"
    blob = "".join(getattr(c, "text", "") for c in ctx.text_chunks)
    assert "工会" in blob, "召回内容与提问不对口（未含「工会」）"


# ----------------------------------------------------------------------------
# 5) 红线与不膨胀
# ----------------------------------------------------------------------------
def test_d117_no_blacklisted_material():
    banned = ("菲共", "菲律宾共产党", "他加禄", "光辉道路", "印共（毛）")
    for b in BOOKS:
        blob = b["work"] + b["author"]
        for w in banned:
            assert w not in blob, f"黑名单相关材料混入正文库: {b['work']} → {w}"
    for sid, items in READING_EXTENSIONS.items():
        for it in items:
            blob = it["title"] + it.get("author", "") + it.get("intro", "")
            for w in banned:
                assert w not in blob, f"黑名单相关材料进入延伸阅读: {sid}/{it['title']} → {w}"
    assert any("反政府武装" in x or "恐怖组织" in x for x in READING_BLACKLIST), \
        "黑名单第 4 条（反政府武装/恐怖组织组织文献）缺失"


def test_d117_chapters_still_32():
    assert len(SECTIONS) == 32
    assert len({s["id"] for s in SECTIONS}) == 32
    assert set(D117_EXTENSIONS) <= {s["id"] for s in SECTIONS}
