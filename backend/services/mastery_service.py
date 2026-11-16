"""MasteryService — 掌握度计算与学情信号融合（D1）

掌握分 = 各分项加权的『已存在分量归一化』：
  accuracy / difficulty / stability / dialogue / feynman
  score = Σ(wᵢ·vᵢ) / Σ(wᵢ, 仅已存在分量)
五级映射见 config.MASTERY_THRESHOLDS；mastered 额外要求 feynman 通过（近似 data-model）。

学情双信号：测试（写 accuracy/difficulty/stability）+ 对话（写 dialogue）+ 费曼（写 feynman）。
"""
from __future__ import annotations

from datetime import datetime

from sqlalchemy import select

from core.config import MASTERY_WEIGHTS, MASTERY_THRESHOLDS
from services.learning_db import session_scope
from model.models_learning import MasteryRecord, StruggleSignal
from content.knowledge_graph import nodes_by_section

_WEIGHT_KEYS = ("accuracy", "difficulty", "stability", "dialogue", "feynman")


def compute_score(basis: dict) -> float:
    num = 0.0
    den = 0.0
    for k in _WEIGHT_KEYS:
        v = basis.get(k)
        if v is None:
            continue
        num += MASTERY_WEIGHTS[k] * float(v)
        den += MASTERY_WEIGHTS[k]
    return round(num / den, 4) if den > 0 else 0.0


def level_from_score(score: float, basis: dict | None = None) -> str:
    basis = basis or {}
    if score < MASTERY_THRESHOLDS["unseen"]:
        level = "unseen"
    elif score < MASTERY_THRESHOLDS["beginner"]:
        level = "beginner"
    elif score < MASTERY_THRESHOLDS["familiar"]:
        level = "familiar"
    elif score < MASTERY_THRESHOLDS["proficient"]:
        level = "proficient"
    else:
        level = "mastered"
    # mastered 需费曼通过，否则降为 proficient
    if level == "mastered":
        fey = basis.get("feynman")
        if fey is None or fey < 0.8:
            level = "proficient"
    return level


async def _get_record(s, user_id, node_id, route_id):
    res = await _execute(s, select(MasteryRecord).where(
        MasteryRecord.user_id == user_id,
        MasteryRecord.node_id == node_id,
        MasteryRecord.route_id == route_id,
    ))
    return res.scalars().first()


async def upsert_mastery(user_id: str, node_id: str, route_id: str,
                         basis_patch: dict, source: str, schedule_review: bool = False) -> dict:
    """合并分项 → 重算 score/level → 写库

    schedule_review=True 时（测试/复习产生 accuracy/stability），
    同步设置 last_reviewed_at 并按 stability 排下一次复习（D8 间隔复习）。
    """
    async with session_scope() as s:
        rec = await _get_record(s, user_id, node_id, route_id)
        if rec is None:
            rec = MasteryRecord(user_id=user_id, node_id=node_id, route_id=route_id,
                                basis={}, source_flags={})
            s.add(rec)
        basis = dict(rec.basis or {})
        for k, v in basis_patch.items():
            if v is None:
                continue
            basis[k] = v
        flags = dict(rec.source_flags or {})
        for k in basis_patch:
            flags[k] = source
        score = compute_score(basis)
        level = level_from_score(score, basis)
        rec.basis = basis
        rec.source_flags = flags
        rec.score = score
        rec.level = level
        if schedule_review:
            from services.review_service import schedule_next
            rec.last_reviewed_at = datetime.utcnow()
            rec.next_review_at = schedule_next(float(basis.get("stability", 0.0) or 0.0))
        rec.updated_at = datetime.utcnow()
        await _flush(s)
        return {"node_id": node_id, "score": score, "level": level, "basis": basis}


