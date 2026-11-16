"""ReviewService — 间隔复习调度（FSRS-lite，D8）

解决的问题：掌握度会随时间遗忘。达标 ≠ 永久记住。本服务对每个已评估知识点建模
「记忆稳定性 stability → 复习间隔」，到期推入复习队列，复习结果回写 stability。

模型（轻量 FSRS 近似）：
  - 保持率 retention(t) = 0.5 ** (elapsed_days / half_life)，half_life = 3 + 12*stability 天
  - 复习间隔 interval = base * 2^(stability/0.3)，封顶 MAX 天
  - 到期判定：now >= next_review_at，或 retention < REVIEW_DUE_RETENTION
  - 复习成功（正确率≥0.8）→ stability += REVIEW_GAIN（间隔指数变长）
    复习失败 → stability = max(0, stability - REVIEW_REGRESS)（间隔缩短，重新密集）
"""
from __future__ import annotations

from datetime import datetime, timedelta

from core.config import (
    REVIEW_BASE_INTERVAL_DAYS, REVIEW_MAX_INTERVAL_DAYS,
    REVIEW_HALF_LIFE_MIN_DAYS, REVIEW_HALF_LIFE_MAX_DAYS,
    REVIEW_DUE_RETENTION, REVIEW_GAIN, REVIEW_REGRESS,
)
import core.config as _cfg
from services import mastery_service as ms
from services.learning_db import session_scope
from services.knowledge_graph_service import get_kg
from content.knowledge_graph import get_node
from model.models_learning import MasteryRecord, ReviewLog
from sqlalchemy import select


def _half_life(stability: float) -> float:
    return REVIEW_HALF_LIFE_MIN_DAYS + (REVIEW_HALF_LIFE_MAX_DAYS - REVIEW_HALF_LIFE_MIN_DAYS) * max(0.0, min(1.0, stability))


def retention(elapsed_days: float, stability: float) -> float:
    """当前记忆保持率（0~1）"""
    hl = _half_life(stability)
    return round(0.5 ** (max(0.0, elapsed_days) / hl), 4)


def interval_days(stability: float) -> float:
    """给定稳定性下的建议复习间隔（天）"""
    raw = REVIEW_BASE_INTERVAL_DAYS * (2 ** (max(0.0, stability) / 0.3))
    return round(min(REVIEW_MAX_INTERVAL_DAYS, max(0.5, raw)), 2)


def schedule_next(stability: float, now: datetime | None = None) -> datetime:
    now = now or datetime.utcnow()
    return now + timedelta(days=interval_days(stability))


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


async def _flush(s):
    if _is_async_session(s):
        await s.flush()
    else:
        s.flush()


async def _load_records(user_id: str, route_id: str) -> list[MasteryRecord]:
    async with session_scope() as s:
        res = await _exec(s, select(MasteryRecord).where(
            MasteryRecord.user_id == user_id, MasteryRecord.route_id == route_id))
        return list(res.scalars().all())


async def due_reviews(user_id: str, route_id: str, now: datetime | None = None) -> list[dict]:
    """到期复习队列：按遗忘风险（保持率低 + 依赖出度高）排序"""
    now = now or datetime.utcnow()
    kg = get_kg()
    rows = await _load_records(user_id, route_id)
    out = []
    for r in rows:
        if r.score is None or r.score < 0.2:
            continue  # 尚未形成稳定记忆，按普通学习处理
        stability = float((r.basis or {}).get("stability", 0.0) or 0.0)
        last = r.last_reviewed_at or r.updated_at
        elapsed = (now - last).total_seconds() / 86400.0 if last else 999.0
        ret = retention(elapsed, stability)
        due = (r.next_review_at is not None and now >= r.next_review_at) or ret < REVIEW_DUE_RETENTION
        if not due:
            continue
        node = get_node(r.node_id)
        risk = (1.0 - ret) * (1 + kg.dependents_count(r.node_id))
        out.append({
            "node_id": r.node_id,
            "name": node["name"] if node else r.node_id,
            "section_id": node["section_id"] if node else "",
            "score": round(r.score, 4),
            "stability": round(stability, 4),
            "retention": ret,
            "elapsed_days": round(elapsed, 2),
            "next_review_at": r.next_review_at.isoformat() if r.next_review_at else None,
            "_risk": round(risk, 4),
        })
    out.sort(key=lambda x: x["_risk"], reverse=True)
    for x in out:
        x.pop("_risk", None)
    return out


