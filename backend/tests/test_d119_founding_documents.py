"""D119 门禁：建党文献原文（1920—1925）——《中共中央文件选集》第一册 10 篇

背景：D118 补的是「建党前史」的个人著述（李大钊、蔡和森），库里仍没有一份党的本体文件
（纲领、决议、章程、组织问题议决案），`sec_B_01`／`sec_B_04` 只能讲列宁的党，
讲不到中国党自己的组织构造。本轮补 10 篇，全部**全文照录**（含篇内说明、注释与卷末注文），
不设节选规则、不做裁剪备份。

本测试覆盖五类约束：

  1) **甄别**：10 部全部登记在 BOOKS，前缀／分片 id 唯一；一律按「正统 0.9」
     （党的文件，非个人经典原著）；不命中黑名单；
  2) **照录**：10 篇都不在 TRIM 里、无裁剪备份；首行即篇名；关键句逐篇坐实；
  3) **可溯源**：每篇篇末必须带刊印依据（「根据……刊印」或
     「译自中共驻共产国际代表团档案的俄文稿」）——这是本批唯一的收文口径；
  4) **挂接**：10 条延伸阅读挂 sec_B_01 / sec_B_04 / sec_B_08 / sec_C_02 / sec_C_06，
     local_work 指向真实正文，caution 必须声明「一字未改」且不含开发标记；
  5) **不膨胀**：章节数仍为 32，不新开章节；建党文献（文件类）正文件数为 10。

坑位记录：这几篇的标题行常带网页脚注锚（如「中国共产党第一个决议 [1]」），
首行判定用 `startswith(work)` 而非严格相等；导航行判定按整行精确匹配，
不做全文字串匹配（《第二个决议》注释里合法引用文库名，子串断言会误伤）。
"""
from __future__ import annotations

import importlib.util
import re
from pathlib import Path

from content.book_chunks import BOOKS, all_book_chunks, available_works
from content.reading_extensions import READING_BLACKLIST, READING_EXTENSIONS
from content.reading_extensions_d119 import D119_EXTENSIONS
from content.routes import SECTIONS

ROOT = Path(__file__).resolve().parents[2]
TEXTS = ROOT / "sources" / "texts"
BACKUP_DIRS = ("_backup_d116_pretrim", "_backup_d117_pretrim",
               "_backup_d118_pretrim", "_backup_d101_pretrim", "_backup_d102_pretrim")

# 文件 → (work, author, 溯源关键词元组)
WORKS = {
    "1-中国共产党第一个纲领.txt": (
        "中国共产党第一个纲领", "中国共产党第一次全国代表大会",
        ("译自中共驻共产国际代表团档案的俄文稿", "注释")),
    "1-中国共产党第一个决议.txt": (
        "中国共产党第一个决议", "中国共产党第一次全国代表大会",
        ("译自中共驻共产国际代表团档案的俄文稿", "第三国际远东书记处")),
    "1-中国共产党宣言.txt": (
        "中国共产党宣言", "中国共产党上海发起组",
        ("根据中共驻共产国际代表团档案刊印", "一九二一年十二月十日")),
    "1-中国共产党章程.txt": (
        "中国共产党章程", "中国共产党第二次全国代表大会",
        ("根据一九二二年七月印行的《中国共产党第二次全国大会决议案》刊印",)),
    "1-关于共产党的组织章程决议案.txt": (
        "关于共产党的组织章程决议案", "中国共产党第二次全国代表大会",
        ("根据一九二二年七月印行的《中国共产党第二次全国大会决议案》刊印",)),
    "1-关于民主的联合战线的议决案.txt": (
        "关于“民主的联合战线”的议决案", "中国共产党第二次全国代表大会",
        ("根据一九二二年七月印行的《中国共产党第二次全国大会决议案》刊印",)),
    "1-关于妇女运动的决议.txt": (
        "关于妇女运动的决议", "中国共产党第二次全国代表大会",
        ("根据一九二二年七月印行的《中国共产党第二次全国大会决议案》刊印",)),
    "1-中国共产党第二次全国大会宣言.txt": (
        "中国共产党第二次全国大会宣言", "中国共产党第二次全国代表大会",
        ("根据一九二六年印行的《中国共产党", "五年来之政治主张》刊印")),
    "1-党内组织及宣传教育问题议决案.txt": (
        "党内组织及宣传教育问题议决案", "中共中央执行委员会扩大会议",
        ("根据一九二四年五月二十日出版的《中国共产党党报》第三号刊印",)),
    "1-对于组织问题之议决案.txt": (
        "对于组织问题之议决案", "中国共产党第四次全国代表大会",
        ("根据一九二五年二月印行的《中国共产党第四次全国大会议决案及宣言》刊印",)),
}

