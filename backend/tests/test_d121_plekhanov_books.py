"""D121 门禁：普列汉诺夫前期哲学著作 2 篇（1898／1895）

收录边界（本批最重要的约束，写死在这里）：

  * **只收 1883—1903 年马克思主义时期的理论著作**。1903 年二大后转孟什维克、
    一战期间护国主义、1917 年反对十月革命这条线上的文字一律不入库，
    《在祖国的一年》永作争议版本。故普列汉诺夫名下的正文只允许出现三个文件：
    《论一元论历史观的发展》（既有）＋本批 2 篇；
  * 作者是理论来源、不是路线标杆，分档写「正统／0.9」，不写「经典原著／1.0」，
    与列宁、毛泽东原文区分开；
  * 两篇均**全文照录**，不设节选规则、不做裁剪备份。

测试覆盖：

  1) 甄别与登记：BOOKS 唯一前缀／slug／分片 id；分档与权威分；黑名单；白名单
  2) 照录：不在 TRIM、无裁剪备份、首行即篇名、关键句逐篇坐实、导航行零残留
  3) 溯源：篇首或篇末必须带中译版本说明（这两篇是按篇首版本说明溯源的，
     与周恩来那批按篇末编者附记溯源不同——断言必须查全文而非只看篇末）
  4) 引文逐字在文（20 处引文；覆盖 <15 条即判门禁失效）
  5) 挂接 sec_A_14 / sec_A_07、local_work 指向真实正文、caution 一字未改且无开发标记
  6) 不膨胀：章节数 32；普列汉诺夫正文件数 3；概念词典标准名与分片 mention 一致

坑位记录：正文保留了镜像页面的加粗残留空格（「政治制度在成为 原因 之前是 结果」、
「诸 必然 过程的交会点」），这是照录，不是错字；引文比对必须先剥空白与注释锚。
"""
from __future__ import annotations

import importlib.util
import re
from pathlib import Path

from content.book_chunks import BOOKS, _GENERIC_TERMS, _terms, all_book_chunks, available_works
from content.reading_extensions import READING_BLACKLIST, READING_EXTENSIONS
from content.reading_extensions_d121 import D121_EXTENSIONS
from content.routes import SECTIONS
from core.rag.concept_dict import CONCEPT_MAP, ConceptDictionary

ROOT = Path(__file__).resolve().parents[2]
TEXTS = ROOT / "sources" / "texts"
BACKUP_DIRS = ("_backup_d116_pretrim", "_backup_d117_pretrim", "_backup_d118_pretrim",
               "_backup_d101_pretrim", "_backup_d102_pretrim")

# 文件 → (work, 溯源关键词元组（任一命中即可）)
WORKS = {
    "1-个人在历史上的作用问题.txt": (
        "个人在历史上的作用问题",
        ("按：本文以基尔桑诺夫为笔名发表在彼得堡出版的科学和社会政治刊物《科学评论》杂志1898年第3、4期上",
         "说明：本文为中央编译出版社根据《普列汉诺夫哲学著作选集》所录版本",
         "《普列汉诺夫读本》重新编译的版本"),
    ),
    "1-奥古斯丹·梯叶里和唯物史观.txt": (
        "奥古斯丹·梯叶里和唯物史观",
        ("中译文来自《马列主义研究资料》1982年第2辑",
         "收录于《格·瓦·普列汉诺夫全集》俄文第2版第8卷第9—25页",
         "1895年11月（王荫庭 译）"),
    ),
}

KEY_LINES = {
    "1-个人在历史上的作用问题.txt": (
        "个人在历史上的作用问题是历史观中与实践联系最密切的重要问题之一",
        "自由是认识了的必然性",
        "领导人物的个人特点决定历史事变的个别外貌",
        "偶然性是某种相对的东西",
    ),
    "1-奥古斯丹·梯叶里和唯物史观.txt": (
        "制度在成为原因以前是结果",
        "人民、整个民族应当成为历史的主人公",
        "任何阶级斗争都是政治斗争",
        "他第一个揭示了人类历史运动的真正原因",
    ),
}

EXPECTED = {
    "sec_A_14": ("个人在历史上的作用问题",),
    "sec_A_07": ("奥古斯丹·梯叶里和唯物史观",),
}

# 普列汉诺夫名下允许入库的全部正文（白名单：只到 1903 年）
PLEKHANOV_ALLOWED = {
    "3-论一元论历史观的发展.txt",
    "1-个人在历史上的作用问题.txt",
    "1-奥古斯丹·梯叶里和唯物史观.txt",
}


def _load_import_module():
    p = ROOT / "scripts" / "import_mirror.py"
    spec = importlib.util.spec_from_file_location("import_mirror_d121", p)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


