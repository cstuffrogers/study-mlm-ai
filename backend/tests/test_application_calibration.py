"""P1-② 应用/案例题论证评分 + P2-④ 元认知校准 测试"""
import uuid
import pytest

from services.learning_startup import ensure_learning_ready
from services import quiz_service
from content.concept_keywords import terms_for, misconceptions_for


def uid():
    return "ap_" + uuid.uuid4().hex[:8]


def _app_item_from_bank():
    import io, json, os
    p = os.path.join(os.path.dirname(os.path.dirname(__file__)), "content", "quiz_bank", "outline_chapter.json")
    d = json.load(io.open(p, encoding="utf-8"))
    return next(it for it in d["items"] if it["type"] == "application")


def test_bank_has_application_item_with_source():
    it = _app_item_from_bank()
    assert it["source_chunk_id"], "应用题也必须带溯源"
    assert it["authority_status"] == "reviewed"


def test_concept_keywords_available():
    assert "实践" in terms_for(["kn_practice"])
    assert misconceptions_for(["kn_practice"])


@pytest.mark.asyncio
async def test_application_item_present_and_no_leak():
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    app = [it for it in t["items"] if it.get("application")]
    assert app, "章节应含应用题"
    assert "answer" not in app[0] and "explanation" not in app[0]


@pytest.mark.asyncio
async def test_application_scoring_rewards_concepts_and_structure():
    """应用题：用好术语 + 有案例结构 → 高分；空洞回答 → 低分"""
    from model.models_learning import QuizItem
    q = QuizItem(id="q_app_test", section_id="sec_A_02", node_id="kn_practice", type="application",
                 stem="x", options=[], answer="", explanation="实践是感性的对象性活动；实践检验真理",
                 difficulty=0.7, source_chunk_id="CH-ME-TH-02-1", authority_status="reviewed",
                 exempt_marked=False, trial_only=False, subjective=False)
    good = quiz_service._grade_application(
        q, "实践是感性的、对象性的物质活动，必须改造世界。例如技术方案通过试点检验真理性，因此实践检验认识，结论落到改变世界。")
    bad = quiz_service._grade_application(q, "背熟就好。")
    assert good["score"] > bad["score"]
    assert good["concept_use"] >= bad["concept_use"]
    assert good["structure"] >= bad["structure"]


@pytest.mark.asyncio
async def test_calibration_overconfident_detected():
    """自评高但实际错 → overconfident"""
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    # 全部自评 high，但客观题故意答错
    answers = []
    for it in t["items"]:
        ans = "A" if it.get("subjective") or it.get("application") else "B"  # 客观题答错
        answers.append({"item_id": it["id"], "answer": ans, "confidence": "high"})
    res = await quiz_service.submit_test(t["test_id"], u, answers)
    cal = res["calibration"]
    assert cal["available"] is True
    assert cal["verdict"] == "overconfident"
    assert cal["gap"] > 0


@pytest.mark.asyncio
async def test_calibration_unavailable_without_confidence():
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    res = await quiz_service.submit_test(t["test_id"], u, [{"item_id": it["id"], "answer": "A"} for it in t["items"]])
    assert res["calibration"]["available"] is False
