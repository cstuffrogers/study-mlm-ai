"""P2-⑤ 交错练习 + P2-④ 校准聚合 + P3 学习分析看板 测试"""
import uuid
from datetime import datetime, timedelta

import pytest

from services.learning_startup import ensure_learning_ready
from services import quiz_service, review_service, analytics_service
from services.calibration_service import calibration_report
from services.learning_db import session_scope
from model.models_learning import MasteryRecord
from sqlalchemy import select


def uid():
    return "an_" + uuid.uuid4().hex[:8]


async def _seed(user, age_days=0):
    t = await quiz_service.start_section_test(user, "sec_A_02", "route_A")
    answers = [{"item_id": it["id"], "answer": "A", "confidence": "high"} for it in t["items"]]
    await quiz_service.submit_test(t["test_id"], user, answers)
    if age_days:
        async with session_scope() as s:
            for r in (await s.execute(select(MasteryRecord).where(MasteryRecord.user_id == user))).scalars().all():
                r.last_reviewed_at = datetime.utcnow() - timedelta(days=age_days)
                r.next_review_at = datetime.utcnow() - timedelta(days=1)


@pytest.mark.asyncio
async def test_interleaved_queue_mixes_due_and_consolidation():
    await ensure_learning_ready()
    u = uid()
    await _seed(u, age_days=30)  # 全部到期
    q = await review_service.interleaved_reviews(u, "route_A", n=8)
    assert q, "应有交错复习队列"
    kinds = {it["kind"] for it in q}
    assert "due" in kinds
    # 相邻项尽量不同节点（交错）
    nodes = [it["node_id"] for it in q]
    assert len(nodes) >= 2
    # 不应出现同一节点连续超过 2 次（打散有效）
    streak = 1
    for a, b in zip(nodes, nodes[1:]):
        streak = streak + 1 if a == b else 1
        assert streak <= 2, "交错队列不应出现长时间块状重复"


@pytest.mark.asyncio
async def test_interleaved_includes_consolidation_when_not_due():
    await ensure_learning_ready()
    u = uid()
    await _seed(u)  # 刚测完未到期
    q = await review_service.interleaved_reviews(u, "route_A", n=8)
    # 未到期时也应能取到已掌握节点的巩固项
    assert all(it["kind"] == "interleave" for it in q), "未到期时应只有巩固项"


@pytest.mark.asyncio
async def test_calibration_report_aggregates_history():
    await ensure_learning_ready()
    u = uid()
    # 两次测试：全部自评 high，一次全对一次全错
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    await quiz_service.submit_test(t["test_id"], u,
                                   [{"item_id": it["id"], "answer": "A", "confidence": "high"} for it in t["items"]])
    t2 = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    await quiz_service.submit_test(t2["test_id"], u,
                                   [{"item_id": it["id"], "answer": "Z", "confidence": "high"} for it in t2["items"]])
    rep = await calibration_report(u)
    assert rep["n"] > 0
    assert rep["overall"]["expected"] is not None
    assert rep["overall"]["actual"] is not None
    assert rep["verdict"] in ("overconfident", "underconfident", "calibrated")


@pytest.mark.asyncio
async def test_calibration_report_empty():
    await ensure_learning_ready()
    rep = await calibration_report(uid())
    assert rep["n"] == 0
    assert rep["verdict"] == "unknown"


@pytest.mark.asyncio
async def test_analytics_overview_structure_and_health():
    await ensure_learning_ready()
    u = uid()
    await _seed(u, age_days=20)
    ov = await analytics_service.overview(u, "route_A")
    from content.knowledge_graph import KNOWLEDGE_NODES
    assert ov["total_nodes"] == len(KNOWLEDGE_NODES)
    assert ov["assessed_nodes"] > 0
    assert set(ov["mastery_distribution"].keys()) == {"unseen", "beginner", "familiar", "proficient", "mastered"}
    assert ov["due_count"] >= 0
    assert 0 <= ov["health_score"] <= 100
    assert "verdict" in ov["calibration"]
    assert ov["weakest_dim"]["dim"] in ("materialism", "dialectics", "epistemology",
                                        "historical_materialism", "political_economy")


@pytest.mark.asyncio
async def test_analytics_error_breakdown_present():
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    # 客观题全错 → 引入错因
    answers = []
    for it in t["items"]:
        answers.append({"item_id": it["id"], "answer": ("Z" if not (it.get("subjective") or it.get("application")) else "")})
    await quiz_service.submit_test(t["test_id"], u, answers)
    ov = await analytics_service.overview(u, "route_A")
    assert isinstance(ov["error_breakdown"], dict)
