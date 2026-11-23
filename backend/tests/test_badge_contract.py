"""spec 001 学习勋章系统 —— 契约测试

覆盖：目录完整性、指标采集、授予判定（threshold/ratio/completion）、
幂等、已停用勋章、mine/unseen/read、API 端点、5 处检测挂接点。
"""
import uuid

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select

from app import app
from services.learning_startup import ensure_learning_ready
from services.learning_db import session_scope
from services import badge_service
from services import mastery_service as ms
from services import quiz_service
from model.models_learning import MasteryRecord, QuizAttempt
from content.badges import all_badges, get_badge, total_count, BadgeDef


def uid():
    return "bd_" + uuid.uuid4().hex[:8]


# ---------- 造数辅助 ----------

async def _seed_mastery(user, route_id, node_id, score=1.0, level="mastered"):
    async with session_scope() as s:
        s.add(MasteryRecord(user_id=user, node_id=node_id, route_id=route_id,
                            score=score, level=level, basis={"seed": True}))


async def _complete_route(user, route_id):
    """把一条路线的所有章节知识点全部置为满分 → 该路线判定完成。"""
    from content.routes import sections_for_route
    for sec in sections_for_route(route_id):
        for node in ms.nodes_by_section(sec["id"]):
            await _seed_mastery(user, route_id, node["id"], score=1.0, level="mastered")


async def _complete_all_routes(user):
    from content.routes import ROUTES
    for r in ROUTES:
        await _complete_route(user, r["id"])


async def _seed_quiz_attempts(user, correct, wrong=0):
    """直接造题作答记录（用于比率型勋章的确定性测试）。

    QuizAttempt 仅 is_correct / created_at 参与勋章指标聚合，其余字段给默认值即可。
    """
    async with session_scope() as s:
        for _ in range(correct):
            s.add(QuizAttempt(user_id=user, quiz_id="seed", test_id="seed",
                              answer="A", is_correct=True, score=1.0))
        for _ in range(wrong):
            s.add(QuizAttempt(user_id=user, quiz_id="seed", test_id="seed",
                              answer="A", is_correct=False, score=0.0))


def _disable_badge(badge_id):
    """把某勋章从 BADGES 目录中临时替换为停用副本，返回用于恢复的原对象。"""
    import content.badges as cat
    idx = next(i for i, b in enumerate(cat.BADGES) if b.badge_id == badge_id)
    b = cat.BADGES[idx]
    disabled = BadgeDef(badge_id=b.badge_id, name=b.name, description=b.description,
                        category=b.category, icon_key=b.icon_key,
                        condition_type=b.condition_type, metric_key=b.metric_key,
                        threshold=b.threshold, ratio_metric=b.ratio_metric,
                        accuracy_threshold=b.accuracy_threshold,
                        sort_order=b.sort_order, enabled=False)
    cat.BADGES[idx] = disabled
    return b


def _restore_badge(badge_id, original):
    import content.badges as cat
    idx = next(i for i, b in enumerate(cat.BADGES) if b.badge_id == badge_id)
    cat.BADGES[idx] = original


# ---------- 1. 目录完整性 ----------

def test_catalog_integrity():
    badges = all_badges()
    ids = [b.badge_id for b in badges]
    assert len(ids) == len(set(ids)), "勋章 id 必须唯一"
    assert total_count() == len(badges)
    assert total_count() == 29
    valid_types = {"threshold", "ratio", "completion"}
    for b in badges:
        assert b.condition_type in valid_types
        assert b.category and b.name and b.description
        assert b.metric_key
        if b.condition_type == "ratio":
            assert b.ratio_metric and b.accuracy_threshold is not None
        if b.condition_type == "threshold":
            assert b.threshold is not None


def test_get_badge():
    b = get_badge("mastery_1")
    assert b is not None and b.badge_id == "mastery_1"
    assert get_badge("not_exist") is None


# ---------- 2. 指标采集 ----------

@pytest.mark.asyncio
async def test_collect_metrics_keys():
    await ensure_learning_ready()
    m = await badge_service.collect_metrics(uid())
    expected = {"mastered_count", "journey_count", "milestones_achieved",
                "quiz_correct_total", "quiz_attempt_total", "routes_completed",
                "streak_days", "dialogues_completed"}
    assert set(m.keys()) == expected
    for k in expected:
        assert isinstance(m[k], int) and m[k] >= 0


@pytest.mark.asyncio
async def test_metrics_reflect_mastery():
    await ensure_learning_ready()
    u = uid()
    for node in ms.nodes_by_section("sec_A_02")[:3]:
        await _seed_mastery(u, "route_A", node["id"], score=1.0, level="mastered")
    m = await badge_service.collect_metrics(u)
    assert m["mastered_count"] == 3
    assert m["journey_count"] >= 3
    assert m["milestones_achieved"] >= 1


@pytest.mark.asyncio
async def test_metrics_reflect_quiz():
    await ensure_learning_ready()
    u = uid()
    await _seed_quiz_attempts(u, correct=7, wrong=3)
    m = await badge_service.collect_metrics(u)
    assert m["quiz_attempt_total"] == 10
    assert m["quiz_correct_total"] == 7


