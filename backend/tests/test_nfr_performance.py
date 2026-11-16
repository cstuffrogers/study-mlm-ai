"""NFR-001/002/003 性能时延抽测（Polish 遗留 Low 项）

- NFR-001: 章节测试判分 + 掌握度更新 端到端 ≤ 3s（客观题）
- NFR-002: 学情档案页与薄弱点排序查询 ≤ 1s（首屏）
- NFR-003: 路径推荐生成 ≤ 2s

内存 SQLite 模式，实测通常在几十毫秒，断言按规格阈值（相对宽松，避免 CI 抖动）。
"""
import time
import uuid

import pytest

from services.learning_startup import ensure_learning_ready
from services import quiz_service, profile_service, recommendation_service, route_service


def uid():
    return "nfr_" + uuid.uuid4().hex[:8]


async def _answer_all(u, section_id, route_id, ans="A"):
    t = await quiz_service.start_section_test(u, section_id, route_id)
    items = [{"item_id": it["id"], "answer": ans} for it in t["items"]]
    return await quiz_service.submit_test(t["test_id"], u, items)


@pytest.mark.asyncio
async def test_nfr001_submit_test_latency_under_3s():
    await ensure_learning_ready()
    u = uid()
    # warmup（首次会触发建表/播种等一次性开销，不计入）
    await _answer_all(u, "sec_A_02", "route_A")

    start = time.perf_counter()
    res = await _answer_all(u, "sec_A_02", "route_A")
    elapsed = time.perf_counter() - start

    assert "total_score" in res and "gating" in res
    assert elapsed < 3.0, f"NFR-001 违规：判分+掌握度更新耗时 {elapsed:.3f}s > 3s"


@pytest.mark.asyncio
async def test_nfr002_profile_dashboard_latency_under_1s():
    await ensure_learning_ready()
    u = uid()
    await _answer_all(u, "sec_A_02", "route_A", ans="A")  # 制造一些学情
    await profile_service.build_profile(u, "route_A")  # warmup

    start = time.perf_counter()
    prof = await profile_service.build_profile(u, "route_A")
    elapsed = time.perf_counter() - start

    assert "ability_radar" in prof and "weak_points" in prof
    assert elapsed < 1.0, f"NFR-002 违规：学情档案+薄弱排序耗时 {elapsed:.3f}s > 1s"


@pytest.mark.asyncio
async def test_nfr003_recommendation_latency_under_2s():
    await ensure_learning_ready()
    u = uid()
    await route_service.select_route(u, "route_A")
    await recommendation_service.next_step(u, "route_A", "sec_A_02")  # warmup

    start = time.perf_counter()
    rec = await recommendation_service.next_step(u, "route_A", "sec_A_02")
    elapsed = time.perf_counter() - start

    assert "rec_type" in rec and "reason" in rec
    assert elapsed < 2.0, f"NFR-003 违规：路径推荐耗时 {elapsed:.3f}s > 2s"
