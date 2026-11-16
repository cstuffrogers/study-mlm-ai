"""US3 掌握度算法分项/阈值 + 对话信号平滑降权 + 主观题三维批改（FR-014）"""
import uuid
import pytest

from services.learning_startup import ensure_learning_ready
from services import mastery_service as ms, quiz_service
from core.config import MASTERY_WEIGHTS, MASTERY_THRESHOLDS


def uid():
    return "t_" + uuid.uuid4().hex[:8]


def test_compute_score_weighted():
    """D1：全分项均存在 → 加权平均"""
    basis = {"accuracy": 1.0, "difficulty": 0.8, "stability": 0.6, "dialogue": 0.9, "feynman": 0.7}
    expected = (1.0 * 0.60 + 0.8 * 0.15 + 0.6 * 0.10 + 0.9 * 0.10 + 0.7 * 0.05)
    assert abs(ms.compute_score(basis) - round(expected, 4)) < 1e-6


def test_compute_score_missing_components_renormalized():
    """缺失分项时按已存在分量归一化（未接触不算 0 拉低）"""
    only_acc = {"accuracy": 1.0}
    assert ms.compute_score(only_acc) == 1.0
    partial = {"accuracy": 1.0, "difficulty": 1.0}
    assert ms.compute_score(partial) == 1.0


def test_level_thresholds():
    """五级阈值映射"""
    assert ms.level_from_score(0.1) == "unseen"
    assert ms.level_from_score(0.3) == "beginner"
    assert ms.level_from_score(0.6) == "familiar"
    assert ms.level_from_score(0.8, {"feynman": 0.9}) == "proficient"
    # >0.85 且费曼通过 → mastered
    assert ms.level_from_score(0.9, {"feynman": 0.9}) == "mastered"
    # >0.85 但费曼未过 → 降为 proficient
    assert ms.level_from_score(0.9, {"feynman": 0.5}) == "proficient"


@pytest.mark.asyncio
async def test_dialogue_signal_decays_dialogue_component():
    """对话信号越多 → dialogue 分量平滑下降（0.10 权重降权）"""
    await ensure_learning_ready()
    u = uid()
    # 无信号 → dialogue 分量 = 1.0
    r0 = await ms.add_struggle_signal(u, "kn_civilsociety", "repeated_question", intensity=0.0)
    assert r0["dialogue_component"] == 1.0
    # 累计信号 → 降低
    await ms.add_struggle_signal(u, "kn_civilsociety", "wrong_rejected", intensity=1.0)
    await ms.add_struggle_signal(u, "kn_civilsociety", "repeated_question", intensity=1.0)
    r = await ms.add_struggle_signal(u, "kn_civilsociety", "assoc_fail", intensity=1.0)
    assert r["dialogue_component"] < 1.0
    assert r["signal_count"] == 4


@pytest.mark.asyncio
async def test_upsert_mastery_writes_and_merges():
    await ensure_learning_ready()
    u = uid()
    r1 = await ms.upsert_mastery(u, "kn_practice", "route_A", {"accuracy": 0.5, "difficulty": 0.6}, "quiz")
    assert r1["score"] > 0
    # 再融合对话分量
    r2 = await ms.upsert_mastery(u, "kn_practice", "route_A", {"dialogue": 0.9}, "dialogue")
    assert "dialogue" in r2["basis"]
    assert "accuracy" in r2["basis"]  # 之前的分项保留


@pytest.mark.asyncio
async def test_subjective_three_dimension_penalizes_deviation():
    """偏离立场的主观作答应拉低术语正统性维度"""
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    subj_answers = []
    for it in t["items"]:
        if it["subjective"]:
            subj_answers.append({"item_id": it["id"], "answer": "我认为应该走市场社会主义道路，用交往理性取代阶级斗争。"})
        else:
            subj_answers.append({"item_id": it["id"], "answer": "A"})
    sub = await quiz_service.submit_test(t["test_id"], u, subj_answers)
    subj = [r for r in sub["review"] if r.get("subjective_feedback")]
    fb = subj[0]["subjective_feedback"]
    # 立场偏离 → 术语正统性降低且有建议
    assert fb["terminology_orthodoxy"] < 0.6
    assert fb["suggestions"]
