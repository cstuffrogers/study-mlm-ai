"""大模型 API 运行时配置 — 供功能中心「LLM 大模型 API 配置」页面读写。

设计：
  · 页面保存的凭证写入本机 backend/.llm_config.json（自动加入 .gitignore，
    不会进正文库/版本库），进程内立即 os.environ 生效，无需重启后端。
  · 配置优先级：页面保存值 > 缺省值（**不再回落 .env**，运行时只认 web 端输入）。
  · GET 永不回传完整密钥，只给 masked 掩码与来源，避免前端泄露。
  · 清空某字段 = 恢复 .env / 缺省值。
  · 内置 provider 预设只帮用户填 base_url / model，不上传任何密钥。
  · 测试连接：用当前配置真实发一条极短 prompt，返回 ok/source/耗时/错误，
    不做缓存、不写 DB；失败也不影响已保存配置。
"""
from __future__ import annotations

import json
import logging
import os
import re
import threading
from pathlib import Path

from core.llm.cloud import PROVIDER_PRESETS

logger = logging.getLogger(__name__)

_CONFIG_PATH = Path(__file__).resolve().parents[1] / ".llm_config.json"
_KEYS = ("LLM_API_KEY", "LLM_BASE_URL", "LLM_MODEL", "LLM_MAX_CONCURRENT",
         "LLM_MAX_RETRIES", "LLM_TIMEOUT", "LLM_INTERACTIVE_TIMEOUT",
         "LLM_MAX_TOKENS", "LLM_DISABLE_THINKING")
_DEFAULTS = {
    "LLM_BASE_URL": "https://dashscope.aliyuncs.com/compatible-mode/v1",
    "LLM_MODEL": "qwen-plus",
}
_LOCK = threading.Lock()


