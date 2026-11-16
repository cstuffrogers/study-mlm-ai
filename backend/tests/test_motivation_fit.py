"""P3 动机/挫折调节（D14）+ FSRS 参数拟合（D15）测试"""
import uuid
from datetime import datetime, timedelta

import pytest

from services.learning_startup import ensure_learning_ready
from services import quiz_service, review_service, motivation_service
from services.learning_db import session_scope
from model.models_learning import MasteryRecord, ReviewLog
from sqlalchemy import select


def uid():
    return "mo_" + uuid.uuid4().hex[:8]


async def _seed(user):
    t = await quiz_service.start_section_test(user, "sec_A_02", "route_A")
    await quiz_service.submit_test(t["test_id"], user,
                                   [{"item_id": it["id"], "answer": "A", "confidence": "high"} for it in t["items"]])


async def _age(user, days=30):
    async with session_scope() as s:
        for r in (await s.execute(select(MasteryRecord).where(MasteryRecord.user_id == user))).scalars().all():
            r.last_reviewed_at = datetime.utcnow() - timedelta(days=days)
            r.next_review_at = datetime.utcnow() - timedelta(days=1)


@pytest.mark.asyncio
async def test_motivation_low_frustration_after_success():
    await ensure_learning_ready()
    u = uid()
    await _seed(u)
    st = await motivation_service.motivation_state(u, "route_A")
    assert st["frustration"]["level"] in ("low", "mid")
    assert st["encouragement"]
    assert "next_best_action" in st
    assert isinstance(st["milestones"], list) and st["milestones"]


@pytest.mark.asyncio
async def test_motivation_high_frustration_from_failures_and_dialogue():
    await ensure_learning_ready()
    u = uid()
    await _seed(u)
    # 制造大量挫折信号
    from services import mastery_service as ms
    for node in ("kn_practice", "kn_object_activity", "kn_cishixing"):
        for _ in range(3):
            await ms.add_struggle_signal(u, node, "repeated_question", intensity=0.5, source="dialogue")
    # 制造错误作答（低正确率）
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    await quiz_service.submit_test(t["test_id"], u,
                                   [{"item_id": it["id"], "answer": "Z"} for it in t["items"]])
    st = await motivation_service.motivation_state(u, "route_A")
    assert st["frustration"]["level"] in ("mid", "high")
    assert st["frustration"]["score"] > 0
    # 高挫折时应优先 easy_win 或 break
    assert st["next_best_action"]["kind"] in ("easy_win", "break", "light_review", "reinforce")


@pytest.mark.asyncio
async def test_review_writes_log():
    await ensure_learning_ready()
    u = uid()
    await _seed(u)
    await _age(u, 30)
    due = await review_service.due_reviews(u, "route_A")
    await review_service.apply_review(u, "route_A", due[0]["node_id"], 1.0)
    async with session_scope() as s:
        logs = (await s.execute(select(ReviewLog).where(ReviewLog.user_id == u))).scalars().all()
    assert len(logs) == 1
    assert logs[0].correct is True
    assert logs[0].stability_after >= logs[0].stability_before


@pytest.mark.asyncio
async def test_fit_insufficient_samples():
    await ensure_learning_ready()
    u = uid()
    fit = await review_service.fit_parameters(user_id=u)
    assert fit["available"] is False
    assert "n" in fit


@pytest.mark.asyncio
async def test_fit_available_with_enough_logs():
    await ensure_learning_ready()
    u = uid()
    await _seed(u)
    # 反复老化+复习，制造 >=6 条日志
    for i in range(8):
        await _age(u, 30)
        due = await review_service.due_reviews(u, "route_A")
        if not due:
            break
        await review_service.apply_review(u, "route_A", due[0]["node_id"], 1.0 if i % 2 == 0 else 0.2)
    fit = await review_service.fit_parameters(user_id=u)
    assert fit["available"] is True
    assert fit["n"] >= 6
    assert "suggested" in fit and "gain" in fit["suggested"]
    assert "note" in fit
