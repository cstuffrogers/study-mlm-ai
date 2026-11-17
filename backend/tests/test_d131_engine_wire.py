"""D131 门禁：服务端 ai_message 必须带「作答引擎」标注，且与单机版同口径。

这条链曾经三处漂移：`dialogue_service` 算了 `llm_source` 也塞进了 ai_message，
但 `AiMessageOut` 没这个字段，pydantic 静默丢掉 → 前端浮窗徽标在**联网模式永远空白**
（单机版 `local_dialogue.dart` 会发 engine/engine_note，所以只有联网时界面不一致）。
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from fastapi.testclient import TestClient  # noqa: E402

from app import app  # noqa: E402
from core.llm.base import LLMResponse  # noqa: E402
from services.dialogue_service import _engine_of  # noqa: E402

client = TestClient(app)


def test_engine_of_mapping() -> None:
    assert _engine_of(LLMResponse("t", "cloud", model="qwen-plus")) == "cloud:qwen-plus"
    assert _engine_of(LLMResponse("t", "cloud")) == "cloud"
    assert _engine_of(LLMResponse("t", "mock", note="failed:x")) == "local"
    assert _engine_of(LLMResponse("t", "cache", cached=True)) == "cache"


def test_ws_ai_message_carries_engine() -> None:
    """真连一次 WS：返回的 ai_message 必须有 engine，降级时还要有原因。"""
    ai = None
    with client.websocket_connect("/ws/dialogue") as ws:
        ws.send_text(json.dumps({
            "type": "user_message", "dialogue_id": "d_engine_probe",
            "content": "实践是检验真理的唯一标准，为什么？",
            "mode": "socratic", "user_id": "demo_user",
        }))
        for _ in range(4):
            msg = json.loads(ws.receive_text())
            if msg.get("type") == "ai_message":
                ai = msg
                break
            if msg.get("type") in ("blocked", "error"):
                break
    assert ai is not None, "WS 没有返回 ai_message"
    engine = ai.get("engine", "")
    assert engine, "ai_message 缺 engine（前端徽标会空白）"
    assert engine in ("cache", "cloud", "local") or engine.startswith("cloud:"), engine
    if ai.get("llm_source") == "mock":
        assert ai.get("engine") == "local", "Mock 必须标成本机引擎，不能冒充在线模型"
        note = ai.get("engine_note", "")
        assert note.startswith(("not-configured", "failed:")), \
            f"降级原因口径不对：{note!r}（前端按这两个前缀出文案）"


def test_protocol_keeps_engine_fields() -> None:
    from websocket.protocol import AiMessageOut

    m = AiMessageOut(content="x", mode="socratic", engine="cloud:qwen-plus",
                     engine_note="failed:401", llm_source="cloud")
    dumped = json.loads(m.model_dump_json())
    for k in ("engine", "engine_note", "llm_source"):
        assert k in dumped, f"协议丢了 {k}"
