"""神经网络语音合成（TTS）服务 —— 基于微软 Edge 神经语音（edge-tts）。

为什么要它：Windows 10 自带、且夸克/Chrome 暴露给网页的 `speechSynthesis` 语音，
只有 2010 年代的老式 SAPI「机器腔」（Huihui/Kangkang/Yaoyao），读中文非常生硬。
浏览器端 speechSynthesis 无法调用更好的语音。

本服务在后端用 `edge-tts` 调用微软 Edge 的在线神经语音（如 zh-CN-XiaoxiaoNeural
「晓晓」、zh-CN-YunxiNeural「云希」），合成真人级 MP3，前端直接播放。
纯确定性工程：不训练、不蒸馏、不接大模型，只调用现成语音合成。

设计要点：
- 结果做**内容寻址缓存**（key = voice|rate|text），热门句子（课文、导读、常见问答）
  只合成一次，重复朗读命中缓存近乎零延迟。
- 合成失败 / 离线时抛异常，由前端**回退**到浏览器原生 speechSynthesis，功能不中断。
- 语音白名单，避免任意文本 + 任意 voice 被滥用。
"""
from __future__ import annotations

import asyncio
import hashlib
import threading
import time
from collections import OrderedDict
from typing import Optional

try:  # edge-tts 为可选依赖：缺失时本服务优雅降级（available=False）
    import edge_tts  # type: ignore
    _EDGE_OK = True
except Exception:  # pragma: no cover
    edge_tts = None  # type: ignore
    _EDGE_OK = False

# 允许的神经语音（全部为 zh-CN 普通话；默认「晓晓」，最自然温和）
DEFAULT_VOICE = "zh-CN-XiaoxiaoNeural"
ALLOWED_VOICES = {
    "zh-CN-XiaoxiaoNeural",   # 女·温暖
    "zh-CN-XiaoyiNeural",     # 女·活泼
    "zh-CN-YunxiNeural",      # 男·阳光
    "zh-CN-YunyangNeural",    # 男·专业
    "zh-CN-YunjianNeural",    # 男·激昂
    "zh-CN-YunxiaNeural",     # 男·可爱
    "zh-CN-liaoning-XiaobeiNeural",  # 女·东北
    "zh-CN-shaanxi-XiaoniNeural",    # 女·陕西
}

_MAX_TEXT = 4000          # 单次朗读上限（防滥用）
_CACHE_MAX = 256          # 缓存条目上限
# 内存缓存总字节上限：只按条目数限时，长段落（4000 字 ≈ 1~2MB MP3）
# 能把 256 条堆到几十上百 MB。语音是临时产物，堆着没用。
_CACHE_MAX_BYTES = 48 * 1024 * 1024
_SYNTH_TIMEOUT = 20.0     # 单次合成超时（秒）

_cache: "OrderedDict[str, bytes]" = OrderedDict()
_cache_lock = threading.Lock()
_cache_bytes_total = 0


def available() -> bool:
    return _EDGE_OK


def _cache_key(voice: str, rate: str, text: str) -> str:
    h = hashlib.sha256()
    h.update(voice.encode("utf-8"))
    h.update(b"\x00")
    h.update(rate.encode("utf-8"))
    h.update(b"\x00")
    h.update(text.encode("utf-8"))
    return h.hexdigest()


def _cache_get(key: str) -> Optional[bytes]:
    with _cache_lock:
        if key in _cache:
            _cache.move_to_end(key)
            return _cache[key]
    return None


def _cache_put(key: str, data: bytes) -> None:
    global _cache_bytes_total
    with _cache_lock:
        old = _cache.pop(key, None)
        if old is not None:
            _cache_bytes_total -= len(old)
        _cache[key] = data
        _cache_bytes_total += len(data)
        # 双上限：条目数 + 总字节。逐个淘汰最旧的，最后一条无论多大都留着
        # （刚合成完马上要返回给它，淘汰了等于白合成）。
        while len(_cache) > _CACHE_MAX or (
            _cache_bytes_total > _CACHE_MAX_BYTES and len(_cache) > 1
        ):
            _, dropped = _cache.popitem(last=False)
            _cache_bytes_total -= len(dropped)


async def _synth_async(text: str, voice: str, rate: str) -> bytes:
    comm = edge_tts.Communicate(text, voice, rate=rate)
    buf = bytearray()
    async for chunk in comm.stream():
        if chunk.get("type") == "audio":
            buf.extend(chunk["data"])
    return bytes(buf)


def synthesize(text: str, voice: str = DEFAULT_VOICE, rate: str = "+0%") -> bytes:
    """把文本合成为 MP3 字节。命中缓存直接返回；失败抛 RuntimeError。"""
    if not _EDGE_OK:
        raise RuntimeError("edge-tts 不可用")
    t = (text or "").strip()
    if not t:
        raise ValueError("文本为空")
    if len(t) > _MAX_TEXT:
        t = t[:_MAX_TEXT]
    if voice not in ALLOWED_VOICES:
        voice = DEFAULT_VOICE
    # rate 归一：允许 "+10%" / "-5%" / "0%"；空或非法则用默认
    r = (rate or "+0%").strip()
    if not r or r[-1] != "%":
        r = "+0%"

    key = _cache_key(voice, r, t)
    hit = _cache_get(key)
    if hit is not None:
        return hit

    # edge-tts 是异步的；在同步接口里用独立事件循环跑，并加超时。
    async def _runner() -> bytes:
        return await asyncio.wait_for(_synth_async(t, voice, r), timeout=_SYNTH_TIMEOUT)

    def _one_attempt() -> bytes:
        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            loop = None
        if loop is not None:
            # 已在事件循环内（不应发生在同步路由里）：新建线程跑
            result: dict = {}
            err: dict = {}

            def _worker():
                try:
                    result["data"] = asyncio.run(_runner())
                except Exception as e:  # pragma: no cover
                    err["e"] = e

            th = threading.Thread(target=_worker)
            th.start()
            th.join()
            if "e" in err:
                raise err["e"]
            return result.get("data", b"")
        return asyncio.run(_runner())

    # 失败重试一次：连续朗读时请求密集，微软侧偶发连接重置/限流/慢响应，
    # 这类瞬时故障重试一次基本能接上。不重试的话前端只能回退浏览器机器腔，
    # 用户听感就是「念着念着突然变声」。
    last_err: Exception | None = None
    for _attempt in range(2):
        try:
            data = _one_attempt()
            if not data:
                raise RuntimeError("语音合成返回空音频")
            _cache_put(key, data)
            return data
        except Exception as e:
            last_err = e
            if _attempt == 0:
                time.sleep(0.8)
    raise RuntimeError(f"语音合成失败：{last_err}") from last_err


def cache_size() -> int:
    with _cache_lock:
        return len(_cache)


def cache_bytes() -> int:
    """缓存占用的内存字节数（给容量门禁与排查用）。"""
    with _cache_lock:
        return _cache_bytes_total


def cache_clear() -> None:
    """主动清空语音缓存。语音是临时产物，不需要跨会话留着。"""
    global _cache_bytes_total
    with _cache_lock:
        _cache.clear()
        _cache_bytes_total = 0
