"""US5 推荐：门控0.8边界 / 推荐理由 / 回补优先"""
import uuid
import pytest

from services.learning_startup import ensure_learning_ready
from services import quiz_service, mastery_service as ms, recommendation_service as rec


def uid():
    return "t_" + uuid.uuid4().hex[:8]


@pytest.mark.asyncio
async def test_gating_boundary_just_below():
    """低于 0.8 → 不解锁，推荐回补"""
    await ensure_learning_ready()
    u = uid()
    # 全答 B（错为主）→ 掌握度低
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    await quiz_service.submit_test(t["test_id"], u, [{"item_id": it["id"], "answer": "B"} for it in t["items"]])
    r = await rec.next_step(u, "route_A", "sec_A_02")
    assert r["rec_type"] in ("reinforce",)
    assert r["reason"]


@pytest.mark.asyncio
async def test_gating_above_unlocks_next():
    """达到门槛 → 推荐下一章"""
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    await quiz_service.submit_test(t["test_id"], u, [{"item_id": it["id"], "answer": "A"} for it in t["items"]])
    r = await rec.next_step(u, "route_A", "sec_A_02")
    assert r["rec_type"] == "next_section"
    # D87 新书单：A_02（提纲）之后的下一章是 A_06（共产党宣言）
    assert r["target_section_id"] == "sec_A_06"
    assert r["reason"]


@pytest.mark.asyncio
async def test_today_returns_recommendation_with_reason():
    await ensure_learning_ready()
    u = uid()
    out = await rec.today(u, "route_A")
    assert "recommendation" in out
    assert out["recommendation"]["reason"]


@pytest.mark.asyncio
async def test_weak_top_has_statement():
    await ensure_learning_ready()
    u = uid()
    weak = await rec.weak_top(u, "route_A", 5)
    assert "weak_points" in weak
    for w in weak["weak_points"]:
        assert "statement" in w
