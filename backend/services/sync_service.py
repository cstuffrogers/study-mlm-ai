"""SyncService — 跨设备同步与断点续学（NFR-004）

服务端权威 + 本地断点续学：客户端离线暂存作答/进度增量，恢复后批量合并；
历史全量留存（不覆盖，仅追加 attempt / 累加信号）。
"""
from __future__ import annotations

from datetime import datetime

from sqlalchemy import select

from services.learning_db import session_scope
from services import mastery_service as ms, quiz_service
from model.models_learning import LearningProgress, QuizAttempt

_APPROVED_EVENTS = {"quiz_attempt", "progress", "struggle_signal", "section_complete"}


def _is_async_session(s) -> bool:
    try:
        from sqlalchemy.ext.asyncio import AsyncSession
        return isinstance(s, AsyncSession)
    except Exception:
        return False


async def _exec(s, stmt):
    if _is_async_session(s):
        return await s.execute(stmt)
    return s.execute(stmt)


async def _flush(s):
    if _is_async_session(s):
        await s.flush()
    else:
        s.flush()


async def push(user_id: str, route_id: str, events: list[dict]) -> dict:
    """客户端上行业务增量；按事件类型合并，冲突以服务端为准"""
    applied, skipped = [], []
    for ev in events:
        et = ev.get("type")
        if et not in _APPROVED_EVENTS:
            skipped.append({"event": ev, "reason": "unknown_type"})
            continue
        try:
            if et == "struggle_signal":
                await ms.add_struggle_signal(user_id, ev["node_id"], ev.get("signal_type", "offline"),
                                             intensity=ev.get("intensity", 0.3), source="offline")
            elif et == "quiz_attempt":
                # 离线作答仅留存历史，不计正式掌握度（需 reunlock 时在线重做）
                async with session_scope() as s:
                    s.add(QuizAttempt(user_id=user_id, quiz_id=ev["quiz_id"],
                                      test_id=ev.get("test_id", ""), answer=ev.get("answer", ""),
                                      is_correct=bool(ev.get("is_correct", False)),
                                      score=float(ev.get("score", 0.0)),
                                      duration_ms=int(ev.get("duration_ms", 0)),
                                      error_category=ev.get("error_category", "")))
                    await _flush(s)
            elif et == "progress":
                await save_progress(user_id, route_id, ev.get("section_id", ""),
                                    ev.get("last_position", 0), ev.get("status", "in_progress"))
            applied.append(et)
        except Exception as e:  # 单条失败不影响整批
            skipped.append({"event": ev, "reason": str(e)})
    return {"applied": len(applied), "skipped": len(skipped), "details": skipped}


async def save_progress(user_id: str, route_id: str, section_id: str,
                        last_position: int = 0, status: str = "in_progress") -> dict:
    async with session_scope() as s:
        res = await _exec(s, select(LearningProgress).where(
            LearningProgress.user_id == user_id,
            LearningProgress.route_id == route_id,
            LearningProgress.section_id == section_id))
        p = res.scalars().first()
        if p is None:
            p = LearningProgress(user_id=user_id, route_id=route_id, section_id=section_id)
            s.add(p)
        p.current_anchor = str(last_position)
        p.status = status
        p.updated_at = datetime.utcnow()
        await _flush(s)
    return {"section_id": section_id, "last_position": last_position, "status": status}


async def pull(user_id: str, route_id: str) -> dict:
    """下发服务端权威进度快照，供客户端断点续学"""
    async with session_scope() as s:
        res = await _exec(s, select(LearningProgress).where(
            LearningProgress.user_id == user_id, LearningProgress.route_id == route_id))
        rows = res.scalars().all()
    return {"route_id": route_id,
            "progress": [{"section_id": r.section_id, "last_position": int(r.current_anchor or 0),
                          "status": r.status,
                          "updated_at": r.updated_at.isoformat() if r.updated_at else None}
                         for r in rows],
            "mastery": await ms.get_mastery_map(user_id, route_id),
            "server_time": datetime.utcnow().isoformat()}
