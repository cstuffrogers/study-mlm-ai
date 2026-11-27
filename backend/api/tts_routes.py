"""朗读（TTS）API —— 神经语音合成，供前端直接播放 MP3。

- GET  /api/tts/health   → {available, voices, default}
- POST /api/tts/speak    → body {text, voice?, rate?}，返回 audio/mpeg 字节

前端播放策略：先调本接口拿微软神经语音 MP3（真人级），
失败（离线/未安装 edge-tts/合成超时）再回退到浏览器原生 speechSynthesis。
"""
from __future__ import annotations

from fastapi import APIRouter, HTTPException, Response
from pydantic import BaseModel, Field

from services import tts_service

router = APIRouter()


class SpeakIn(BaseModel):
    text: str = Field(..., description="要朗读的纯文本（前端已剥离 Markdown/LaTeX）")
    voice: str | None = Field(None, description="神经语音 ShortName；默认晓晓")
    rate: str | None = Field(None, description="语速，如 '+10%' / '-5%'")
    pitch: str | None = Field(None, description="音调偏移，如 '-3Hz' / '+10Hz'；不传用微软默认")


@router.get("/health")
def tts_health():
    return {
        "available": tts_service.available(),
        "voices": sorted(tts_service.ALLOWED_VOICES),
        "default": tts_service.DEFAULT_VOICE,
    }


@router.post("/speak")
def tts_speak(body: SpeakIn):
    text = (body.text or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="文本为空")
    if not tts_service.available():
        raise HTTPException(status_code=503, detail="神经语音不可用（edge-tts 未安装）")
    try:
        audio = tts_service.synthesize(
            text,
            voice=body.voice or tts_service.DEFAULT_VOICE,
            rate=body.rate or "+0%",
            pitch=body.pitch or "",
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:  # 网络/服务端错误 → 前端回退浏览器语音
        raise HTTPException(status_code=502, detail=f"语音合成失败：{e}")
    return Response(
        content=audio,
        media_type="audio/mpeg",
        headers={
            # 语音是按需合成的**临时产物**：一段几百 KB，读一本书能堆到几十 MB。
            # no-store 明确告诉浏览器/中间层「别落盘」：播完就只剩内存里那一小段。
            # 重复念同一段仍有后端内存缓存兜底，不会重新调微软。
            "Cache-Control": "no-store, max-age=0",
            "X-TTS-Engine": "edge-neural",
        },
    )


@router.get("/speak")
def tts_speak_get(
    text: str,
    voice: str | None = None,
    rate: str | None = None,
    pitch: str | None = None,
):
    """GET 版朗读：让前端可把 <audio src=此URL> 并「同步」调用 play()。

    关键：把合成放在「媒体流式下载」里，前端在点击手势内同步 play()，
    不会被浏览器自动播放策略拦截（异步 XHR+play 则会丢用户手势而失败）。
    """
    t = (text or "").strip()
    if not t:
        raise HTTPException(status_code=400, detail="文本为空")
    if not tts_service.available():
        raise HTTPException(status_code=503, detail="神经语音不可用（edge-tts 未安装）")
    try:
        audio = tts_service.synthesize(
            t,
            voice=voice or tts_service.DEFAULT_VOICE,
            rate=rate or "+0%",
            pitch=pitch or "",
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"语音合成失败：{e}")
    return Response(
        content=audio,
        media_type="audio/mpeg",
        headers={
            # 语音是按需合成的**临时产物**：一段几百 KB，读一本书能堆到几十 MB。
            # no-store 明确告诉浏览器/中间层「别落盘」：播完就只剩内存里那一小段。
            # 重复念同一段仍有后端内存缓存兜底，不会重新调微软。
            "Cache-Control": "no-store, max-age=0",
            "X-TTS-Engine": "edge-neural",
        },
    )
