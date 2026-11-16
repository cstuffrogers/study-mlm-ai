"""D120 门禁：周恩来建国后文献 6 篇（1951—1963）——《周恩来选集》上下卷

背景：库里原有周恩来 7 篇（`CH-HLDZ-`／`CH-FGL-`／`CH-BSKB-`／`CH-XYYZ-`／
`CH-JQDC-`／`CH-LD-`／`CH-SZH-`），全部挂 `sec_B_04`，讲的是「党怎样工作」。
本轮补 6 篇讲「国家怎样治理」的建国后文献，全部**全文照录**，不设节选规则、
不做裁剪备份。

本测试覆盖六类约束：

  1) **甄别**：6 部登记在 BOOKS，前缀／slug／分片 id 唯一；一律「经典原著 1.0」
     （与既有 7 篇周恩来同档）；不命中黑名单；
  2) **照录**：6 篇都不在 TRIM 里、无裁剪备份；首行即篇名；关键句逐篇坐实；
     导航行／面包屑／站点致谢行零残留；
  3) **可溯源**：每篇篇末必须带《周恩来选集》编者的「＊这是……」说明
     （《在文艺工作座谈会……的讲话》无该行，以标题行日期「（一九六一年六月十九日）」
     替代——它是本批唯一没有编者附记的一篇，须在断言里显式列出）；
  4) **引文不虚**：延伸阅读条目里所有「」／『』引文（去掉选集注释锚〔NN〕／[NN]
     与省略号后）必须逐字出现在对应正文里。这是本批新增的一道门——
     六篇导读写了 88 处引文，靠人工眼看不住；
  5) **挂接**：6 条延伸阅读挂 sec_B_10 / sec_C_03 / sec_C_04 / sec_C_06 / sec_C_07，
     local_work 指向真实正文，caution 声明原文一字未改且不含开发标记；
  6) **不膨胀**：章节数仍为 32；周恩来正文件数为 13（既有 7 + 本轮 6）。

坑位记录：正文里的「〔10〕」「〔448〕」「[262]」是选集与文集的注释锚，
引文核对必须先剥掉这些锚再比；「树个“的”，让大家来射」则用全角双引号，
不可写成直角引号。
"""
from __future__ import annotations

import importlib.util
import re
from pathlib import Path

from content.book_chunks import BOOKS, all_book_chunks, available_works
from content.reading_extensions import READING_BLACKLIST, READING_EXTENSIONS
from content.reading_extensions_d120 import D120_EXTENSIONS
from content.routes import SECTIONS

ROOT = Path(__file__).resolve().parents[2]
TEXTS = ROOT / "sources" / "texts"
BACKUP_DIRS = ("_backup_d116_pretrim", "_backup_d117_pretrim", "_backup_d118_pretrim",
               "_backup_d101_pretrim", "_backup_d102_pretrim")

# 文件 → (work, author, 篇末溯源关键词元组（任一命中即可）)
WORKS = {
    "1-专政要继续民主要扩大.txt": (
        "专政要继续，民主要扩大", "周恩来",
        ("＊这是在中国共产党上海市第一次代表大会上的讲话节录。",)),
    "1-关于知识分子问题的报告.txt": (
        "关于知识分子问题的报告", "周恩来",
        ("＊这是在中共中央召开的关于知识分子问题会议上的报告",)),
    "1-论知识分子问题.txt": (
        "论知识分子问题", "周恩来",
        ("＊这是对在广州召开的全国科学工作、戏剧创作等会议代表的讲话。",)),
    "1-在文艺工作座谈会和故事片创作会议上的讲话.txt": (
        "在文艺工作座谈会和故事片创作会议上的讲话", "周恩来",
        # 本篇无「＊这是……」编者附记，用标题行日期坐实
        ("（一九六一年六月十九日）",)),
    "1-学习毛泽东.txt": (
        "学习毛泽东", "周恩来",
        ("＊这是在中华全国青年第一次代表大会上的报告第三部分的节录",)),
    "1-切实执行婚姻法保护妇女合法权益.txt": (
        "切实执行婚姻法，保护妇女合法权益", "周恩来",
        ("＊这是由政务院总理周恩来署名发布的",)),
}

