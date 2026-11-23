"""BadgeService — spec 001 勋章系统（学习勋章）

职责：
1. ``collect_metrics``：从既有学情表聚合 8 项勋章指标快照（口径复用
   motivation / mastery / quiz / route 等服务，不另起炉灶）。
2. ``evaluate``：达成检测 + 幂等授予（``lr_user_badges`` 唯一约束兜底），
   返回新授予勋章列表，供事件响应携带 ``badges_awarded``。
3. ``mine`` / ``unseen`` / ``mark_read``：「我的勋章」页与首页提醒的数据源。

事件挂接（见 spec FR-03）：答题提交 / 复习提交 / 对话完成 / 路线页加载 /
动机结算，均调用 ``evaluate``，source_event 仅作审计与展示。
"""
from __future__ import annotations

import logging
from datetime import datetime

from sqlalchemy import select, update

from content import badges as badge_catalog
from content.routes import ROUTES, sections_for_route, get_section
from model.models_learning import (
    UserBadge, MasteryRecord, QuizAttempt, ReviewLog, LearningProgress,
)
from services import dialogue_store
from services.learning_db import session_scope
from services.motivation_service import _estimate_streak, _milestones

logger = logging.getLogger(__name__)

# 指标键 → 中文名（用于 condition_text / 进度展示）
_METRIC_LABELS = {
    "mastered_count": "掌握知识点",
    "journey_count": "贯通知识点",
    "milestones_achieved": "达成里程碑",
    "quiz_correct_total": "累计答对题",
    "quiz_attempt_total": "累计作答题",
    "routes_completed": "完成路线",
    "streak_days": "连续学习",
    "dialogues_completed": "完成对话",
}


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
    """> 兼容 async/sync 会话的 flush（AsyncSession.flush 是协程）。"""
    if _is_async_session(s):
        await s.flush()
    else:
        s.flush()


