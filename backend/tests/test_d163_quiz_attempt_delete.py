"""错题本删除接口门禁（D163）。

用户口径：错题本只收录错题，条目可删除；点删除先问「是否已掌握」，确认后调
``DELETE /api/quiz/attempt/{attempt_id}`` 删掉这一条作答记录。

设计口径：**只删 ``QuizAttempt`` 记录，不回滚已写入的掌握度**——掌握分是多次
作答累积的信号，删单条不应抹掉学习成果（学习者可重新作答刷新）。
"""

import uuid

import pytest
from fastapi import HTTPException

from api.quiz_routes import delete_attempt
from model.models_learning import MasteryRecord
from services.learning_startup import ensure_learning_ready
from services.learning_db import session_scope
from services import quiz_service
from sqlalchemy import select


def uid() -> str:
    return "t_" + uuid.uuid4().hex[:8]


async def _submit(user: str, answers: str = "ZZZ") -> tuple[str, list[dict]]:
    """交一份全错测验，返回 (test_id, 记录列表)。"""
    t = await quiz_service.start_section_test(user, "sec_A_02", "route_A")
    await quiz_service.submit_test(
        t["test_id"], user,
        [{"item_id": it["id"], "answer": answers} for it in t["items"]])
    async with session_scope() as s:
        rows = (await s.execute(select(quiz_service.QuizAttempt).where(
            quiz_service.QuizAttempt.user_id == user))).scalars().all()
    return t["test_id"], [{"id": r.id, "quiz_id": r.quiz_id} for r in rows]


@pytest.mark.asyncio
async def test_delete_attempt_removes_only_that_row():
    await ensure_learning_ready()
    u = uid()
    _, rows = await _submit(u)
    assert len(rows) > 1, "全错提交应产生多条作答记录"
    target = rows[0]["id"]

    out = await delete_attempt(target, u)
    assert out["deleted"] == target

    async with session_scope() as s:
        left = (await s.execute(select(quiz_service.QuizAttempt).where(
            quiz_service.QuizAttempt.user_id == u))).scalars().all()
    ids = {r.id for r in left}
    assert target not in ids, "被删记录不应再出现在错题本"
    assert len(left) == len(rows) - 1, "只应删掉这一条，其余记录必须保留"


@pytest.mark.asyncio
async def test_delete_attempt_keeps_mastery():
    """删除作答记录不回滚掌握度（累积信号）。"""
    await ensure_learning_ready()
    u = uid()
    _, rows = await _submit(u)
    async with session_scope() as s:
        before = (await s.execute(select(MasteryRecord).where(
            MasteryRecord.user_id == u))).scalars().all()
    assert before, "提交测验应写入掌握度"

    await delete_attempt(rows[0]["id"], u)

    async with session_scope() as s:
        after = (await s.execute(select(MasteryRecord).where(
            MasteryRecord.user_id == u))).scalars().all()
    assert len(after) == len(before), "删除错题不应抹掉掌握度记录"
    assert all(abs(a.score - b.score) < 1e-9 for a, b in zip(after, before))


@pytest.mark.asyncio
async def test_delete_attempt_missing_is_404():
    await ensure_learning_ready()
    with pytest.raises(HTTPException) as ei:
        await delete_attempt("no_such_attempt", uid())
    assert ei.value.status_code == 404
