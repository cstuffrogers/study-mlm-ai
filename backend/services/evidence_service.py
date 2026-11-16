"""MasteryService 增补 — 证据事件模型（spec 003 FR-113/114/115/117，research D2）

设计约束：
  1. **不引入平行体系**：证据最终仍写入 MasteryRecord.basis（既有 accuracy/difficulty/
     stability/dialogue/feynman 五分量），本模块只负责「可撤销 + 可重放」的记录与重算。
  2. **证据强度分级**：quiz 1.0 / feynman 0.8 / dialogue 0.4 / reading 0.1 / manual 1.0；
     对话证据不得单独把节点推过 2 级（familiar），避免"假精度"。
  3. **低置信不写库**：confidence < MIN_EVIDENCE_CONFIDENCE 直接丢弃并计数。
  4. **撤销可重放**：revoke 后按剩余有效证据重放，结果与顺序无关（不变量 6）。

表：`lr_evidence_events`（spec 003 data-model §0，新建）。
"""
from __future__ import annotations

import hashlib
import uuid
from datetime import datetime, timedelta

from sqlalchemy import select

from services.learning_db import session_scope
from model.models_learning import EvidenceEvent, MasteryRecord

# 来源权重（spec 003 FR-114）
SOURCE_WEIGHT = {
    "quiz": 1.0,
    "feynman": 0.8,
    "manual": 1.0,
    "dialogue": 0.4,
    "reading": 0.1,
}

# 低置信阈值：低于此值的证据不写库（FR-115）
MIN_EVIDENCE_CONFIDENCE = 0.6

# 同一题 7 天内重复作答不计分（FR-123）
REPEAT_WINDOW_DAYS = 7

# 对话证据单独作用时的证据强度上限（不许单靠对话跨到 familiar 以上）
DIALOGUE_ONLY_MAX_LEVEL = 2

_LEVELS = ["unseen", "beginner", "familiar", "proficient", "mastered"]


def _uuid() -> str:
    return uuid.uuid4().hex


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


def dedupe_key(user_id: str, node_id: str, source: str, ref: str) -> str:
    """幂等键：同一来源同一引用（题号/会话轮次/批注 id）只算一次（FR-114）。"""
    raw = f"{user_id}|{node_id}|{source}|{ref}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:40]


async def add_evidence(user_id: str, route_id: str, node_id: str,
                       source: str, judgement: str,
                       ref: str = "", confidence: float = 1.0,
                       error_type: str = "", strength: float | None = None,
                       counts_toward_mastery: bool = True) -> dict:
    """写一条证据。返回 {written, reason, evidence_id}。

    judgement ∈ correct | partial | wrong | engaged
    - confidence < MIN_EVIDENCE_CONFIDENCE → 丢弃（reason=low_confidence）
    - 幂等键已存在 → 丢弃（reason=duplicate）
    - 7 天内同 ref 重复作答 → 写入但 counts_toward_mastery=False
    """
    if source not in SOURCE_WEIGHT:
        return {"written": False, "reason": "unknown_source"}

    if confidence < MIN_EVIDENCE_CONFIDENCE:
        return {"written": False, "reason": "low_confidence"}

    key = dedupe_key(user_id, node_id, source, ref or _uuid())
    now = datetime.utcnow()

    if counts_toward_mastery and source == "quiz" and ref:
        win_start = now - timedelta(days=REPEAT_WINDOW_DAYS)
        async with session_scope() as s:
            res = await _exec(s, select(EvidenceEvent).where(
                EvidenceEvent.user_id == user_id,
                EvidenceEvent.node_id == node_id,
                EvidenceEvent.ref == ref,
                EvidenceEvent.created_at >= win_start,
                EvidenceEvent.revoked_at.is_(None),
            ))
            if res.scalars().first() is not None:
                counts_toward_mastery = False

    async with session_scope() as s:
        res = await _exec(s, select(EvidenceEvent).where(EvidenceEvent.dedupe_key == key))
        if res.scalars().first() is not None:
            return {"written": False, "reason": "duplicate"}

        ev = EvidenceEvent(
            id=_uuid(), user_id=user_id, route_id=route_id, node_id=node_id,
            source=source, judgement=judgement, ref=ref or "",
            confidence=float(confidence),
            strength=float(strength if strength is not None else SOURCE_WEIGHT[source]),
            error_type=error_type or "",
            counts_toward_mastery=bool(counts_toward_mastery),
            dedupe_key=key, created_at=now,
        )
        s.add(ev)
        await _flush(s)
        ev_id = ev.id

    # 只有计分证据才触发掌握度重算
    if counts_toward_mastery:
        await recompute(user_id, route_id, node_id)

    return {"written": True, "reason": "", "evidence_id": ev_id,
            "counts_toward_mastery": counts_toward_mastery}


async def revoke(evidence_id: str, user_id: str) -> dict:
    """撤销证据并重算（FR-115）。只允许撤销自己的证据。"""
    async with session_scope() as s:
        res = await _exec(s, select(EvidenceEvent).where(
            EvidenceEvent.id == evidence_id, EvidenceEvent.user_id == user_id))
        ev = res.scalars().first()
        if ev is None:
            return {"ok": False, "reason": "not_found"}
        if ev.revoked_at is not None:
            return {"ok": True, "already_revoked": True, "node_id": ev.node_id}
        ev.revoked_at = datetime.utcnow()
        route_id, node_id = ev.route_id, ev.node_id
        await _flush(s)

    state = await recompute(user_id, route_id, node_id)
    return {"ok": True, "already_revoked": False, "node_id": node_id, "state": state}