# 每篇必须存在的关键句（原文一字未改的最低证据）
KEY_LINES = {
    "1-专政要继续民主要扩大.txt": (
        "我们的国家政权是人民民主专政，实质上是无产阶级专政",
        "权力过分集中时就会有偏向",
        "一直到检查公安、司法工作",
    ),
    "1-关于知识分子问题的报告.txt": (
        "为着加强党对于知识分子的领导",
        "约占百分之四十左右",
        "是毫无根据的",
        "我们将以一个具有高度文化的民族出现于世界",
    ),
    "1-论知识分子问题.txt": (
        "知识分子不是独立的阶级，而是脑力劳动者构成的社会阶层",
        "没有人是专门改造别人的",
        "党的领导是组织领导，不是个人领导",
    ),
    "1-在文艺工作座谈会和故事片创作会议上的讲话.txt": (
        "民主作风不够",
        "目中无人，心中有人",
        "树个“的”，让大家来射",
    ),
    "1-学习毛泽东.txt": (
        "他之所以伟大，更在于他敢于承认旧的过去",
        "坚持方向",
        "实现方向",
    ),
    "1-切实执行婚姻法保护妇女合法权益.txt": (
        "是中央人民政府成立后公布的国家大法之一",
        "必须经过经常的有系统的思想斗争和法律斗争才能贯彻",
    ),
}

# 挂接期望：章节 → 篇目标题关键词
EXPECTED = {
    "sec_B_10": ("学习毛泽东",),
    "sec_C_03": ("专政要继续，民主要扩大",),
    "sec_C_04": ("关于知识分子问题的报告",),
    "sec_C_06": ("切实执行婚姻法",),
    "sec_C_07": ("论知识分子问题", "在文艺工作座谈会和故事片创作会议上的讲话"),
}


def _load_import_module():
    p = ROOT / "scripts" / "import_mirror.py"
    spec = importlib.util.spec_from_file_location("import_mirror_d120", p)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


def _norm_for_quote(s: str) -> str:
    """剥掉选集注释锚（〔10〕／[262]）与所有空白，供引文逐字比对。"""
    return re.sub(r"\s+", "", re.sub(r"〔\d+〕|［\d+］|\[\d+\]", "", s))


# ----------------------------------------------------------------------------
# 1) 甄别与登记
# ----------------------------------------------------------------------------
def test_d120_books_registered_and_unique():
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
        assert b["orthodoxy_tag"] == "经典原著", f"{f} 分档应为经典原著"
        assert b["authority_score"] == 1.0, f"{f} 权威分应为 1.0"


def test_d120_works_available():
    works = set(available_works())
    for _, (work, _, _) in WORKS.items():
        assert work in works, f"可用正文缺: {work}"


def test_d120_no_blacklisted_material():
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
def test_d120_full_text_not_trimmed():
    mod = _load_import_module()
    for f in WORKS:
        assert f not in getattr(mod, "TRIM", {}), f"{f} 应全文照录，不应设节选规则"
        for d in BACKUP_DIRS:
            assert not (ROOT / "sources" / d / f).exists(), \
                f"{f} 为全文照录，不应出现在裁剪前备份 {d}"


def test_d120_first_line_is_title_and_structure_intact():
    for f, (work, _, _) in WORKS.items():
        t = (TEXTS / f).read_text(encoding="utf-8")
        first = t.splitlines()[0].strip()
        assert first.startswith(work), f"{f} 首行不是篇名: {first!r}"
        assert len(t) > 1000, f"{f} 正文过短，疑被截断"
        assert "\n\n\n\n" not in t, f"{f} 段落结构被破坏（连续空行）"
        lines = [x.strip() for x in t.splitlines()]
        assert "中文马克思主义文库" not in lines, f"{f} 混入导航行"
        assert not any(x.startswith("->") for x in lines), f"{f} 混入面包屑"
        assert not any(x.startswith("感谢") and "校对" in x for x in lines), \
            f"{f} 混入站点录入致谢行"
        for kw in KEY_LINES[f]:
            assert kw in t, f"{f} 关键句缺失（原文被改写？）: {kw}"


# 本批唯一没有篇末编者附记的一篇：出处只有标题行日期，须查全文
NO_EDITOR_NOTE = {"1-在文艺工作座谈会和故事片创作会议上的讲话.txt"}


