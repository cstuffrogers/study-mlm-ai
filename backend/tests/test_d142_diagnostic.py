# -*- coding: utf-8 -*-
"""D142 门禁：摸底测（诊断测试）不能出「点进去答不了」的题，也不能静默不出题。

症状：单机版「重新摸底测」点进去是空的 —— `LocalRouter` 直接返回 `items: []`。
修的时候顺手在**两侧**发现两个真问题，本门禁锁住它们：

  1. 「每章取前 3 题」会把**应用题/主观题**一起抽中，它们 `options == []`
     （走三维 rubric 评分），摸底测里没有选项可点，用户只能卡死。
     → 摸底测只出选项 ≥2 的题。
  2. 判分口径：逐章正确率 ≥ 解锁阈值（UNLOCK_THRESHOLD）判「可跳过」，
     起点 = 第一张「未达标或有数据缺口」的章；**没作答数据的章不能算可跳过**。

与单机版 `LocalQuiz.startDiagnostic / submitDiagnostic` 同口径（`frontend/test/d142_diagnostic_test.dart`）。
"""
from __future__ import annotations

import uuid

import pytest

from content.routes import sections_for_route
from core.config import UNLOCK_THRESHOLD
from services import quiz_service
from services.learning_startup import ensure_learning_ready

ROUTES = ("route_A", "route_B", "route_C")


def uid() -> str:
    return "dg_" + uuid.uuid4().hex[:8]


def _sec_ids(route_id: str) -> list[str]:
    return [s["id"] for s in sections_for_route(route_id)]


@pytest.mark.asyncio
@pytest.mark.parametrize("route_id", ROUTES)
async def test_diagnostic_has_answerable_items(route_id):
    await ensure_learning_ready()
    t = await quiz_service.start_diagnostic(uid(), route_id)
    items = t["items"]
    assert items, f"{route_id} 摸底测不该是空的"
    assert t["diag_id"], "有题就必须给 diag_id，否则提交无处落"
    assert len(items) <= 12
    for it in items:
        assert len(it.get("options") or []) > 1, f"{it['id']} 没有选项，摸底测里答不了"
        assert it.get("source_chunk_id"), f"{it['id']} 缺溯源锚点，等于放行未溯源题"
        assert it.get("stem", "").strip()
        assert "answer" not in it and "explanation" not in it, "下发题面不能带答案"


@pytest.mark.asyncio
async def test_diagnostic_sampling_is_ordered_and_capped_per_section():
    await ensure_learning_ready()
    t = await quiz_service.start_diagnostic(uid(), "route_A")
    from model.models_learning import QuizItem
    from services.learning_db import session_scope
    from sqlalchemy import select

    ids = [it["id"] for it in t["items"]]
    async with session_scope() as s:
        rows = (await s.execute(select(QuizItem).where(QuizItem.id.in_(ids)))).scalars().all()
    sec_of = {r.id: r.section_id for r in rows}

    per_sec: dict[str, int] = {}
    for i in ids:
        per_sec[sec_of[i]] = per_sec.get(sec_of[i], 0) + 1
    assert all(v <= 3 for v in per_sec.values()), per_sec

    order = _sec_ids("route_A")
    seen = [sec_of[i] for i in ids]
    uniq: list[str] = []
    for s in seen:
        if not uniq or uniq[-1] != s:
            uniq.append(s)
    assert uniq == order[: len(uniq)], "抽取必须按章节顺序走，不能跳章乱序"
    assert len(uniq) == len(per_sec), "同一章只能出现一段连续区间"


@pytest.mark.asyncio
async def test_all_correct_skips_answered_sections_only():
    await ensure_learning_ready()
    route_id = "route_A"
    t = await quiz_service.start_diagnostic(uid(), route_id)
    ids = [it["id"] for it in t["items"]]

    from model.models_learning import QuizItem
    from services.learning_db import session_scope
    from sqlalchemy import select

    async with session_scope() as s:
        rows = (await s.execute(select(QuizItem).where(QuizItem.id.in_(ids)))).scalars().all()
    by_id = {r.id: r for r in rows}
    answers = [{"item_id": i, "answer": by_id[i].answer} for i in ids]

    res = await quiz_service.submit_diagnostic(t["diag_id"], uid(), answers)
    answered = {by_id[i].section_id for i in ids}
    assert set(res["skippable"]) == answered, "全对就该把有作答数据的章全标可跳过"
    for sid in _sec_ids(route_id):
        if sid not in answered:
            assert sid not in res["skippable"], f"{sid} 没有作答数据，不能判为可跳过"
            assert sid in res["order"], "没作答数据的章必须留在要学清单里"
    assert res["recommended_start"] not in answered, "全部可跳过时起点应落到第一个没数据的章"
    assert res["to_reinforce"] == []


@pytest.mark.asyncio
async def test_all_wrong_starts_from_first_section():
    await ensure_learning_ready()
    route_id = "route_B"
    t = await quiz_service.start_diagnostic(uid(), route_id)
    answers = [{"item_id": it["id"], "answer": "Z"} for it in t["items"]]
    res = await quiz_service.submit_diagnostic(t["diag_id"], uid(), answers)
    order = _sec_ids(route_id)
    assert res["recommended_start"] == order[0]
    assert res["skippable"] == []
    assert res["order"] == order, "全错 = 每章都要学，顺序即路线顺序"
    assert res["to_reinforce"], "全错必须给出要补强的知识点"
    for r in res["to_reinforce"]:
        assert r["node_id"].startswith("kn_")
        assert r["name"] != r["node_id"], "要显示知识点名字，不能直接甩 id"
        assert r["reason"]


@pytest.mark.asyncio
async def test_unknown_diag_id_raises():
    await ensure_learning_ready()
    with pytest.raises(ValueError):
        await quiz_service.submit_diagnostic("local_diag_bogus", uid(), [])


@pytest.mark.asyncio
async def test_unlock_threshold_is_the_cut_line():
    """阈值口径必须单一来源：单机版硬编码 0.8 会与后端漂移。"""
    assert UNLOCK_THRESHOLD == pytest.approx(0.8)
