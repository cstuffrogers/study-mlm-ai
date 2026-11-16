"""D104：军事 / 过渡时期政治 / 经济政策 / 文化四块的 26 部原著 —— 门禁测试

用户口径（2026-11）：与 D103 一致 —— **不整篇照录**，只挑与学习路线章节
对得上的章节入库。硬约束：

  1) 原文一字不改：从 `sources/_backup_d104_pretrim/` 的裁剪前全文按 TRIM 重切，
     必须与现库逐字节一致（未裁剪的 23 部同样等于其全文）；
  2) 边界一律落在章节标题行：只删整章/整节，绝不截断段落；
  3) 不新开章节：章节数仍为 32，只向既有章节追加延伸阅读；
  4) 每条延伸阅读必须带 `local_work`（真实正文），caution 如实写明保留/删去了什么。

刻意不收（口径见 `content/reading_extensions_d104.py` 文档串）：镜像仅有
非官方汇编来源的毛著（如《同音乐工作者的谈话》）、《人的正确思想是从哪里来的？》，
以及各类批判对象与路线分歧材料。
"""
from __future__ import annotations

import importlib.util
import re
from pathlib import Path

from content.book_chunks import BOOKS, available_works
from content.reading_extensions import READING_EXTENSIONS
from content.reading_extensions_d104 import D104_EXTENSIONS
from content.routes import SECTIONS

ROOT = Path(__file__).resolve().parents[2]
TEXTS = ROOT / "sources" / "texts"
BACKUP = ROOT / "sources" / "_backup_d104_pretrim"

D104_WORKS = (
    # 军事与策略
    "5-目前形势和我们的任务.txt",
    "5-集中优势兵力各个歼灭敌人.txt",
    # 思想战线 / 历史唯物主义基石
    "3-劳动在从猿到人的转变中的作用.txt",
    "3-反杜林论政治经济学篇.txt",
    "3-自然辩证法辩证法作为科学.txt",
    "1-论战斗唯物主义的意义.txt",
    "1-马克思主义和修正主义.txt",
    # 过渡时期政治与经济
    "1-无产阶级专政时代的经济和政治.txt",
    "1-大难临头出路何在.txt",
    "1-十月革命四周年.txt",
    "1-论黄金在目前和社会主义完全胜利后的作用.txt",
    # 国际战略
    "1-民族和殖民地问题提纲初稿.txt",
    "1-民族和殖民地问题委员会的报告.txt",
    "1-帝国主义和社会主义运动中的分裂.txt",
    # 阶级与农业
    "5-怎样分析农村阶级.txt",
    "3-法德农民问题.txt",
    "5-关于农业合作化问题.txt",
    # 政策与统一战线
    "5-论政策.txt",
    "5-目前抗日统一战线中的策略问题.txt",
    "5-将革命进行到底.txt",
    # 文化 / 意识形态上层建筑
    "5-为人民服务.txt",
    "5-纪念白求恩.txt",
    "5-愚公移山.txt",
    "5-在中国共产党全国宣传工作会议上的讲话.txt",
    "5-应当重视电影武训传的讨论.txt",
    "5-大量吸收知识分子.txt",
)

# 只有这 3 部需要按章节节选，其余 23 部为单篇全文（不含裁剪）
TRIMMED = (
    "1-大难临头出路何在.txt",
    "3-反杜林论政治经济学篇.txt",
    "3-自然辩证法辩证法作为科学.txt",
)

KEEP = {
    "1-大难临头出路何在.txt": ("银行国有化", "辛迪加国有化", "监督办法是众所周知和轻而易举的"),
    "3-反杜林论政治经济学篇.txt": ("对象和方法", "暴力论", "政治经济学"),
    "3-自然辩证法辩证法作为科学.txt": ("辩证法", "偶然性和必然性", "量"),
}
DROP = {
    "1-大难临头出路何在.txt": ("政府破坏民主组织的工作", "财政破产和挽救的办法",
                                "革命民主派和革命无产阶级"),
    "3-反杜林论政治经济学篇.txt": ("五 价值论", "六 简单劳动和复合劳动",
                                    "七 资本和剩余价值"),
    "3-自然辩证法辩证法作为科学.txt": ("［札记和片断］", "［认识］"),
}


def _load_import_module():
    p = ROOT / "scripts" / "import_mirror.py"
    spec = importlib.util.spec_from_file_location("import_mirror_d104", p)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