def _read_file() -> dict[str, str]:
    try:
        data = json.loads(_CONFIG_PATH.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            return {k: str(v) for k, v in data.items() if k in _KEYS and v is not None}
    except (OSError, ValueError):
        pass
    return {}


def _baseline(key: str) -> str:
    """页面未覆盖时的值：.env 环境变量或缺省。"""
    return os.getenv(key, _DEFAULTS.get(key, ""))


def apply_to_environment() -> dict[str, str]:
    """把页面保存的值覆盖到 os.environ；返回实际生效的完整配置。

    **只认 web 端（功能中心）写入的 .llm_config.json，不再从 .env 回填**：
    页面没配或配空的项，用硬编码缺省值（仅 base_url / model 有），其余直接
    从 os.environ 移除，避免 .env 里的旧值漏进运行时。web 端输入什么，
    对话引擎就用什么。

    CloudLayer / LLMRouter 每次构造都重新读取 os.environ，因此保存后立即生效。
    """
    saved = _read_file()
    eff: dict[str, str] = {}
    with _LOCK:
        for key in _KEYS:
            val = saved.get(key, "").strip()
            if val:
                os.environ[key] = val
                eff[key] = val
            else:
                default = _DEFAULTS.get(key, "")
                if default:
                    os.environ[key] = default
                    eff[key] = default
                else:
                    os.environ.pop(key, None)
                    eff[key] = ""
    return eff


def masked(secret: str) -> str:
    if not secret:
        return ""
    if len(secret) <= 8:
        return "••••••••"
    return f"{secret[:4]}••••{secret[-4:]}"


def current_status() -> dict:
    """给前端的状态：只回传掩码，不回传完整密钥。"""
    saved = _read_file()
    eff = apply_to_environment()
    key = eff.get("LLM_API_KEY", "")
    sources = {k: ("页面配置" if saved.get(k, "").strip() else "缺省") for k in _KEYS}
    return {
        "configured": bool(key and eff.get("LLM_BASE_URL") and eff.get("LLM_MODEL")),
        "masked_api_key": masked(key),
        "base_url": eff.get("LLM_BASE_URL", ""),
        "model": eff.get("LLM_MODEL", ""),
        "max_concurrent": _safe_int(eff.get("LLM_MAX_CONCURRENT"), 3),
        "max_retries": _safe_int(eff.get("LLM_MAX_RETRIES"), 2),
        "timeout": _safe_float(eff.get("LLM_TIMEOUT"), 60.0),
        "interactive_timeout": _safe_float(eff.get("LLM_INTERACTIVE_TIMEOUT"), 30.0),
        "max_tokens": _safe_int(eff.get("LLM_MAX_TOKENS"), 2048),
        "disable_thinking": str(eff.get("LLM_DISABLE_THINKING", "1")).lower()
                            in ("1", "true", "yes"),
        "source": sources,
        "presets": {
            name: {"base_url": p["base_url"], "model": p["model"]}
            for name, p in PROVIDER_PRESETS.items()
        },
        "config_path": str(_CONFIG_PATH),
    }


def _safe_int(v: str | None, d: int) -> int:
    try:
        return int(float(v or d))
    except (TypeError, ValueError):
        return d


def _safe_float(v: str | None, d: float) -> float:
    try:
        return float(v or d)
    except (TypeError, ValueError):
        return d


def save(payload: dict) -> dict:
    """保存页面提交的值；api_key 为空字符串表示「不修改已有密钥」。

    api_key == "__CLEAR__" 表示明确清空密钥（回落到 Mock）。
    """
    saved = _read_file()
    new_key = str(payload.get("api_key") or "").strip()
    if new_key == "__CLEAR__":
        saved.pop("LLM_API_KEY", None)
        os.environ.pop("LLM_API_KEY", None)
    elif new_key:
        if not re.fullmatch(r"[\x20-\x7e]+", new_key):
            raise ValueError("API Key 只能包含 ASCII 可打印字符")
        saved["LLM_API_KEY"] = new_key
    # 注意：Pydantic model_dump() 会把未提供的字段也序列化成 None；
    # None = 「本次不修改」，空字符串 = 「显式恢复缺省」，不能混为一谈，
    # 否则只改 model 会把 .env 里的真实端点悄悄重置成预设值。
    base_raw = payload.get("base_url")
    if base_raw is not None:
        base = str(base_raw).strip()
        if base:
            if not re.match(r"^https?://[^\s]+$", base):
                raise ValueError("Base URL 必须是 http(s):// 开头的合法地址")
            saved["LLM_BASE_URL"] = base.rstrip("/")
        else:
            saved["LLM_BASE_URL"] = _DEFAULTS["LLM_BASE_URL"]
    model_raw = payload.get("model")
    if model_raw is not None:
        model = str(model_raw).strip()
        saved["LLM_MODEL"] = model or _DEFAULTS["LLM_MODEL"]
    for field, key, lo, hi in (
        ("max_concurrent", "LLM_MAX_CONCURRENT", 1, 16),
        ("max_retries", "LLM_MAX_RETRIES", 0, 5),
        ("timeout", "LLM_TIMEOUT", 3.0, 180.0),
        ("interactive_timeout", "LLM_INTERACTIVE_TIMEOUT", 3.0, 120.0),
        ("max_tokens", "LLM_MAX_TOKENS", 128, 8192),
    ):
        if field in payload and payload[field] is not None:
            raw = str(payload[field]).strip()
            if not raw:
                saved.pop(key, None)
                continue
            try:
                num = float(raw)
            except ValueError as e:
                raise ValueError(f"{field} 必须是数字") from e
            if not lo <= num <= hi:
                raise ValueError(f"{field} 必须在 {lo:g}–{hi:g} 之间")
            saved[key] = str(int(num)) if num.is_integer() else str(num)
    dt_raw = payload.get("disable_thinking")
    if dt_raw is not None:
        saved["LLM_DISABLE_THINKING"] = (
            "1" if str(dt_raw).strip().lower() in ("1", "true", "yes") else "0"
        )

    _CONFIG_PATH.write_text(
        json.dumps(saved, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    try:
        _CONFIG_PATH.chmod(0o600)
    except OSError:  # Windows 可能不支持 posix chmod
        pass
    # 立即覆盖进程环境；CloudLayer 每次 run() 都 _refresh()，下次请求即读新值。
    apply_to_environment()
    from core.llm.router import bump_cache_epoch
    bump_cache_epoch()  # 已存在的 DialogueService/LLMRouter 缓存键也随 epoch 变化
    return current_status()


async def test_connection() -> dict:
    """用当前生效配置真实调用一次；不缓存、不重试、不写 DB。"""
    import time
    from core.llm.base import LLMRequest
    from core.llm.cloud import CloudLayer

    eff = apply_to_environment()
    if not (eff.get("LLM_API_KEY") and eff.get("LLM_BASE_URL") and eff.get("LLM_MODEL")):
        return {"ok": False, "message": "未配齐 API Key / Base URL / 模型，当前为 Mock 模式"}
    cloud = CloudLayer()
    req = LLMRequest(key="config-test", prompt="请只回复：连接成功", task="general", complexity=0.1)
    t0 = time.perf_counter()
    try:
        # 直接用 _call 绕过 run() 的「失败自动降级 Mock」，否则测不出真实故障
        resp = await cloud._call(req, timeout=min(cloud.timeout, 15.0), retries=0)
        return {
            "ok": resp.source == "cloud",
            "source": resp.source,
            "model": cloud.model,
            "elapsed_ms": int((time.perf_counter() - t0) * 1000),
            "message": "连接成功，模型已返回文本" if resp.source == "cloud" else "未返回云端文本",
            "preview": (resp.text or "")[:80],
        }
    except Exception as e:
        return {
            "ok": False,
            "source": "error",
            "model": cloud.model,
            "elapsed_ms": int((time.perf_counter() - t0) * 1000),
            "message": f"连接失败：{e}",
        }
