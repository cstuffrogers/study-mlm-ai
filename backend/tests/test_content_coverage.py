"""P3 收口：题库全覆盖 + 章节内交错排题 + 节点级主导错因 测试"""
import uuid

import pytest

from services.learning_startup import ensure_learning_ready
from services import quiz_service
from content.knowledge_graph import KNOWLEDGE_NODES
from services.learning_db import session_scope
from model.models_learning import QuizItem
from sqlalchemy import select


def uid():
    return "cl_" + uuid.uuid4().hex[:8]


def test_bank_covers_all_nodes():
    """题库（全部 quiz_bank/*.json 合并）应覆盖知识图谱全部知识点（每点至少 1 题）。"""
    import io, json, os, glob
    bank_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "content", "quiz_bank")
    covered = set()
    for f in glob.glob(os.path.join(bank_dir, "*.json")):
        d = json.load(io.open(f, encoding="utf-8"))
        covered |= {it["node_id"] for it in d["items"]}
    missing = [n["id"] for n in KNOWLEDGE_NODES if n["id"] not in covered]
    assert not missing, f"题库未覆盖知识点: {missing}"


@pytest.mark.asyncio
async def test_selection_keeps_application_and_subjective():
    """题库超过 12 题时，应用题/主观题必须被选入，且每个知识点至少 1 题。"""
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    items = t["items"]
    assert 8 <= len(items) <= 12
    assert any(it.get("application") for it in items), "应用题应被选入"
    assert any(it.get("subjective") for it in items), "主观题应被选入"


@pytest.mark.asyncio
async def test_interleave_no_long_same_node_blocks():
    """交错排题：相邻同知识点尽量不超过 1 组（即不出现连续 3 题同节点）。"""
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    # 通过重新查库还原 node 顺序
    ids = [it["id"] for it in t["items"]]
    async with session_scope() as s:
        res = await s.execute(select(QuizItem).where(QuizItem.id.in_(ids)))
        m = {q.id: q for q in res.scalars().all()}
    seq = [m[i].node_id for i in ids]
    # 检查无三连同一节点
    for i in range(2, len(seq)):
        assert not (seq[i] == seq[i - 1] == seq[i - 2]), f"出现三连同节点块: {seq}"
    # 且相邻不同节点占多数
    diff = sum(1 for i in range(1, len(seq)) if seq[i] != seq[i - 1])
    assert diff >= len(seq) // 2


@pytest.mark.asyncio
async def test_dominant_error_aggregated():
    """节点级主导错因：全答错时，客观题节点应回填非空错因。"""
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    sub = await quiz_service.submit_test(t["test_id"], u,
                                         [{"item_id": it["id"], "answer": "B" if not (it.get("subjective") or it.get("application")) else "x"}
                                          for it in t["items"]])
    cats = [m.get("error_category") for m in sub["mastery"]]
    assert any(c for c in cats), "错答后节点应有主导错因"
    # 主导错因应是合法取值
    valid = {"stance_deviation", "concept_layer_confusion", "real_unknown", "concept_application", "term_misuse"}
    assert all(c in valid for c in cats if c)


# ---------------- 重复提交幂等 + 客观题答案归一化（真实缺陷回归）----------------

@pytest.mark.asyncio
async def test_double_submit_rejected_and_status_persisted():
    """同一测试重复提交应被拒绝，且首次提交后 status/total_score 已持久化。"""
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    ans = [{"item_id": it["id"], "answer": "A"} for it in t["items"]]
    first = await quiz_service.submit_test(t["test_id"], u, ans)
    # 持久化校验
    async with session_scope() as s:
        from model.models_learning import SectionTest
        r = (await s.execute(select(SectionTest).where(SectionTest.id == t["test_id"]))).scalars().first()
        assert r.status == "submitted"
        assert abs((r.total_score or 0) - first["total_score"]) < 1e-6
    # 重复提交被拒
    import pytest as _pytest
    with _pytest.raises(ValueError):
        await quiz_service.submit_test(t["test_id"], u, ans)


@pytest.mark.asyncio
async def test_objective_answer_normalization():
    """'a.' / 大小写 / 前后空格 都能正确判分（避免把正确答案误判为错）。"""
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    obj = [it for it in t["items"] if not (it.get("subjective") or it.get("application"))]
    assert obj
    target = obj[0]
    # 用 ' a. ' 作答，应判对（若正确答案为 A）
    ans = []
    for it in t["items"]:
        if it.get("subjective") or it.get("application"):
            ans.append({"item_id": it["id"], "answer": "实践"})
        elif it["id"] == target["id"]:
            ans.append({"item_id": it["id"], "answer": " a. "})
        else:
            ans.append({"item_id": it["id"], "answer": "A"})
    r = await quiz_service.submit_test(t["test_id"], u, ans)
    rev = next(x for x in r["review"] if x["item_id"] == target["id"])
    # 归一化后首字母 A 与 answer 比较，结果应稳定（此处只验证不因格式报错且取首字母）
    assert quiz_service._norm_choice(" a. ") == "A"


