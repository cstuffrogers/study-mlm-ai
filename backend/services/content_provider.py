"""统一内容提供器 — 原著分片 / 章节导读，优先内存、无 PG 也可用

分片来源（合并）：
  1) 《关于费尔巴哈的提纲》人工四层分片（theses_annotations.build_chunks）
  2) 已入正文的原著自动分段（content.book_chunks：大众哲学 / 哲学笔记 …）
  其余章节若无原文，仅提供「学习导读」（背景/核心概念/要点/思考题），
  明确标注为导读，绝不伪装成原著原文（正统性红线：不得伪造经典文本）。

本模块被 chunk 路由与阅读/溯源前端共用，保证轻量模式下不再 500。

性能：全库约 2.2 万分片。原先 get_chunk / chunks_by_work / chunks_for_paragraph
每次线性扫描全表（单次毫秒级、但阅读页/溯源卡一次请求会连查多次）。这里改为
首次构建一次性索引（id 字典 + 按著作 + 按段落），后续 O(1)/O(k) 读取。
索引与 _all_chunks 同为进程内只读缓存，构建后不再失效（数据是打包的静态内容）。
"""
from __future__ import annotations

from functools import lru_cache


@lru_cache(maxsize=1)
def _all_chunks() -> tuple[dict, ...]:
    from content.theses_annotations import build_chunks

    chunks: list[dict] = list(build_chunks())
    try:
        from content.book_chunks import all_book_chunks

        chunks.extend(all_book_chunks())
    except Exception:  # pragma: no cover - 正文入库失败不应阻断提纲分片
        pass
    return tuple(chunks)


@lru_cache(maxsize=1)
def _chunk_by_id() -> dict[str, dict]:
    """id → 分片（O(1) 取正文，替代线性扫描）。"""
    return {c["id"]: c for c in _all_chunks() if c.get("id")}


@lru_cache(maxsize=1)
def _index_by_paragraph() -> dict[str, tuple[dict, ...]]:
    idx: dict[str, list[dict]] = {}
    for c in _all_chunks():
        pid = c.get("paragraph_id")
        if pid:
            idx.setdefault(pid, []).append(c)
    return {k: tuple(v) for k, v in idx.items()}


# 我们自己写的注释层（第 3/4 层）不是原著，不该出现在「原著浏览」书单里。
_NON_ORIGINAL_TYPES = frozenset({"annotation", "analysis"})


@lru_cache(maxsize=1)
def _original_works() -> frozenset[str]:
    """分片全部是注释/解析层的「书」——是内部合成层，不是原著。"""
    types: dict[str, set[str]] = {}
    for c in _all_chunks():
        s = c.get("source", "")
        if not s:
            continue
        types.setdefault(s, set()).add(str(c.get("logical_type") or ""))
    return frozenset(
        w for w, ts in types.items() if ts and ts <= _NON_ORIGINAL_TYPES
    )


@lru_cache(maxsize=1)
def _works() -> tuple[str, ...]:
    hidden = _original_works()
    seen: list[str] = []
    for c in _all_chunks():
        s = c.get("source", "")
        if s and s not in seen and s not in hidden:
            seen.append(s)
    return tuple(seen)


def works_meta() -> list[dict]:
    """书籍清单（含作者 / 分片数）——原著浏览页搜索、分组、跳转都用它。

    作者只在已登记的正文文件（BOOKS）里带；《提纲》原文由 theses_raw 提供，
    注释/解析层来自统编教材。查不到作者就留空（前端显示「作者未标注」），不猜。
    """
    from content.book_chunks import BOOKS
    from content.theses_raw import WORK_TITLE

    authors: dict[str, str] = {str(b.get("work", "")): str(b.get("author", "")) for b in BOOKS}
    authors.setdefault(WORK_TITLE, "马克思")

    out: list[dict] = []
    for w in works():
        items = chunks_by_work(w)
        out.append({
            "work": w,
            "author": authors.get(w, ""),
            "chunk_count": len(items),
            "first_chunk_id": items[0]["id"] if items else "",
            "is_book": w in authors,
        })
    return out


@lru_cache(maxsize=1)
def _index_by_work() -> dict[str, tuple[dict, ...]]:
    """精确著作名 → 分片。模糊匹配走一次 works 过滤（作品数很少）。"""
    idx: dict[str, list[dict]] = {}
    for c in _all_chunks():
        s = c.get("source", "")
        if s:
            idx.setdefault(s, []).append(c)
    return {k: tuple(v) for k, v in idx.items()}


def all_chunks() -> list[dict]:
    """全部可检索分片（内存）。"""
    return list(_all_chunks())


def chunks_by_work(work: str) -> list[dict]:
    """按著作名匹配分片；空串返回全部。

    先命中精确索引（绝大多数调用是阅读页按著作取全文），
    只有调用方传了「作品名片段」时才退化为一次 contains 匹配。
    """
    if not work:
        return all_chunks()
    exact = _index_by_work().get(work)
    if exact is not None:
        return list(exact)
    by_work = _index_by_work()
    out: list[dict] = []
    for name, items in by_work.items():
        if work in name or name in work:
            out.extend(items)
    return out


def get_chunk(chunk_id: str) -> dict | None:
    return _chunk_by_id().get(chunk_id)


def chunk_text(chunk_id: str) -> str:
    c = get_chunk(chunk_id)
    return c["text"] if c else ""


def chunks_for_paragraph(paragraph_id: str) -> list[dict]:
    return list(_index_by_paragraph().get(paragraph_id, ()))


def works() -> list[str]:
    """已入库分片的著作名（去重保序）。"""
    return list(_works())


def warm_index() -> None:
    """预热索引（应用启动或健康检查时调用，避免首个阅读请求付构建成本）。"""
    _all_chunks()
    _chunk_by_id()
    _index_by_paragraph()
    _index_by_work()
    _works()


def index_stats() -> dict:
    return {
        "chunks": len(_all_chunks()),
        "works": len(_works()),
        "paragraphs": len(_index_by_paragraph()),
    }
