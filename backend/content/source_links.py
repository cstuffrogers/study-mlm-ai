"""章节导读 → 真实原文分片的链接索引（只读，不改写正文/知识点）。

背景：深入学习页「本章知识点」里，只有内容表显式写了 source_chunk_id 的
节点（《关于费尔巴哈的提纲》等）才会显示「溯源」标签；其余为「导读型
知识点」，历史上 source_chunk_id 为空，因此没有链接。

本模块不篡改任何知识点数据，也不伪造权威溯源：
  · authoritative：内容表已标注的真实分片 id（经 get_chunk 校验存在）。
  · related：按节点名/释义的汉字二元组，在本章主文「已入库真实分片」
    里做只读检索，给出最相关的原文片段，供用户核对原文。
  · none：本章原文里未检索到可用片段，只保留「阅读本章原文」通读入口。

红线：related 只是「相关原文片段（关键词检索）」，绝不冒充逐条权威溯源；
不改 ROUTE_NODES / KNOWLEDGE_NODES / 题库的 source_chunk_id。
"""
from __future__ import annotations

import re
from functools import lru_cache

from services import content_provider

_PUNCT = re.compile(r"[^\u4e00-\u9fffA-Za-z0-9]+")


def _bigrams(text: str) -> frozenset[str]:
    """汉字/ASCII 二元组词袋：对中文短概念名比整词匹配更稳。"""
    s = _PUNCT.sub("", (text or "").lower())
    if len(s) < 2:
        return frozenset({s}) if s else frozenset()
    return frozenset(s[i : i + 2] for i in range(len(s) - 1))


@lru_cache(maxsize=64)
def _work_index(work: str) -> tuple[tuple[str, str, str, frozenset[str], str], ...]:
    """按著作缓存「分片 id / 出处 / 二元组词袋 / 预览」，避免每次 guide 重扫全库。"""
    out: list[tuple[str, str, str, frozenset[str], str]] = []
    for c in content_provider.chunks_by_work(work):
        cid = (c.get("id") or "").strip()
        if not cid:
            continue
        text = c.get("text") or ""
        out.append((
            cid,
            c.get("source", ""),
            c.get("source_location", ""),
            _bigrams(text[:1600]),
            text[:90],
        ))
    return tuple(out)


def _best(query: str, index: tuple, min_hits: int = 2) -> dict | None:
    q = _bigrams(query)
    if not q or not index:
        return None
    best = None
    best_hits = 0
    best_idx = None
    for row in index:
        hits = len(q & row[3])
        if hits > best_hits:
            best_hits, best_idx = hits, row
    if best_idx is None or best_hits < min_hits:
        return None
    return {
        "chunk_id": best_idx[0],
        "source": best_idx[1],
        "source_location": best_idx[2],
        "hits": best_hits,
        "preview": best_idx[4],
        "kind": "related",
    }


@lru_cache(maxsize=64)
def _work_postings(work: str) -> dict[str, tuple[int, ...]]:
    """二元组 → 分片下标。把「逐条求交集」降为「只打分命中候选」，

    一章两三千分片时，原先每个知识点/每个块都要全扫一遍（O(N) × 块数），
    现在是 O(候选数)。
    """
    index = _work_index(work)
    post: dict[str, list[int]] = {}
    for i, row in enumerate(index):
        for g in row[3]:
            post.setdefault(g, []).append(i)
    return {k: tuple(v) for k, v in post.items()}


@lru_cache(maxsize=512)
def _cached_best(work: str, query: str, min_hits: int = 2) -> dict | None:
    """按（著作, 查询）缓存检索结果；导读块在多用户/多次打开时高度重复。"""
    q = _bigrams(query)
    index = _work_index(work) if work else ()
    if not q or not index:
        return None
    post = _work_postings(work) if work else {}
    counts: dict[int, int] = {}
    for g in q:
        for i in post.get(g, ()):  # 只遍历命中的分片
            counts[i] = counts.get(i, 0) + 1
    best_i = None
    best_hits = 0
    for i in sorted(counts):  # 保序：同分取更靠前的分片，与原线性扫描一致
        hits = counts[i]
        if hits > best_hits:
            best_hits, best_i = hits, i
    if best_i is None or best_hits < min_hits:
        return None
    row = index[best_i]
    return {
        "chunk_id": row[0],
        "source": row[1],
        "source_location": row[2],
        "hits": best_hits,
        "preview": row[4],
        "kind": "related",
    }