async def apply_review(user_id: str, route_id: str, node_id: str, correct_ratio: float,
                       now: datetime | None = None) -> dict:
    """复习结果回写：调整 stability 并重排下一次复习时间；同步刷新掌握分里的 stability 分量。"""
    now = now or datetime.utcnow()
    async with session_scope() as s:
        res = await _exec(s, select(MasteryRecord).where(
            MasteryRecord.user_id == user_id, MasteryRecord.node_id == node_id,
            MasteryRecord.route_id == route_id))
        r = res.scalars().first()
        if r is None:
            return {"node_id": node_id, "applied": False, "reason": "尚无掌握记录"}
        stability = float((r.basis or {}).get("stability", 0.0) or 0.0)
        stability_before = stability
        last = r.last_reviewed_at or r.updated_at
        elapsed_days = (now - last).total_seconds() / 86400.0 if last else 0.0
        if correct_ratio >= 0.8:
            stability = min(1.0, stability + REVIEW_GAIN)
        else:
            stability = max(0.0, stability - REVIEW_REGRESS)
        r.review_count = (r.review_count or 0) + 1
        r.last_reviewed_at = now
        r.next_review_at = now + timedelta(days=interval_days(stability))
        # D15：写复习日志，供真实数据驱动的 FSRS 参数拟合使用
        s.add(ReviewLog(user_id=user_id, route_id=route_id, node_id=node_id,
                        stability_before=round(stability_before, 4),
                        stability_after=round(stability, 4),
                        interval_days=round(interval_days(stability_before), 2),
                        correct_ratio=correct_ratio, elapsed_days=round(elapsed_days, 2),
                        correct=(correct_ratio >= 0.8)))
        await _flush(s)
        next_at = r.next_review_at
    # 刷新掌握度（写回 stability 分量，会改变 score/level）
    await ms.upsert_mastery(user_id, node_id, route_id, {"stability": round(stability, 4)}, source="review")
    return {
        "node_id": node_id, "applied": True,
        "stability": round(stability, 4),
        "retention_now": retention(0.0, stability),
        "next_review_at": next_at.isoformat(),
        "review_count_delta": 1,
    }


async def review_status(user_id: str, route_id: str) -> dict:
    """复习概览：到期数 / 各节点稳定性与保持率"""
    rows = await _load_records(user_id, route_id)
    now = datetime.utcnow()
    items = []
    for r in rows:
        stability = float((r.basis or {}).get("stability", 0.0) or 0.0)
        last = r.last_reviewed_at or r.updated_at
        elapsed = (now - last).total_seconds() / 86400.0 if last else 0.0
        node = get_node(r.node_id)
        items.append({
            "node_id": r.node_id, "name": node["name"] if node else r.node_id,
            "score": round(r.score, 4), "stability": round(stability, 4),
            "retention": retention(elapsed, stability),
            "review_count": r.review_count or 0,
            "next_review_at": r.next_review_at.isoformat() if r.next_review_at else None,
        })
    due = await due_reviews(user_id, route_id)
    return {"route_id": route_id, "due_count": len(due), "due": due, "items": items}


# ---------------- P2-⑤ 交错练习（interleaving）----------------
# 证据：把不同知识点的复习混在一轮（交错）比长时间只练一个点（块状）更能促进
# 检索与迁移。这里把「已掌握但未到期」的知识点也纳入混合队列，并强制跨小节交错。

_INTERLEAVE_MIX_RATIO = _cfg.INTERLEAVE_MIX_RATIO  # 混合队列中「非最弱」知识点的目标占比


async def interleaved_reviews(user_id: str, route_id: str, n: int = 8,
                              now: datetime | None = None) -> list[dict]:
    """生成一轮交错复习队列：优先到期项，再穿插不同节点的稳定项，避免块状重复。

    返回每项带 kind：due（到期）/ interleave（交错巩固），按「到期优先 → 跨小节轮转」排列。
    """
    now = now or datetime.utcnow()
    rows = await _load_records(user_id, route_id)
    due = await due_reviews(user_id, route_id, now=now)
    due_ids = {d["node_id"] for d in due}

    # 巩固池：已形成记忆（score≥0.45）但本轮未到期、未进 due 的节点
    pool = []
    for r in rows:
        if r.node_id in due_ids or r.score is None or r.score < 0.45:
            continue
        stability = float((r.basis or {}).get("stability", 0.0) or 0.0)
        node = get_node(r.node_id)
        pool.append({
            "node_id": r.node_id,
            "name": node["name"] if node else r.node_id,
            "section_id": node["section_id"] if node else "",
            "score": round(r.score, 4),
            "stability": round(stability, 4),
            "kind": "interleave",
        })
    # 稳定项按 score 升序（越弱越靠前，优先巩固），并跨小节轮转打散
    pool.sort(key=lambda x: (x["score"], x["node_id"]))
    pool = _rotate_by_section(pool)

    queue = [{**d, "kind": "due"} for d in due]
    # 按比例穿插：到期项之间插入巩固项，避免连续同节
    target_interleave = max(0, min(len(pool), int(round(n * _INTERLEAVE_MIX_RATIO))))
    queue.extend(pool[:target_interleave])
    queue = _interleave_order(queue)
    return queue[:n]


