"""间隔复习 API（P1-① D8）"""
from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel

from services.learning_startup import ensure_learning_ready
from services import review_service

router = APIRouter()


class ReviewSubmitIn(BaseModel):
    user_id: str
    route_id: str = "route_A"
    node_id: str
    correct_ratio: float = 1.0


@router.get("/due")
async def due(route_id: str = "route_A", user_id: str = "demo_user") -> dict:
    await ensure_learning_ready()
    items = await review_service.due_reviews(user_id, route_id)
    return {"route_id": route_id, "due_count": len(items), "due": items}


@router.get("/status")
async def status(route_id: str = "route_A", user_id: str = "demo_user") -> dict:
    await ensure_learning_ready()
    return await review_service.review_status(user_id, route_id)


@router.post("/submit")
async def submit(body: ReviewSubmitIn) -> dict:
    await ensure_learning_ready()
    return await review_service.apply_review(body.user_id, body.route_id, body.node_id, body.correct_ratio)


@router.get("/interleaved")
async def interleaved(route_id: str = "route_A", user_id: str = "demo_user", n: int = 8) -> dict:
    """交错复习队列（P2-⑤）：到期项 + 跨知识点巩固项混排，降低块状效应。"""
    await ensure_learning_ready()
    items = await review_service.interleaved_reviews(user_id, route_id, n=n)
    return {"route_id": route_id, "count": len(items), "items": items}


@router.get("/fit")
async def fit(user_id: str | None = None, route_id: str | None = None) -> dict:
    """FSRS 参数拟合建议（D15）：从真实复习日志估计 GAIN/REGRESS。"""
    await ensure_learning_ready()
    return await review_service.fit_parameters(user_id=user_id, route_id=route_id)
