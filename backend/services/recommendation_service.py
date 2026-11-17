"""RecommendationService — 路径推荐 + 门控联动（D4 规则优先，可解释）

rec_type：start（起点）/ next_section（下一章）/ reinforce（回补）/ review（复习）
所有推荐必带一句话 reason。
"""
from __future__ import annotations



from services.learning_db import session_scope
from services import mastery_service as ms
from services.knowledge_graph_service import get_kg
from content.routes import sections_for_route, get_section
from content.knowledge_graph import KNOWLEDGE_NODES, get_node
from model.models_learning import Recommendation


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


async def _save(user_id, route_id, rec: dict) -> dict:
    async with session_scope() as s:
        s.add(Recommendation(user_id=user_id, route_id=route_id,
                             rec_type=rec["rec_type"],
                             target_section_id=rec.get("target_section_id", ""),
                             target_node_id=rec.get("target_node_id", ""),
                             reason=rec.get("reason", "")))
        await _flush(s)
    return rec


async def today(user_id: str, route_id: str) -> dict:
    rec = await next_step(user_id, route_id, None)
    return {"recommendation": rec}


async def next_step(user_id: str, route_id: str, current_section_id: str | None) -> dict:
    m_map = await ms.get_mastery_map(user_id, route_id)
    secs = sections_for_route(route_id)
    kg = get_kg()

    # 0) 间隔复习优先（D8）：若有到期复习且用户在学习中，则先提醒复习抗遗忘
    from services import review_service
    due = await review_service.due_reviews(user_id, route_id)
    if due and (current_section_id is None or m_map):
        top = due[0]
        # 仅当到期项确有遗忘风险（保持率偏低）时才打断主线，避免频繁打断
        if top["retention"] < 0.9:
            rec = {"rec_type": "review", "target_section_id": top["section_id"],
                   "target_node_id": top["node_id"],
                   "reason": f"『{top['name']}』已隔 {top['elapsed_days']} 天，记忆保持率降至 {int(top['retention']*100)}%，建议先做一次快速复习"}
            return await _save(user_id, route_id, rec)

    # 1) 若有当前章：判断门控/完成度（统一 section_progress，兼容无题库占位章）
    # D135：`current_section_id` 不存在（缓存过期 / 手输）时不能当「当前章」用，
    # 否则下面会把它原样回显成 target_section_id，点进去是一张空页。
    cur = get_section(current_section_id) if current_section_id else None
    if cur:
        prog = await ms.section_progress(user_id, route_id, current_section_id, m_map)
        if prog["completed"]:
            nxt_id = next((x["id"] for x in secs
                           if cur and x["order_index"] > cur["order_index"]), None)
            if nxt_id:
                nxt = get_section(nxt_id)
                why = (f"《{cur['title']}/已达标({prog['score']}≥{prog['threshold']})" if prog["bank"]
                       else f"已完成《{cur['title']}》学习")
                rec = {"rec_type": "next_section", "target_section_id": nxt_id,
                       "reason": f"{why}，可进入《{nxt['title'] if nxt else nxt_id}》"}
                return await _save(user_id, route_id, rec)
        elif prog["bank"]:
            # 有题库但未达标 → 回补最阻塞薄弱点（若尚未开考，先测试摸底）
            if not prog.get("started"):
                rec = {"rec_type": "start", "target_section_id": current_section_id,
                       "reason": f"建议先完成《{cur['title'] if cur else current_section_id}》章节测试摸底"}
                return await _save(user_id, route_id, rec)
            g = ms.compute_gating(m_map, route_id, current_section_id)
            need = sorted(g["need_reinforce"], key=lambda n: kg.dependents_count(n), reverse=True)
            if need:
                node = get_node(need[0])
                rec = {"rec_type": "reinforce", "target_section_id": current_section_id,
                       "target_node_id": need[0],
                       "reason": f"你在『{node['name'] if node else need[0]}』未达标({g['section_score']}<{g['threshold']})，建议先回补该专项"}
                return await _save(user_id, route_id, rec)
        else:
            # 无题库且未完成 → 继续按段落学习当前章
            rec = {"rec_type": "start", "target_section_id": current_section_id,
                   "reason": f"继续学习《{cur['title'] if cur else current_section_id}》"}
            return await _save(user_id, route_id, rec)

    # 2) 无当前章 / 兜底：找第一个未完成章节作为推荐（兼容无题库占位章）
    for sec in secs:
        prog = await ms.section_progress(user_id, route_id, sec["id"], m_map)
        if prog["completed"]:
            continue
        if prog["bank"]:
            # 检查有无强阻塞薄弱点
            nodes = [n for n in KNOWLEDGE_NODES if n["section_id"] == sec["id"]]
            weak = [n for n in nodes if m_map.get(n["id"], {}).get("score", 0.0) < 0.45]
            if weak:
                weak.sort(key=lambda n: kg.dependents_count(n["id"]), reverse=True)
                w = weak[0]
                rec = {"rec_type": "reinforce", "target_section_id": sec["id"],
                       "target_node_id": w["id"],
                       "reason": f"『{w['name']}』掌握度低，建议从该节专项开始"}
                return await _save(user_id, route_id, rec)
        rec = {"rec_type": "start", "target_section_id": sec["id"],
               "reason": f"建议从《{sec['title']}》开始学习"}
        return await _save(user_id, route_id, rec)

    # 全部达标
    last = secs[-1] if secs else None
    rec = {"rec_type": "next_section", "target_section_id": last["id"] if last else "",
           "reason": "该路线已全部达标，可进入更高阶学习或复习巩固"}
    return await _save(user_id, route_id, rec)


async def weak_top(user_id: str, route_id: str, n: int = 5) -> dict:
    # D135：`n` 是外部入参，负值在 Python 里是「从尾部切片」（n=-1 → 除最后一条外
    # 全部 105 条），与单机 `take(n)`（空表）语义相反。两端统一钳制。
    n = max(0, min(n, 50))
    from services.profile_service import build_profile
    prof = await build_profile(user_id, route_id)
    weak = prof["weak_points"][:n]
    out = []
    for w in weak:
        stmt_txt = f"阻塞后续{w['blocking_sections']}章" if w["blocking_sections"] else "同章内薄弱"
        out.append({**w, "statement": stmt_txt})
    return {"weak_points": out}
