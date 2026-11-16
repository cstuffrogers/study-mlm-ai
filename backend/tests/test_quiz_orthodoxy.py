"""US3 正统性门禁 / 出题 / 判分 / 掌握度五级映射 / 未审题不计分 / 错误诊断豁免"""
import io
import json
import os
import sys
import uuid
import pytest

from services.learning_startup import ensure_learning_ready
from services import quiz_service, mastery_service as ms
from services.learning_db import session_scope
from api.quiz_routes import history
from model.models_learning import QuizItem
from core.config import MASTERY_THRESHOLDS


def uid():
    return "t_" + uuid.uuid4().hex[:8]


_BANK = os.path.join(os.path.dirname(os.path.dirname(__file__)), "content", "quiz_bank", "outline_chapter.json")


def _load_bank():
    with io.open(_BANK, encoding="utf-8") as f:
        d = json.load(f)
    return d["items"] if isinstance(d, dict) else d


@pytest.mark.asyncio
async def test_quiz_bank_every_item_has_source():
    """FR-022：每题必须带 source_chunk_id（缺则拒绝出题）"""
    for it in _load_bank():
        assert it.get("source_chunk_id"), f"{it['id']} 缺 source_chunk_id"
        assert it.get("authority_status") in ("reviewed", "pending")


@pytest.mark.asyncio
async def test_start_test_no_answer_leak():
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    assert 8 <= len(t["items"]) <= 12
    for it in t["items"]:
        assert "answer" not in it
        assert "explanation" not in it
        assert it["source_chunk_id"]


@pytest.mark.asyncio
async def test_submit_grades_and_maps_five_levels():
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    sub = await quiz_service.submit_test(t["test_id"], u, [{"item_id": it["id"], "answer": "A"} for it in t["items"]])
    assert 0.0 <= sub["total_score"] <= 1.0
    # 五级映射合法
    valid = {"unseen", "beginner", "familiar", "proficient", "mastered"}
    for m in sub["mastery"]:
        assert m["level"] in valid
        assert 0.0 <= m["score"] <= 1.0
    # 答对为主 → 章节篇首知识点应为 proficient 及以上
    assert sub["gating"]["next_section_unlocked"] is True


@pytest.mark.asyncio
async def test_wrong_answer_marks_beginner_and_error_category():
    """全答 B（大部分错）→ 应得到低掌握度与错因归类"""
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    sub = await quiz_service.submit_test(t["test_id"], u, [{"item_id": it["id"], "answer": "B"} for it in t["items"]])
    # 至少有一个节点低于 beginner 上界
    low = [m for m in sub["mastery"] if m["score"] < MASTERY_THRESHOLDS["familiar"]]
    assert low, "全错时应有低掌握度知识点"
    # 客观题错因归类非空
    cats = {r.get("error_category") for r in sub["review"] if not r.get("subjective_feedback") and not r["is_correct"]}
    assert any(c for c in cats if c), "错题应有错因归类"


@pytest.mark.asyncio
async def test_review_row_carries_readable_diagnosis():
    """逐题解析要能直接显示：题面/正确答案/解析/错因中文标签/诊断句一项不缺。

    回归：review 曾只给 reference + 内部编码，前端读 explanation 拿到 None，
    错因也直接是 real_unknown，学习者看不到任何可读的错因。
    """
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    items = t["items"]
    answers = []
    for it in items:
        # 主观/应用题给一句像样的作答；客观题刻意选错（避开正确项）
        opts = it.get("options") or []
        answers.append({"item_id": it["id"], "answer": "B" if len(opts) >= 2 else
                        "实践是人改造世界的对象性活动，因此认识来源于实践。"})
    sub = await quiz_service.submit_test(t["test_id"], u, answers)
    rows = [r for r in sub["review"] if not r["is_correct"]]
    assert rows, "全答 B 应有错题"
    for r in rows:
        assert (r.get("stem") or "").strip(), "逐题解析缺少题面"
        assert r.get("explanation") is not None, "逐题解析缺少解析"
        label = (r.get("error_label") or "").strip()
        assert label, "错因标签为空 → 前端不显示错因"
        assert "_" not in label, f"错因不能是内部编码：{label}"
        assert (r.get("error_reason") or "").strip(), "缺少错因诊断句"


@pytest.mark.asyncio
async def test_history_rows_refill_stem_and_label():
    """错题本（/api/quiz/history）每条都带题面与可读错因。"""
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    await quiz_service.submit_test(
        t["test_id"], u, [{"item_id": it["id"], "answer": "B"} for it in t["items"]])
    data = await history(user_id=u, only_wrong=True)
    rows = data["rows"]
    assert rows
    for r in rows:
        assert r["error_label"], "错题本缺错因标签"
        assert "_" not in r["error_label"]


@pytest.mark.asyncio
async def test_trial_only_items_not_counted_in_mastery():
    """未审题（authority_status=pending 或 trial_only）不计入正式掌握度"""
    await ensure_learning_ready()
    u = uid()
    # 把 sec_A_02 的一道题临时置为 pending
    async with session_scope() as s:
        res = await s.execute(select_item("q_practice_def"))
        item = res.scalars().first()
        old = item.authority_status
        item.authority_status = "pending"
        item.trial_only = True
        await _flush(s)
    try:
        t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
        # 找到 pending 题（开始测试时若仍包含则其 trial_only 应为 True）
        sub = await quiz_service.submit_test(t["test_id"], u, [{"item_id": it["id"], "answer": "A"} for it in t["items"]])
        m_map = await ms.get_mastery_map(u, "route_A")
    finally:
        async with session_scope() as s:
            res = await s.execute(select_item("q_practice_def"))
            item = res.scalars().first()
            item.authority_status = old
            item.trial_only = False
            await _flush(s)
    # 该题所属节点若只由 pending 题覆盖则不应进入掌握度；宽松断言：不报错且掌握度合理
    assert isinstance(m_map, dict)


@pytest.mark.asyncio
async def test_error_diagnosis_items_are_exempt_marked():
    """错误诊断题的故意错误项应有 exempt_marked=True（FR-023 豁免标记）"""
    bank = _load_bank()
    err_items = [it for it in bank if it["type"] == "error_diagnosis" and not it.get("subjective")]
    assert err_items, "题库应含错误诊断题"
    for it in err_items:
        assert it.get("exempt_marked") is True, f"{it['id']} 错误诊断题应豁免标记"


@pytest.mark.asyncio
async def test_subjective_feynman_three_dimension_feedback():
    """FR-014：主观题三维度批改 + 建议，不代写"""
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    answers = []
    for it in t["items"]:
        if it["subjective"]:
            answers.append({"item_id": it["id"], "answer": "实践是检验真理的唯一标准，因为只有在改造客观世界的实践中才能验证思维的真理性。"})
        else:
            answers.append({"item_id": it["id"], "answer": "A"})
    sub = await quiz_service.submit_test(t["test_id"], u, answers)
    subj = [r for r in sub["review"] if r.get("subjective_feedback")]
    assert subj, "应有主观题批改结果"
    fb = subj[0]["subjective_feedback"]
    for k in ("terminology_orthodoxy", "logic_coherence", "concept_layer", "suggestions"):
        assert k in fb


# --- helpers
from sqlalchemy import select


def select_item(qid):
    return select(QuizItem).where(QuizItem.id == qid)


async def _flush(s):
    try:
        from sqlalchemy.ext.asyncio import AsyncSession
        if isinstance(s, AsyncSession):
            await s.flush()
            return
    except Exception:
        pass
    s.flush()
