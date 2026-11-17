"""D133 门禁：离线同步队列的**路线归属**与「假 applied」。

原状（真实缺陷，均已修）：
1. `SyncController.flush()` 调 `_api.push(q)` 不带 routeId（默认 route_A），
   后端又只看请求体的 route_id → 用户在 route_B/C 离线学完、联网合并后，
   进度被写到 route_A。
2. `section_complete` 在 `_APPROVED_EVENTS` 里却没有处理分支：什么也没写，
   却被计入 `applied`（假成功）。
"""
from __future__ import annotations

import uuid

import pytest

from services import sync_service
from services.learning_startup import ensure_learning_ready


def uid() -> str:
    return "sync133_" + uuid.uuid4().hex[:8]


@pytest.mark.asyncio
async def test_event_route_id_wins_over_request_route() -> None:
    """事件自带的 route_id 优先：混合队列不能整体归到 route_A。"""
    await ensure_learning_ready()
    u = uid()
    res = await sync_service.push(u, "route_A", [
        {"type": "progress", "section_id": "sec_A_02", "last_position": 1,
         "status": "in_progress", "route_id": "route_A"},
        {"type": "progress", "section_id": "sec_B_01", "last_position": 7,
         "status": "in_progress", "route_id": "route_B"},
    ])
    assert res["applied"] == 2 and res["skipped"] == 0

    a = await sync_service.pull(u, "route_A")
    b = await sync_service.pull(u, "route_B")
    a_secs = {p["section_id"] for p in a["progress"]}
    b_secs = {p["section_id"]: p for p in b["progress"]}
    assert a_secs == {"sec_A_02"}, a_secs
    assert set(b_secs) == {"sec_B_01"}, b_secs
    assert b_secs["sec_B_01"]["last_position"] == 7
    # 反向验证：route_A 里不该出现 B 路线的章节
    assert "sec_B_01" not in a_secs


@pytest.mark.asyncio
async def test_section_complete_actually_writes_completed_status() -> None:
    """原先计入 applied 却什么都没写（假成功）。"""
    await ensure_learning_ready()
    u = uid()
    res = await sync_service.push(u, "route_A", [
        {"type": "section_complete", "section_id": "sec_A_03", "last_position": 9},
    ])
    assert res["applied"] == 1 and res["skipped"] == 0
    snap = await sync_service.pull(u, "route_A")
    prog = {p["section_id"]: p for p in snap["progress"]}
    assert prog["sec_A_03"]["status"] == "completed"
    assert prog["sec_A_03"]["last_position"] == 9


@pytest.mark.asyncio
async def test_unknown_route_is_skipped_not_written() -> None:
    await ensure_learning_ready()
    u = uid()
    res = await sync_service.push(u, "route_A", [
        {"type": "progress", "section_id": "sec_A_02", "route_id": "route_ZZZ"},
    ])
    assert res["applied"] == 0
    assert res["skipped"] == 1
    assert res["details"][0]["reason"].startswith("unknown_route")
    snap = await sync_service.pull(u, "route_ZZZ")
    assert snap["progress"] == []