def test_d120_all_traceable_to_selected_works():
    """收文口径：每篇都必须带选集编者说明（或标题行日期），否则不可溯源。"""
    for f, (_, _, kws) in WORKS.items():
        t = (TEXTS / f).read_text(encoding="utf-8")
        hay = t if f in NO_EDITOR_NOTE else t[-1200:]
        assert any(kw in hay for kw in kws), f"{f} 缺出处说明: {kws}"


# ----------------------------------------------------------------------------
# 3) 引文逐字在文（本批新增门禁）
# ----------------------------------------------------------------------------
def test_d120_quotes_verbatim_in_source():
    body = {f: _norm_for_quote((TEXTS / f).read_text(encoding="utf-8")) for f in WORKS}
    by_work = {WORKS[f][0]: f for f in WORKS}
    checked = 0
    for sid, items in D120_EXTENSIONS.items():
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
    assert checked >= 80, f"引文核对覆盖不足（{checked} 条），门禁形同虚设"


# ----------------------------------------------------------------------------
# 4) 挂接
# ----------------------------------------------------------------------------
def test_d120_extensions_attached_with_local_work():
    works = set(available_works())
    section_ids = {s["id"] for s in SECTIONS}
    total = 0
    for sid, items in D120_EXTENSIONS.items():
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
            assert "一字未改" in c, f"{it['title']} caution 未声明编者说明一字未改"
            assert not re.search(r"D\d{2,3}|TRIM|sec_[A-C]_\d\d|OCR|入库|镜像", c), \
                f"{it['title']} caution 暴露开发标记"
    assert total == 6, f"条目数异常: {total}"


def test_d120_mounted_in_expected_sections():
    for sid, keys in EXPECTED.items():
        titles = [it["title"] for it in READING_EXTENSIONS[sid]]
        for k in keys:
            assert any(k in t for t in titles), f"{sid} 未挂入: {k}"


# ----------------------------------------------------------------------------
# 5) 规模
# ----------------------------------------------------------------------------
def test_d120_chapters_still_32():
    assert len(SECTIONS) == 32, "不得新开章节"


def test_d120_zhouenlai_works_count():
    zhou = [b for b in BOOKS if b["author"] == "周恩来"]
    # 既有 7 + D120 6 + D125 2（1945《论统一战线》、1957《关于我国民族政策的几个问题》）
    # + D126 12（1926—1949 民主革命期，按六章内容缺口选篇）
    assert len(zhou) == 27, f"周恩来正文件数应为 27，实际 {len(zhou)}"
    assert all(b["orthodoxy_tag"] == "经典原著" for b in zhou)


# ----------------------------------------------------------------------------
# 6) 概念词典（提问侧要能命中「知识分子／人民民主专政／文艺／自我改造」）
# ----------------------------------------------------------------------------
def test_d120_concept_terms_match_chunk_mentions():
    """标准名必须是分片 mention 里真实出现的原文用词：「知识分子」294 次、
    「人民民主专政」11 次、「文艺」50 次、「自我改造」13 次，均为正文原词。"""
    from content.book_chunks import _GENERIC_TERMS, _terms
    from core.rag.concept_dict import CONCEPT_MAP, ConceptDictionary

    for term in ("知识分子", "人民民主专政", "文艺", "自我改造"):
        assert term in _GENERIC_TERMS, f"{term} 未进 mention 词表"
        assert term in _terms(), f"{term} 未进 _terms()"
        assert term in CONCEPT_MAP, f"{term} 未进 CONCEPT_MAP"
    d = ConceptDictionary()
    assert d.extract_concepts("知识分子是工人阶级的一部分吗") == ["知识分子"]
    assert d.extract_concepts("人民民主专政的实质") == ["人民民主专政"]
    assert d.extract_concepts("文艺工作的规律") == ["文艺"]
    # 顺序随 variant 字典而定，只断言命中集合
    assert set(d.extract_concepts("知识分子的自我改造")) == {"知识分子", "自我改造"}
    # 分片侧确实抽到了这些 mention
    rep = [c for c in all_book_chunks() if c["source"] == "关于知识分子问题的报告"]
    assert rep, "缺少《关于知识分子问题的报告》分片"
    mentions = {m for c in rep for m in c["concept_mentions"]}
    assert "知识分子" in mentions, f"分片侧未抽到「知识分子」mention: {sorted(mentions)[:20]}"
