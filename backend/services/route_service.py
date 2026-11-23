"""RouteService — 路线/章节导航 + 选择/切换 + 起点（应用层）

进度状态由掌握度推导：章节掌握分 ≥ 门槛 → completed；有部分记录 → in_progress；
其余一律 reachable（unlocked）。**允许自由选章/跳章学习**：不再因前一章未完成而锁定，
学习者可从任意章节开始、跳着学；掌握度与「下一章达标」反馈仍照常计算，只作为建议而非硬门禁。
切换路线保留公共地基（is_foundation）学情。
"""
from __future__ import annotations

from sqlalchemy import select

from services import mastery_service as ms
from content.routes import (
    FOUNDATION_ROUTE_ID, ROUTES, foundation_ids_of_route, foundation_sections,
    sections_for_route, stage_label,
)


async def list_routes() -> list[dict]:
    return [{"id": r["id"], "name": r["name"], "goal": r["goal"],
             "est_duration": r["est_duration"], "shares_foundation": r["shares_foundation"]}
            for r in ROUTES]


async def get_routes_sections(user_id: str, route_id: str) -> dict:
    secs = sections_for_route(route_id)
    m_map = await ms.get_mastery_map(user_id, route_id)
    # 批量取进度：原先每章一次 section_progress（含一次 DB 查询）
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

    # 勋章系统（spec 001）：路线完成检测（评估失败不阻断导航页）
    badges_awarded: list[dict] = []
    try:
        from services import badge_service
        badges_awarded = await badge_service.evaluate(user_id, source_event="route_check")
    except Exception as e:  # 勋章是激励反馈，任何异常不得影响路线导航
        import logging
        logging.getLogger(__name__).warning("勋章评估失败（不影响路线页）: %s", e)

    return {"route_id": route_id, "sections": out,
            "foundation": await shared_foundation(user_id, route_id, own_secs=secs),
            "badges_awarded": badges_awarded}


async def shared_foundation(user_id: str, route_id: str,
                            own_secs: list[dict] | None = None) -> list[dict]:
    """公共地基章（三条路线共用）：把「本路线没覆盖到的地基」也摆到页面上。

    三个容易踩的坑，都在这里处理掉：

    ① **地基章只排在路线 A**：`sections_for_route()` 按 route_id 过滤，
       切到 B/C 的章节列表里看不到《大众哲学》两章 → 学习者以为地基不用管了。
    ② **但《提纲》在 B/C 有占位章**（sec_B_00 / sec_C_00「公共地基：实践观（共享）」）：
       所以「这条路线有没有覆盖某地基章」不能只比 section_id，要按 `local_work`
       （同一部原著）判断；按 id 比会把《提纲》重复展示两遍。
    ③ **掌握度按「用户 × 路线」存**（`MasteryRecord.route_id`）：
       占位章的学习记录落在当前路线名下，其余地基章只会在 route_A 名下产生。
       所以进度要么读当前路线的占位章、要么锚 route_A，**绝不能一律读当前路线**
       （那样从 A 切到 B 会看到刚学完的地基又归零）。

    返回的每行都带 `in_route`（本路线是否已覆盖）与 `covered_by`（占位章 id）。
    """
    declared = set(foundation_ids_of_route(route_id))
    own = sections_for_route(route_id) if own_secs is None else own_secs
    own_ids = {s["id"] for s in own}
    # 占位章候选：本路线自己标了 is_foundation 的章（sec_B_00 / sec_C_00）。
    # 只认这些，不能拿「local_work 相同」去匹配——《大众哲学》两章共用同一部原著，
    # 按 work 匹配会把 sec_A_01 错认成被 sec_A_00 覆盖。
    placeholders: dict[str, dict] = {}
    for sec in own:
        if not sec.get("is_foundation") or sec["id"] in declared:
            continue
        lw = (sec.get("local_work") or "").strip()
        if lw:
            placeholders.setdefault(lw, sec)
    target = [s for s in foundation_sections() if s["id"] in declared]
    if not target:
        return []

    anchor = FOUNDATION_ROUTE_ID
    anchor_map = await ms.get_mastery_map(user_id, anchor)
    cur_map = anchor_map if route_id == anchor else await ms.get_mastery_map(user_id, route_id)

    # 先分组：被本路线占位章覆盖的读当前路线；没覆盖的读地基锚路线
    plan: list[tuple[dict, dict | None, str, dict]] = []
    for sec in target:
        lw = (sec.get("local_work") or "").strip()
        if sec["id"] in own_ids:
            # 路线 A：地基章本体就在本路线里（进度读本路线 = 锚路线）
            plan.append((sec, sec, route_id, cur_map))
            continue
        placeholder = placeholders.get(lw) if lw else None
        if placeholder is not None:
            # B/C：《提纲》有占位章，进度按本路线名下的占位章记账
            plan.append((sec, placeholder, route_id, cur_map))
        else:
            # B/C 完全没覆盖的地基章（《大众哲学》两章）：进度锚 route_A
            plan.append((sec, None, anchor, anchor_map))

    # 按 (路线, 掌握度) 分组批量算进度，避免逐章查库
    groups: dict[str, tuple[str, dict, list[str]]] = {}
    for sec, covered, rid, mmap in plan:
        key = f"{rid}|{'covered' if covered else 'anchor'}"
        if key not in groups:
            groups[key] = (rid, mmap, [])
        groups[key][2].append(covered["id"] if covered else sec["id"])
    prog: dict[str, dict] = {}
    for rid, mmap, ids in groups.values():
        prog.update(await ms.section_progress_all(user_id, rid, ids, mmap))

    rows = []
    for sec, covered, _rid, _m in plan:
        p = prog[covered["id"] if covered else sec["id"]]
        status = "completed" if p["completed"] else (
            "in_progress" if p["started"] else "unlocked")
        covered_by = covered["id"] if (covered and covered["id"] != sec["id"]) else None
        rows.append({
            "id": sec["id"], "route_id": anchor,
            "in_route": covered is not None,
            "covered_by": covered_by,
            "order_index": sec["order_index"], "stage_no": sec["stage_no"],
            "work": sec["work"], "title": sec["title"], "is_foundation": True,
            "local_work": sec.get("local_work"), "work_short": sec.get("work_short"),
            "status": status, "mastery_score": p["score"],
            "unlock_threshold": p["threshold"], "has_bank": p["bank"],
        })
    return rows


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