def _find(query: str, work: str, min_hits: int = 2) -> dict | None:
    """带缓存的检索入口（返回拷贝，调用方可安全 update）。"""
    if not work or not query:
        return None
    hit = _cached_best(work, query, min_hits)
    return dict(hit) if hit else None


def best_related_chunk(query: str, chunks: list[dict]) -> dict | None:
    """在本章真实分片里按二元组重合度找最相关片段；找不到返回 None。

    保留此公开函数便于单测；生产链路走 _work_index 缓存版本。
    """
    if not chunks:
        return None
    work = (chunks[0].get("source") or "").strip()
    return _best(query, _work_index(work))


def node_links(nodes: list[dict], local_work: str) -> list[dict]:
    """为每个知识点生成一条可点击的原文链接（或明确标注无链接）。"""
    out: list[dict] = []
    for n in nodes:
        nid = (n.get("id") or "").strip()
        name = (n.get("name") or "").strip()
        cid = (n.get("source_chunk_id") or "").strip()
        item: dict = {
            "node_id": nid,
            "name": name,
            "kind": "none",
            "chunk_id": "",
            "source": "",
            "source_location": "",
            "reason": "导读型知识点：内容库未逐条标注原文分片，且本章原文未检索到相关片段",
        }
        if cid:
            real = content_provider.get_chunk(cid)
            if real:
                item.update(
                    kind="authoritative",
                    chunk_id=cid,
                    source=real.get("source", ""),
                    source_location=real.get("source_location", ""),
                    reason="原著正文中已标注权威溯源位置",
                )
            else:
                item["reason"] = f"标注的分片 {cid} 不在本机正文库，待核对"
            out.append(item)
            continue
        rel = _find(f"{name} {n.get('definition') or ''}", local_work)
        if rel:
            item.update(
                kind="related",
                chunk_id=rel["chunk_id"],
                source=rel["source"],
                source_location=rel["source_location"],
                reason="按知识点名/释义在本章原文中检索到的相关片段（非逐条权威溯源）",
            )
        out.append(item)
    return out


def block_links(guide: dict, local_work: str) -> dict:
    """为「写作背景 / 核心概念 / 正文导读 / 要点提炼 / 思考题」找相关原文。"""

    def find(q: str) -> dict | None:
        return _find(q[:160], local_work)

    concepts = []
    for c in guide.get("core_concepts") or []:
        q = " ".join(str(x) for x in c[:1]) if isinstance(c, (list, tuple)) else str(c)
        concepts.append(find(q))

    sections = []
    for s in guide.get("sections") or []:
        m = s if isinstance(s, dict) else {}
        sections.append(find(f"{m.get('heading') or ''} {m.get('body') or ''}"))

    scalars = [str(x) for x in (guide.get("key_points") or [])]
    discusses = [str(x) for x in (guide.get("discussion") or [])]

    return {
        "background": find(str(guide.get("background") or "")),
        "concepts": concepts,
        "sections": sections,
        "key_points": [find(x) for x in scalars],
        "discussion": [find(x) for x in discusses],
    }


def chapter_source(sec: dict) -> dict:
    local_work = (sec.get("local_work") or "").strip()
    index = _work_index(local_work) if local_work else ()
    return {
        "work": sec.get("work") or "",
        "local_work": local_work,
        "work_short": sec.get("work_short") or local_work,
        "chunk_count": len(index),
        "has_full_text": bool(index),
        "first_chunk_id": index[0][0] if index else "",
    }
