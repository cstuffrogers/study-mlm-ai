"""NFR-004 / T051 跨设备同步与断点续学测试"""
import uuid

import pytest

from services.learning_startup import ensure_learning_ready
from services import sync_service, mastery_service as ms


def uid():
    return "sync_" + uuid.uuid4().hex[:8]


@pytest.mark.asyncio
async def test_push_applies_known_events_and_skips_unknown():
    await ensure_learning_ready()
    u = uid()
    events = [
        {"type": "progress", "section_id": "sec_A_02", "last_position": 3, "status": "in_progress"},
        {"type": "struggle_signal", "node_id": "kn_practice", "signal_type": "offline", "intensity": 0.4},
        {"type": "bogus_type", "foo": "bar"},
    ]
    res = await sync_service.push(u, "route_A", events)
    assert res["applied"] == 2
    assert res["skipped"] == 1
    assert res["details"][0]["reason"] == "unknown_type"


@pytest.mark.asyncio
async def test_pull_returns_progress_and_mastery_snapshot():
    await ensure_learning_ready()
    u = uid()
    await sync_service.push(u, "route_A", [
        {"type": "progress", "section_id": "sec_A_02", "last_position": 5, "status": "in_progress"},
    ])
    snap = await sync_service.pull(u, "route_A")
    assert snap["route_id"] == "route_A"
    prog = {p["section_id"]: p for p in snap["progress"]}
    assert "sec_A_02" in prog
    assert prog["sec_A_02"]["last_position"] == 5
    assert "mastery" in snap and "server_time" in snap


@pytest.mark.asyncio
async def test_offline_quiz_attempt_does_not_count_mastery():
    """离线作答只留存历史，不计正式掌握度（重连需在线重做才计分）"""
    await ensure_learning_ready()
    u = uid()
    before = await ms.get_mastery_map(u, "route_A")
    await sync_service.push(u, "route_A", [
        {"type": "quiz_attempt", "quiz_id": "q_x", "is_correct": True, "score": 1.0},
    ])
    after = await ms.get_mastery_map(u, "route_A")
    # 掌握度图不应因离线作答而变化
    assert before == after


@pytest.mark.asyncio
async def test_save_progress_upsert_idempotent():
    await ensure_learning_ready()
    u = uid()
    await sync_service.save_progress(u, "route_A", "sec_A_02", 2, "in_progress")
    await sync_service.save_progress(u, "route_A", "sec_A_02", 7, "completed")
    snap = await sync_service.pull(u, "route_A")
    prog = {p["section_id"]: p for p in snap["progress"]}
    assert prog["sec_A_02"]["last_position"] == 7
    assert prog["sec_A_02"]["status"] == "completed"
