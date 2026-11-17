"""ProfileService — 学情档案聚合 + 薄弱点排序 + 五维雷达 + AI 学习总结

薄弱点排序 key（D4）：(1-score) × 依赖出度 × 考频权重；
blocking_sections：该点未掌握会阻塞的其他章节数（KnowledgeGraphService）。
能力雷达：五维（materialism/dialectics/epistemology/historical_materialism/political_economy）
= 该维度下知识点 score 均值。
"""
from __future__ import annotations

from datetime import datetime

from sqlalchemy import select

from services.learning_db import session_scope
from services import mastery_service as ms
from services.knowledge_graph_service import get_kg
from content.knowledge_graph import KNOWLEDGE_NODES
from model.models_learning import LearningProfile

_DIMS = ("materialism", "dialectics", "epistemology", "historical_materialism", "political_economy")


async def build_profile(user_id: str, route_id: str) -> dict:
    m_map = await ms.get_mastery_map(user_id, route_id)
    kg = get_kg()

    # 能力雷达
    radar = {d: [] for d in _DIMS}
    for n in KNOWLEDGE_NODES:
        dim = n["ability_dim"]
        if dim in radar:
            radar[dim].append(m_map.get(n["id"], {}).get("score", 0.0))
    ability_radar = {d: round(sum(v) / len(v), 4) if v else 0.0 for d, v in radar.items()}

    # 薄弱点排序
    weak = []
    _ERR_LABEL = {
        "stance_deviation": "立场偏差",
        "concept_layer_confusion": "概念层次混淆",
        "real_unknown": "知识盲点",
        "concept_application": "应用迁移不足",
        "term_misuse": "术语误用",
    }
    for n in KNOWLEDGE_NODES:
        rec = m_map.get(n["id"])
        score = rec["score"] if rec else 0.0
        if score >= 0.8:
            continue
        key = (1 - score) * (1 + kg.dependents_count(n["id"])) * n["exam_weight"]
        err_cat = (rec or {}).get("basis", {}).get("error_category", "")
        err_label = _ERR_LABEL.get(err_cat, "")
        reason = "掌握度低×依赖出度高×考频高"
        if err_label:
            reason = f"{err_label}×掌握度低×依赖出度高×考频高"
        weak.append({
            "node_id": n["id"], "name": n["name"],
            "score": score, "level": rec["level"] if rec else "unseen",
            "section_id": n["section_id"],
            "error_category": err_cat,
            "reason": reason,
            "blocking_sections": kg.blocking_sections(n["id"]),
            "_rank": round(key, 4),
        })
    # D136：并列按 node_id 升序落定（原先只有 `reverse=True`，同 rank 的先后取决于
    # KNOWLEDGE_NODES 的定义顺序，单机侧则是 Map 迭代序 —— 同一份数据显示两种排法）。
    weak.sort(key=lambda x: (-x["_rank"], x["node_id"]))
    for w in weak:
        w.pop("_rank", None)

    # 掌握度分布
    dist = {"unseen": 0, "beginner": 0, "familiar": 0, "proficient": 0, "mastered": 0}
    for n in KNOWLEDGE_NODES:
        lv = m_map.get(n["id"], {}).get("level", "unseen")
        dist[lv] = dist.get(lv, 0) + 1

    summary = _summary_text(weak)

    # 持久化档案
    async with session_scope() as s:
        res = await _exec(s, select(LearningProfile).where(
            LearningProfile.user_id == user_id, LearningProfile.route_id == route_id))
        prof = res.scalars().first()
        if prof is None:
            prof = LearningProfile(user_id=user_id, route_id=route_id)
            s.add(prof)
        prof.ability_radar = ability_radar
        prof.weak_points = weak
        prof.summary_text = summary
        prof.updated_at = datetime.utcnow()
        await _flush(s)

    return {"route_id": route_id, "ability_radar": ability_radar,
            "weak_points": weak, "mastery_distribution": dist,
            "summary": summary, "updated_at": datetime.utcnow().isoformat()}


def _summary_text(weak: list[dict]) -> str:
    if not weak:
        return "暂无薄弱点，继续保持！"
    top = weak[0]
    return f"当前最需补强：{top['name']}（掌握度{top['score']}，阻塞{top['blocking_sections']}章）；建议优先专项复习。"


async def generate_summary(user_id: str, route_id: str, period: str = "week") -> dict:
    """AI 学习总结反馈（已掌握/待巩固/下一步 + source_tags 数据来源）"""
    m_map = await ms.get_mastery_map(user_id, route_id)
    mastered, to_reinforce = [], []
    source_tags: dict[str, str] = {}
    for n in KNOWLEDGE_NODES:
        rec = m_map.get(n["id"])
        if not rec:
            continue
        if rec["score"] >= 0.8:
            mastered.append(n["name"])
            source_tags[n["name"]] = ",".join(k for k, v in (rec.get("source_flags") or {}).items() if v) or "quiz"
        elif rec["score"] < 0.45:
            to_reinforce.append(n["name"])
            source_tags[n["name"]] = ",".join(k for k, v in (rec.get("source_flags") or {}).items() if v) or "quiz"
    next_step = "从薄弱章节专项复习" if to_reinforce else "进入下一章学习"
    if to_reinforce:
        next_step = f"建议先补强《{to_reinforce[0]}》相关知识点"
    text = f"已掌握{len(mastered)}项；待巩固{len(to_reinforce)}项。下一步：{next_step}。"
    return {"route_id": route_id, "period": period, "mastered": mastered,
            "to_reinforce": to_reinforce, "next_step": next_step,
            "summary": text, "source_tags": source_tags}


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
