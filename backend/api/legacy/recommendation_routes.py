"""推荐与门控 API"""
from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel

from services.learning_startup import ensure_learning_ready
from services import recommendation_service as rec

router = APIRouter()


class NextIn(BaseModel):
    user_id: str
    route_id: str = "route_A"
    current_section_id: str | None = None


@router.get("/today")
async def today(route_id: str = "route_A", user_id: str = "demo_user") -> dict:
    await ensure_learning_ready()
    return await rec.today(user_id, route_id)


@router.post("/next")
async def next_step(body: NextIn) -> dict:
    await ensure_learning_ready()
    return await rec.next_step(body.user_id, body.route_id, body.current_section_id)


@router.get("/weak-top")
async def weak_top(route_id: str = "route_A", user_id: str = "demo_user", n: int = 5) -> dict:
    await ensure_learning_ready()
    return await rec.weak_top(user_id, route_id, n)
