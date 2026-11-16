"""云层 — 国产大模型接入点（OpenAI 兼容协议）

配齐凭证后走真实国产模型（通义/文心/DeepSeek 等，均提供 OpenAI 兼容端点）。
未配齐凭证、或真实调用失败/超时，都回退 Mock，并在文案里写明真实原因，
避免把「调用超时」误报成「缺 LLM_API_KEY」。

接入方式：在 .env 或功能中心设置 LLM_API_KEY / LLM_BASE_URL / LLM_MODEL。
"""
from __future__ import annotations

import asyncio
import logging
import os
from typing import Optional

from core.llm.base import LLMRequest, LLMResponse

logger = logging.getLogger(__name__)

# 国产模型 OpenAI 兼容端点速查（仅供文档化，实际读 env）
PROVIDER_PRESETS: dict[str, dict[str, str]] = {
    "qwen": {"base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1", "model": "qwen-plus"},
    "wenxin": {"base_url": "https://qianfan.baidubce.com/v2", "model": "ernie-4.0-8k"},
    "deepseek": {"base_url": "https://api.deepseek.com/v1", "model": "deepseek-chat"},
}


class CloudLayer:
    """云 LLM 层"""

    def __init__(self) -> None:
        self._refresh()

    def _refresh(self) -> None:
        """每次调用前重读 os.environ：功能中心保存配置后无需重启/重连 WS 即生效。"""
        self.api_key = os.getenv("LLM_API_KEY", "").strip()
        self.base_url = os.getenv("LLM_BASE_URL", "").strip()
        self.model = os.getenv("LLM_MODEL", "").strip()
        self.max_retries = int(os.getenv("LLM_MAX_RETRIES", "2"))
        # 单次请求超时，避免端点无响应时永达阻塞（缺省 30s）
        # 交互式对话（/ws/dialogue）用 LLM_INTERACTIVE_TIMEOUT 收紧；云端点不通时
        # 要快速降级 Mock，不能让「选中文字 → 释义」等到 WS 40s 超时。
        self.timeout = float(os.getenv("LLM_TIMEOUT", "60"))
        # 交互式默认给 30s：带思维链的国产模型即使是 flash 版，完整答完
        # 300~800 字也常需 10~15s；旧的 12s 会让「配置成功但对话仍 Mock」。
        self.interactive_timeout = float(os.getenv("LLM_INTERACTIVE_TIMEOUT", "30"))
        # 限制单次生成长度。推理型模型若不限 max_tokens，会先写一大段
        # reasoning_content 再写正文，耗时可达 80s+（必然超时降级 Mock）。
        self.max_tokens = _env_int("LLM_MAX_TOKENS", 2048)
        # 推理型模型（DeepSeek v4 / Qwen thinking 等）默认先输出长思维链，
        # 会把 max_tokens 预算吃光导致正文为空。LLM_DISABLE_THINKING=1 时
        # 传入各家通用的关闭开关；非推理模型会忽略或报参数错误，届时自动重试。
        self.disable_thinking = os.getenv(
            "LLM_DISABLE_THINKING", "1").strip().lower() in ("1", "true", "yes")
        self.enabled = bool(self.api_key and self.base_url and self.model)

    async def run(self, req: LLMRequest, interactive: bool = False) -> LLMResponse:
        """interactive=True（WebSocket 对话）：用更短的超时并关闭重试。"""
        self._refresh()
        if not self.enabled:
            return self._mock(req, self._missing_reason())

        try:
            return await self._call(
                req,
                timeout=self.interactive_timeout if interactive else self.timeout,
                retries=0 if interactive else self.max_retries,
            )
        except Exception as e:
            logger.warning("云 LLM 调用失败，降级 Mock: %s", e)
            reason = f"真实模型调用失败（{type(e).__name__}: {e}），已降级"
            return self._mock(req, reason)

    def _missing_reason(self) -> str:
        missing = [n for n, v in (
            ("LLM_API_KEY", self.api_key),
            ("LLM_BASE_URL", self.base_url),
            ("LLM_MODEL", self.model),
        ) if not v]
        return f"真实国产模型未配置（缺 {'、'.join(missing)}）" if missing else "真实国产模型未启用"

    async def _call(
        self,
        req: LLMRequest,
        timeout: float | None = None,
        retries: int | None = None,
    ) -> LLMResponse:
        """真实国产模型调用（OpenAI 兼容）"""
        try:
            from openai import AsyncOpenAI  # type: ignore
        except ImportError as e:
            raise RuntimeError("openai 包未安装，无法走真实 LLM") from e

        # timeout：连接/读超时，确保慢/不通的端点不会无限挂起；
        # max_retries=0：重试由下面的 for 循环控制，避免外层再叠一层指数退避重试。
        eff_timeout = self.timeout if timeout is None else timeout
        eff_retries = self.max_retries if retries is None else retries
        client = AsyncOpenAI(
            api_key=self.api_key,
            base_url=self.base_url,
            timeout=eff_timeout,
            max_retries=0,
        )
        # 推理型模型「关闭思维链」的兼容参数各家不一，而且同一中转对
        # 「多个私有参数同时传」会间歇性 403（实测长 prompt 下 403 / 正常交替）。
        # 更糟的是：不带私有参数时，思维链会吃满 max_tokens 导致正文为空。
        # 因此按实测稳定性排好优先级，逐个策略试；「正文为空」不是致命错误，
        # 而是「这组参数不行」的信号，立即换下一组，而不是原地重试或退回标准参数。
        _THINK = {"thinking": {"type": "disabled"}}
        _ENABLE = {"enable_thinking": False}
        _BOTH = {"thinking": {"type": "disabled"}, "enable_thinking": False}
        if self.disable_thinking:
            variants: list[tuple[str, Optional[dict]]] = [
                ("thinking", _THINK),          # 实测长 prompt 5/5 成功，最稳
                ("enable_thinking", _ENABLE),
                ("both", _BOTH),
                ("standard", None),            # 最后兜底：可能只回思维链
            ]
        else:
            # 用户显式关闭该开关时先按标准参数试；若正文为空仍自动自救，
            # 避免「关掉开关 → 长 prompt 必然空正文 → 必然 Mock」。
            variants = [("standard", None), ("thinking", _THINK), ("enable_thinking", _ENABLE)]

        loop = asyncio.get_running_loop()
        deadline = loop.time() + eff_timeout
        errors: list[str] = []
        empty_body = 0

        for name, extra in variants:
            for attempt in range(eff_retries + 1):
                remaining = deadline - loop.time()
                if remaining <= 0:
                    errors.append("总超时预算耗尽")
                    break
                try:
                    create_kwargs = dict(
                        model=self.model,
                        messages=[{"role": "user", "content": req.prompt}],
                        temperature=0.3,
                        max_tokens=self.max_tokens,
                        extra_body=extra,
                    )
                    # 单请求也受总预算约束，避免逐级降级把 WS 超时拖爆。
                    resp = await asyncio.wait_for(
                        client.chat.completions.create(**create_kwargs),
                        timeout=min(eff_timeout, remaining),
                    )
                    msg = resp.choices[0].message
                    text = msg.content or ""
                    if text.strip():
                        if name != variants[0][0]:
                            logger.info("云 LLM 用兼容参数 %s 成功返回正文", name)
                        return LLMResponse(text=text, source="cloud")
                    # 正文为空：预算被 reasoning_content 吃光。同一参数重试几乎
                    # 必然还是空，直接换下一组兼容策略（不能把思维链当答案）。
                    reason_len = len(getattr(msg, "reasoning_content", "") or "")
                    errors.append(f"{name}: 正文为空(思维链 {reason_len} 字)")
                    empty_body += 1
                    logger.warning("云 LLM 参数 %s 只返回思维链、正文为空，换兼容参数重试", name)
                    break  # 跳出本策略的重试循环
                except Exception as e:
                    errors.append(f"{name}: {type(e).__name__}: {str(e)[:100]}")
                    logger.info("云 LLM 参数 %s 第 %d 次失败: %s", name, attempt + 1, e)
                    if attempt < eff_retries:
                        await asyncio.sleep(0.5 * (attempt + 1))
            if errors and errors[-1].startswith("总超时预算"):
                break

        detail = "；".join(errors[-4:]) if errors else "无可用响应"
        hint = "（推理型模型思维链吃满 max_tokens）" if empty_body else ""
        raise RuntimeError(f"云 LLM 所有兼容参数均失败{hint}: {detail}")

    def _mock(self, req: LLMRequest, reason: str = "") -> LLMResponse:
        """Mock 占位 — 回退时说明真实原因，保持防偏离链路可联调"""
        prompt_tail = req.prompt[-80:].replace("\n", " ")
        text = (
            f"【Mock LLM】{reason or '真实国产模型未启用'}。"
            f"收到 prompt 末尾: …{prompt_tail}"
        )
        return LLMResponse(text=text, source="mock")


def _env_int(name: str, default: int) -> int:
    try:
        return max(1, int(float(os.getenv(name, default))))
    except (TypeError, ValueError):
        return default
