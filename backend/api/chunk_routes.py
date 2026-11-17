"""原著分片路由 — 从内存内容提供器读取（轻量模式无需 PG，不再 500）

前端「原著浏览 / 溯源卡片」用它拉取分片原文。数据来自 content_provider，
底层是已入库的提纲分片（theses_annotations.build_chunks）。
"""
from __future__ import annotations

from fastapi import APIRouter

from services import content_provider

router = APIRouter()


@router.get("/works")
async def list_works() -> dict:
    """已入库著作清单。

    `works`：著作名数组（旧口径，保持兼容）；
    `items`：带作者 / 分片数 / 首片 id，原著浏览页的搜索与分组用（`is_book=False`
    表示分片来自内部注释层而非某本原著）。
    """
    items = content_provider.works_meta()
    return {
        "works": [it["work"] for it in items],
        "items": items,
        "total": len(items),
    }


@router.get("/by_work/{work}")
async def list_by_work(work: str) -> dict:
    """按著作列出分片（work=all 或空返回全部）。"""
    items = content_provider.all_chunks() if work in ("all", "", "_") else content_provider.chunks_by_work(work)
    return {"work": work, "count": len(items), "items": items}


@router.get("/{chunk_id}")
async def get_chunk(chunk_id: str) -> dict:
    c = content_provider.get_chunk(chunk_id)
    if not c:
        return {"error": "not_found", "chunk_id": chunk_id}
    return c