@pytest.mark.asyncio
async def test_metrics_routes_completed():
    await ensure_learning_ready()
    u = uid()
    await _complete_route(u, "route_A")
    m = await badge_service.collect_metrics(u)
    assert m["routes_completed"] == 1


@pytest.mark.asyncio
async def test_metrics_all_routes():
    await ensure_learning_ready()
    u = uid()
    await _complete_all_routes(u)
    m = await badge_service.collect_metrics(u)
    assert m["routes_completed"] == 3


# ---------- 3. 授予判定 ----------

@pytest.mark.asyncio
async def test_threshold_badge_award():
    await ensure_learning_ready()
    u = uid()
    for node in ms.nodes_by_section("sec_A_02")[:1]:
        await _seed_mastery(u, "route_A", node["id"], score=1.0, level="mastered")
    awarded = await badge_service.evaluate(u, source_event="quiz_submit")
    ids = [a["badge_id"] for a in awarded]
    assert "mastery_1" in ids


@pytest.mark.asyncio
async def test_mastery_5_requires_five():
    await ensure_learning_ready()
    u = uid()
    for node in ms.nodes_by_section("sec_A_02")[:3]:
        await _seed_mastery(u, "route_A", node["id"], score=1.0, level="mastered")
    awarded = await badge_service.evaluate(u)
    ids = [a["badge_id"] for a in awarded]
    assert "mastery_1" in ids
    assert "mastery_5" not in ids


@pytest.mark.asyncio
async def test_mastery_5_with_five():
    await ensure_learning_ready()
    u = uid()
    for node in ms.nodes_by_section("sec_A_02")[:5]:
        await _seed_mastery(u, "route_A", node["id"], score=1.0, level="mastered")
    awarded = await badge_service.evaluate(u)
    ids = [a["badge_id"] for a in awarded]
    assert "mastery_5" in ids


@pytest.mark.asyncio
async def test_ratio_badge_quiz_acc_50():
    await ensure_learning_ready()
    u = uid()
    # 50 次作答、46 正确 → 正确率 0.92 >= 0.9，且次数 >= 50
    await _seed_quiz_attempts(u, correct=46, wrong=4)
    awarded = await badge_service.evaluate(u)
    ids = [a["badge_id"] for a in awarded]
    assert "quiz_acc_50" in ids


@pytest.mark.asyncio
async def test_ratio_badge_needs_both():
    await ensure_learning_ready()
    u = uid()
    # 次数够但正确率不足：不应授予
    await _seed_quiz_attempts(u, correct=30, wrong=20)  # 正确率 0.6
    awarded = await badge_service.evaluate(u)
    ids = [a["badge_id"] for a in awarded]
    assert "quiz_acc_50" not in ids


@pytest.mark.asyncio
async def test_ratio_badge_needs_enough_attempts():
    await ensure_learning_ready()
    u = uid()
    # 正确率够但次数不足：不应授予
    await _seed_quiz_attempts(u, correct=9, wrong=0)  # 正确率 1.0 但仅 9 次
    awarded = await badge_service.evaluate(u)
    ids = [a["badge_id"] for a in awarded]
    assert "quiz_acc_50" not in ids


@pytest.mark.asyncio
async def test_completion_badge_route_all():
    await ensure_learning_ready()
    u = uid()
    await _complete_all_routes(u)
    awarded = await badge_service.evaluate(u)
    ids = [a["badge_id"] for a in awarded]
    assert "route_all" in ids


@pytest.mark.asyncio
async def test_milestone_badge():
    await ensure_learning_ready()
    u = uid()
    for node in ms.nodes_by_section("sec_A_02")[:1]:
        await _seed_mastery(u, "route_A", node["id"], score=1.0, level="mastered")
    awarded = await badge_service.evaluate(u)
    ids = [a["badge_id"] for a in awarded]
    assert "milestone_1" in ids


# ---------- 4. 幂等 ----------

@pytest.mark.asyncio
async def test_evaluate_idempotent():
    await ensure_learning_ready()
    u = uid()
    for node in ms.nodes_by_section("sec_A_02")[:1]:
        await _seed_mastery(u, "route_A", node["id"], score=1.0, level="mastered")
    first = await badge_service.evaluate(u)
    assert first, "首次应授予"
    second = await badge_service.evaluate(u)
    assert second == [], "重复评估不应重复授予"


@pytest.mark.asyncio
async def test_no_badges_for_no_progress():
    await ensure_learning_ready()
    u = uid()
    awarded = await badge_service.evaluate(u)
    assert awarded == []


# ---------- 5. 已停用勋章 ----------

@pytest.mark.asyncio
async def test_disabled_badge_not_awarded():
    await ensure_learning_ready()
    u = uid()
    original = _disable_badge("mastery_1")
    try:
        for node in ms.nodes_by_section("sec_A_02")[:1]:
            await _seed_mastery(u, "route_A", node["id"], score=1.0, level="mastered")
        awarded = await badge_service.evaluate(u)
        ids = [a["badge_id"] for a in awarded]
        assert "mastery_1" not in ids, "已停用勋章不参与新授予"
    finally:
        _restore_badge("mastery_1", original)


