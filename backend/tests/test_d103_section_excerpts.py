"""D103：按「合适章节」节选入库的 15 部原著 —— 门禁测试

用户口径（2026-11）：**不整篇照录**，只挑与学习路线章节对得上的章节入库。
裁剪沿用 D101 的 `TRIM` 机制，硬约束：

  1) 原文一字不改：从 `sources/_backup_d103_pretrim/` 的裁剪前全文按 TRIM 重切，
     必须与现库逐字节一致；
  2) 边界一律落在章节标题行：只删整章/整节，绝不截断段落；
  3) 不新开章节：章节数仍为 32，只向既有章节追加延伸阅读；
  4) 每条延伸阅读必须带 `local_work`（真实正文），caution 如实写明保留/删去了什么。
"""
from __future__ import annotations

import importlib.util
import re
from pathlib import Path

from content.book_chunks import BOOKS, available_works
from content.reading_extensions import READING_EXTENSIONS
from content.reading_extensions_d103 import D103_EXTENSIONS
from content.routes import SECTIONS

ROOT = Path(__file__).resolve().parents[2]
TEXTS = ROOT / "sources" / "texts"
BACKUP = ROOT / "sources" / "_backup_d103_pretrim"

# 15 部（《论国家》整页照录、无 TRIM，故裁剪表只有 14 部）
D103_WORKS = (
    "5-中国革命战争的战略问题.txt",
    "5-抗日游击战争的战略问题.txt",
    "5-战争和战略问题.txt",
    "5-井冈山的斗争.txt",
    "5-中国的红色政权为什么能够存在.txt",
    "5-论反对日本帝国主义的策略.txt",
    "5-学习和时局.txt",
    "5-在省市自治区党委书记会议上的讲话.txt",
    "1-论国家.txt",
    "1-评经济浪漫主义.txt",
    "1-马克思主义和语言学问题.txt",
    "1-马克思主义和民族问题.txt",
    "2-无政府主义还是社会主义.txt",
    "2-1848年至1850年的法兰西阶级斗争.txt",
    "2-德国农民战争.txt",
)

# 必须保留 / 必须以「独立标题行」消失（保留侧用子串判断，删去侧用整行判断）
KEEP = {
    "5-中国革命战争的战略问题.txt": ("如何研究战争", "中国革命战争的特点", "围剿"),
    "5-抗日游击战争的战略问题.txt": ("为什么提起游击战争的战略问题", "主动性", "计划性"),
    "5-战争和战略问题.txt": ("中国的特点和革命", "抗日游击战争的战略地位"),
    "5-井冈山的斗争.txt": ("湘赣边界的割据和八月失败", "革命性质问题", "割据地区问题"),
    "5-中国的红色政权为什么能够存在.txt": ("国内的政治状况", "中国红色政权", "经济问题"),
    "5-论反对日本帝国主义的策略.txt": ("目前政治形势的特点", "民族统一战线", "人民共和国"),
    "5-学习和时局.txt": ("放下包袱", "开动机器"),
    "5-在省市自治区党委书记会议上的讲话.txt": ("一月十八日的讲话", "闹事问题", "百花齐放"),
    "1-评经济浪漫主义.txt": ("浪漫主义者对资本主义的批评的性质", "浪漫主义的反动性"),
    "1-马克思主义和语言学问题.txt": ("论语言学中的马克思主义", "上层建筑"),
    "1-马克思主义和民族问题.txt": ("民族运动", "俄国的民族问题"),
    "2-无政府主义还是社会主义.txt": ("一 辩证方法", "辩证方法"),
    "2-1848年至1850年的法兰西阶级斗争.txt": ("1848年的六月失败", "1850年普选权的废除"),
    "2-德国农民战争.txt": ("1870年第二版序言", "德意志民族"),
}
DROP = {
    "5-中国革命战争的战略问题.txt": ("第五章 战略防御", "第九节 歼灭战", "注释"),
    "5-抗日游击战争的战略问题.txt": ("第六章 建立根据地", "第九章 指挥关系", "注释"),
    "5-战争和战略问题.txt": ("二 中国国民党的战争史", "六 注意研究军事问题", "注释"),
    "5-井冈山的斗争.txt": ("军事问题", "注释"),
    "5-中国的红色政权为什么能够存在.txt": (
        "三 湘赣边界的割据和八月的失败", "六 军事根据地问题", "注释"),
    "5-论反对日本帝国主义的策略.txt": ("注释",),
    "5-学习和时局.txt": ("注释", "· 附录：关于若干历史问题的决议"),
    "5-在省市自治区党委书记会议上的讲话.txt": ("第六点，法制问题。讲三条：一定要守法，一定要肃反，一定要肯定肃反的成绩。", "注释"),
    "1-评经济浪漫主义.txt": ("注释：",),
    "1-马克思主义和语言学问题.txt": ("中文马克思主义文库", "论语言学的几个问题", "答同志们"),
    "1-马克思主义和民族问题.txt": ("四 民族文化自治",),
    "2-无政府主义还是社会主义.txt": ("二 唯物主义理论", "三 无产阶级的社会主义"),
    "2-1848年至1850年的法兰西阶级斗争.txt": ("二 1849年6月13日", "三 1849年六月十三日事件的后果"),
    "2-德国农民战争.txt": ("二", "弗·恩格斯写于1850年夏秋"),
}


