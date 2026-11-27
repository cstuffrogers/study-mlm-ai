"""章节导读 → 原文链接索引 / LLM 运行时配置 的回归测试。

口径：
  · source_links 只读——不改写 ROUTE_NODES / KNOWLEDGE_NODES / 题库。
  · authoritative 必须指向真实存在的分片；related 必须诚实声明非逐条权威溯源。
  · LLM 配置 API 永不回传完整密钥。
"""
from __future__ import annotations

import asyncio
import json
import os

import pytest

from api.legacy.llm_config_routes import ConfigIn, get_config, save_config
from api.legacy.route_routes import section_guide
from content import source_links
from content.routes import SECTIONS, get_section
from services.content_provider import chunks_by_work, get_chunk


def _guide(sid: str) -> dict:
    return asyncio.run(section_guide("route_A", sid))


def test_guide_response_includes_source_links():
    r = _guide("sec_A_00")
    assert "source_links" in r
    sl = r["source_links"]
    assert set(sl) == {"chapter", "nodes", "blocks"}
    assert sl["chapter"]["has_full_text"] is True
    assert sl["chapter"]["chunk_count"] > 0
    assert len(sl["nodes"]) == len(r["nodes"])
    assert set(sl["blocks"]) >= {
        "background", "sections", "discussion"
    }


def test_authoritative_links_point_to_real_chunks():
    r = _guide("sec_A_02")  # 《关于费尔巴哈的提纲》：全部显式标注 source_chunk_id
    links = r["source_links"]["nodes"]
    assert links and all(x["kind"] == "authoritative" for x in links)
    for x in links:
        assert x["chunk_id"]
        assert get_chunk(x["chunk_id"]) is not None
        assert "权威" in x["reason"]


def test_related_links_are_honest_and_real():
    r = _guide("sec_A_00")  # 全部知识点已补锚：链接须指向真实分片
    nodes = r["nodes"]
    links = r["source_links"]["nodes"]
    assert len(links) == len(nodes)
    for x in links:
        if x["kind"] == "authoritative":
            assert x["chunk_id"]
            assert get_chunk(x["chunk_id"]) is not None
            assert "权威" in x["reason"]
        elif x["kind"] == "related":
            assert x["chunk_id"]
            assert get_chunk(x["chunk_id"]) is not None
            assert "非逐条权威溯源" in x["reason"]
        elif x["kind"] == "none":
            assert x["chunk_id"] == ""
            assert x["reason"]


def test_source_links_never_mutate_content_tables():
    from content import chapter_content, knowledge_graph

    before = {k: [dict(n) for n in v] for k, v in chapter_content.ROUTE_NODES.items()}
    kb = [dict(n) for n in knowledge_graph.KNOWLEDGE_NODES]
    for sid in ("sec_A_00", "sec_A_02", "sec_B_04"):
        _guide(sid)
    assert {k: [dict(n) for n in v] for k, v in chapter_content.ROUTE_NODES.items()} == before
    assert [dict(n) for n in knowledge_graph.KNOWLEDGE_NODES] == kb


def test_all_sections_have_ingested_local_work():
    # 补链接的前提：32 章都有已入库的主文，且分片真实存在。
    assert len(SECTIONS) == 32
    for sec in SECTIONS:
        work = (sec.get("local_work") or "").strip()
        assert work, f"{sec['id']} 缺 local_work"
        assert chunks_by_work(work), f"{sec['id']} / {work} 无分片"


def test_llm_config_api_masks_secret_and_validates():
    st = asyncio.run(get_config())
    assert "api_key" not in st
    assert "masked_api_key" in st
    assert "presets" in st and "deepseek" in st["presets"]
    assert st["base_url"] and st["model"]
    with pytest.raises(Exception) as e:
        asyncio.run(save_config(ConfigIn(base_url="not a url")))
    assert "Base URL" in str(e.value)


def test_partial_save_does_not_reset_other_fields(tmp_path, monkeypatch):
    """只改 model 时，web 上已保存的 base_url / 密钥不能被重置（None ≠ 空字符串）。

    新语义：运行时只认 web 端（.llm_config.json），不再从 .env 回填。
    """
    from services import llm_config_service as svc

    fake = tmp_path / "cfg.json"
    # 模拟用户此前已在 web 端保存过的配置
    fake.write_text(json.dumps({
        "LLM_API_KEY": "web-saved-secret",
        "LLM_BASE_URL": "https://example.com/v1",
        "LLM_MODEL": "model-a",
    }), encoding="utf-8")
    monkeypatch.setattr(svc, "_CONFIG_PATH", fake)
    # .env 里放不同的值，验证它们不会漏进运行时
    monkeypatch.setenv("LLM_API_KEY", "env-secret-should-not-leak")
    monkeypatch.setenv("LLM_BASE_URL", "https://env-should-not-leak.example")
    monkeypatch.setenv("LLM_MODEL", "env-model-should-not-leak")
    st = svc.save({"api_key": "", "model": "model-b",
                   "base_url": None, "max_retries": None})
    assert st["base_url"] == "https://example.com/v1"
    assert st["model"] == "model-b"
    assert st["configured"] is True
    assert st["masked_api_key"] != "web-saved-secret"
    assert st["masked_api_key"] != "env-secret-should-not-leak"
    # base_url=None 表示不改动，web 上已保存的地址应原样留在文件里
    assert "https://example.com/v1" in fake.read_text(encoding="utf-8")
    # .env 的旧值不得出现在生效配置里
    assert st["base_url"] != "https://env-should-not-leak.example"
    assert st["model"] != "env-model-should-not-leak"


def test_llm_config_runtime_refresh(monkeypatch):
    """CloudLayer.run() 每次重读 os.environ：配置保存后无需重启/重连即生效。"""
    from core.llm.base import LLMRequest
    from core.llm.cloud import CloudLayer

    c = CloudLayer()
    monkeypatch.setenv("LLM_MODEL", "unit-test-model")
    asyncio.run(c.run(LLMRequest(key="x", prompt="x", task="general", complexity=0.1)))
    assert c.model == "unit-test-model"

# 依赖 sources/texts/ 原著正文；无正文时由 conftest.py 自动跳过。
pytestmark = pytest.mark.needs_texts