def _norm_for_quote(s: str) -> str:
    """剥掉注释锚（〔10〕／[262]）与所有空白，供引文逐字比对。"""
    return re.sub(r"\s+", "", re.sub(r"〔\d+〕|［\d+］|\[\d+\]", "", s))


# ----------------------------------------------------------------------------
# 1) 甄别与登记
# ----------------------------------------------------------------------------
def test_d121_books_registered_and_unique():
    files = {b["file"] for b in BOOKS}
    for f, (work, _) in WORKS.items():
        assert f in files, f"未在 BOOKS 登记: {f}"
        assert (TEXTS / f).exists(), f"正文文件缺失: {f}"
    prefixes = [b["id_prefix"] for b in BOOKS]
    assert len(prefixes) == len(set(prefixes)), "id_prefix 有重复"
    slugs = [b["slug"] for b in BOOKS]
    assert len(slugs) == len(set(slugs)), "slug 有重复"
    ids = [c["id"] for c in all_book_chunks()]
    assert len(ids) == len(set(ids)), "分片 id 有重复"
    by_file = {b["file"]: b for b in BOOKS}
    for f, (work, _) in WORKS.items():
        b = by_file[f]
        assert b["work"] == work, f"{f} work 登记不符"
        assert b["author"] == "普列汉诺夫", f"{f} 作者登记不符"
        # 作者是理论来源、不是路线标杆：写「正统 0.9」，与列宁／毛泽东原文区分开
        assert b["orthodoxy_tag"] == "正统", f"{f} 分档应为正统（不是经典原著）"
        assert b["authority_score"] == 0.9, f"{f} 权威分应为 0.9"


def test_d121_works_available():
    works = set(available_works())
    for _, (work, _) in WORKS.items():
        assert work in works, f"可用正文缺: {work}"


def test_d121_no_blacklisted_material():
    banned = ("菲共", "菲律宾共产党", "光辉道路", "印共（毛）", "反政府武装", "恐怖组织")
    for f, (work, _) in WORKS.items():
        blob = work + (TEXTS / f).read_text(encoding="utf-8")
        for w in banned:
            assert w not in blob, f"{f} 命中黑名单词: {w}"
    assert any("菲共" in x or "反政府武装" in x for x in READING_BLACKLIST), \
        "黑名单第 4 条（反政府武装／恐怖组织文献）必须仍在"


def test_d121_only_pre_1903_works_by_plekhanov():
    """只收马克思主义时期（1883—1903）的理论著作：白名单外一律不得入库。"""
    got = {b["file"] for b in BOOKS if b["author"] == "普列汉诺夫"}
    assert got == PLEKHANOV_ALLOWED, f"普列汉诺夫入库范围越界: {sorted(got)}"
    assert len(got) == 3, f"普列汉诺夫正文件数应为 3（既有 1 + 本批 2），实际 {len(got)}"


# ----------------------------------------------------------------------------
# 2) 全文照录（不设节选）
# ----------------------------------------------------------------------------
def test_d121_full_text_not_trimmed():
    mod = _load_import_module()
    for f in WORKS:
        assert f not in getattr(mod, "TRIM", {}), f"{f} 应全文照录，不应设节选规则"
        for d in BACKUP_DIRS:
            assert not (ROOT / "sources" / d / f).exists(), \
                f"{f} 为全文照录，不应出现在裁剪前备份 {d}"


def test_d121_first_line_is_title_and_structure_intact():
    for f, (work, _) in WORKS.items():
        t = (TEXTS / f).read_text(encoding="utf-8")
        first = t.splitlines()[0].strip()
        assert first.startswith(work), f"{f} 首行不是篇名: {first!r}"
        assert t.count(work) >= 1
        # 首行之后不应立刻重复篇名（网页顶部重复输出必须已剔除）
        head = [x.strip() for x in t.splitlines()[1:6] if x.strip()]
        assert work not in head, f"{f} 篇名重复输出未剔除: {head}"
        assert len(t) > 8000, f"{f} 正文过短，疑被截断"
        assert "\n\n\n\n" not in t, f"{f} 段落结构被破坏（连续空行）"
        lines = [x.strip() for x in t.splitlines()]
        assert "中文马克思主义文库" not in lines, f"{f} 混入导航行"
        assert not any(x.startswith("->") for x in lines), f"{f} 混入面包屑"
        assert not any(x.startswith("感谢") and "校对" in x for x in lines), \
            f"{f} 混入站点录入致谢行"
        for kw in KEY_LINES[f]:
            assert kw in t, f"{f} 关键句缺失（原文被改写？）: {kw}"


