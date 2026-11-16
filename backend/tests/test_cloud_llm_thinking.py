"""云 LLM 层回归：推理型模型的「关闭思维链」兼容参数降级逻辑。

真实中转 ccapi.cgdoem.cn 对 `thinking` + `enable_thinking` 同时传会间歇性
403；不带私有参数时长 prompt 又会把 max_tokens 全花在 reasoning_content 上，
导致正文为空。本测试用假客户端锁定：
  1. 首个参数 403 时不再退回「标准参数」，而是换下一个兼容参数；
  2. 只返回思维链、正文为空时也算失败并换参数，绝不把思维链当答案；
  3. 所有参数都失败时错误信息说明真实原因，不再误导为「缺 API Key」。
"""
from __future__ import annotations

import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from core.llm.base import LLMRequest  # noqa: E402
from core.llm.cloud import CloudLayer  # noqa: E402


def _msg(content: str, reasoning: str = "") -> SimpleNamespace:
    return SimpleNamespace(content=content, reasoning_content=reasoning)


def _resp(msg) -> SimpleNamespace:
    return SimpleNamespace(choices=[SimpleNamespace(message=msg, finish_reason="stop")])


class _FakeCompletions:
    """按 extra_body 里的参数名决定返回值，模拟中转的兼容性差异。"""

    def __init__(self, script: dict[str, object]):
        self.script = script
        self.calls: list[object] = []

    async def create(self, *, extra_body=None, **kwargs):
        keys = tuple(sorted((extra_body or {}).keys()))
        name = ",".join(keys) or "standard"
        self.calls.append(name)
        outcome = self.script.get(name, self.script.get("*"))
        if isinstance(outcome, Exception):
            raise outcome
        return outcome


class _FakeClient:
    def __init__(self, script: dict[str, object], sink: list):
        self.chat = SimpleNamespace(completions=_FakeCompletions(script))
        sink.append(self.chat.completions)


def _patch_client(monkeypatch, script: dict[str, object]):
    import openai

    sink: list[_FakeCompletions] = []

    def factory(**kwargs):
        return _FakeClient(script, sink)

    monkeypatch.setattr(openai, "AsyncOpenAI", factory, raising=False)
    return sink


def _configured_layer(monkeypatch, disable_thinking: str = "1") -> CloudLayer:
    monkeypatch.setenv("LLM_API_KEY", "test-key")
    monkeypatch.setenv("LLM_BASE_URL", "https://example.invalid/v1")
    monkeypatch.setenv("LLM_MODEL", "unit-model")
    monkeypatch.setenv("LLM_DISABLE_THINKING", disable_thinking)
    monkeypatch.setenv("LLM_MAX_RETRIES", "0")
    monkeypatch.setenv("LLM_TIMEOUT", "5")
    return CloudLayer()


REQ = LLMRequest(key="unit", prompt="请解释实践概念")


@pytest.mark.asyncio
async def test_403_on_first_variant_falls_to_next_compatible_param(monkeypatch):
    """403 不再退回标准参数（标准参数在长 prompt 下必然空正文）。"""
    sink = _patch_client(monkeypatch, {
        "thinking": PermissionError("403 request illegal"),
        "enable_thinking": _resp(_msg("这是真实模型正文")),
        "standard": _resp(_msg("", "一大段思维链")),
    })
    layer = _configured_layer(monkeypatch)
    r = await layer.run(REQ)
    assert r.source == "cloud" and r.text == "这是真实模型正文"
    # 关键：调用顺序里不能出现 standard
    assert sink[0].calls == ["thinking", "enable_thinking"]


@pytest.mark.asyncio
async def test_empty_body_is_not_an_answer_and_triggers_next_variant(monkeypatch):
    """正文为空时换参数，且不会跳过兼容参数直接降级 Mock。"""
    sink = _patch_client(monkeypatch, {
        "standard": _resp(_msg("", "思维链吃满预算")),
        "thinking": _resp(_msg("正统原理解释")),
    })
    # 显式关掉开关 → 先试 standard（空正文）→ 自动自救到 thinking
    layer = _configured_layer(monkeypatch, disable_thinking="0")
    r = await layer.run(REQ)
    assert r.source == "cloud" and r.text == "正统原理解释"
    assert sink[0].calls == ["standard", "thinking"]


@pytest.mark.asyncio
async def test_all_variants_fail_reports_real_reason(monkeypatch):
    """全部失败时降级 Mock，但文案写明真实原因，不再说「缺 LLM_API_KEY」。"""
    _patch_client(monkeypatch, {
        "*": RuntimeError("上游不可用"),
    })
    layer = _configured_layer(monkeypatch)
    r = await layer.run(REQ)
    assert r.source == "mock"
    assert "真实模型调用失败" in r.text
    assert "上游不可用" in r.text
    assert "缺 LLM_API_KEY" not in r.text


@pytest.mark.asyncio
async def test_disable_thinking_uses_most_stable_variant_first(monkeypatch):
    """默认开启时优先用实测最稳的单参数 thinking，而不是 both / standard。"""
    sink = _patch_client(monkeypatch, {
        "*": _resp(_msg("OK")),
    })
    layer = _configured_layer(monkeypatch)
    r = await layer.run(REQ)
    assert r.source == "cloud"
    assert sink[0].calls == ["thinking"]