def test_d104_backup_and_texts_present():
    """裁剪前全文备份齐备（复核/回退用），现库 26 部正文都在。"""
    assert {p.name for p in BACKUP.glob("*.txt")} == set(D104_WORKS)
    for f in D104_WORKS:
        assert (TEXTS / f).exists(), f"正文缺失: {f}"


def test_d104_trim_reproduces_current_texts():
    """从备份全文按 TRIM 重切，必须与现库逐字节一致（原文一字未改、可复现）。"""
    mod = _load_import_module()
    assert set(TRIMMED) <= set(mod.TRIM)
    for f in TRIMMED:
        full = (BACKUP / f).read_text(encoding="utf-8")
        cur = (TEXTS / f).read_text(encoding="utf-8")
        assert len(cur) < len(full), f"{f} 未裁剪"
        assert 0.15 < len(cur) / len(full) < 0.95, \
            f"{f} 裁剪比例异常: {len(cur)/len(full):.2%}"
        assert mod.apply_trim(f, full) == cur, f"{f} 裁剪结果不可复现（原文被改写？）"


def test_d104_untouched_works_copied_verbatim():
    """其余 23 部不裁剪：现库必须与「裁剪前全文」逐字节一致。"""
    mod = _load_import_module()
    for f in D104_WORKS:
        if f in TRIMMED:
            continue
        assert f not in mod.TRIM, f"{f} 意外登记了裁剪配置"
        assert (TEXTS / f).read_text(encoding="utf-8") == \
            (BACKUP / f).read_text(encoding="utf-8"), f"{f} 正文被改动"


def test_d104_kept_and_dropped_sections():
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


def test_d104_book_registration():
    """26 部已登记进 BOOKS，id_prefix/slug 全局唯一，作者与口径一致。"""
    by_file = {b["file"]: b for b in BOOKS}
    for f in D104_WORKS:
        assert f in by_file, f"BOOKS 未登记: {f}"
        assert by_file[f]["orthodoxy_tag"] == "经典原著"
    authors = {by_file[f]["author"] for f in D104_WORKS}
    assert authors <= {"马克思", "恩格斯", "列宁", "斯大林", "毛泽东"}, authors
    prefixes = [b["id_prefix"] for b in BOOKS]
    slugs = [b["slug"] for b in BOOKS]
    assert len(prefixes) == len(set(prefixes)), "id_prefix 冲突"
    assert len(slugs) == len(set(slugs)), "slug 冲突"
    for f in D104_WORKS:
        assert re.fullmatch(r"CH-[A-Z0-9]+-", by_file[f]["id_prefix"]), by_file[f]["id_prefix"]


def test_d104_extensions_have_local_work_and_declare_scope():
    """延伸阅读 26 条全部挂 local_work，且 caution 如实声明「全文照录 / 节选」。"""
    works = set(available_works())
    entries = [it for items in D104_EXTENSIONS.values() for it in items]
    assert len(entries) == 26, len(entries)
    assert len({it["title"] for it in entries}) == 26, "标题重复"
    declared = 0
    for it in entries:
        assert it["kind"] == "classic", it["title"]
        lw = it.get("local_work")
        assert lw and lw in works, f"{it['title']} local_work 未入库: {lw}"
        c = it["caution"]
        assert ("全文照录" in c or "保留" in c), f"{it['title']} caution 未声明收到哪里"
        assert ("未作节选" in c or "节选" in c), f"{it['title']} caution 未声明节选口径"
        if "节选" in c and "全文照录" not in c:
            declared += 1
        # 读者向文案：不得暴露开发标记
        for word in ("D104", "TRIM", "sec_", "local_work"):
            assert word not in c + it["title"] + it["intro"], \
                f"{it['title']} 暴露开发标记 {word}"
    assert declared == len(TRIMMED), f"声明节选的条目数应等于需裁剪的部数: {declared}"


def test_d104_no_new_sections_and_merge_order():
    """不新开章节（仍 32 章）；D104 条目确实合并进主表且本批连续保序。

    后续批次（D105 起）会继续向同一章节追加条目，故不再要求「位于全表末尾」，
    只要求本批条目在表中占一段连续区间、批内顺序不变。
    """
    assert len(SECTIONS) == 32
    ids = {s["id"] for s in SECTIONS}
    for sid, items in D104_EXTENSIONS.items():
        assert sid in ids, f"D104 章节 id 不存在: {sid}"
        assert sid in READING_EXTENSIONS
        titles = [it["title"] for it in READING_EXTENSIONS[sid]]
        idx = [titles.index(it["title"]) for it in items]
        assert idx == sorted(idx) and idx == list(range(idx[0], idx[0] + len(idx))), \
            f"{sid} D104 条目未连续追加"
