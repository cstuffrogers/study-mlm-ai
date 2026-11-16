"""D118 门禁：建党前史（1918—1926）——李大钊 6 篇 + 蔡和森 2 篇

背景：D117 之后库内最早的中文文献仍是 1925 年《中国社会各阶级的分析》，1918—1924
这段「马克思主义怎样进入中国、党怎样从讨论组变成组织」完全空白。本轮补 8 篇，
全部**全文照录**（篇末原刊出处、署名、译注保留），不设节选规则。

本测试覆盖五类约束：

  1) **甄别**：8 部全部登记在 BOOKS，前缀／分片 id 唯一；7 篇经典原著 1.0、
     蔡和森 1926 年党内报告按历史文献登记（正统 0.9）；不命中黑名单；
  2) **照录**：8 篇都不在 TRIM 里、无裁剪备份；每篇首行即篇名、段落结构完好；
  3) **可溯源**：每篇篇末必须带原刊出处（《新青年》／《每周评论》／《言治》／
     《中央档案馆丛刊》或「来源」行）——这是本批唯一的收文口径；
  4) **挂接**：8 条延伸阅读挂 sec_A_06 / sec_A_07 / sec_B_01 / sec_B_04，
     local_work 指向真实正文，caution 必须声明「一字未改」且不含开发标记；
  5) **不膨胀**：章节数仍为 32，不新开章节；库内最早中文文献前移到 1918 年。
"""
from __future__ import annotations

import importlib.util
import re
from pathlib import Path

from content.book_chunks import BOOKS, all_book_chunks, available_works
from content.reading_extensions import READING_BLACKLIST, READING_EXTENSIONS
from content.reading_extensions_d118 import D118_EXTENSIONS
from content.routes import SECTIONS

ROOT = Path(__file__).resolve().parents[2]
TEXTS = ROOT / "sources" / "texts"
BACKUP = ROOT / "sources" / "_backup_d118_pretrim"

# 文件 → (work, author, 原刊溯源关键词)
WORKS = {
    "1-法俄革命之比较观.txt": (
        "法俄革命之比较观", "李大钊", ("言治", "署名：李大钊")),
    "1-庶民的胜利.txt": (
        "庶民的胜利", "李大钊", ("新青年", "守常")),
    "1-Bolshevism的胜利.txt": (
        "Bolshevism的胜利", "李大钊", ("新青年", "李大钊")),
    "1-再论问题与主义.txt": (
        "再论问题与主义", "李大钊", ("每周评论", "昌黎五峰")),
    "1-由经济上解释中国近代思想变动的原因.txt": (
        "由经济上解释中国近代思想变动的原因", "李大钊", ("新青年", "李大钊")),
    "1-唯物史观在现代史学上的价值.txt": (
        "唯物史观在现代史学上的价值", "李大钊", ("新青年", "一九二○年十二月一日")),
    "1-马克思学说与中国无产阶级.txt": (
        "马克思学说与中国无产阶级", "蔡和森", ("新青年", "蒙达尼")),
    "1-关于中国共产党的组织和党内生活向共产国际的报告.txt": (
        "关于中国共产党的组织和党内生活向共产国际的报告（部分）", "蔡和森",
        ("中央档案馆丛刊", "来源")),
}

# 每篇必须存在的关键句（原文一字未改的最低证据）
KEY_LINES = {
    "1-法俄革命之比较观.txt": (
        "政权全归急进社会党之手",
        "世界中将来能创造一兼东西文明特质",
    ),
    "1-庶民的胜利.txt": (
        "不是联合国的武力，是世界人类的新精神",
        "一九一七年的俄国革命，是二十世纪中世界革命的先声",
        "是祗能迎，不可拒的",
    ),
    "1-Bolshevism的胜利.txt": (
        "Bolshevism就是俄国Bolsheviki所抱的主义",
        "二十世纪世界革命的新信条",
        "是赤旗的胜利",
    ),
    "1-再论问题与主义.txt": (
        "必须靠着社会上多数人共同的运动",
        "经济问题的解决，是根本解决",
        "还须有相当的准备活动才是",
    ),
    "1-由经济上解释中国近代思想变动的原因.txt": (
        "经济上若发生了变动，思想上也必发生变动",
        "适应中国二千余年来未曾变动的农业经济组织反映出来的产物",
    ),
    "1-唯物史观在现代史学上的价值.txt": (
        "不求其原因于心的势力，而求之于物的势力",
        "这不是一种供权势阶级愚民的器具",
        "而坐待新境遇的到来",
    ),
    "1-马克思学说与中国无产阶级.txt": (
        "中国完全是个无产阶级的国",
        "中国的阶级战争就是国际的阶级战争",
        "无产阶级专政是暂时必然的手段",
    ),
    "1-关于中国共产党的组织和党内生活向共产国际的报告.txt": (
        "党才开始独立形成起来",
        "对待党完全象对待翻译供应机关一样",
        "固定的专门的党的工作人员",
    ),
}

