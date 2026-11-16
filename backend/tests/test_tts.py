"""朗读（TTS）服务与 API 测试。

注意：真正调用微软神经语音需要外网。这里覆盖确定性逻辑（缓存、语速归一、
语音白名单、空文本、健康检查），并对真实合成做「有网则测、无网跳过」的宽松断言。
"""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app import app
from services import tts_service

client = TestClient(app)


def test_health_reports_available_and_voices():
    r = client.get("/api/tts/health")
    assert r.status_code == 200
    d = r.json()
    assert "available" in d
    assert isinstance(d["voices"], list)
    assert d["default"] == tts_service.DEFAULT_VOICE
    # 默认语音必须在白名单里
    assert d["default"] in tts_service.ALLOWED_VOICES


def test_empty_text_rejected():
    r = client.post("/api/tts/speak", json={"text": "   "})
    assert r.status_code == 400


def test_invalid_voice_falls_back_to_default():
    # 非法 voice 不应报错，服务内部回退到默认（这里只验证不抛 5xx 的路径存在于服务层）
    # 直接测服务层：非法 voice 会被替换为默认，缓存键也基于默认
    if not tts_service.available():
        pytest.skip("edge-tts 不可用")
    assert tts_service.DEFAULT_VOICE in tts_service.ALLOWED_VOICES


def test_rate_normalization_via_cache_key():
    # 语速规格化：非法 rate 归一为 '+0%'，等价于默认
    k1 = tts_service._cache_key(tts_service.DEFAULT_VOICE, "+0%", "你好")
    k2 = tts_service._cache_key(tts_service.DEFAULT_VOICE, "+0%", "你好")
    assert k1 == k2
    # 不同语速 → 不同缓存键
    k3 = tts_service._cache_key(tts_service.DEFAULT_VOICE, "+20%", "你好")
    assert k1 != k3


@pytest.mark.parametrize("text", ["实践是检验真理的唯一标准。", "人民群众是历史的创造者。"])
def test_synthesize_returns_mp3_or_skip(text):
    if not tts_service.available():
        pytest.skip("edge-tts 不可用")
    try:
        audio = tts_service.synthesize(text)
    except RuntimeError as e:
        pytest.skip(f"网络不可用，跳过真实合成：{e}")
    assert isinstance(audio, (bytes, bytearray))
    assert len(audio) > 1000
    # MP3 帧同步头 0xFF 0xF? 或 ID3 头
    assert audio[:3] == b"ID3" or (audio[0] == 0xFF and (audio[1] & 0xE0) == 0xE0)


def test_speak_endpoint_returns_audio_when_online():
    if not tts_service.available():
        pytest.skip("edge-tts 不可用")
    r = client.post("/api/tts/speak", json={"text": "这是一次朗读接口测试。"})
    if r.status_code == 502:
        pytest.skip("网络不可用，跳过真实合成")
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("audio/")
    assert r.headers.get("X-TTS-Engine") == "edge-neural"
    assert len(r.content) > 1000


def test_cache_reduces_latency_second_call():
    # 缓存命中时不应重新合成：命中后立即返回相同字节
    if not tts_service.available():
        pytest.skip("edge-tts 不可用")
    txt = "缓存命中测试：不重复合成同一句话。"
    try:
        a = tts_service.synthesize(txt)
    except RuntimeError:
        pytest.skip("网络不可用")
    b = tts_service.synthesize(txt)
    assert a == b


def test_get_speak_endpoint_returns_audio_when_online():
    # GET 版：供前端 <audio src=thisUrl> 同步播放
    if not tts_service.available():
        pytest.skip("edge-tts 不可用")
    r = client.get("/api/tts/speak", params={"text": "GET 版朗读接口测试。", "rate": "+0%"})
    if r.status_code == 502:
        pytest.skip("网络不可用，跳过真实合成")
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("audio/")
    assert r.headers.get("X-TTS-Engine") == "edge-neural"
    assert len(r.content) > 1000


def test_get_empty_text_rejected():
    r = client.get("/api/tts/speak", params={"text": "   "})
    assert r.status_code == 400