async def add_struggle_signal(user_id: str, node_id: str, signal_type: str,
                              intensity: float = 0.3, source: str = "dialogue") -> dict:
    """记录学情信号，并把 dialogue 分量拉低（信号越多 → dialogue 分越低）"""
    async with session_scope() as s:
        s.add(StruggleSignal(user_id=user_id, node_id=node_id, signal_type=signal_type,
                             intensity=intensity, source=source))
        await _flush(s)
    # 计算该节点累计信号强度 → dialogue 分量 (1 - 归一化强度)
    async with session_scope() as s:
        res = await _execute(s, select(StruggleSignal).where(
            StruggleSignal.user_id == user_id, StruggleSignal.node_id == node_id))
        signals = res.scalars().all()
        total = sum((x.intensity or 0.0) for x in signals)
        dialogue_score = max(0.0, 1.0 - min(1.0, total / 3.0))
    return {"dialogue_component": round(dialogue_score, 4), "signal_count": len(signals)}


async def sync_dialogue_mastery(user_id: str, node_id: str, route_id: str) -> dict:
    """把当前累计对话信号折算为 dialogue 分量并写回掌握度"""
    async with session_scope() as s:
        res = await _execute(s, select(StruggleSignal).where(
            StruggleSignal.user_id == user_id, StruggleSignal.node_id == node_id))
        signals = res.scalars().all()
        total = sum((x.intensity or 0.0) for x in signals)
        dialogue_score = max(0.0, 1.0 - min(1.0, total / 3.0))
    return await upsert_mastery(user_id, node_id, route_id,
                                {"dialogue": dialogue_score}, source="dialogue")


async def get_mastery_map(user_id: str, route_id: str) -> dict[str, dict]:
    async with session_scope() as s:
        res = await _execute(s, select(MasteryRecord).where(
            MasteryRecord.user_id == user_id, MasteryRecord.route_id == route_id))
        rows = res.scalars().all()
    return {r.node_id: {"node_id": r.node_id, "score": r.score, "level": r.level,
                        "basis": r.basis, "source_flags": r.source_flags,
                        "review_count": r.review_count or 0,
                        "last_reviewed_at": r.last_reviewed_at.isoformat() if r.last_reviewed_at else None,
                        "next_review_at": r.next_review_at.isoformat() if r.next_review_at else None}
            for r in rows}


def section_mastery_score(mastery_map: dict[str, dict], section_id: str) -> float:
    """章节掌握分 = 该章『已评估』知识点 score 均值；未评估的知识点不参与（避免拉低到 0）。
    全部未评估则返回 0。"""
    nodes = nodes_by_section(section_id)
    if not nodes:
        return 0.0
    assessed = [mastery_map[n["id"]]["score"] for n in nodes if n["id"] in mastery_map]
    if not assessed:
        return 0.0
    return round(sum(assessed) / len(assessed), 4)


async def progress_map(user_id: str, route_id: str) -> dict[str, dict]:
    """一次取回整条路线的学习进度（替代逐章查询）。

    路线页/选路都要对每章判完成度；无题库章原先每章开一次 session，
    十几章就是十几次数据库往返。这里一次查完，后续纯内存判断。
    """
    from model.models_learning import LearningProgress
    async with session_scope() as s:
        res = await _execute(s, select(LearningProgress).where(
            LearningProgress.user_id == user_id,
            LearningProgress.route_id == route_id))
        rows = res.scalars().all()
    out: dict[str, dict] = {}
    for p in rows:
        sid = getattr(p, "section_id", "") or ""
        if not sid or sid in out:
            continue
        out[sid] = {
            "exists": True,
            "status": getattr(p, "status", "") or "",
            "anchor": int(getattr(p, "current_anchor", "0") or 0),
        }
    return out