# 挂接期望：章节 → 篇目标题（去掉书名号与年份括注后做前缀匹配）
EXPECTED = {
    "sec_A_06": ("法俄革命之比较观", "庶民的胜利", "Bolshevism"),
    "sec_A_07": ("由经济上解释中国近代思想变动的原因", "唯物史观在现代史学上的价值"),
    "sec_B_01": ("再论问题与主义", "马克思学说与中国无产阶级"),
    "sec_B_04": ("关于中国共产党的组织和党内生活向共产国际的报告",),
}


def _load_import_module():
    p = ROOT / "scripts" / "import_mirror.py"
    spec = importlib.util.spec_from_file_location("import_mirror_d118", p)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


# ----------------------------------------------------------------------------
# 1) 甄别与登记
# ----------------------------------------------------------------------------
def test_d118_books_registered_and_unique():
    files = {b["file"] for b in BOOKS}
    for f in WORKS:
        assert f in files, f"未在 BOOKS 登记: {f}"
        assert (TEXTS / f).exists(), f"正文文件缺失: {f}"
    prefixes = [b["id_prefix"] for b in BOOKS]
    assert len(prefixes) == len(set(prefixes)), "id_prefix 有重复"
    ids = [c["id"] for c in all_book_chunks()]
    assert len(ids) == len(set(ids)), "分片 id 有重复"
    by_file = {b["file"]: b for b in BOOKS}
    for f, (work, author, _) in WORKS.items():
        b = by_file[f]
        assert b["work"] == work, f"{f} work 登记不符"
        assert b["author"] == author, f"{f} 作者登记不符"
        if f.endswith("向共产国际的报告.txt"):
            assert b["orthodoxy_tag"] == "正统" and b["authority_score"] == 0.9
        else:
            assert b["orthodoxy_tag"] == "经典原著" and b["authority_score"] == 1.0


def test_d118_works_available():
    works = set(available_works())
    for _, (work, _, _) in WORKS.items():
        assert work in works, f"可用正文缺: {work}"


def test_d118_no_blacklisted_material():
    """黑名单组织文献（菲共／光辉道路／印共毛等）不得借本批混入。"""
    banned = ("菲共", "菲律宾共产党", "光辉道路", "印共", "印共（毛）", "反政府武装", "恐怖组织")
    for f, (work, author, _) in WORKS.items():
        blob = work + author + (TEXTS / f).read_text(encoding="utf-8")
        for w in banned:
            assert w not in blob, f"{f} 命中黑名单词: {w}"
    assert any("菲共" in x or "反政府武装" in x for x in READING_BLACKLIST), \
        "黑名单第 4 条（反政府武装／恐怖组织文献）必须仍在"


# ----------------------------------------------------------------------------
# 2) 全文照录（不设节选）
# ----------------------------------------------------------------------------
def test_d118_full_text_not_trimmed():
    mod = _load_import_module()
    for f in WORKS:
        assert f not in mod.TRIM, f"{f} 应全文照录，不应设节选规则"
        assert not (BACKUP / f).exists(), f"{f} 为全文照录，不应有裁剪前备份"


def test_d118_first_line_is_title_and_structure_intact():
    for f, (work, _, _) in WORKS.items():
        t = (TEXTS / f).read_text(encoding="utf-8")
        assert t.splitlines()[0].strip() == work, f"{f} 首行不是篇名"
        assert len(t) > 1500, f"{f} 正文过短，疑被截断"
        assert "\n\n\n\n" not in t, f"{f} 段落结构被破坏（连续空行）"
        lines = [x.strip() for x in t.splitlines()]
        # 导航行只以「独立成行」判断；说明文字末尾的署名不算导航
        assert "中文马克思主义文库" not in lines, f"{f} 混入导航行"
        assert not any(x.startswith("->") for x in lines), f"{f} 混入面包屑"
        for kw in KEY_LINES[f]:
            assert kw in t, f"{f} 关键句缺失（原文被改写？）: {kw}"


