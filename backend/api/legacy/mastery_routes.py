"""掌握度与学情档案 API"""
from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel

from services.learning_startup import ensure_learning_ready
from services import mastery_service as ms, profile_service

router = APIRouter()


class SummaryIn(BaseModel):
    user_id: str
    route_id: str = "route_A"
    period: str = "week"


@router.get("/profile")
async def profile(route_id: str = "route_A", user_id: str = "demo_user") -> dict:
    await ensure_learning_ready()
    return await profile_service.build_profile(user_id, route_id)


@router.get("/node/{node_id}")
async def node_detail(node_id: str, route_id: str = "route_A", user_id: str = "demo_user") -> dict:
    """知识点详情：自身掌握记录 + 节点元信息 + 前置/后继节点（含掌握度）+ 证据信号。"""
    await ensure_learning_ready()
    from content.knowledge_graph import get_node, get_node as _gn
    from services.knowledge_graph_service import get_kg
    m = await ms.get_mastery_map(user_id, route_id)

    meta = _gn(node_id) or {}
    rec = m.get(node_id) or {"node_id": node_id, "level": "unseen", "score": 0.0, "basis": {}, "signals": []}

    kg = get_kg()
    def _brief(nid: str) -> dict:
        n = get_node(nid) or {}
        mr = m.get(nid) or {}
        return {"node_id": nid, "name": n.get("name", nid), "section_id": n.get("section_id", ""),
                "level": mr.get("level", "unseen"), "score": mr.get("score", 0.0)}

    prereqs = [_brief(p) for p in kg.prereq_map.get(node_id, [])]
    dependents = [_brief(d) for d in kg.dependents(node_id)]

    return {
        **rec,
        "name": meta.get("name", node_id),
        "definition": meta.get("definition", ""),
        "section_id": meta.get("section_id", ""),
        "ability_dim": meta.get("ability_dim", ""),
        "exam_weight": meta.get("exam_weight", 0.0),
        "source_chunk_id": meta.get("source_chunk_id", ""),
        "prerequisites": prereqs,
        "dependents": dependents,
        "dependents_count": kg.dependents_count(node_id),
    }


@router.post("/summary")
async def summary(body: SummaryIn) -> dict:
    await ensure_learning_ready()
    return await profile_service.generate_summary(body.user_id, body.route_id, body.period)