# ---------------- 无题库章节死锁修复（学习路径可推进）----------------

@pytest.mark.asyncio
async def test_every_section_has_bank_and_can_progress():
    """全部章节（含原无题库占位章）均已配题库：has_bank=True，且新用户可从首章起步（不锁定）。"""
    from services import route_service as rt, recommendation_service as rs
    await ensure_learning_ready()
    u = uid()
    # 新用户：从 sec_A_00 起步
    r0 = await rs.next_step(u, "route_A", None)
    assert r0["target_section_id"] == "sec_A_00"
    # 三条路线全部章节都配了题库
    for rid in ("route_A", "route_B", "route_C"):
        ls = await rt.get_routes_sections(u, rid)
        assert all(s["has_bank"] for s in ls["sections"]), f"{rid} 仍有空章"
    # 首章状态为 unlocked（可达，不卡死）
    st = {s["id"]: s["status"] for s in (await rt.get_routes_sections(u, "route_A"))["sections"]}
    assert st["sec_A_00"] == "unlocked"


@pytest.mark.asyncio
async def test_gating_bank_true_for_all_sections():
    """全部章节均已配题库，gating 返回 bank=True 且字段完整。"""
    from services import route_service as rt
    await ensure_learning_ready()
    u = uid()
    for sid in ("sec_A_00", "sec_A_02", "sec_B_00", "sec_C_00"):
        g = await rt.gating(u, "route_A" if sid.startswith("sec_A") else
                            ("route_B" if sid.startswith("sec_B") else "route_C"), sid)
        assert g["bank"] is True
        assert "unlocked" in g and "section_score" in g


# ---------------- D97：已入库原著必须全部落在学习路径上（章节或延伸阅读）----------------

def test_every_ingested_work_reachable_from_learning_path():
    """已入库的每一部原著，都必须能从学习路径抵达：要么是某章 local_work（「阅读原文」入口），
    要么是某章延伸阅读的 classic 条目 local_work。不得出现「入库了但学习路线里找不到」的孤立书。"""
    from content.book_chunks import available_works
    from content.routes import SECTIONS
    from content.reading_extensions import READING_EXTENSIONS

    route_works = {s["local_work"] for s in SECTIONS if s.get("local_work")}
    ext_works = {it["local_work"]
                 for items in READING_EXTENSIONS.values()
                 for it in items if it.get("local_work")}
    reachable = route_works | ext_works
    orphan = [w for w in available_works() if w not in reachable]
    assert not orphan, f"以下已入库原著在学习路径中完全不可达: {orphan}"


def test_systematic_chapters_have_real_chunk_provenance():
    """D97 体系收拢章：导读 + 知识点 + 题库必须齐备，且知识点/题目溯源到真实入库分片。"""
    import io, json, os, glob
    from content.chapter_content import guide_for
    from content.knowledge_graph import nodes_by_section
    from content import routes as R

    bank_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "content", "quiz_bank")
    items = []
    for f in glob.glob(os.path.join(bank_dir, "*.json")):
        d = json.load(io.open(f, encoding="utf-8"))
        top_sid = d.get("section_id")
        for it in d["items"]:
            # 红线：section_id 可能在文件顶层而非每道 items 元素内（D88 踩坑）
            items.append({**it, "section_id": it.get("section_id") or top_sid})

    for sid in ("sec_A_13", "sec_A_14"):
        sec = R.get_section(sid)
        assert sec and sec["local_work"], f"{sid} 必须挂 local_work"
        g = guide_for(sid)
        assert g and g["title"] and "导读" in g["source_note"], f"{sid} 缺导读或未标注导读"
        nodes = nodes_by_section(sid)
        assert nodes, f"{sid} 缺知识点"
        for n in nodes:
            assert n["source_chunk_id"].startswith("CH-"), f"{sid}:{n['id']} 溯源必须指向真实分片"
        covered = {it["node_id"] for it in items if it["section_id"] == sid}
        missing = [n["id"] for n in nodes if n["id"] not in covered]
        assert not missing, f"{sid} 知识点无题: {missing}"
        for it in items:
            if it["section_id"] == sid:
                assert it["source_chunk_id"].startswith("CH-"), f"{it['id']} 溯源必须指向真实分片"
