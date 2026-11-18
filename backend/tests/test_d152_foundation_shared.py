"""D152 门禁：公共地基（「1+3」）的归属、口径与「跨路线可见」

背景（这次要钉住的问题）：
  公共地基是「三条路线共用」的，但地基章只排在路线 A 的章节列表里。
  后端 `sections_for_route()` 按 route_id 过滤 → 切到 B/C 的页面上根本看不到
  这三章，学习者会误以为「地基已经过关」。更糟的是注释里只写了《提纲》一章，
  而代码里 `is_foundation=True` 的是三章（《大众哲学》两章 + 《提纲》）。

钉住四件事：
  ① 地基章清单与 `is_foundation` 标记必须一一对应，且都在学习顺序的前三位；
  ② 三条路线声明共享的地基是同一批（`foundation_ref` 不许再写含糊的 "shared"）；
  ③ `/api/routes/{id}/sections` 对 B/C 也要返回 `foundation`，且进度读 route_A
     （掌握度按「用户 × 路线」存，地基记录只在 route_A 下产生）；
  ④ 地基两章各有一条「经典原文替代路径」（三个来源 / 反杜林论哲学篇），
     且都挂真实正文（不许只作导读、不许伪造原文）。
"""
import uuid

import pytest

from content.book_chunks import available_works
from content.reading_extensions import extensions_for
from content.routes import (
    FOUNDATION_ROUTE_ID, FOUNDATION_SECTION_IDS, ROUTES, SECTIONS,
    foundation_ids_of_route, foundation_sections, sections_for_route,
)
from services import mastery_service as ms, quiz_service, route_service
from services.learning_startup import ensure_learning_ready


def uid() -> str:
    return "t_" + uuid.uuid4().hex[:8]


def test_foundation_ids_match_is_foundation_flag():
    """路线 A 的地基章 = FOUNDATION_SECTION_IDS；B/C 只有一个《提纲》占位章。"""
    a_flagged = [s["id"] for s in SECTIONS
                 if s.get("is_foundation") and s["route_id"] == FOUNDATION_ROUTE_ID]
    assert a_flagged == list(FOUNDATION_SECTION_IDS), (
        "路线 A 的地基标记与 FOUNDATION_SECTION_IDS 必须完全一致："
        "只改一处会让「三章地基」在展示与统计上对不上"
    )
    # 顺序即学习顺序：先《大众哲学》建坐标系，再体系化，最后才读《提纲》
    orders = [s["order_index"] for s in foundation_sections()]
    assert orders == sorted(orders) == [0, 1, 2]

    # B/C 各自有一个《提纲》占位章（「公共地基：实践观（共享）」）——这是既有设计，
    # 说明地基章「有没有被本路线覆盖」必须按 local_work 判断（见 shared_foundation）。
    for rid in ("route_B", "route_C"):
        flagged = [s for s in SECTIONS if s.get("is_foundation") and s["route_id"] == rid]
        assert len(flagged) == 1, f"{rid} 不应重复排《大众哲学》，只保留《提纲》占位章"
        assert flagged[0]["local_work"] == "关于费尔巴哈的提纲"


def test_foundation_belongs_to_one_route_only():
    assert FOUNDATION_ROUTE_ID == "route_A"
    for sid in FOUNDATION_SECTION_IDS:
        owners = [s["route_id"] for s in SECTIONS if s["id"] == sid]
        assert owners == ["route_A"], f"{sid} 只能挂在路线 A，否则会与 B/C 重复排课"


def test_all_routes_declare_the_same_foundation():
    for r in ROUTES:
        assert r["shares_foundation"] is True
        assert r["foundation_ref"] == "sec_A_00,sec_A_01,sec_A_02", (
            "foundation_ref 不许再写含糊的 shared：没有任何代码消费那个值，"
            "写明确才能让地基清单可核对"
        )
        assert foundation_ids_of_route(r["id"]) == list(FOUNDATION_SECTION_IDS)


def test_foundation_chapters_not_in_b_or_c_lists():
    for rid in ("route_B", "route_C"):
        ids = {s["id"] for s in sections_for_route(rid)}
        assert not (ids & set(FOUNDATION_SECTION_IDS)), "地基章不重复排进 B/C"


