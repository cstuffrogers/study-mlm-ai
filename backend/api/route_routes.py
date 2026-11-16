"""路线与导航 API"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from services.learning_startup import ensure_learning_ready
from services import route_service, quiz_service
from content.chapter_content import guide_for, nodes_for_section
from content.routes import get_section
from content.reading_extensions import extensions_for, blacklist
from content.source_links import block_links, chapter_source, node_links

router = APIRouter()


class SelectIn(BaseModel):
    user_id: str


class DiagnosticSubmitIn(BaseModel):
    user_id: str
    answers: list[dict] = []


@router.get("")
async def list_routes() -> dict:
    await ensure_learning_ready()
    return {"routes": await route_service.list_routes()}


@router.get("/{route_id}/sections")
async def routes_sections(route_id: str, user_id: str = "demo_user") -> dict:
    await ensure_learning_ready()
    return await route_service.get_routes_sections(user_id, route_id)


@router.post("/{route_id}/select")
async def select_route(route_id: str, body: SelectIn) -> dict:
    await ensure_learning_ready()
    return await route_service.select_route(body.user_id, route_id)


@router.post("/{route_id}/diagnostic")
async def start_diagnostic(route_id: str, body: SelectIn) -> dict:
    await ensure_learning_ready()
    return await quiz_service.start_diagnostic(body.user_id, route_id)


@router.post("/diagnostic/{diag_id}/submit")
async def submit_diagnostic(diag_id: str, body: DiagnosticSubmitIn) -> dict:
    await ensure_learning_ready()
    return await quiz_service.submit_diagnostic(diag_id, body.user_id, body.answers)


@router.get("/{route_id}/sections/{section_id}/gating")
async def gating(route_id: str, section_id: str, user_id: str = "demo_user") -> dict:
    await ensure_learning_ready()
    return await route_service.gating(user_id, route_id, section_id)


@router.get("/{route_id}/sections/{section_id}/guide")
async def section_guide(route_id: str, section_id: str) -> dict:
    """章节导读（背景/核心概念/要点/思考题/正文分段）+ 知识点清单 + 原文链接。

    source_links 只读地从本章已入库的真实分片里检索相关片段，用于把
    「导读型知识点 / 正文各板块」也连到本机原文；权威溯源仍以内容表
    的 source_chunk_id 为准，不改动任何知识点数据。
    """
    guide = guide_for(section_id)
    nodes = nodes_for_section(section_id)
    sec = get_section(section_id) or {}
    local_work = (sec.get("local_work") or "").strip()
    return {"section_id": section_id, "route_id": route_id,
            "guide": guide, "nodes": nodes,
            "section_work": sec.get("work"),
            "section_title": sec.get("title"),
            "local_work": sec.get("local_work"),
            "work_short": sec.get("work_short"),
            "source_links": {
                "chapter": chapter_source(sec),
                "nodes": node_links(nodes, local_work),
                "blocks": block_links(guide, local_work),
            },
            "extensions": extensions_for(section_id), "extensions_blacklist": blacklist()}
