"""D105：帝国主义论三源头 + 《资本论》第四卷 + 唯物史观前史 —— 门禁测试

本批 5 部著作 + 1 处「既有正文内插入」：

  * 新著作（5）：《剩余价值理论（节选）》（马恩全集 26 卷 I/III）、
    《神圣家族（节选）》（全集 2 卷）、卢森堡《资本积累论（节选）》、
    布哈林《世界经济与帝国主义》、希法亭《金融资本（节选）》；
  * 插入（1）：《资本论》第一卷 第十一/十二/十三章 并入既有
    `0-资本论节选.txt`（相对剩余价值的生产整篇），**原有行一个字节不改**。

硬约束：

  1) 原文一字不改：新著作必须能由 `import_mirror.build()` 从镜像逐字节复现，
     或由「备份全文 + `apply_trim`」复现；
  2) 插入只做「加行」：以 `sources/_backup_d105_append/0-资本论节选.txt`（插入前）
     为基准 + `insert_sc()` 必须复现现库，且章次顺序不变；
  3) 不新开章节：章节数仍 32，只向既有章节追加延伸阅读；
  4) 每条延伸阅读必须带 `local_work`（真实正文）；三本历史文献的 caution 必须
     写明「须对照批判」，不得进正面路径。
"""
from __future__ import annotations

import importlib.util
import re
import shutil
from collections import Counter
from pathlib import Path

import pytest

from content.book_chunks import BOOKS, available_works
from content.reading_extensions import READING_EXTENSIONS
from content.reading_extensions_d105 import D105_EXTENSIONS
from content.routes import SECTIONS

ROOT = Path(__file__).resolve().parents[2]
TEXTS = ROOT / "sources" / "texts"
BACKUP_TRIM = ROOT / "sources" / "_backup_d105_pretrim"
BACKUP_APPEND = ROOT / "sources" / "_backup_d105_append"

# 新增著作（不含插入目标 0-资本论节选.txt）
D105_WORKS = (
    "4-剩余价值理论节选.txt",
    "1-神圣家族节选.txt",
    "1-资本积累论节选.txt",
    "1-世界经济与帝国主义.txt",
    "1-金融资本节选.txt",
)

CLASSIC = (
    "4-剩余价值理论节选.txt",
    "1-神圣家族节选.txt",
)
HISTORICAL = (
    "1-资本积累论节选.txt",
    "1-世界经济与帝国主义.txt",
    "1-金融资本节选.txt",
)

# 必须保留的关键章节/概念
KEEP = {
    "4-剩余价值理论节选.txt": ("关于生产劳动和非生产劳动的理论", "重农学派",
                              "收入及其源泉。庸俗政治经济学", "资本的生产性"),
    "1-神圣家族节选.txt": ("对法国唯物主义的批判的战斗", "绝对的批判",
                          "批判的末日的审判"),
    "1-资本积累论节选.txt": ("原序", "简单再生产", "军国主义", "保护关税"),
    "1-世界经济与帝国主义.txt": ("序 言", "世界经济", "超帝国主义", "资本输出"),
    "1-金融资本节选.txt": ("前言", "股份公司", "金融资本", "资本输出"),
}


def _load_import_module():
    p = ROOT / "scripts" / "import_mirror.py"
    spec = importlib.util.spec_from_file_location("import_mirror_d105", p)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


def test_d105_backups_and_texts_present():
    """裁剪前/插入前备份齐备（复核与回退用），现库 5 部正文都在。"""
    assert {p.name for p in BACKUP_TRIM.glob("*.txt")} == {"4-剩余价值理论节选.txt"}
    assert {p.name for p in BACKUP_APPEND.glob("*.txt")} == {"0-资本论节选.txt"}
    for f in D105_WORKS:
        assert (TEXTS / f).exists(), f"正文缺失: {f}"


def test_d105_trim_reproduces_current_text():
    """《剩余价值理论》：只删网页沿页重复的卷名页头，其余与备份全文逐字节一致。"""
    mod = _load_import_module()
    f = "4-剩余价值理论节选.txt"
    assert f in mod.TRIM
    full = (BACKUP_TRIM / f).read_text(encoding="utf-8")
    cur = (TEXTS / f).read_text(encoding="utf-8")
    assert mod.apply_trim(f, full) == cur, f"{f} 裁剪结果不可复现（原文被改写？）"
    # 删的确实只有版式噪声：页头行 + 随之合并的一个空行，不涉任何正文
    assert len(full.splitlines()) - len(cur.splitlines()) == 2
    # 备份为「用字统一」前存档：那一行里的异体字先规范，才谈得上「只删了页头」
    removed = Counter(mod.fix_typos(full).splitlines()) - Counter(cur.splitlines())
    assert removed == Counter({"第二十六卷（I）": 1, "": 1}), removed
    assert "\n第二十六卷（I）\n" not in cur