@pytest.mark.asyncio
async def test_sections_payload_exposes_shared_foundation():
    await ensure_learning_ready()
    u = uid()
    expect_cover = {"route_B": "sec_B_00", "route_C": "sec_C_00"}
    for rid in ("route_A", "route_B", "route_C"):
        data = await route_service.get_routes_sections(u, rid)
        rows = data["foundation"]
        assert [r["id"] for r in rows] == list(FOUNDATION_SECTION_IDS), (
            f"{rid} 的返回里必须带地基三章，否则页面没法提示「地基还没读」"
        )
        assert all(r["route_id"] == "route_A" for r in rows)
        by_id = {r["id"]: r for r in rows}
        if rid == "route_A":
            # 路线 A 自己已经列了这三章 → 全部 in_route，前端不重复展示
            assert all(r["in_route"] for r in rows)
            assert all(r["covered_by"] is None for r in rows)
        else:
            # 《大众哲学》两章这条路线压根没有 → 必须由地基卡补出来
            assert by_id["sec_A_00"]["in_route"] is False
            assert by_id["sec_A_01"]["in_route"] is False
            # 《提纲》由本路线的占位章覆盖 → 不重复展示，但要指向占位章
            assert by_id["sec_A_02"]["in_route"] is True
            assert by_id["sec_A_02"]["covered_by"] == expect_cover[rid]


@pytest.mark.asyncio
async def test_foundation_progress_reads_route_a_mastery():
    """在 route_A 学完《大众哲学》→ 切到 B 路线，地基卡也要显示「已读」，不能归零。

    掌握度按「用户 × 路线」存（`MasteryRecord.route_id`），而《大众哲学》两章只排在
    route_A，所以这两章的进度必须锚 route_A；否则换个路线看就是刚学完又归零。
    """
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_00", "route_A")
    await quiz_service.submit_test(
        t["test_id"], u, [{"item_id": it["id"], "answer": "A"} for it in t["items"]])

    a_row = next(r for r in (await route_service.get_routes_sections(u, "route_A"))["foundation"]
                 if r["id"] == "sec_A_00")
    assert a_row["status"] in ("in_progress", "completed") and a_row["mastery_score"] > 0

    for rid in ("route_B", "route_C"):
        b_row = next(r for r in (await route_service.get_routes_sections(u, rid))["foundation"]
                     if r["id"] == "sec_A_00")
        assert b_row["status"] == a_row["status"]
        assert b_row["mastery_score"] == a_row["mastery_score"], (
            f"{rid} 读到的是别的路线名下的掌握度 —— 地基卡会显示「待补」，与实际不符"
        )


@pytest.mark.asyncio
async def test_tijiang_placeholder_progress_is_route_scoped():
    """《提纲》占位章：B 路线读 sec_B_00 的进度，也与 A 的 sec_A_02 各自记账。"""
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_B_00", "route_B")
    await quiz_service.submit_test(
        t["test_id"], u, [{"item_id": it["id"], "answer": "A"} for it in t["items"]])
    b_row = next(r for r in (await route_service.get_routes_sections(u, "route_B"))["foundation"]
                 if r["id"] == "sec_A_02")
    assert b_row["covered_by"] == "sec_B_00"
    assert b_row["status"] in ("in_progress", "completed")
    # B 名下学完，A 名下的 sec_A_02 仍是未开始（占位章就是按路线记账的）
    a_row = next(r for r in (await route_service.get_routes_sections(u, "route_A"))["foundation"]
                 if r["id"] == "sec_A_02")
    assert a_row["status"] == "unlocked"


@pytest.mark.asyncio
async def test_foundation_route_without_shares_flag_is_empty():
    """没有声明共享地基的路线不该凭空冒出地基卡。"""
    await ensure_learning_ready()
    rows = await route_service.shared_foundation(uid(), "route_X")
    assert rows == []


def test_classic_alternative_path_for_foundation_chapters():
    """地基两章各有一条「经典原文版」替代路径，且挂的是真实入库正文。"""
    works = set(available_works())
    expect = {"sec_A_00": "马克思主义的三个来源和三个组成部分",
              "sec_A_01": "反杜林论（哲学篇）"}
    for sid, work in expect.items():
        rows = [r for r in extensions_for(sid) if r.get("local_work") == work]
        assert len(rows) == 1, f"{sid} 缺少指向《{work}》的经典替代路径条目"
        it = rows[0]
        assert "经典原文版" in it["title"], "标题要写明这是「经典原文版」，与通俗版并列"
        assert it["kind"] == "classic"
        assert work in works, f"《{work}》正文未入库，不能挂 local_work"
        assert it.get("how_to_use") and it.get("points"), "替代路径要写清怎么用、包含哪些板块"
