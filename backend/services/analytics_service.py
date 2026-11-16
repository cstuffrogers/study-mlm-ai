"""AnalyticsService — 学习分析看板聚合（P3，D12）

把分散在各服务的学习数据聚合成一屏可读的「学习健康度」概览：
  - 掌握度分布（五级）
  - 记忆保持/遗忘预测（平均保持率 + 到期积压）
  - 复习积压（due 数）
  - 元认知校准（调用 CalibrationService）
  - 错因分布（来自 QuizAttempt.error_category）
  - 能力雷达短板（五维最低维）
  - 学习连续性（最近 N 天有作答的天数 = streak）
"""
from __future__ import annotations

from datetime import datetime, timedelta
from collections import Counter

from sqlalchemy import select

from services.learning_db import session_scope
from services import mastery_service as ms
from services import review_service
from services.calibration_service import calibration_report
from content.knowledge_graph import KNOWLEDGE_NODES
from model.models_learning import QuizAttempt

_LEVELS = ("unseen", "beginner", "familiar", "proficient", "mastered")
_DIMS = ("materialism", "dialectics", "epistemology", "historical_materialism", "political_economy")


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


async def overview(user_id: str, route_id: str, streak_days: int = 14) -> dict:
    m_map = await ms.get_mastery_map(user_id, route_id)

    # 1) 掌握度分布
    dist = {lv: 0 for lv in _LEVELS}
    for n in KNOWLEDGE_NODES:
        lv = m_map.get(n["id"], {}).get("level", "unseen")
        dist[lv] = dist.get(lv, 0) + 1
    total_nodes = len(KNOWLEDGE_NODES)
    assessed = sum(1 for n in KNOWLEDGE_NODES if n["id"] in m_map)
    mastered = dist.get("mastered", 0)

    # 2) 记忆保持 / 复习积压
    status = await review_service.review_status(user_id, route_id)
    rets = [it["retention"] for it in status["items"] if it.get("retention") is not None]
    avg_retention = round(sum(rets) / len(rets), 4) if rets else None
    due_count = status["due_count"]

    # 3) 元认知校准
    cal = await calibration_report(user_id, route_id)

    # 4) 错因分布（最近 streak 天）
    since = datetime.utcnow() - timedelta(days=streak_days)
    async with session_scope() as s:
        res = await _exec(s, select(QuizAttempt).where(QuizAttempt.user_id == user_id))
        attempts = list(res.scalars().all())
    recent = [a for a in attempts if a.confidence is not None]  # 全部（无时间字段则用整体）
    err_counter: Counter = Counter()
    day_set: set = set()
    scores = []
    for a in attempts:
        if a.error_category:
            err_counter[a.error_category] += 1
        scores.append(a.score or 0.0)
    error_breakdown = dict(err_counter)

    # 5) 能力雷达短板
    radar = {d: [] for d in _DIMS}
    for n in KNOWLEDGE_NODES:
        dim = n["ability_dim"]
        if dim in radar:
            radar[dim].append(m_map.get(n["id"], {}).get("score", 0.0))
    ability = {d: round(sum(v) / len(v), 4) for d, v in radar.items() if v}
    weakest_dim = min(ability.items(), key=lambda kv: kv[1]) if ability else (None, None)

    # 6) 学习连续性（用 QuizAttempt 是否有 created 时间；若无字段则用总数近似）
    streak = _estimate_streak(attempts, streak_days)

    avg_score = round(sum(scores) / len(scores), 4) if scores else None

    # 学习健康度评分（0-100，加权聚合，供看板顶部大数展示）
    health = _health_score(dist, total_nodes, avg_retention, due_count, cal, avg_score)

    return {
        "route_id": route_id,
        "total_nodes": total_nodes,
        "assessed_nodes": assessed,
        "mastery_distribution": dist,
        "mastered": mastered,
        "avg_retention": avg_retention,
        "due_count": due_count,
        "calibration": {"n": cal["n"], "verdict": cal["verdict"], "gap": cal["overall"]["gap"], "tip": cal["tip"]},
        "error_breakdown": error_breakdown,
        "ability_radar": ability,
        "weakest_dim": {"dim": weakest_dim[0], "score": weakest_dim[1]},
        "total_attempts": len(attempts),
        "avg_score": avg_score,
        "streak_days": streak,
        "health_score": health,
    }


def _estimate_streak(attempts: list, window: int) -> int:
    """用 QuizAttempt.created 近似：无法取到时间时退化为 0。"""
    days = set()
    for a in attempts:
        created = getattr(a, "created_at", None)
        if created is None:
            continue
        days.add(created.date())
    if not days:
        return 0
    streak = 0
    cur = datetime.utcnow().date()
    while cur in days:
        streak += 1
        cur = cur - timedelta(days=1)
    return streak


def _health_score(dist, total, avg_retention, due_count, cal, avg_score) -> int:
    """综合健康度（0-100）：掌握面 40% + 长期保持 25% + 校准 15% + 近期正确 20%。"""
    mastery_ratio = (dist.get("proficient", 0) + dist.get("mastered", 0)) / max(1, total)
    retention_part = 1.0 if avg_retention is None else avg_retention
    # 积压惩罚：到期越多，保持分越低
    backlog_penalty = min(0.5, due_count * 0.05)
    retention_part = max(0.0, retention_part - backlog_penalty)
    cal_part = {"calibrated": 1.0, "underconfident": 0.7, "overconfident": 0.5, "unknown": 0.6}.get(cal["verdict"], 0.6)
    acc_part = 1.0 if avg_score is None else avg_score
    score = 0.40 * mastery_ratio + 0.25 * retention_part + 0.15 * cal_part + 0.20 * acc_part
    return int(round(score * 100))