# 每篇必须存在的关键句（原文一字未改的最低证据）
KEY_LINES = {
    "1-中国共产党第一个纲领.txt": (
        "本党定名为“中国共产党”",
        "承认无产阶级专政，直到阶级斗争结束",
        "本纲领须经全国代表大会三分之二代表同意，始得修改",
    ),
    "1-中国共产党第一个决议.txt": (
        "本党的基本任务是成立产业工会",
        "工人学校应逐渐变成工人政党的中心机构",
        "不同其他党派建立任何关系",
    ),
    "1-中国共产党宣言.txt": (
        "共产主义者主张将生产工具——机器工厂，原料，土地",
        "这宣言之中文原稿不能在此地找到",
        "不过以此为收纳党员之标准",
    ),
    "1-中国共产党章程.txt": (
        "第一章 党员",
        "全国大会及中央执行委员会之议决，本党党员皆须绝对服从之",
        "第二十九条",
    ),
    "1-关于共产党的组织章程决议案.txt": (
        "不是“知识者所组织的马克思学会”",
        "要组成一个大的“群众党”",
        "个个党员都要在行动上受党中军队式的训练",
    ),
    "1-关于民主的联合战线的议决案.txt": (
        "无产阶级加入民主革命的运动，并不是投降于",
        "半独立国家",
    ),
    "1-关于妇女运动的决议.txt": (
        "妇女解放是要伴着劳动解放进行的",
        "公共食堂，公共洗濯场",
        "不过为达到完全解放目的必须经过的站驿",
    ),
    "1-中国共产党第二次全国大会宣言.txt": (
        "国际帝国主义宰制下之中国",
        "消除内乱，打倒军阀，建设国内和平",
        "渐次达到一个共产主义的社会",
    ),
    "1-党内组织及宣传教育问题议决案.txt": (
        "能有更明显的组织形式",
        "训练产业无产阶级群众的阶级精神及阶级意识",
    ),
    "1-对于组织问题之议决案.txt": (
        "组织问题为吾党生存和发展之一个最重要的问题",
        "实行民主的集权主义，巩固党的纪律",
    ),
}

# 挂接期望：章节 → 篇目标题关键词
EXPECTED = {
    "sec_B_01": ("中国共产党第一个纲领", "中国共产党第一个决议",
                 "中国共产党宣言", "关于共产党的组织章程决议案"),
    "sec_B_04": ("中国共产党章程", "党内组织及宣传教育问题议决案",
                 "对于组织问题之议决案"),
    "sec_B_08": ("民主的联合战线",),
    "sec_C_02": ("中国共产党第二次全国大会宣言",),
    "sec_C_06": ("关于妇女运动的决议",),
}


def _load_import_module():
    p = ROOT / "scripts" / "import_mirror.py"
    spec = importlib.util.spec_from_file_location("import_mirror_d119", p)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


# ----------------------------------------------------------------------------
# 1) 甄别与登记
# ----------------------------------------------------------------------------
def test_d119_books_registered_and_unique():
    files = {b["file"] for b in BOOKS}
    for f in WORKS:
        assert f in files, f"未在 BOOKS 登记: {f}"
        assert (TEXTS / f).exists(), f"正文文件缺失: {f}"
    prefixes = [b["id_prefix"] for b in BOOKS]
    assert len(prefixes) == len(set(prefixes)), "id_prefix 有重复"
    slugs = [b["slug"] for b in BOOKS]
    assert len(slugs) == len(set(slugs)), "slug 有重复"
    ids = [c["id"] for c in all_book_chunks()]
    assert len(ids) == len(set(ids)), "分片 id 有重复"
    by_file = {b["file"]: b for b in BOOKS}
    for f, (work, author, _) in WORKS.items():
        b = by_file[f]
        assert b["work"] == work, f"{f} work 登记不符"
        assert b["author"] == author, f"{f} 作者登记不符"
        assert b["orthodoxy_tag"] == "正统", f"{f} 分档应为正统（党的文件）"
        assert b["authority_score"] == 0.9, f"{f} 权威分应为 0.9"


def test_d119_works_available():
    works = set(available_works())
    for _, (work, _, _) in WORKS.items():
        assert work in works, f"可用正文缺: {work}"


def test_d119_no_blacklisted_material():
    """黑名单组织文献（菲共／光辉道路／印共毛等）不得借本批混入。"""
    banned = ("菲共", "菲律宾共产党", "光辉道路", "印共（毛）", "反政府武装", "恐怖组织")
    for f, (work, author, _) in WORKS.items():
        blob = work + author + (TEXTS / f).read_text(encoding="utf-8")
        for w in banned:
            assert w not in blob, f"{f} 命中黑名单词: {w}"
    assert any("菲共" in x or "反政府武装" in x for x in READING_BLACKLIST), \
        "黑名单第 4 条（反政府武装／恐怖组织文献）必须仍在"


# ----------------------------------------------------------------------------
# 2) 全文照录（不设节选）
# ----------------------------------------------------------------------------
def test_d119_full_text_not_trimmed():
    mod = _load_import_module()
    for f in WORKS:
        assert f not in getattr(mod, "TRIM", {}), f"{f} 应全文照录，不应设节选规则"
        for d in BACKUP_DIRS:
            assert not (ROOT / "sources" / d / f).exists(), \
                f"{f} 为全文照录，不应出现在裁剪前备份 {d}"


