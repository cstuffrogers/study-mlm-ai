"""测验 API"""
from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from sqlalchemy import select, delete

from services.learning_startup import ensure_learning_ready
from services.learning_db import session_scope
from services import quiz_service
from model.models_learning import QuizAttempt, QuizItem
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
    """判分申诉（D167）。

    本机版（App / Web 构建）的申诉走 `frontend/lib/offline/local_insight.dart`：只在本机
    记一笔、不改分。这个 HTTP 端点保留给「带后端部署」的形态，同样**不重判、不落库**
    （项目里没有人工复核台）——所以返回体必须带 `message`，让界面能把话说清，
    不能只回一个 `pending_review` 让用户以为点了就有人在审。
    """
    await ensure_learning_ready()
    return {
        "appeal_id": f"ap_{body.test_id}_{body.item_id}",
        "status": "pending_review",
        "test_id": body.test_id,
        "item_id": body.item_id,
        "message": "申诉已接收：本部署没有人工复核台，不会自动改分；请对照原文分片再核一遍。",
    }


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
        # D136：一次提交里所有小题的 `created_at` 完全相同（同一事务），只按时间倒序
        # 等于没定义顺序 —— SQLite/PG 各自给一种，单机侧则是另一个不稳定排序。
        # 并列按 quiz_id 升序（题内顺序），两端同式。
        stmt = stmt.order_by(QuizAttempt.created_at.desc(),
                             QuizAttempt.quiz_id.asc()).limit(max(1, min(limit, 500)))
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


@router.delete("/attempt/{attempt_id}")
async def delete_attempt(attempt_id: str, user_id: str = "demo_user") -> dict:
    """删除单条作答记录（错题本删除）。

    只删除该条 QuizAttempt，不回滚已写入的掌握度——掌握度是多次作答的累积信号，
    删除单条记录不应抹掉学习成果。若用户认为掌握度失准，可重新作答刷新。
    """
    await ensure_learning_ready()
    async with session_scope() as s:
        existing = (await s.execute(
            select(QuizAttempt).where(
                QuizAttempt.id == attempt_id, QuizAttempt.user_id == user_id
            )
        )).scalar_one_or_none()
        if existing is None:
            raise HTTPException(status_code=404, detail="作答记录不存在")
        await s.execute(delete(QuizAttempt).where(QuizAttempt.id == attempt_id))
    return {"deleted": attempt_id}