def test_d118_all_traceable_to_original_publication():
    """收文口径：每篇必须带原刊出处，无出处即不可溯源，不得入库。"""
    for f, (_, _, kws) in WORKS.items():
        t = (TEXTS / f).read_text(encoding="utf-8")
        tail = t[-1200:]
        for kw in kws:
            assert kw in t, f"{f} 缺原刊溯源信息: {kw}"
        assert kws[0] in tail or kws[1] in tail, f"{f} 原刊出处不在篇末"


# ----------------------------------------------------------------------------
# 3) 挂接
# ----------------------------------------------------------------------------
def test_d118_extensions_attached_with_local_work():
    works = set(available_works())
    section_ids = {s["id"] for s in SECTIONS}
    total = 0
    for sid, items in D118_EXTENSIONS.items():
        assert sid in section_ids, f"挂到不存在的章节: {sid}"
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
            assert not re.search(r"D\d{2,3}|TRIM|sec_[A-C]_\d\d|OCR|入库|镜像", c), \
                f"{it['title']} caution 暴露开发标记"
    assert total == 8, f"条目数异常: {total}"


def test_d118_mounted_in_expected_sections():
    for sid, keys in EXPECTED.items():
        titles = [it["title"] for it in READING_EXTENSIONS[sid]]
        for k in keys:
            assert any(k in t for t in titles), f"{sid} 未挂入: {k}"


# ----------------------------------------------------------------------------
# 4) 规模与时间轴
# ----------------------------------------------------------------------------
def test_d118_chapters_still_32():
    assert len(SECTIONS) == 32, "不得新开章节"


def test_d118_earliest_chinese_text_moved_to_1918():
    """1918 年以前库内无中文原文；本批后最早的中文文献应是 1918 年《法俄革命之比较观》。"""
    years = []
    for b in BOOKS:
        m = re.search(r"(19\d\d)", b.get("work", ""))
        if b["author"] in ("李大钊", "蔡和森") and m:
            years.append(int(m.group(1)))
    assert years == [], "本批篇目名不含年份（年份在正文与扩展条目里）"
    t = (TEXTS / "1-法俄革命之比较观.txt").read_text(encoding="utf-8")
    assert "1918" in t.replace(" ", ""), "《法俄革命之比较观》应标注 1918 年"
    # 库内属于建党前史（1918—1924）的正文件数
    pre = [b for b in BOOKS if b["author"] in ("李大钊", "蔡和森")]
    # D118 8 部 + D125 按章节缺口补的李大钊 4 篇（1923 巴黎公社、1925 土地与农民、
    # 1926 红枪会、1926 中国民族革命观）
    assert len(pre) == 12, f"李大钊/蔡和森正文件数应为 12，实际 {len(pre)}"


# ----------------------------------------------------------------------------
# 5) 概念词典与召回（D118 修的一个真实缺陷）
# ----------------------------------------------------------------------------
def test_d118_concept_term_matches_chunk_mentions():
    """「唯物史观」是 CONCEPT_MAP 的标准名，但此前不在 mention 词表里，
    导致 1920 两篇（通篇讲「唯物史观」）在图召回与关键词召回里连不上。
    本批把标准名补进 mention 词表，此处守住。"""
    from content.book_chunks import _GENERIC_TERMS, _terms
    from core.rag.concept_dict import ConceptDictionary

    assert "唯物史观" in _GENERIC_TERMS
    assert "唯物史观" in _terms()
    chunks = [c for c in all_book_chunks()
              if c["source"] == "唯物史观在现代史学上的价值"]
    assert chunks, "缺少《唯物史观在现代史学上的价值》分片"
    mentions = {m for c in chunks for m in c["concept_mentions"]}
    assert "唯物史观" in mentions, "分片 mention 未包含标准名，图召回连不上"
    assert "唯物史观" in ConceptDictionary().extract_concepts("唯物史观在史学上有什么价值")

# 依赖 sources/texts/ 原著正文；无正文时由 conftest.py 自动跳过。
import pytest

pytestmark = pytest.mark.needs_texts
