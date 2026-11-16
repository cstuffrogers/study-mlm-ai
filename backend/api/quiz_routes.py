"""测验 API"""
from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from sqlalchemy import select

from services.learning_startup import ensure_learning_ready
from services.learning_db import session_scope
from services import quiz_service
from model.models_learning import QuizAttempt, QuizItem, SectionTest
from content.routes import get_section

router = APIRouter()


class StartIn(BaseModel):
    user_id: str
    route_id: str = "route_A"


class SubmitIn(BaseModel):
    user_id: str
    answers: list[dict] = []


class AppealIn(BaseModel):
    test_id: str
    item_id: str
    reason: str = ""


@router.post("/section/{section_id}/start")
async def start(section_id: str, body: StartIn) -> dict:
    await ensure_learning_ready()
    try:
        return await quiz_service.start_section_test(body.user_id, section_id, body.route_id)
    except quiz_service.OrthodoxyViolation as e:
        raise HTTPException(status_code=409, detail=str(e))


@router.post("/{test_id}/submit")
async def submit(test_id: str, body: SubmitIn) -> dict:
    await ensure_learning_ready()
    try:
        return await quiz_service.submit_test(test_id, body.user_id, body.answers)
    except ValueError as e:
        msg = str(e)
        # 重复提交 → 409；其余不存在类 → 404
        if "已提交" in msg:
            raise HTTPException(status_code=409, detail=msg)
        raise HTTPException(status_code=404, detail=msg)


@router.post("/appeal")
async def appeal(body: AppealIn) -> dict:
    await ensure_learning_ready()
    # P0：进入待审核（复用既有专家审核队列的占位）
    return {"appeal_id": f"ap_{body.test_id}_{body.item_id}", "status": "pending_review"}


# ---- 测试历史 / 错题本（逐题历史 + 错题回顾）----

@router.get("/history")
async def history(user_id: str = "demo_user", limit: int = 100,
                  only_wrong: bool = False) -> dict:
    """逐题作答历史（按时间倒序），附带题面/选项/解析/所属章节。"""
    await ensure_learning_ready()
    async with session_scope() as s:
        stmt = select(QuizAttempt).where(QuizAttempt.user_id == user_id)
        if only_wrong:
            stmt = stmt.where(QuizAttempt.is_correct == False)  # noqa: E712
        stmt = stmt.order_by(QuizAttempt.created_at.desc()).limit(max(1, min(limit, 500)))
        attempts = (await s.execute(stmt)).scalars().all()
        items = {q.id: q for q in (await s.execute(select(QuizItem))).scalars().all()}

    rows = []
    for a in attempts:
        q = items.get(a.quiz_id)
        sec = get_section(q.section_id) if q else None
        rows.append({
            "attempt_id": a.id, "quiz_id": a.quiz_id, "test_id": a.test_id,
            "is_correct": bool(a.is_correct), "score": a.score,
            "answer": a.answer, "error_category": a.error_category,
            "error_label": quiz_service._err_label(a.error_category),
            "error_reason": quiz_service._err_advice(a.error_category),
            "confidence": a.confidence,
            "created_at": str(a.created_at) if a.created_at else "",
            "stem": q.stem if q else "",
            "type": q.type if q else "",
            "options": q.options if q else [],
            "answer_key": q.answer if q else "",
            "explanation": q.explanation if q else "",
            "source_chunk_id": q.source_chunk_id if q else "",
            "section_id": q.section_id if q else "",
            "section_title": sec.get("title", "") if sec else "",
        })
    wrong = sum(1 for r in rows if not r["is_correct"])
    return {"user_id": user_id, "total": len(rows), "wrong": wrong, "rows": rows}