async def list_evidence(user_id: str, node_id: str, include_revoked: bool = False) -> list[dict]:
    stmt = select(EvidenceEvent).where(
        EvidenceEvent.user_id == user_id, EvidenceEvent.node_id == node_id)
    if not include_revoked:
        stmt = stmt.where(EvidenceEvent.revoked_at.is_(None))
    async with session_scope() as s:
        res = await _exec(s, stmt)
        rows = list(res.scalars().all())
    rows.sort(key=lambda r: r.created_at or datetime.min)
    return [{
        "id": r.id, "source": r.source, "judgement": r.judgement,
        "confidence": r.confidence, "error_type": r.error_type,
        "counts_toward_mastery": r.counts_toward_mastery,
        "created_at": r.created_at.isoformat() if r.created_at else "",
        "revoked_at": r.revoked_at.isoformat() if r.revoked_at else "",
    } for r in rows]


def _evidence_to_basis(events: list[dict]) -> dict:
    """把一组有效证据映射回 MasteryRecord 的五分量（重放核心，顺序无关）。

    - accuracy   : 来自 quiz/feynman/manual 的加权正确率（0..1）
    - difficulty : 来自 quiz 的难度加权（此处用平均 confidence 近似题目区分度）
    - stability  : 由证据条数与跨度决定（越多越稳，上限 1）
    - dialogue   : 对话类证据的加权正答率
    - feynman    : 费曼类证据的加权得分
    """
    def _w(ev):
        return SOURCE_WEIGHT.get(ev["source"], 0.1) * float(ev.get("confidence") or 1.0)

    def _val(ev):
        return {"correct": 1.0, "partial": 0.5, "wrong": 0.0, "engaged": 0.5}.get(
            ev["judgement"], 0.5)

    basis: dict = {}

    testing = [e for e in events if e["source"] in ("quiz", "manual", "feynman")]
    if testing:
        num = sum(_w(e) * _val(e) for e in testing)
        den = sum(_w(e) for e in testing)
        basis["accuracy"] = round(num / den, 4) if den else 0.0
        basis["difficulty"] = round(
            sum(float(e.get("confidence") or 1.0) for e in testing) / len(testing), 4)

    dialogue = [e for e in events if e["source"] == "dialogue"]
    if dialogue:
        num = sum(_w(e) * _val(e) for e in dialogue)
        den = sum(_w(e) for e in dialogue)
        basis["dialogue"] = round(num / den, 4) if den else 0.0

    feyn = [e for e in events if e["source"] == "feynman"]
    if feyn:
        num = sum(_w(e) * _val(e) for e in feyn)
        den = sum(_w(e) for e in feyn)
        basis["feynman"] = round(num / den, 4) if den else 0.0

    scored = [e for e in events if e.get("counts_toward_mastery", True)]
    if scored:
        basis["stability"] = round(min(1.0, len(scored) / 5.0), 4)

    return basis


async def recompute(user_id: str, route_id: str, node_id: str) -> dict:
    """按剩余有效证据重放，写回 MasteryRecord（不变量 6：顺序无关）。"""
    from services import mastery_service as ms

    async with session_scope() as s:
        res = await _exec(s, select(EvidenceEvent).where(
            EvidenceEvent.user_id == user_id,
            EvidenceEvent.node_id == node_id,
            EvidenceEvent.revoked_at.is_(None),
        ))
        rows = list(res.scalars().all())

    events = [{
        "source": r.source, "judgement": r.judgement,
        "confidence": r.confidence,
        "counts_toward_mastery": r.counts_toward_mastery,
    } for r in rows if r.counts_toward_mastery]
    basis = _evidence_to_basis(events)
    score = ms.compute_score(basis)
    level = ms.level_from_score(score, basis)

    # 对话证据单独作用时的上限保护
    only_dialogue = all(e["source"] == "dialogue" for e in events) if events else False
    if only_dialogue and _LEVELS.index(level) > DIALOGUE_ONLY_MAX_LEVEL:
        level = _LEVELS[DIALOGUE_ONLY_MAX_LEVEL]

    confidence = _confidence_from_evidence(events)

    async with session_scope() as s:
        res = await _exec(s, select(MasteryRecord).where(
            MasteryRecord.user_id == user_id,
            MasteryRecord.node_id == node_id,
            MasteryRecord.route_id == route_id,
        ))
        rec = res.scalars().first()
        if rec is None:
            rec = MasteryRecord(user_id=user_id, node_id=node_id, route_id=route_id,
                                basis={}, source_flags={})
            s.add(rec)
        rec.basis = basis
        rec.score = score
        rec.level = level
        rec.confidence = confidence
        await _flush(s)

    return {"node_id": node_id, "level": level, "score": score,
            "confidence": confidence, "evidence_count": len(events)}


def _confidence_from_evidence(events: list[dict]) -> float:
    """贝叶斯近似：证据越多、来源越硬，置信度越高（D2）。"""
    if not events:
        return 0.0
    k = sum(SOURCE_WEIGHT.get(e["source"], 0.1) for e in events)
    # 1 - exp(-k/2)：k=0.4→0.18, k=1→0.39, k=2→0.63, k=4→0.86
    import math
    return round(1 - math.exp(-k / 2.0), 4)
