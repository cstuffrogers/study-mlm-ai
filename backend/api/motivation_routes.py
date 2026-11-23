"""动机/挫折调节 API（P3 D14）"""
from __future__ import annotations

from fastapi import APIRouter

from services.learning_startup import ensure_learning_ready
from services import motivation_service

router = APIRouter()


@router.get("/state")
async def state(route_id: str = "route_A", user_id: str = "demo_user") -> dict:
    await ensure_learning_ready()
    result = await motivation_service.motivation_state(user_id, route_id)
    # 勋章系统（spec 001）：动机结算入口检测（连续学习/里程碑类跨日达成兜底）
    try:
        from services import badge_service
        result["badges_awarded"] = await badge_service.evaluate(
            user_id, source_event="daily_settle")
    except Exception as e:  # 勋章是激励反馈，任何异常不得影响动机状态
        import logging
        logging.getLogger(__name__).warning("勋章评估失败（不影响动机状态）: %s", e)
        result["badges_awarded"] = []
    return result
