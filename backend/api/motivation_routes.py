"""动机/挫折调节 API（P3 D14）"""
from __future__ import annotations

from fastapi import APIRouter

from services.learning_startup import ensure_learning_ready
from services import motivation_service

router = APIRouter()


@router.get("/state")
async def state(route_id: str = "route_A", user_id: str = "demo_user") -> dict:
    await ensure_learning_ready()
    return await motivation_service.motivation_state(user_id, route_id)