async def section_progress(user_id: str, route_id: str, section_id: str,
                           mastery_map: dict[str, dict] | None = None,
                           progress: dict[str, dict] | None = None) -> dict:
    """统一的章节完成度判定（修复无题库章节死锁）：
      - 有知识点的章节：掌握分 ≥ 门槛即完成；
      - 无知识点章节（占位章，降级为按段落学习）：以『已学完』(LearningProgress
        status ∈ {completed, done} 或 last_position>0）视为完成，避免永远卡在门槛前。
    返回 {bank, completed, score, threshold, assessed}。
    """
    from content.routes import get_section
    nodes = nodes_by_section(section_id)
    cur = get_section(section_id)
    threshold = cur.get("unlock_threshold", 0.8) if cur else 0.8
    if nodes:
        m_map = mastery_map if mastery_map is not None else await get_mastery_map(user_id, route_id)
        score = section_mastery_score(m_map, section_id)
        assessed = sum(1 for n in nodes if n["id"] in m_map)
        return {"bank": True, "completed": score >= threshold, "started": assessed > 0,
                "score": score, "threshold": threshold, "assessed": assessed}
    # 无知识点：按学习进度判定（可传入整条路线的批量进度，避免逐章查询）
    if progress is not None:
        p = progress.get(section_id)
    else:
        from model.models_learning import LearningProgress
        async with session_scope() as s:
            res = await _execute(s, select(LearningProgress).where(
                LearningProgress.user_id == user_id,
                LearningProgress.route_id == route_id,
                LearningProgress.section_id == section_id))
            row = res.scalars().first()
        p = None if row is None else {
            "exists": True,
            "status": getattr(row, "status", "") or "",
            "anchor": int(getattr(row, "current_anchor", "0") or 0),
        }
    done = bool(p) and (p.get("status", "") in ("completed", "done")
                        or int(p.get("anchor", 0) or 0) > 0)
    return {"bank": False, "completed": done, "started": bool(p), "score": 0.0,
            "threshold": threshold, "assessed": 0}


async def section_progress_all(user_id: str, route_id: str, section_ids: list[str],
                               mastery_map: dict[str, dict] | None = None) -> dict[str, dict]:
    """批量算整条路线每章进度：一次取掌握度 + （仅当有无题库章时）一次取学习进度。"""
    m_map = mastery_map if mastery_map is not None else await get_mastery_map(user_id, route_id)
    # 全是有题库章时不需要查 LearningProgress，避免多一次往返。
    progress = None
    if any(not nodes_by_section(sid) for sid in section_ids):
        progress = await progress_map(user_id, route_id)
    out: dict[str, dict] = {}
    for sid in section_ids:
        out[sid] = await section_progress(user_id, route_id, sid, m_map, progress)
    return out


def compute_gating(mastery_map: dict[str, dict], route_id: str, section_id: str) -> dict:
    """门控：本章『已评估』知识点得分 ≥ 门槛则解锁下一章；未达则返回需补强知识点。"""
    from content.routes import sections_for_route
    secs = sections_for_route(route_id)
    cur = next((x for x in secs if x["id"] == section_id), None)
    score = section_mastery_score(mastery_map, section_id)
    threshold = cur.get("unlock_threshold", 0.8) if cur else 0.8
    nodes = nodes_by_section(section_id)
    # 仅『已评估且低于门槛』的知识点视为需补强
    need = [n["id"] for n in nodes
            if n["id"] in mastery_map and mastery_map[n["id"]].get("score", 0.0) < threshold]
    assessed_count = sum(1 for n in nodes if n["id"] in mastery_map)
    # 找下一章
    next_id = None
    if cur:
        for x in secs:
            if x["order_index"] > cur["order_index"]:
                next_id = x["id"]
                break
    unlocked = (assessed_count > 0) and (score >= threshold)
    return {
        "section_id": section_id,
        "section_score": score,
        "threshold": threshold,
        "assessed_nodes": assessed_count,
        "next_section_id": next_id,
        "next_section_unlocked": unlocked,
        "need_reinforce": need,
    }


# ---- async/sync 适配
def _is_async_session(s) -> bool:
    try:
        from sqlalchemy.ext.asyncio import AsyncSession
        return isinstance(s, AsyncSession)
    except Exception:
        return False


async def _execute(s, stmt):
    if _is_async_session(s):
        return await s.execute(stmt)
    return s.execute(stmt)


async def _flush(s):
    if _is_async_session(s):
        await s.flush()
    else:
        s.flush()