def test_d105_insert_reproduces_kaplital_chapters():
    """《资本论》第十一至十三章：插入前备份 + insert_sc 必须复现现库，且不丢原行。"""
    mod = _load_import_module()
    f = mod.INSERT_SC["file"]
    before = (BACKUP_APPEND / f).read_text(encoding="utf-8")
    cur = (TEXTS / f).read_text(encoding="utf-8")
    tmp = BACKUP_APPEND.parent / ".tmp_d105_insert"
    tmp.mkdir(exist_ok=True)
    try:
        (tmp / f).write_bytes((BACKUP_APPEND / f).read_bytes())
        mod.insert_sc(tmp)
        assert (tmp / f).read_text(encoding="utf-8") == cur, \
            "插入结果不可复现（原有行被改写？）"
        # 幂等：再插一次不改动
        (tmp / f).write_bytes((BACKUP_APPEND / f).read_bytes())
        mod.insert_sc(tmp)
        mod.insert_sc(tmp)
        assert (tmp / f).read_text(encoding="utf-8") == cur
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    # 原有行全部保留（插入块是一段连续新增：去掉它应还原为插入前全文）
    # 插入前备份是「用字统一」之前的历史存档，比对前先过同样的规范化
    before_lines = mod.fix_typos(before).splitlines()
    cur_lines = cur.splitlines()
    assert len(cur_lines) > len(before_lines)
    i = cur_lines.index(mod.INSERT_SC["markers"][0])
    j = cur_lines.index(mod.INSERT_SC["anchor"])
    assert cur_lines[:i] + cur_lines[j:] == before_lines, "插入破坏了原有行内容/顺序"
    # 三章标题都在，且落在第二十二章之前（章次不乱）
    idx = {m: cur_lines.index(m) for m in mod.INSERT_SC["markers"]}
    assert idx["第十一章。协 作"] < idx["第十二章 分工和工场手工业"] \
        < idx["第十三章 机器和大工业。1—5"] < cur_lines.index(mod.INSERT_SC["anchor"])
    assert sum(1 for ln in cur_lines if ln.startswith("第十三章 机器和大工业")) == 1, \
        "第十三章的镜像分页页头未去重"


def test_d105_kept_sections_and_paragraph_structure():
    """关键章节必须在，段落结构未被破坏。"""
    for f, kws in KEEP.items():
        t = (TEXTS / f).read_text(encoding="utf-8")
        for k in kws:
            assert k in t, f"{f} 误删关键章节: {k}"
        assert "\n\n\n\n" not in t, f"{f} 段落结构被破坏（连续空行）"


@pytest.mark.skipif(not Path(r"D:/BaiduNetdiskDownload").exists(),
                    reason="本机无镜像（CI/他人环境跳过）")
def test_d105_mirror_rebuild_is_verbatim():
    """有镜像时：5 部新著作必须能由 build() 从镜像逐字节复现（原文一字未改）。"""
    mod = _load_import_module()
    specs = {s["file"]: s for s in mod.SPECS}
    for f in D105_WORKS:
        assert f in specs, f"SPECS 未登记: {f}"
        text, _ = mod.build(specs[f], trim=True, keep_titles=True)
        assert text == (TEXTS / f).read_text(encoding="utf-8"), f"{f} 与镜像重build不一致"


def test_d105_book_registration():
    """5 部已登记进 BOOKS；id_prefix/slug 全局唯一；正统性分档正确。"""
    by_file = {b["file"]: b for b in BOOKS}
    for f in D105_WORKS:
        assert f in by_file, f"BOOKS 未登记: {f}"
    for f in CLASSIC:
        assert by_file[f]["orthodoxy_tag"] == "经典原著", f
        assert by_file[f]["authority_score"] == 1.0, f
    for f in HISTORICAL:
        assert by_file[f]["orthodoxy_tag"] == "正统", f
        assert 0.8 <= by_file[f]["authority_score"] < 1.0, f
    prefixes = [b["id_prefix"] for b in BOOKS]
    slugs = [b["slug"] for b in BOOKS]
    assert len(prefixes) == len(set(prefixes)), "id_prefix 冲突"
    assert len(slugs) == len(set(slugs)), "slug 冲突"
    for f in D105_WORKS:
        assert re.fullmatch(r"CH-[A-Z0-9]+-", by_file[f]["id_prefix"]), by_file[f]["id_prefix"]


def test_d105_extensions_have_local_work_and_declare_scope():
    """延伸阅读 6 条全部挂可解析的 local_work；三本历史文献必须写明对照批判。"""
    works = set(available_works())
    entries = [it for items in D105_EXTENSIONS.values() for it in items]
    assert len(entries) == 6, len(entries)
    assert len({it["title"] for it in entries}) == 6, "标题重复"
    kinds = [it["kind"] for it in entries]
    assert kinds.count("classic") == 3 and kinds.count("historical") == 3, kinds
    for it in entries:
        lw = it.get("local_work")
        assert lw and lw in works, f"{it['title']} local_work 未入库: {lw}"
        c = it["caution"]
        assert ("节选" in c or "全文" in c), f"{it['title']} caution 未声明节选口径"
        if it["kind"] == "historical":
            assert "对照" in c and "批判" in c, f"{it['title']} 历史文献未写对照批判"
        for word in ("D105", "TRIM", "sec_", "local_work", "INSERT"):
            assert word not in c + it["title"] + it["intro"] + it["how_to_use"], \
                f"{it['title']} 暴露开发标记 {word}"


def test_d105_no_new_sections_and_merge_order():
    """不新开章节（仍 32 章）；D105 条目合并进主表且本批连续保序。"""
    assert len(SECTIONS) == 32
    ids = {s["id"] for s in SECTIONS}
    for sid, items in D105_EXTENSIONS.items():
        assert sid in ids, f"D105 章节 id 不存在: {sid}"
        titles = [it["title"] for it in READING_EXTENSIONS[sid]]
        idx = [titles.index(it["title"]) for it in items]
        assert idx == sorted(idx) and idx == list(range(idx[0], idx[0] + len(idx))), \
            f"{sid} D105 条目未连续追加"

# 依赖 sources/texts/ 原著正文；无正文时由 conftest.py 自动跳过。
pytestmark = pytest.mark.needs_texts
