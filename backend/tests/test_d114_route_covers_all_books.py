"""D114 门禁：学习路线必须覆盖库内全部著作，且不得引用库里没有的书。

背景：原著库从 90 部扩到 122 部后，前端「原著浏览」看不到（D114 前半段已修）。
这里守的是另一条链：**新入库的书必须被某一章的导读或延伸阅读引用**，
否则它在学习路线里完全没有入口（库里有、路线里找不到 = 隐形书）。

覆盖口径（两层都算）：
  · 章节主书 `SECTIONS[i]['local_work']` —— 该章的原文直读对象；
  · 延伸阅读 `READING_EXTENSIONS[section_id][*]['local_work']` —— 导读页的扩展读物卡。
"""
from __future__ import annotations

from content.book_chunks import BOOKS
from content.reading_extensions import READING_EXTENSIONS
from content.routes import SECTIONS


def _referenced() -> tuple[set[str], dict[str, list[str]]]:
    """返回（路线引用的全部书名, 书名 → 出处列表）。"""
    origins: dict[str, list[str]] = {}

    for s in SECTIONS:
        w = s.get("local_work")
        if w:
            origins.setdefault(w, []).append(f"主书:{s['id']}")

    for sid, items in READING_EXTENSIONS.items():
        for it in items:
            w = it.get("local_work") or it.get("work")
            if w:
                origins.setdefault(w, []).append(f"延伸:{sid}")

    return set(origins), origins


def test_no_dangling_route_references() -> None:
    """路线指向的书必须真的在库里，否则界面点了打不开。"""
    books = {b["work"] for b in BOOKS}
    referenced, origins = _referenced()
    dangling = sorted(referenced - books)
    assert not dangling, (
        "以下书名被学习路线引用，但 BOOKS 里没有（前端点击会打不开/空白）：\n  "
        + "\n  ".join(f"{w}  ← {origins[w]}" for w in dangling)
    )


def test_every_book_reachable_from_routes() -> None:
    """库里每部书都要在学习路线有入口（章节主书或延伸阅读）。"""
    books = {b["work"] for b in BOOKS}
    referenced, _ = _referenced()
    orphans = sorted(books - referenced)
    assert not orphans, (
        f"{len(orphans)} 部著作已入库但没有挂到任何章节（学习路线里找不到入口）：\n  "
        + "\n  ".join(orphans)
        + "\n请加进某章的 READING_EXTENSIONS（不新增章节）。"
    )


def test_coverage_stats_sane() -> None:
    """基本盘点：章节数固定 32，主书不超章节数，延伸阅读有内容。"""
    assert len(SECTIONS) == 32, "章节数固定 32 章，不得新增"
    main_works = {s["local_work"] for s in SECTIONS if s.get("local_work")}
    assert 25 <= len(main_works) <= 32
    assert sum(len(v) for v in READING_EXTENSIONS.values()) >= 100


def test_every_section_has_extensions() -> None:
    """D114：32 章不应有「零延伸阅读」的章节（读者读完导读无下一步读物）。"""
    empty = [s["id"] for s in SECTIONS if not READING_EXTENSIONS.get(s["id"])]
    assert not empty, f"以下章节没有延伸阅读条目：{empty}"


def test_extension_local_work_exists() -> None:
    """延伸阅读挂的 local_work 必须真有正文，否则「阅读原文」打开空白。"""
    books = {b["work"] for b in BOOKS}
    bad = [
        f"{sid} / {it.get('title')} → {it.get('local_work')}"
        for sid, items in READING_EXTENSIONS.items()
        for it in items
        if it.get("local_work") and it["local_work"] not in books
    ]
    assert not bad, "延伸阅读引用了不存在的正文：\n  " + "\n  ".join(bad)
