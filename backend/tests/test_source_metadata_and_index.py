"""结构化溯源 + 内容索引回归

覆盖：
  1. 模型内部编码 `[CH-...]` / `[GUIDE-...]` 只在服务端用于事实校验，
     对外正文必须清洗干净，改由 source_chunks 结构化携带；
  2. 不存在的分片不进 source_chunks（避免前端「相关原文」点开是空卡）；
  3. 内容索引（O(1) 取分片 / 按著作）与线性扫描结果一致。
"""
import uuid

import pytest

from services import content_provider
from services.dialogue_service import DialogueService
from services.source_metadata import (
    cited_chunk_ids, merge_source_chunks, strip_citations,
)
from websocket.protocol import AiMessageOut, UserMessageIn


# ---------------- 纯函数 ----------------

def test_strip_citations_removes_internal_codes():
    raw = "实践是认识的基础[CH-ME-TH-01-1]，另见 [GUIDE-A-B2]。结论成立。"
    out = strip_citations(raw)
    assert "CH-" not in out and "GUIDE-" not in out
    assert "[" not in out
    assert "实践是认识的基础" in out and "结论成立" in out


def test_cited_ids_dedup_and_order():
    raw = "[CH-A-1] 与 [CH-B-2] 再说 [CH-A-1]"
    assert cited_chunk_ids(raw) == ["CH-A-1", "CH-B-2"]


def test_merge_source_chunks_marks_related_only():
    merged = merge_source_chunks(
        ["CH-ME-TH-01-1"],
        [{"chunk_id": "CH-ME-TH-01-1", "source": "关于费尔巴哈的提纲",
          "location": "第一条", "kind": "related"}],
    )
    assert len(merged) == 1
    row = merged[0]
    assert row["chunk_id"] == "CH-ME-TH-01-1"
    assert row["kind"] == "related"          # 绝不冒充权威溯源
    assert row["source_location"] == "第一条"


def test_protocol_has_structured_source_chunks():
    msg = AiMessageOut(content="正文", mode="explain",
                       source_chunks=[{"chunk_id": "CH-ME-TH-01-1"}])
    assert msg.model_dump()["source_chunks"][0]["chunk_id"] == "CH-ME-TH-01-1"


# ---------------- 内容索引 ----------------

def test_content_index_matches_linear_scan():
    content_provider.warm_index()
    chunks = content_provider.all_chunks()
    assert len(chunks) > 1000
    lookup = {c["id"]: c for c in chunks}
    for c in chunks[:200]:
        assert content_provider.get_chunk(c["id"]) is lookup[c["id"]]
    # 未知 id 不报错
    assert content_provider.get_chunk("CH-NOT-EXIST-999") is None

    first = chunks[0]
    work = first.get("source", "")
    if work:
        by_work = content_provider.chunks_by_work(work)
        assert by_work and all(c["source"] == work for c in by_work)

    pid = next((c.get("paragraph_id") for c in chunks if c.get("paragraph_id")), "")
    if pid:
        same = content_provider.chunks_for_paragraph(pid)
        assert same and all(c.get("paragraph_id") == pid for c in same)


def test_content_index_stats_cached():
    a = content_provider.index_stats()
    b = content_provider.index_stats()
    assert a == b and a["chunks"] > 0


# ---------------- 对话链路 ----------------

@pytest.mark.asyncio
async def test_chat_output_is_clean_and_structured(monkeypatch):
    content_provider.warm_index()
    real_id = content_provider.all_chunks()[0]["id"]
    svc = DialogueService()

    async def fake_generate(*args, **kwargs):
        class _R:
            text = f"实践是认识的基础[{real_id}]，另见 [GUIDE-NOT-EXIST] 与 [CH-NOT-EXIST]。"
            source = "mock"
        return _R()

    monkeypatch.setattr(svc.llm_router, "generate", fake_generate)
    res = await svc.chat(UserMessageIn(
        dialogue_id="d_" + uuid.uuid4().hex[:8], content="什么是实践？"))
    ai = res["ai_message"]

    assert "CH-" not in ai["content"] and "GUIDE-" not in ai["content"]
    ids = [c["chunk_id"] for c in ai["source_chunks"]]
    assert real_id in ids
    # 不存在于正文库的引用不进结构化列表
    assert all(content_provider.get_chunk(i) is not None for i in ids)
    assert all(c.get("kind") == "related" for c in ai["source_chunks"])
