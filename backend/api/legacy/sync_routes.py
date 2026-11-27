"""跨设备同步 API（NFR-004）"""
from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel

from services.learning_startup import ensure_learning_ready
from services import sync_service

router = APIRouter()


class PushIn(BaseModel):
    user_id: str
    route_id: str = "route_A"
    events: list[dict] = []


class ProgressIn(BaseModel):
    user_id: str
    route_id: str = "route_A"
    section_id: str
    last_position: int = 0
    status: str = "in_progress"


@router.post("/push")
async def push(body: PushIn) -> dict:
    await ensure_learning_ready()
    return await sync_service.push(body.user_id, body.route_id, body.events)


@router.get("/pull")
async def pull(route_id: str = "route_A", user_id: str = "demo_user") -> dict:
    await ensure_learning_ready()
    return await sync_service.pull(user_id, route_id)


@router.post("/progress")
async def progress(body: ProgressIn) -> dict:
    await ensure_learning_ready()
    return await sync_service.save_progress(body.user_id, body.route_id, body.section_id,
                                            body.last_position, body.status)