def _rotate_by_section(items: list[dict]) -> list[dict]:
    """按 section 轮转：不同小节的节点交替排列，降低块状效应。"""
    buckets: dict[str, list[dict]] = {}
    for it in items:
        buckets.setdefault(it.get("section_id", ""), []).append(it)
    out: list[dict] = []
    while any(buckets.values()):
        for k in list(buckets.keys()):
            if buckets[k]:
                out.append(buckets[k].pop(0))
    return out


def _interleave_order(items: list[dict]) -> list[dict]:
    """贪心重排：尽量让相邻项属于不同节点与不同小节。"""
    remaining = list(items)
    out: list[dict] = []
    prev_node = prev_sec = None
    while remaining:
        pick_idx = 0
        for i, it in enumerate(remaining):
            if it["node_id"] != prev_node and it.get("section_id") != prev_sec:
                pick_idx = i
                break
        it = remaining.pop(pick_idx)
        out.append(it)
        prev_node, prev_sec = it["node_id"], it.get("section_id")
    return out


# ---------------- D15 真实数据驱动的 FSRS 参数拟合 ----------------
# 用真实复习日志校准 GAIN/REGRESS：比较「复习后实际是否记住」与模型预期，
# 若成功用例中 stability 增长后仍频繁遗忘 → 增益偏乐观，建议调小；反之调大。
# 输出仅“建议值”，不自动改配置（避免小样本抖动破坏体验）。

_MIN_LOG_SAMPLES = 6


async def fit_parameters(user_id: str | None = None, route_id: str | None = None) -> dict:
    """从复习日志估计更贴合实际的 GAIN/REGRESS 建议值。"""
    from core.config import REVIEW_GAIN as _GAIN, REVIEW_REGRESS as _REGRESS
    async with session_scope() as s:
        stmt = select(ReviewLog)
        if user_id:
            stmt = stmt.where(ReviewLog.user_id == user_id)
        if route_id:
            stmt = stmt.where(ReviewLog.route_id == route_id)
        rows = list((await _exec(s, stmt)).scalars().all())

    n = len(rows)
    if n < _MIN_LOG_SAMPLES:
        return {"available": False, "n": n,
                "message": f"复习日志不足（{n}/{_MIN_LOG_SAMPLES}），继续积累后再拟合",
                "current": {"gain": _GAIN, "regress": _REGRESS}}

    # 成功样本：观察“复习成功后到下次复习之间是否又遗忘”（用相邻同节点日志推断）
    by_node: dict[str, list[ReviewLog]] = {}
    for r in rows:
        by_node.setdefault(r.node_id, []).append(r)
    for k in by_node:
        by_node[k].sort(key=lambda x: x.created_at or datetime.min)

    succ = [r for r in rows if r.correct]
    fail = [r for r in rows if not r.correct]
    # 真实成功率
    succ_rate = len(succ) / n if n else 0.0
    # 若成功率显著低于 0.8（模型默认复习合格线），说明间隔偏激进 → 建议更频繁（增益小、回退大）
    implicit_gain = round(max(0.05, min(0.4, _GAIN * (0.5 + succ_rate))), 3)
    implicit_regress = round(max(0.1, min(0.4, _REGRESS * (1.5 - succ_rate))), 3)
    # 遗忘率：一次复习后在下一次同节点复习又失败的占比
    relearn_fail = 0
    relearn_total = 0
    for logs in by_node.values():
        for a, b in zip(logs, logs[1:]):
            relearn_total += 1
            if not b.correct:
                relearn_fail += 1
    lapse_rate = round(relearn_fail / relearn_total, 3) if relearn_total else None

    note = []
    if succ_rate < 0.7:
        note.append("复习成功率偏低，当前间隔可能过激进，建议降低 gain / 提高 regress（更频繁复习）")
    elif succ_rate > 0.95 and fail == []:
        note.append("复习几乎全对，间隔可更激进，建议适当提高 gain（减少无效复习）")
    else:
        note.append("复习表现接近模型预期，当前参数基本合理")
    return {
        "available": True, "n": n,
        "succ_rate": round(succ_rate, 3),
        "lapse_rate": lapse_rate,
        "current": {"gain": _GAIN, "regress": _REGRESS},
        "suggested": {"gain": implicit_gain, "regress": implicit_regress},
        "note": "；".join(note),
    }