@pytest.mark.asyncio
async def test_disabled_badge_shown_in_mine():
    await ensure_learning_ready()
    u = uid()
    original = _disable_badge("mastery_1")
    try:
        mine = await badge_service.mine(u)
        b = next(x for x in mine["badges"] if x["badge_id"] == "mastery_1")
        assert b["disabled"] is True
        assert b["earned"] is False
    finally:
        _restore_badge("mastery_1", original)


# ---------- 6. mine / unseen / read ----------

@pytest.mark.asyncio
async def test_mine_summary_structure():
    await ensure_learning_ready()
    u = uid()
    for node in ms.nodes_by_section("sec_A_02")[:1]:
        await _seed_mastery(u, "route_A", node["id"], score=1.0, level="mastered")
    await badge_service.evaluate(u)
    mine = await badge_service.mine(u)
    assert "metrics" in mine and "badges" in mine and "summary" in mine
    sm = mine["summary"]
    assert sm["total"] == 29
    assert sm["earned"] + sm["unearned"] == 29
    for b in mine["badges"]:
        assert "progress" in b and "condition_text" in b
        assert "sort_order" in b and isinstance(b["sort_order"], int), (
            f"勋章 {b.get('badge_id')} 缺少 sort_order，badge_screen 排序会崩溃")


@pytest.mark.asyncio
async def test_unseen_and_read_flow():
    await ensure_learning_ready()
    u = uid()
    for node in ms.nodes_by_section("sec_A_02")[:1]:
        await _seed_mastery(u, "route_A", node["id"], score=1.0, level="mastered")
    await badge_service.evaluate(u)
    unseen = await badge_service.unseen(u)
    assert unseen["count"] >= 1
    award_ids = [a["award_id"] for a in unseen["awards"]]
    updated = await badge_service.mark_read(u, award_ids)
    assert updated == len(award_ids)
    unseen2 = await badge_service.unseen(u)
    assert unseen2["count"] == 0


@pytest.mark.asyncio
async def test_mark_read_ignores_unknown():
    await ensure_learning_ready()
    u = uid()
    updated = await badge_service.mark_read(u, ["nonexistent_award"])
    assert updated == 0


# ---------- 7. 判定逻辑纯函数 ----------

def test_condition_text_threshold():
    txt = badge_service.condition_text(get_badge("mastery_5"))
    assert "5" in txt and "≥" in txt


def test_condition_text_ratio():
    txt = badge_service.condition_text(get_badge("quiz_acc_50"))
    assert "50" in txt and "90" in txt


def test_progress_for_ratio():
    from content.routes import ROUTES
    p = badge_service._progress_for(get_badge("quiz_acc_50"),
                                    {"quiz_attempt_total": 60, "quiz_correct_total": 55},
                                    len(ROUTES))
    assert isinstance(p, dict)
    assert "display" in p and "accuracy" in p


# ---------- 8. API 端点 ----------

@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


def test_api_mine(client):
    u = uid()
    r = client.get("/api/badges/mine", params={"user_id": u})
    assert r.status_code == 200
    j = r.json()
    assert j["summary"]["total"] == 29
    assert "metrics" in j and "badges" in j


def test_api_unseen_and_read(client):
    u = uid()
    r = client.get("/api/badges/unseen", params={"user_id": u})
    assert r.status_code == 200
    assert "awards" in r.json() and "count" in r.json()
    r2 = client.post("/api/badges/read", json={"user_id": u, "award_ids": []})
    assert r2.status_code == 200 and "updated" in r2.json()


# ---------- 9. 挂接点 ----------

@pytest.mark.asyncio
async def test_quiz_submit_hook_returns_badges_awarded():
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    res = await quiz_service.submit_test(t["test_id"], u,
                                         [{"item_id": it["id"], "answer": "A", "confidence": "high"} for it in t["items"]])
    assert "badges_awarded" in res
    assert isinstance(res["badges_awarded"], list)


@pytest.mark.asyncio
async def test_route_sections_hook_returns_badges_awarded():
    await ensure_learning_ready()
    from services import route_service
    u = uid()
    res = await route_service.get_routes_sections(u, "route_A")
    assert "badges_awarded" in res
    assert isinstance(res["badges_awarded"], list)


def test_motivation_state_hook_returns_badges_awarded(client):
    u = uid()
    r = client.get("/api/motivation/state", params={"user_id": u, "route_id": "route_A"})
    assert r.status_code == 200
    assert "badges_awarded" in r.json()
    assert isinstance(r.json()["badges_awarded"], list)


@pytest.mark.asyncio
async def test_review_submit_hook_returns_badges_awarded():
    await ensure_learning_ready()
    from services import review_service
    u = uid()
    for node in ms.nodes_by_section("sec_A_02")[:1]:
        await _seed_mastery(u, "route_A", node["id"], score=0.6, level="developing")
    res = await review_service.apply_review(u, "route_A", ms.nodes_by_section("sec_A_02")[0]["id"], 0.9)
    assert "badges_awarded" in res
    assert isinstance(res["badges_awarded"], list)
