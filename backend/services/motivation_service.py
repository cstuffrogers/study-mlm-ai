"""MotivationService — 动机与挫折调节（P3，D14）

学习系统不能只判分；持续低分/反复卡顿会引发挫败与放弃。本服务把「挫折信号 +
近期正确率 + 复习积压」折算成挫折度，给出分级的鼓励语、里程碑成就与「最小可行
下一步」（easy win），在受挫时降低认知负荷、重建信心，在顺利时点亮里程碑维持动机。
"""
from __future__ import annotations

from datetime import datetime, timedelta

from sqlalchemy import select

from services.learning_db import session_scope
from services import mastery_service as ms
from services import review_service
from content.knowledge_graph import KNOWLEDGE_NODES
from content.routes import SECTIONS
from model.models_learning import QuizAttempt, StruggleSignal

# section_id -> 章节摘要，用于把知识点关联到所属书籍（work/title/work_short）
_SECTION_INDEX = {s["id"]: s for s in SECTIONS}


def _node_brief(n: dict, m_map: dict) -> dict:
    """知识点摘要：关联所属书籍，附掌握度。"""
    sec = _SECTION_INDEX.get(n.get("section_id", ""), {})
    rec = m_map.get(n["id"], {})
    return {
        "node_id": n["id"],
        "name": n["name"],
        "section_id": n.get("section_id", ""),
        "work": sec.get("work", ""),
        "work_short": sec.get("work_short", ""),
        "title": sec.get("title", ""),
        "score": round(rec.get("score", 0.0), 3),
        "level": rec.get("level", "unseen"),
    }

# 里程碑定义（key, 文案, 达成条件由 _milestones 计算）
_MASTER_STEPS = [1, 3, 6, len(KNOWLEDGE_NODES)]
_STREAK_STEPS = [3, 7]


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


def _clamp(x, lo=0.0, hi=1.0):
    return max(lo, min(hi, x))


async def motivation_state(user_id: str, route_id: str) -> dict:
    # 1) 挫折信号（近 14 天）
    since = datetime.utcnow() - timedelta(days=14)
    async with session_scope() as s:
        sig_res = await _exec(s, select(StruggleSignal).where(StruggleSignal.user_id == user_id))
        signals = [x for x in sig_res.scalars().all()
                   if (x.created_at or datetime.utcnow()) >= since]
        att_res = await _exec(s, select(QuizAttempt).where(QuizAttempt.user_id == user_id))
        attempts = list(att_res.scalars().all())

    struggle_load = _clamp(sum((x.intensity or 0.0) for x in signals) / 3.0)

    # 近期正确率（按 created_at 取最近 10 次）
    attempts.sort(key=lambda a: a.created_at or datetime.utcnow())
    recent = attempts[-10:]
    avg_recent = (sum(1.0 if a.is_correct else 0.0 for a in recent) / len(recent)) if recent else None

    # 掌握 / 复习
    m_map = await ms.get_mastery_map(user_id, route_id)
    mastered = sum(1 for n in KNOWLEDGE_NODES if m_map.get(n["id"], {}).get("level") == "mastered")
    proficient = sum(1 for n in KNOWLEDGE_NODES
                     if m_map.get(n["id"], {}).get("level") in ("proficient", "mastered"))
    status = await review_service.review_status(user_id, route_id)
    due_count = status["due_count"]

    # 2) 挫折度
    acc_part = 0.0 if avg_recent is None else (1.0 - avg_recent)
    backlog_part = _clamp(due_count / 10.0)
    frustration = round(_clamp(0.5 * struggle_load + 0.35 * acc_part + 0.15 * backlog_part), 3)
    level = "high" if frustration >= 0.6 else "mid" if frustration >= 0.35 else "low"

    drivers = []
    if struggle_load >= 0.4:
        drivers.append(f"对话中反复卡顿（{len(signals)} 次）")
    if avg_recent is not None and avg_recent < 0.6:
        drivers.append(f"近期正确率偏低（{int(avg_recent*100)}%）")
    if due_count >= 5:
        drivers.append(f"待复习积压 {due_count} 项")

    # 3) 鼓励语
    encouragement = _encourage(level, avg_recent, mastered)

    # 4) 里程碑
    streak = _estimate_streak(attempts)
    milestones = _milestones(mastered, streak, len(attempts))

    # 5) 下一步（easy win 优先，降低受挫时负荷）
    next_best = _next_best_action(level, m_map, due_count, avg_recent)

    # 6) 已掌握 / 薄弱知识点列表（供前端「进度平稳」卡片点击展开查看）
    mastered_nodes = [_node_brief(n, m_map) for n in KNOWLEDGE_NODES
                      if m_map.get(n["id"], {}).get("level") == "mastered"]
    weak_nodes = [_node_brief(n, m_map) for n in KNOWLEDGE_NODES
                  if m_map.get(n["id"], {}).get("level") in ("unseen", "beginner")]

    return {
        "route_id": route_id,
        "frustration": {"level": level, "score": frustration, "drivers": drivers},
        "encouragement": encouragement,
        "avg_recent_accuracy": None if avg_recent is None else round(avg_recent, 3),
        "mastered": mastered,
        "proficient": proficient,
        "weak": len(weak_nodes),
        "due_count": due_count,
        "streak_days": streak,
        "milestones": milestones,
        "next_best_action": next_best,
        "mastered_nodes": mastered_nodes,
        "weak_nodes": weak_nodes,
    }


