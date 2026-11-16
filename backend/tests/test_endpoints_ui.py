"""前后端补齐端点回归：章节导读 / 知识点详情 / 测试历史 / 原著分片 / 对话历史。

对应本轮「前端页面补齐」所消费的后端接口，确保骨架 + 关键字段稳定。
"""
import uuid

import pytest

from services.learning_startup import ensure_learning_ready
from services import quiz_service
from api import route_routes, mastery_routes, quiz_routes, chunk_routes, dialogue_routes


def uid():
    return "ep_" + uuid.uuid4().hex[:8]


@pytest.mark.asyncio
async def test_guide_endpoint_all_sections():
    """章节导读：三条路线全部章节均返回非空 guide + nodes。"""
    await ensure_learning_ready()
    checked = 0
    expected = 0
    for rid in ("route_A", "route_B", "route_C"):
        secs = await route_routes.routes_sections(rid)
        expected += len(secs["sections"])
        for s in secs["sections"]:
            g = await route_routes.section_guide(rid, s["id"])
            assert g["section_id"] == s["id"]
            assert isinstance(g["guide"], dict) and g["guide"].get("title")
            assert isinstance(g["nodes"], list)
            # 导读必须是「导读」，不得伪造原著正文
            note = (g["guide"].get("source_note") or "")
            assert "导读" in note
            checked += 1
    assert checked == expected >= 16


@pytest.mark.asyncio
async def test_node_detail_has_graph_links():
    """知识点详情：含 name/definition/dependents 及后继掌握度字段。"""
    await ensure_learning_ready()
    d = await mastery_routes.node_detail("kn_a00_basic")
    assert d["node_id"] == "kn_a00_basic"
    assert d["name"]
    assert d["section_id"] == "sec_A_00"
    assert "dependents" in d and isinstance(d["dependents"], list)
    assert d["dependents_count"] >= 1
    if d["dependents"]:
        assert {"node_id", "name", "level", "score"} <= set(d["dependents"][0].keys())


@pytest.mark.asyncio
async def test_quiz_history_after_attempt():
    """测试历史：作答后 history 返回题面/解析/溯源字段，only_wrong 可过滤。"""
    await ensure_learning_ready()
    u = uid()
    t = await quiz_service.start_section_test(u, "sec_A_02", "route_A")
    answers = [{"item_id": it["id"], "answer": "A", "confidence": "mid"} for it in t["items"]]
    await quiz_service.submit_test(t["test_id"], u, answers)
    h = await quiz_routes.history(user_id=u, limit=100, only_wrong=False)
    assert h["total"] > 0
    row = h["rows"][0]
    for k in ("quiz_id", "stem", "type", "explanation", "source_chunk_id", "section_id", "section_title"):
        assert k in row
    # only_wrong 只返回错题
    hw = await quiz_routes.history(user_id=u, limit=100, only_wrong=True)
    assert all(r["is_correct"] is False for r in hw["rows"])


@pytest.mark.asyncio
async def test_chunk_endpoints_lightweight():
    """原著分片：works / by_work / 单分片 均可用（轻量模式不 500）。"""
    w = await chunk_routes.list_works()
    assert isinstance(w["works"], list) and w["works"]
    bw = await chunk_routes.list_by_work("all")
    assert bw["count"] >= 1
    cid = bw["items"][0]["id"]
    one = await chunk_routes.get_chunk(cid)
    assert one["id"] == cid and one["text"]


@pytest.mark.asyncio
async def test_every_work_fetchable_by_work():
    """每个著作名都能 by_work 取到分片；著作名不得含路径分隔符 '/'（否则路由被
t    拆段导致 404），即便含全角字符也应整体 URL 编码后正常命中。"""
    from urllib.parse import quote
    w = await chunk_routes.list_works()
    for work in w["works"]:
        assert "/" not in work, f"著作名不得含 '/'（会被当成路径分隔符）: {work}"
        # 模拟前端：整体 URL 编码后作为单一路径段调用
        enc = quote(work, safe="")
        assert "/" not in enc
        r = await chunk_routes.list_by_work(work)
        assert r["count"] >= 1, f"著作 {work} 应有分片"
        assert all(it["source"] == work for it in r["items"])


@pytest.mark.asyncio
async def test_dialogue_history_roundtrip():
    """对话历史：写入一条会话消息后 list/messages 可回读（轻量进程内）。"""
    from services import dialogue_store
    d_id = "dlg_" + uuid.uuid4().hex[:6]
    dialogue_store.ensure_dialogue(d_id, user_id="demo_user", mode="explain")
    dialogue_store.append_message(d_id, "user", "什么是实践？")
    dialogue_store.append_message(d_id, "assistant", "实践是认识的基础。", source_chunks=["CH-ME-TH-01-1"])
    lst = await dialogue_routes.list_dialogues("demo_user")
    assert any(d["id"] == d_id for d in lst["dialogues"])
    msgs = await dialogue_routes.get_messages(d_id, 50)
    assert len(msgs["messages"]) == 2
    assert msgs["messages"][1]["source_chunks"] == ["CH-ME-TH-01-1"]
