"""CalibrationService — 元认知校准聚合（P2-④ 扩展，D10）

单次测试的校准只在 submit 时算一次；这里跨历史作答聚合「自评把握度 vs 实测正确率」，
产出总体偏差、分档（low/mid/high）偏差与校准趋势，帮助用户建立「知之为知之」的元认知。
"""
from __future__ import annotations

from sqlalchemy import select

from core.config import CALIBRATION_CONFIDENCE_MAP, CALIBRATION_OVERCONFIDENT_GAP
from services.learning_db import session_scope
from model.models_learning import QuizAttempt


def _is_async_session(s) -> bool:
    try:
        from sqlalchemy.ext.asyncio import AsyncSession
        return isinstance(s, AsyncSession)
    except Exception:
        return False


async def _exec(s, stmt):
    if _is_async_session(s):
        return await s.execute(stmt)
    return s.execute(stmt)


async def _load_attempts(user_id: str) -> list[QuizAttempt]:
    async with session_scope() as s:
        res = await _exec(s, select(QuizAttempt).where(QuizAttempt.user_id == user_id))
        return list(res.scalars().all())


def _bucket_stats(pairs: list[tuple[float, float]]) -> dict:
    if not pairs:
        return {"n": 0, "expected": None, "actual": None, "gap": None}
    expected = sum(p[0] for p in pairs) / len(pairs)
    actual = sum(p[1] for p in pairs) / len(pairs)
    return {"n": len(pairs),
            "expected": round(expected, 3),
            "actual": round(actual, 3),
            "gap": round(expected - actual, 3)}


def _verdict(gap: float) -> str:
    if gap is None:
        return "unknown"
    if gap > CALIBRATION_OVERCONFIDENT_GAP:
        return "overconfident"
    if gap < -CALIBRATION_OVERCONFIDENT_GAP:
        return "underconfident"
    return "calibrated"


async def calibration_report(user_id: str, route_id: str | None = None) -> dict:
    attempts = await _load_attempts(user_id)
    all_pairs: list[tuple[float, float]] = []
    by_conf: dict[str, list[tuple[float, float]]] = {"low": [], "mid": [], "high": []}
    recent: list[dict] = []  # 用于趋势：按 test 聚合
    for a in attempts:
        conf = (a.confidence or "").lower()
        if conf not in CALIBRATION_CONFIDENCE_MAP:
            continue
        pair = (CALIBRATION_CONFIDENCE_MAP[conf], 1.0 if a.is_correct else 0.0)
        all_pairs.append(pair)
        by_conf[conf].append(pair)
        recent.append({"test_id": a.test_id, "conf": conf, "correct": bool(a.is_correct)})

    overall = _bucket_stats(all_pairs)
    buckets = {k: _bucket_stats(v) for k, v in by_conf.items() if v}
    gap = overall.get("gap")
    if gap is None:
        tip = "还没有带自评把握度的作答，先在做题时标一下『没把握/一般/有把握』，系统才能帮你校准元认知。"
    elif _verdict(gap) == "overconfident":
        tip = "整体偏高估：你『觉得会』的题里有相当比例实际错了。建议对高把握题再做一次快速自检，尤其概念易混点。"
    elif _verdict(gap) == "underconfident":
        tip = "整体偏低估：你实际掌握得比自评更好，可以更自信，减少不必要的反复核对。"
    else:
        tip = "自评与实测总体一致，元认知校准良好。"
    return {
        "user_id": user_id,
        "n": overall["n"],
        "overall": overall,
        "verdict": _verdict(gap),
        "by_confidence": buckets,
        "tip": tip,
    }