def _encourage(level: str, avg_recent, mastered: int) -> str:
    if level == "high":
        return ("别急，卡住的时候正是大脑在重新布线。先把目标缩小：挑一个已经会的知识点快速复习，"
                "找回手感，再回来啃难点——进步往往藏在'再来一次'里。")
    if level == "mid":
        if avg_recent is not None and avg_recent >= 0.7:
            return "节奏在变好，最近的正确率说明方法有效。保持这种小步快跑的节奏，难点会一个个攻下来。"
        return "遇到一点阻力很正常。把注意力放在'今天弄懂一个概念'而不是'一次全懂'，累积会带来质变。"
    if mastered > 0:
        return f"状态在线，你已经贯通 {mastered} 个知识点，乘胜追击，把相邻的薄弱点也拿下。"
    return "开局不错，保持好奇和追问。理解马克思的问题意识，比记住结论更重要。"


def _next_best_action(level: str, m_map: dict, due_count: int, avg_recent) -> dict:
    if level == "high":
        # 找一个已掌握/熟悉节点做 easy win 重建信心
        for n in KNOWLEDGE_NODES:
            lv = m_map.get(n["id"], {}).get("level")
            if lv in ("proficient", "mastered"):
                return {"kind": "easy_win", "node_id": n["id"],
                        "label": f"快速复习《{n['name']}》找回手感",
                        "reason": "受挫时先用已掌握内容重建信心，再挑战难点"}
        return {"kind": "break", "label": "先休息 5 分钟",
                "reason": "连续受挫时短暂离开有助于恢复专注与情绪"}
    if due_count > 0:
        return {"kind": "light_review", "label": f"做一轮交错复习（{due_count} 项到期）",
                "reason": "先清掉遗忘积压，避免越学越乱"}
    if avg_recent is not None and avg_recent >= 0.8:
        return {"kind": "keep_going", "label": "推进下一节或新知识点",
                "reason": "掌握扎实，可以适度加大挑战"}
    return {"kind": "reinforce", "label": "回补当前最薄弱的知识点",
            "reason": "先把地基夯实，再向上搭建"}


def _milestones(mastered: int, streak: int, total_attempts: int) -> list[dict]:
    out = []
    for step in _MASTER_STEPS:
        out.append({"key": f"master_{step}", "label": f"目标：贯通 {step} 个知识点",
                    "category": "贯通", "achieved": mastered >= step})
    for step in _STREAK_STEPS:
        out.append({"key": f"streak_{step}", "label": f"目标：连续学习 {step} 天",
                    "category": "连续学习", "achieved": streak >= step})
    for step in (10, 25, 50):
        out.append({"key": f"attempts_{step}", "label": f"目标：累计作答 {step} 题",
                    "category": "累计作答", "achieved": total_attempts >= step})
    return out


def _estimate_streak(attempts: list) -> int:
    days = set()
    for a in attempts:
        c = getattr(a, "created_at", None)
        if c is not None:
            days.add(c.date())
    if not days:
        return 0
    streak = 0
    cur = datetime.utcnow().date()
    while cur in days:
        streak += 1
        cur = cur - timedelta(days=1)
    return streak
