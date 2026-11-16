"""学习分析 & 元认知校准 API（P2-④ 扩展 / P3 看板，D10/D12）"""
from __future__ import annotations

from fastapi import APIRouter

from services.learning_startup import ensure_learning_ready
from services import analytics_service
from services.calibration_service import calibration_report

router = APIRouter()


@router.get("/overview")
async def overview(route_id: str = "route_A", user_id: str = "demo_user") -> dict:
    await ensure_learning_ready()
    return await analytics_service.overview(user_id, route_id)


@router.get("/calibration")
async def calibration(route_id: str = "route_A", user_id: str = "demo_user") -> dict:
    await ensure_learning_ready()
    return await calibration_report(user_id, route_id)
