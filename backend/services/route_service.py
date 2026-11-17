"""RouteService — 路线/章节导航 + 选择/切换 + 起点（应用层）

进度状态由掌握度推导：章节掌握分 ≥ 门槛 → completed；有部分记录 → in_progress；
其余一律 reachable（unlocked）。**允许自由选章/跳章学习**：不再因前一章未完成而锁定，
学习者可从任意章节开始、跳着学；掌握度与「下一章达标」反馈仍照常计算，只作为建议而非硬门禁。
切换路线保留公共地基（is_foundation）学情。
"""
from __future__ import annotations

from sqlalchemy import select

from services import mastery_service as ms
from content.routes import ROUTES, sections_for_route, stage_label


async def list_routes() -> list[dict]:
    return [{"id": r["id"], "name": r["name"], "goal": r["goal"],
             "est_duration": r["est_duration"], "shares_foundation": r["shares_foundation"]}
            for r in ROUTES]


async def get_routes_sections(user_id: str, route_id: str) -> dict:
    secs = sections_for_route(route_id)
    m_map = await ms.get_mastery_map(user_id, route_id)
    # 批量取进度：原先每章一次 section_progress（无题库章含一次 DB 查询）
    progress = await ms.section_progress_all(
        user_id, route_id, [sec["id"] for sec in secs], m_map)
    out = []
    prev_done = True
    for sec in secs:
        prog = progress[sec["id"]]
        threshold = prog["threshold"]
        if prog["completed"]:
            status = "completed"
        elif prog["started"]:
            status = "in_progress"
        else:
            # 自由学习：任意章节均可达（不再按前一章 completion 锁定）
            status = "unlocked"
        # prev_done 保留：标记「理想顺序上前序是否已完成」，仅作展示/建议
        out.append({
            "id": sec["id"], "order_index": sec["order_index"], "stage_no": sec["stage_no"],
            "stage_label": stage_label(sec["stage_no"]),
            "work": sec["work"], "title": sec["title"], "is_foundation": sec["is_foundation"],
            "local_work": sec.get("local_work"), "work_short": sec.get("work_short"),
            "status": status, "mastery_score": prog["score"], "unlock_threshold": threshold,
            "has_bank": prog["bank"], "prev_completed": prev_done,
        })
        prev_done = prog["completed"]
    return {"route_id": route_id, "sections": out}


def _has_records(m_map, section_id) -> bool:
    from content.knowledge_graph import nodes_by_section
    return any(n["id"] in m_map for n in nodes_by_section(section_id))


async def select_route(user_id: str, route_id: str) -> dict:
    """选择/切换路线：保留公共地基掌握度，重算推荐起点"""
    secs = sections_for_route(route_id)
    m_map = await ms.get_mastery_map(user_id, route_id)
    progress = await ms.section_progress_all(
        user_id, route_id, [sec["id"] for sec in secs], m_map)
    recomputed_start = None
    carried = []
    for sec in secs:
        prog = progress[sec["id"]]
        if prog["completed"]:
            carried.append(sec["id"])
        elif recomputed_start is None:
            recomputed_start = sec["id"]
    return {"selected": route_id, "carried_over": carried,
            "recomputed_start": recomputed_start or (secs[0]["id"] if secs else None)}


async def gating(user_id: str, route_id: str, section_id: str) -> dict:
    m_map = await ms.get_mastery_map(user_id, route_id)
    g = ms.compute_gating(m_map, route_id, section_id)
    # 无题库章：按学习进度判定是否放行（与 section_progress 保持一致）
    prog = await ms.section_progress(user_id, route_id, section_id, m_map)
    if not prog["bank"]:
        g["bank"] = False
        g["unlocked"] = prog["completed"]
        g["completed"] = prog["completed"]
        if not prog["completed"]:
            g["reason"] = "本章为阅读章，通读全文后标记完成即可解锁下一章"
        return g
    g["unlocked"] = g["section_score"] >= g["threshold"]
    g["bank"] = True
    g["blocking_nodes"] = g["need_reinforce"]
    if not g["unlocked"]:
        # 从图角度补充最关键的阻塞节点
        from services.knowledge_graph_service import get_kg
        kg = get_kg()
        need = sorted(g["need_reinforce"], key=lambda n: kg.dependents_count(n), reverse=True)
        if need:
            g["reason"] = f"需先补强 {need[0]}（掌握度未达 {g['threshold']}）"
    return g