def test_d119_first_line_is_title_and_structure_intact():
    for f, (work, _, _) in WORKS.items():
        t = (TEXTS / f).read_text(encoding="utf-8")
        first = t.splitlines()[0].strip()
        # 网页脚注锚（如「中国共产党第一个决议 [1]」）属原样保留，不删
        assert first.startswith(work), f"{f} 首行不是篇名: {first!r}"
        assert len(t) > 900, f"{f} 正文过短，疑被截断"
        assert "\n\n\n\n" not in t, f"{f} 段落结构被破坏（连续空行）"
        lines = [x.strip() for x in t.splitlines()]
        assert "中文马克思主义文库" not in lines, f"{f} 混入导航行"
        assert not any(x.startswith("->") for x in lines), f"{f} 混入面包屑"
        assert not any(x.startswith("感谢") and "校对" in x for x in lines), \
            f"{f} 混入站点录入致谢行"
        for kw in KEY_LINES[f]:
            assert kw in t, f"{f} 关键句缺失（原文被改写？）: {kw}"


def test_d119_all_traceable_to_printed_source():
    """收文口径：每篇必须带刊印依据，无依据即不可溯源，不得入库。"""
    for f, (_, _, kws) in WORKS.items():
        t = (TEXTS / f).read_text(encoding="utf-8")
        tail = t[-900:]
        for kw in kws:
            assert kw in t, f"{f} 缺刊印依据: {kw}"
        assert any(kw in tail for kw in kws), f"{f} 刊印依据不在篇末"


# ----------------------------------------------------------------------------
# 3) 挂接
# ----------------------------------------------------------------------------
def test_d119_extensions_attached_with_local_work():
    works = set(available_works())
    section_ids = {s["id"] for s in SECTIONS}
    total = 0
    for sid, items in D119_EXTENSIONS.items():
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
            assert "一字未改" in c, f"{it['title']} caution 未声明原文一字未改"
            assert not re.search(r"D\d{2,3}|TRIM|sec_[A-C]_\d\d|OCR|入库|镜像", c), \
                f"{it['title']} caution 暴露开发标记"
    assert total == 10, f"条目数异常: {total}"


def test_d119_mounted_in_expected_sections():
    for sid, keys in EXPECTED.items():
        titles = [it["title"] for it in READING_EXTENSIONS[sid]]
        for k in keys:
            assert any(k in t for t in titles), f"{sid} 未挂入: {k}"


# ----------------------------------------------------------------------------
# 4) 规模
# ----------------------------------------------------------------------------
def test_d119_chapters_still_32():
    assert len(SECTIONS) == 32, "不得新开章节"


def test_d119_founding_documents_count():
    # 白名单按 id_prefix 认人：本批 10 篇。1923／1925 年的妇女决议案（D122 收录）
    # 同属「中国共产党第 N 次全国代表大会」名下，但不是本批文件，故按前缀区分。
    d119_prefixes = ("CH-DYGL-", "CH-DYJY-", "CH-ZGCD-", "CH-DZZC-", "CH-ZZZC-",
                     "CH-LHZX-", "CH-FNYD-", "CH-EDXY-", "CH-DNZJ-", "CH-ZZWT-")
    docs = [b for b in BOOKS if b["id_prefix"] in d119_prefixes]
    assert len(docs) == 10, f"建党文献应为 10 部，实际 {len(docs)}"
    assert all(b["orthodoxy_tag"] == "正统" for b in docs)


# ----------------------------------------------------------------------------
# 5) 概念词典（提问侧要能命中「党章／党纲／党的组织」）
# ----------------------------------------------------------------------------
def test_d119_concept_terms_match_chunk_mentions():
    """标准名必须是分片 mention 里真实出现的原文用词：1922 年章程只写「章程」，
    从不用「党章」，故标准名取「章程」、「党章」作变体；「党纲」「党的组织」
    同此理。这条守住「词典标准名 = 分片 mention 名」的约定。"""
    from content.book_chunks import _GENERIC_TERMS, _terms
    from core.rag.concept_dict import CONCEPT_MAP, ConceptDictionary

    for term in ("党纲", "章程", "党的组织"):
        assert term in _GENERIC_TERMS, f"{term} 未进 mention 词表"
        assert term in _terms(), f"{term} 未进 _terms()"
        assert term in CONCEPT_MAP, f"{term} 未进 CONCEPT_MAP"
    d = ConceptDictionary()
    assert d.extract_concepts("党章规定了什么") == ["章程"]
    assert d.extract_concepts("党纲的内容") == ["党纲"]
    assert d.extract_concepts("党的组织问题") == ["党的组织"]
    # 分片侧确实抽到了这些 mention
    chapters = [c for c in all_book_chunks() if c["source"] == "中国共产党章程"]
    assert chapters, "缺少《中国共产党章程》分片"
    assert "章程" in {m for c in chapters for m in c["concept_mentions"]}

# 依赖 sources/texts/ 原著正文；无正文时由 conftest.py 自动跳过。
import pytest

pytestmark = pytest.mark.needs_texts