def _utc_iso(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def condition_text(bdef: badge_catalog.BadgeDef) -> str:
    """生成人类可读的达成条件文案（契约 condition_text 字段）。"""
    if bdef.condition_type == "threshold":
        return f"{_METRIC_LABELS[bdef.metric_key]} ≥ {bdef.threshold}"
    if bdef.condition_type == "ratio":
        pct = int(round(float(bdef.accuracy_threshold) * 100))
        return (f"{_METRIC_LABELS[bdef.metric_key]} ≥ {bdef.threshold} "
                f"且正确率 ≥ {pct}%")
    return "完成当前系统内全部已开放路线"


# ---------------------------------------------------------------- 指标聚合

async def collect_metrics(user_id: str) -> dict:
    """聚合 8 项勋章指标快照（全局口径，跨全部路线去重）。

    单会话聚合：原先拆 5+ 个 session_scope，在 StaticPool+aiosqlite 下高频
    开合会话会触发连接失效重建（空内存库→no such table）。合并为一次会话，
    指标口径不变；路线完成度在内存复算，复用 mastery_service 判定口径。
    """
    async with session_scope() as s:
        # 掌握度：mastered_count = 已掌握知识点去重数；journey_count = 进入过学习的知识点去重数
        # 同时取 score + route_id（路线完成度内存复算需要）
        m_res = await _exec(s, select(
            MasteryRecord.node_id, MasteryRecord.level,
            MasteryRecord.route_id, MasteryRecord.score,
        ).where(MasteryRecord.user_id == user_id))
        m_rows = m_res.all()
        # 测验作答
        att_res = await _exec(s, select(QuizAttempt.is_correct, QuizAttempt.created_at).where(
            QuizAttempt.user_id == user_id))
        attempts = att_res.all()
        # 复习作答（与测验同计入「累计答对/作答」，FR-02 口径）
        rev_res = await _exec(s, select(ReviewLog.correct).where(ReviewLog.user_id == user_id))
        reviews = rev_res.all()
        # 学习进度（路线完成度内存复算用）
        lp_res = await _exec(s, select(
            LearningProgress.route_id, LearningProgress.section_id,
            LearningProgress.status, LearningProgress.current_anchor,
        ).where(LearningProgress.user_id == user_id))
        lp_rows = lp_res.all()

    # 掌握度统计 + 按路线分组（内存复算路线完成度用）
    nodes_mastered: set[str] = set()
    nodes_touched: set[str] = set()
    mastery_by_route: dict[str, dict[str, dict]] = {}
    for node_id, level, route_id, score in m_rows:
        nodes_touched.add(node_id)
        if level == "mastered":
            nodes_mastered.add(node_id)
        mastery_by_route.setdefault(route_id, {})[node_id] = {
            "node_id": node_id, "level": level, "score": score,
        }
    mastered_count = len(nodes_mastered)
    journey_count = len(nodes_touched)

    # 测验作答
    quiz_attempt_quiz = len(attempts)
    quiz_correct_quiz = sum(1 for a in attempts if a[0])
    # 连续学习天数：与动机系统同口径（按测验作答日期回溯）
    streak_days = _estimate_streak([_RowDate(a[1]) for a in attempts])

    # 复习作答
    review_attempt = len(reviews)
    review_correct = sum(1 for r in reviews if r[0])

    quiz_attempt_total = quiz_attempt_quiz + review_attempt
    quiz_correct_total = quiz_correct_quiz + review_correct

    # 里程碑：复用动机系统步骤定义（master/streak/attempts），全局口径计数已达成数
    milestones = _milestones(mastered_count, streak_days, quiz_attempt_total)
    milestones_achieved = sum(1 for m in milestones if m["achieved"])

    # 路线完成数：内存复算（单会话内已取回 mastery + learning progress）
    routes_completed = _routes_completed_in_memory(mastery_by_route, lp_rows)

    # 对话完成数：进程内对话历史中「有用户提问且有 AI 回复」的会话数
    dialogues_completed = _dialogues_completed(user_id)

    return {
        "mastered_count": mastered_count,
        "journey_count": journey_count,
        "milestones_achieved": milestones_achieved,
        "quiz_correct_total": quiz_correct_total,
        "quiz_attempt_total": quiz_attempt_total,
        "routes_completed": routes_completed,
        "streak_days": streak_days,
        "dialogues_completed": dialogues_completed,
    }


class _RowDate:
    """轻量适配对象：把 (is_correct, created_at) 行元组喂给 _estimate_streak。"""
    __slots__ = ("created_at",)

    def __init__(self, created_at):
        self.created_at = created_at


def _routes_completed_in_memory(
    mastery_by_route: dict[str, dict[str, dict]],
    lp_rows,
) -> int:
    """完成路线数：路线内全部章节均 completed（内存复算，复用 mastery_service 口径）。

    - 有知识点章节：掌握分 ≥ 章节 unlock_threshold 即完成（同 section_mastery_score）。
    - 无知识点章节（占位章）：LearningProgress status ∈ {completed, done} 或
      current_anchor>0 视为完成（同 section_progress 降级判定）。
    """
    from content.knowledge_graph import nodes_by_section
    from services.mastery_service import section_mastery_score

    # 学习进度按 route -> section 分组
    progress_by_route: dict[str, dict[str, dict]] = {}
    for route_id, section_id, status, anchor in lp_rows:
        progress_by_route.setdefault(route_id, {})[section_id] = {
            "exists": True,
            "status": status or "",
            "anchor": int(anchor or 0),
        }

    done = 0
    for route in ROUTES:
        rid = route["id"]
        secs = sections_for_route(rid)
        if not secs:
            continue
        m_map = mastery_by_route.get(rid, {})
        p_map = progress_by_route.get(rid, {})
        all_done = True
        for s in secs:
            sid = s["id"]
            nodes = nodes_by_section(sid)
            if nodes:
                score = section_mastery_score(m_map, sid)
                cur = get_section(sid)
                threshold = cur.get("unlock_threshold", 0.8) if cur else 0.8
                if score < threshold:
                    all_done = False
                    break
            else:
                p = p_map.get(sid)
                sec_done = bool(p) and (
                    p.get("status") in ("completed", "done")
                    or int(p.get("anchor", 0) or 0) > 0
                )
                if not sec_done:
                    all_done = False
                    break
        if all_done:
            done += 1
    return done


def _dialogues_completed(user_id: str) -> int:
    """完成对话数：有用户提问且有 AI 回复的会话数（进程内历史，与对话历史页同源）。"""
    n = 0
    for d in dialogue_store.list_dialogues(user_id):
        msgs = dialogue_store.get_messages(d["id"])
        has_user = any(m.get("role") == "user" for m in msgs)
        has_ai = any(m.get("role") == "assistant" for m in msgs)
        if has_user and has_ai:
            n += 1
    return n


# ---------------------------------------------------------------- 达成判定

def _is_achieved(bdef: badge_catalog.BadgeDef, metrics: dict, total_routes: int) -> bool:
    """按条件类型判定单枚勋章是否达成。"""
    if bdef.condition_type == "threshold":
        return metrics.get(bdef.metric_key, 0) >= bdef.threshold
    if bdef.condition_type == "ratio":
        primary = metrics.get(bdef.metric_key, 0)
        if primary < bdef.threshold or primary <= 0:
            return False
        secondary = metrics.get(bdef.ratio_metric or "", 0)
        return (secondary / primary) >= float(bdef.accuracy_threshold)
    if bdef.condition_type == "completion":
        # route_all：完成全部已开放路线（路线总数 0 时不可达）
        return total_routes > 0 and metrics.get("routes_completed", 0) >= total_routes
    return False


def _award_dict(award_id: str, bdef: badge_catalog.BadgeDef,
                awarded_at: datetime, source_event: str) -> dict:
    return {
        "award_id": award_id,
        "badge_id": bdef.badge_id,
        "name": bdef.name,
        "description": bdef.description,
        "category": bdef.category,
        "condition_text": condition_text(bdef),
        "icon_key": bdef.icon_key,
        "awarded_at": _utc_iso(awarded_at),
        "source_event": source_event,
    }


# ---------------------------------------------------------------- 授予引擎

async def evaluate(user_id: str, source_event: str = "") -> list[dict]:
    """达成检测 + 幂等授予，返回新授予的勋章列表（无新授予返回 []）。

    已在授予列表中的勋章不会重复授予（唯一约束 + 先查后写双保险）。
    """
    metrics = await collect_metrics(user_id)
    total_routes = len(ROUTES)
    now = datetime.utcnow()
    newly: list[dict] = []
    async with session_scope() as s:
        res = await _exec(s, select(UserBadge).where(UserBadge.user_id == user_id))
        granted_ids = {r.badge_id for r in res.scalars().all()}
        for bdef in badge_catalog.all_badges(enabled_only=True):
            if bdef.badge_id in granted_ids:
                continue
            if not _is_achieved(bdef, metrics, total_routes):
                continue
            row = UserBadge(user_id=user_id, badge_id=bdef.badge_id,
                            awarded_at=now, source_event=source_event)
            s.add(row)
            await _flush(s)
            granted_ids.add(bdef.badge_id)
            newly.append(_award_dict(row.id, bdef, now, source_event))
    return newly


async def _granted_map(s, user_id: str) -> dict[str, dict]:
    """查询用户全部授予记录：badge_id -> {award_id, awarded_at, source_event, read_flag}。"""
    res = await _exec(s, select(UserBadge).where(UserBadge.user_id == user_id))
    out: dict[str, dict] = {}
    for r in res.scalars().all():
        out[r.badge_id] = {
            "award_id": r.id,
            "awarded_at": _utc_iso(r.awarded_at) if r.awarded_at else None,
            "source_event": r.source_event or "",
            "read_flag": bool(r.read_flag),
        }
    return out


# ---------------------------------------------------------------- 查询 API

def _progress_for(bdef: badge_catalog.BadgeDef, metrics: dict, total_routes: int) -> dict:
    """按条件类型生成进度对象（契约 progress 字段规则）。"""
    if bdef.condition_type == "threshold":
        cur = metrics.get(bdef.metric_key, 0)
        return {"current": cur, "target": bdef.threshold, "display": f"{cur}/{bdef.threshold}"}
    if bdef.condition_type == "ratio":
        cur = metrics.get(bdef.metric_key, 0)
        acc = 0.0
        if cur > 0:
            acc = round(metrics.get(bdef.ratio_metric or "", 0) / cur, 3)
        pct = int(round(acc * 100))
        return {"current": cur, "target": bdef.threshold, "accuracy": acc,
                "display": f"作答 {cur}/{bdef.threshold}，正确率 {pct}%"}
    # completion（route_all）
    cur = metrics.get("routes_completed", 0)
    if total_routes <= 0:
        return {"current": 0, "target": 0, "display": "暂不可达"}
    return {"current": cur, "target": total_routes, "display": f"{cur}/{total_routes}"}


async def mine(user_id: str) -> dict:
    """「我的勋章」页数据：全部启用勋章 + 停用但已授予的 + 授予状态与进度。"""
    metrics = await collect_metrics(user_id)
    total_routes = len(ROUTES)
    async with session_scope() as s:
        granted = await _granted_map(s, user_id)
    out = []
    earned_count = 0
    for bdef in badge_catalog.all_badges(enabled_only=False):
        g = granted.get(bdef.badge_id)
        earned = g is not None
        if earned and bdef.enabled:
            earned_count += 1
        item = {
            "badge_id": bdef.badge_id,
            "name": bdef.name,
            "description": bdef.description,
            "category": bdef.category,
            "condition_text": condition_text(bdef),
            "icon_key": bdef.icon_key,
            "earned": earned,
            "awarded_at": g["awarded_at"] if g else None,
            "source_event": g["source_event"] if g else None,
            "read": g["read_flag"] if g else False,
            "progress": _progress_for(bdef, metrics, total_routes),
        }
        if not bdef.enabled:
            item["disabled"] = True
        out.append(item)
    total = badge_catalog.total_count(enabled_only=True)
    return {
        "metrics": metrics,
        "badges": out,
        "summary": {"total": total, "earned": earned_count,
                    "unearned": total - earned_count},
    }


async def unseen(user_id: str) -> dict:
    """未查看的新勋章（首页提醒 / 动画触发兜底），按授予时间倒序。"""
    async with session_scope() as s:
        res = await _exec(s, select(UserBadge).where(
            UserBadge.user_id == user_id, UserBadge.read_flag.is_(False)).order_by(
            UserBadge.awarded_at.desc()))
        rows = res.scalars().all()
    awards = []
    for r in rows:
        bdef = badge_catalog.get_badge(r.badge_id)
        if bdef is None:
            continue
        awards.append(_award_dict(r.id, bdef, r.awarded_at or datetime.utcnow(),
                                  r.source_event or ""))
    return {"awards": awards, "count": len(awards)}


async def mark_read(user_id: str, award_ids: list[str]) -> int:
    """标记已查看；不存在的 award_id 静默忽略，返回实际更新数。"""
    if not award_ids:
        return 0
    async with session_scope() as s:
        res = await _exec(s, update(UserBadge)
                          .where(UserBadge.user_id == user_id,
                                 UserBadge.id.in_(award_ids),
                                 UserBadge.read_flag.is_(False))
                          .values(read_flag=True))
    return res.rowcount or 0
