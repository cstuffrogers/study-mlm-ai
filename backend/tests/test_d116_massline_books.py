"""D116 门禁：组织领导 / 群众路线谱系补环（5 部）

用户口径（2026-11）：「你甄别好，符合的才加入，也不是全文加入」——即逐篇核对
版本与内容红线，并且**只把与章节对得上的部分入库**，不整篇照录。

本测试覆盖四类约束：

  1) **甄别**：5 部全部出现在 BOOKS，前缀/分片 id 唯一，正文文件齐备；
     红线项（黑名单组织文献、批判对象、路线分歧材料）不得混入；
  2) **节选**：从 `sources/_backup_d116_pretrim/` 的裁剪前全文按 `TRIM` 重切，
     必须与现库逐字节一致（原文一字未改、可复现）；保留/删去的边界按标题行核对；
  3) **挂接**：5 条延伸阅读全部 `kind="classic"` 且带 `local_work`，
     分别挂在 sec_B_04 / sec_B_05 / sec_B_09 / sec_C_04，caution 如实声明保留与删去范围；
  4) **不膨胀**：章节数仍为 32，不新开章节。
"""
from __future__ import annotations

import importlib.util
from pathlib import Path

from content.book_chunks import BOOKS, all_book_chunks, available_works
from content.reading_extensions import READING_EXTENSIONS
from content.reading_extensions_d116 import D116_EXTENSIONS
from content.routes import SECTIONS

ROOT = Path(__file__).resolve().parents[2]
TEXTS = ROOT / "sources" / "texts"
BACKUP = ROOT / "sources" / "_backup_d116_pretrim"

D116_WORKS = (
    "5-关心群众生活注意工作方法.txt",
    "5-农村调查的序言和跋.txt",
    "5-组织起来.txt",
    "1-关于白区的党和群众工作.txt",
    "1-怎样进行群众工作.txt",
)

# 每条延伸阅读 → 期望挂载章节
EXPECTED_SECTION = {
    "《关心群众生活，注意工作方法》（1934）": "sec_B_09",
    "《〈农村调查〉的序言和跋》（1941）": "sec_B_05",
    "《组织起来》（1943）": "sec_C_04",
    "《关于白区的党和群众工作》（1937）": "sec_B_04",
    "《怎样进行群众工作——给群众工作的同志们一封信》（1936）": "sec_B_04",
}

# 保留侧用子串判断；删去侧用「独立成行」判断（正文提及不算残留）
KEEP = {
    "5-关心群众生活注意工作方法.txt": ("关心群众生活", "注意工作方法", "长冈乡",
                                  "柴米油盐", "真正的铜墙铁壁"),
    "5-农村调查的序言和跋.txt": ("序", "跋", "眼睛向下", "开调查会", "没有调查"),
    "5-组织起来.txt": ("组织起来", "合作社", "自愿的原则", "脱离群众"),
    "1-关于白区的党和群众工作.txt": ("党和群众的关系", "公开工作和秘密工作的联系",
                                "群众的领袖", "民主", "党的转变"),
    "1-怎样进行群众工作.txt": ("先锋队", "民主的工作方式", "公开", "党团"),
}

DROP_LINES = {
    # 卷末注释区（注释条目整块删去；正文里的脚注序号 [1] ~ [6] 属于原文，保留）
    "5-关心群众生活注意工作方法.txt": ("注释",),
    "5-农村调查的序言和跋.txt": ("注释",),
    "5-组织起来.txt": ("注释",),
    # 「彻底的转变」整节、「党的转变」后五节与卷末题注/注释
    "1-关于白区的党和群众工作.txt": ("彻底的转变", "注释"),
    # （五）（六）两节与结尾口号
    "1-怎样进行群众工作.txt": ("（五）", "（六）"),
}

# 只对「按节保留」的 2 部刘文要求明显的裁剪比例（毛三篇是短篇全文，只裁注释）
TRIMMED_HARD = (
    "1-关于白区的党和群众工作.txt",
    "1-怎样进行群众工作.txt",
)


def _load_import_module():
    p = ROOT / "scripts" / "import_mirror.py"
    spec = importlib.util.spec_from_file_location("import_mirror_d116", p)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


def test_d116_books_registered_and_unique():
    """5 部全部登记、文件齐备、前缀/分片 id 唯一。"""
    files = {b["file"] for b in BOOKS}
    for f in D116_WORKS:
        assert f in files, f"未在 BOOKS 登记: {f}"
        assert (TEXTS / f).exists(), f"正文文件缺失: {f}"
    prefixes = [b["id_prefix"] for b in BOOKS]
    assert len(prefixes) == len(set(prefixes)), "id_prefix 有重复"
    ids = [c["id"] for c in all_book_chunks()]
    assert len(ids) == len(set(ids)), "分片 id 有重复"
    for b in BOOKS:
        if b["file"] in D116_WORKS:
            assert b["orthodoxy_tag"] == "经典原著"
            assert b["authority_score"] == 1.0
            assert b["author"] in ("毛泽东", "刘少奇"), b["author"]


