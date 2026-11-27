"""勋章 API 路由 — spec 001 勋章系统

- GET  /api/badges/mine   「我的勋章」页数据（全部启用勋章 + 授予状态 + 进度 + 指标快照）
- GET  /api/badges/unseen 未查看的新勋章（首页提醒 / 动画触发兜底）
- POST /api/badges/read   标记已查看（不存在的 award_id 静默忽略）
"""
from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel

from services.learning_startup import ensure_learning_ready
from services import badge_service

router = APIRouter()


class BadgeReadIn(BaseModel):
    user_id: str = "demo_user"
    award_ids: list[str] = []


@router.get("/mine")
async def mine(user_id: str = "demo_user") -> dict:
    await ensure_learning_ready()
    return await badge_service.mine(user_id)


@router.get("/unseen")
async def unseen(user_id: str = "demo_user") -> dict:
    await ensure_learning_ready()
    return await badge_service.unseen(user_id)


@router.post("/read")
async def mark_read(body: BadgeReadIn) -> dict:
    await ensure_learning_ready()
    updated = await badge_service.mark_read(body.user_id, body.award_ids)
    return {"updated": updated}
