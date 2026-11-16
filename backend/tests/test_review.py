"""P1-① 间隔复习调度（FSRS-lite, D8）测试"""
import uuid
from datetime import datetime, timedelta

import pytest

from services.learning_startup import ensure_learning_ready
from services import quiz_service, review_service, recommendation_service as rec
from services.learning_db import session_scope
from model.models_learning import MasteryRecord
from sqlalchemy import select


def uid():
    return "rv_" + uuid.uuid4().hex[:8]


def test_interval_monotonic_in_stability():
    """稳定性越高，复习间隔越长（指数增长，封顶）"""
    assert review_service.interval_days(0.0) <= review_service.interval_days(0.3)
    assert review_service.interval_days(0.3) <= review_service.interval_days(0.6)
    assert review_service.interval_days(1.0) <= review_service.interval_days(100.0)


def test_retention_decays_over_time():
    """保持率随间隔天数单调下降"""
    assert review_service.retention(0.0, 0.5) > review_service.retention(10.0, 0.5)
    assert review_service.retention(10.0, 0.5) > review_service.retention(60.0, 0.5)


@pytest.mark.asyncio
async def test_all_correct_schedules_next_review():
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    await quiz_service.submit_test(t["test_id"], u, [{"item_id": it["id"], "answer": "A"} for it in t["items"]])
    async with session_scope() as s:
        rows = (await s.execute(select(MasteryRecord).where(MasteryRecord.user_id == u))).scalars().all()
    assert rows, "应有掌握记录"
    assert any(r.next_review_at is not None for r in rows), "达标后应调度下次复习"


@pytest.mark.asyncio
async def test_aging_makes_item_due_and_review_boosts_stability():
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    await quiz_service.submit_test(t["test_id"], u, [{"item_id": it["id"], "answer": "A"} for it in t["items"]])
    # 人工老化 30 天
    async with session_scope() as s:
        for r in (await s.execute(select(MasteryRecord).where(MasteryRecord.user_id == u))).scalars().all():
            r.last_reviewed_at = datetime.utcnow() - timedelta(days=30)
            r.next_review_at = datetime.utcnow() - timedelta(days=1)
    due = await review_service.due_reviews(u, "route_A")
    assert due, "老化后应出现到期复习项"
    assert due[0]["retention"] < 0.9
    top = due[0]
    before_stability = top["stability"]
    out = await review_service.apply_review(u, "route_A", top["node_id"], correct_ratio=1.0)
    assert out["applied"] is True
    assert out["stability"] >= before_stability, "复习成功应提升稳定性"
    # 复习后不再立即到期
    due2 = await review_service.due_reviews(u, "route_A")
    assert all(d["node_id"] != top["node_id"] for d in due2)


@pytest.mark.asyncio
async def test_failed_review_lowers_stability():
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    await quiz_service.submit_test(t["test_id"], u, [{"item_id": it["id"], "answer": "A"} for it in t["items"]])
    async with session_scope() as s:
        for r in (await s.execute(select(MasteryRecord).where(MasteryRecord.user_id == u))).scalars().all():
            r.last_reviewed_at = datetime.utcnow() - timedelta(days=30)
    due = await review_service.due_reviews(u, "route_A")
    # 取稳定性最高的一项，确保 before>0 才有下降空间
    due.sort(key=lambda d: d["stability"], reverse=True)
    top = due[0]
    before = top["stability"]
    assert before > 0, "应至少有一个已形成稳定记忆的知识点"
    out = await review_service.apply_review(u, "route_A", top["node_id"], correct_ratio=0.2)
    assert out["stability"] < before, "复习失败应降低稳定性"


@pytest.mark.asyncio
async def test_recommendation_preempts_with_review_when_due():
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    await quiz_service.submit_test(t["test_id"], u, [{"item_id": it["id"], "answer": "A"} for it in t["items"]])
    async with session_scope() as s:
        for r in (await s.execute(select(MasteryRecord).where(MasteryRecord.user_id == u))).scalars().all():
            r.last_reviewed_at = datetime.utcnow() - timedelta(days=30)
            r.next_review_at = datetime.utcnow() - timedelta(days=1)
    r = await rec.next_step(u, "route_A", "sec_A_02")
    assert r["rec_type"] == "review"
    assert "保持率" in r["reason"]