def test_d116_works_available_and_readable():
    """5 部都可被前端/学习路径按著作名检索到（available_works 口径）。"""
    works = set(available_works())
    for w in ("关心群众生活，注意工作方法", "《农村调查》的序言和跋", "组织起来",
              "关于白区的党和群众工作", "怎样进行群众工作"):
        assert w in works, f"著作名不可检索: {w}"


def test_d116_excerpts_reproducible_from_backup():
    """从裁剪前全文按 TRIM 重切，必须与现库逐字节一致（原文一字未改）。"""
    mod = _load_import_module()
    assert {p.name for p in BACKUP.glob("*.txt")} == set(D116_WORKS), \
        "裁剪前全文备份应且只应含 D116 这 5 部"
    for f in D116_WORKS:
        full = (BACKUP / f).read_text(encoding="utf-8")
        cur = (TEXTS / f).read_text(encoding="utf-8")
        assert len(cur) < len(full), f"{f} 未裁剪（注释/未选章节仍在）"
        if f in TRIMMED_HARD:
            assert 0.15 < len(cur) / len(full) < 0.80, \
                f"{f} 裁剪比例异常: {len(cur)/len(full):.2%}"
        assert mod.apply_trim(f, full) == cur, f"{f} 裁剪结果不可复现（原文被改写？）"


def test_d116_kept_and_dropped_sections():
    """保留的章节/概念在，删去的章节标题作为独立行必须不存在。"""
    for f, kws in KEEP.items():
        t = (TEXTS / f).read_text(encoding="utf-8")
        for k in kws:
            assert k in t, f"{f} 误删关键内容: {k}"
        assert "\n\n\n\n" not in t, f"{f} 段落结构被破坏（连续空行）"
    for f, kws in DROP_LINES.items():
        lines = [x.strip() for x in (TEXTS / f).read_text(encoding="utf-8").splitlines()]
        for k in kws:
            assert k not in lines, f"{f} 仍残留应裁章节标题: {k}"


def test_d116_extensions_attached_with_local_work():
    """5 条延伸阅读挂对了章节，且每条都带真实正文与如实 caution。"""
    assert len(D116_EXTENSIONS) == 4
    offset = 0
    for sid, items in D116_EXTENSIONS.items():
        for it in items:
            offset += 1
            assert it["kind"] == "classic", f"{it['title']} 非 classic 档"
            lw = it.get("local_work", "")
            assert lw, f"{it['title']} 缺 local_work"
            assert lw in set(available_works()), f"{it['title']} local_work 指向不存在的正文"
            assert it["title"] in {x["title"] for x in READING_EXTENSIONS[sid]}, \
                f"{it['title']} 未挂到 {sid}"
            assert EXPECTED_SECTION[it["title"]] == sid, \
                f"{it['title']} 挂错章节: {sid}"
            c = it.get("caution", "")
            assert c, f"{it['title']} 缺 caution"
            assert ("节选" in c or "未作节选" in c or "全文" in c), \
                f"{it['title']} caution 未声明节选/全文口径"
            assert "一字未改" in c, f"{it['title']} caution 未声明原文一字未改"
            assert "D116" not in c and "TRIM" not in c, \
                f"{it['title']} caution 暴露开发标记"
            # 读者向：不得把节选说成「全文照录」又同时声称节选（自相矛盾）
            if "未作节选" not in c:
                c2 = c.replace("非全文", "").replace("全文备份", "").replace("短篇全文", "")
                assert "全文" not in c2, \
                    f"{it['title']} caution 可能把节选当成全文"
    assert offset == 5, f"D116 条目数应为 5，实际 {offset}"


def test_d116_no_blacklisted_material():
    """甄别底线：黑名单组织文献、菲共《论群众工作》一类一律不得进入正文/延伸阅读。"""
    from content.reading_extensions import READING_BLACKLIST
    banned = ("菲共", "菲律宾共产党", "他加禄", "论群众工作", "光辉道路", "印共（毛）")
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


def test_d116_chapters_still_32():
    """不新开章节：章节数仍为 32，且 D116 未新增 section id。"""
    assert len(SECTIONS) == 32
    assert len({s["id"] for s in SECTIONS}) == 32
    assert set(D116_EXTENSIONS) <= {s["id"] for s in SECTIONS}

# 依赖 sources/texts/ 原著正文；无正文时由 conftest.py 自动跳过。
import pytest

pytestmark = pytest.mark.needs_texts