# ----------------------------------------------------------------------------
# 3) 溯源（按篇首版本说明，须查全文）
# ----------------------------------------------------------------------------
def test_d121_traceable_to_chinese_edition():
    for f, (_, kws) in WORKS.items():
        t = (TEXTS / f).read_text(encoding="utf-8")
        assert any(kw in t for kw in kws), \
            f"{f} 缺中译版本说明（篇首或篇末）: {kws}"


# ----------------------------------------------------------------------------
# 4) 引文逐字在文
# ----------------------------------------------------------------------------
def test_d121_quotes_verbatim_in_source():
    body = {f: _norm_for_quote((TEXTS / f).read_text(encoding="utf-8")) for f in WORKS}
    by_work = {WORKS[f][0]: f for f in WORKS}
    checked = 0
    for sid, items in D121_EXTENSIONS.items():
        for it in items:
            f = by_work[it["local_work"]]
            for field in ("intro", "points", "how_to_use", "caution"):
                val = it[field]
                chunks = [val] if isinstance(val, str) else val
                for s in chunks:
                    for q in re.findall(r"[「『]([^」』]+)[」』]", s):
                        q2 = _norm_for_quote(q).replace("……", "")
                        if len(q2) < 6:
                            continue
                        checked += 1
                        assert q2 in body[f], (
                            f"{sid}／{it['title']} 的 {field} 引文不在正文里：{q}")
    assert checked >= 15, f"引文核对覆盖不足（{checked} 条），门禁形同虚设"


# ----------------------------------------------------------------------------
# 5) 挂接
# ----------------------------------------------------------------------------
def test_d121_extensions_attached_with_local_work():
    works = set(available_works())
    section_ids = {s["id"] for s in SECTIONS}
    total = 0
    for sid, items in D121_EXTENSIONS.items():
        assert sid in section_ids, f"挂到不存在的章节: {sid}"
        titles = {x["title"] for x in READING_EXTENSIONS[sid]}
        for it in items:
            total += 1
            assert it.get("local_work"), f"{it['title']} 缺 local_work"
            assert it["local_work"] in works, \
                f"{it['title']} local_work 指向不存在的正文: {it['local_work']}"
            assert it["title"] in titles, f"{it['title']} 未挂到 {sid}"
            assert it["kind"] == "classic", f"{it['title']} 分档应为经典原文"
            assert not it.get("link"), f"{it['title']} 已有本地正文，不应再跳外部链接"
            for k in ("intro", "points", "how_to_use"):
                assert it.get(k), f"{it['title']} 缺 {k}"
            c = it.get("caution", "")
            assert c, f"{it['title']} 缺 caution"
            assert "一字未改" in c, f"{it['title']} caution 未声明正文一字未改"
            assert "孟什维克" in c, f"{it['title']} caution 未声明作者后期立场"
            assert not re.search(r"D\d{2,3}|TRIM|sec_[A-C]_\d\d|OCR|入库|镜像", c), \
                f"{it['title']} caution 暴露开发标记"
    assert total == 2, f"条目数异常: {total}"


def test_d121_mounted_in_expected_sections():
    for sid, keys in EXPECTED.items():
        titles = [it["title"] for it in READING_EXTENSIONS[sid]]
        for k in keys:
            assert any(k in t for t in titles), f"{sid} 未挂入: {k}"


# ----------------------------------------------------------------------------
# 6) 规模与概念词典
# ----------------------------------------------------------------------------
def test_d121_chapters_still_32():
    assert len(SECTIONS) == 32, "不得新开章节"


def test_d121_concept_terms_match_chunk_mentions():
    """标准名必须是分片 mention 里真实出现的原文用词：「个人在历史上的作用」正文 8 次、
    「杰出人物」3 次；「必然」「偶然」「自由」「必然性」沿用既有哲学词族。"""
    for term in ("个人在历史上的作用", "杰出人物"):
        assert term in _GENERIC_TERMS, f"{term} 未进 mention 词表"
        assert term in _terms(), f"{term} 未进 _terms()"
    assert "个人在历史上的作用" in CONCEPT_MAP, "未进 CONCEPT_MAP"
    d = ConceptDictionary()
    assert d.extract_concepts("个人在历史上的作用") == ["个人在历史上的作用"]
    assert d.extract_concepts("杰出人物的作用") == ["个人在历史上的作用"]
    rep = [c for c in all_book_chunks() if c["source"] == "个人在历史上的作用问题"]
    assert rep, "缺少《个人在历史上的作用问题》分片"
    mentions = {m for c in rep for m in c["concept_mentions"]}
    assert "个人在历史上的作用" in mentions, \
        f"分片侧未抽到 mention: {sorted(mentions)[:20]}"

# 依赖 sources/texts/ 原著正文；无正文时由 conftest.py 自动跳过。
import pytest

pytestmark = pytest.mark.needs_texts