def _load_import_module():
    p = ROOT / "scripts" / "import_mirror.py"
    spec = importlib.util.spec_from_file_location("import_mirror_d103", p)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


def _trimmed() -> tuple[str, ...]:
    return tuple(f for f in D103_WORKS if f != "1-论国家.txt")


def test_d103_backup_and_texts_present():
    """裁剪前全文备份齐备（复核/回退用），现库 15 部正文都在。"""
    assert {p.name for p in BACKUP.glob("*.txt")} == set(D103_WORKS)
    for f in D103_WORKS:
        assert (TEXTS / f).exists(), f"正文缺失: {f}"


def test_d103_trim_reproduces_current_texts():
    """从备份全文按 TRIM 重切，必须与现库逐字节一致（原文一字未改、可复现）。"""
    mod = _load_import_module()
    for f in _trimmed():
        full = (BACKUP / f).read_text(encoding="utf-8")
        cur = (TEXTS / f).read_text(encoding="utf-8")
        assert len(cur) < len(full), f"{f} 未裁剪"
        assert 0.15 < len(cur) / len(full) < 0.95, \
            f"{f} 裁剪比例异常: {len(cur)/len(full):.2%}"
        assert mod.apply_trim(f, full) == cur, f"{f} 裁剪结果不可复现（原文被改写？）"


def test_d103_untouched_work_copied_verbatim():
    """《论国家》不裁剪：现库必须与「裁剪前全文」逐字节一致。"""
    mod = _load_import_module()
    f = "1-论国家.txt"
    assert f not in mod.TRIM
    full = mod.build([x for x in mod.SPECS if x["file"] == f][0], trim=False)[0]
    assert (TEXTS / f).read_text(encoding="utf-8") == full


def test_d103_kept_and_dropped_sections():
    """保留章节必须在；裁去的章节标题不得作为独立行残留（只删整章，不截段落）。"""
    for f, kws in KEEP.items():
        t = (TEXTS / f).read_text(encoding="utf-8")
        for k in kws:
            assert k in t, f"{f} 误删关键章节: {k}"
        assert "\n\n\n\n" not in t, f"{f} 段落结构被破坏（连续空行）"
    for f, kws in DROP.items():
        lines = [x.strip() for x in (TEXTS / f).read_text(encoding="utf-8").splitlines()]
        for k in kws:
            assert k not in lines, f"{f} 仍残留应裁章节标题: {k}"


def test_d103_book_registration():
    """15 部已登记进 BOOKS，id_prefix/slug 全局唯一，作者与路线一致。"""
    by_file = {b["file"]: b for b in BOOKS}
    for f in D103_WORKS:
        assert f in by_file, f"BOOKS 未登记: {f}"
        assert by_file[f]["orthodoxy_tag"] == "经典原著"
    authors = {by_file[f]["author"] for f in D103_WORKS}
    assert authors <= {"马克思", "恩格斯", "列宁", "斯大林", "毛泽东"}, authors
    for f in D103_WORKS:
        b = by_file[f]
        assert re.fullmatch(r"CH-[A-Z0-9]+-", b["id_prefix"]), b["id_prefix"]
        assert b["id_prefix"] in [x["id_prefix"] for x in BOOKS if x["file"] == f]


def test_d103_extensions_have_local_work_and_declare_excerpt():
    """延伸阅读 15 条全部挂 local_work，且 caution 如实声明「仅收/裁去」。"""
    works = set(available_works())
    entries = [it for items in D103_EXTENSIONS.values() for it in items]
    assert len(entries) == 15, len(entries)
    for it in entries:
        assert it["kind"] == "classic", it["title"]
        lw = it.get("local_work")
        assert lw and lw in works, f"{it['title']} local_work 未入库: {lw}"
        c = it["caution"]
        assert ("仅收" in c or "保留" in c), f"{it['title']} caution 未声明保留范围"
        assert ("裁去" in c or "不收" in c or "未作节选" in c),             f"{it['title']} caution 未声明删去范围"
        # 读者向文案：不得暴露开发标记
        for word in ("D103", "TRIM", "sec_"):
            assert word not in c + it["title"] + it["intro"], f"{it['title']} 暴露开发标记 {word}"


def test_d103_no_new_sections_and_merge_order():
    """不新开章节（仍 32 章）；D103 条目确实合并进主表且保持本批内部顺序。

    注：D104 等后续批次会继续向同一章节追加，故不再要求本批位于全表末尾，
    只要求本批条目连续、按原顺序排列（不改写既有顺序）。
    """
    assert len(SECTIONS) == 32
    for sid, items in D103_EXTENSIONS.items():
        assert sid in READING_EXTENSIONS, f"D103 章节 id 不存在: {sid}"
        titles = [it["title"] for it in READING_EXTENSIONS[sid]]
        idx = [titles.index(it["title"]) for it in items]
        assert idx == sorted(idx), f"{sid} D103 条目顺序被打乱"
        assert idx == list(range(idx[0], idx[0] + len(idx))), f"{sid} D103 条目未连续追加"
