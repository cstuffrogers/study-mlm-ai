"""LLM 4级路由: cache → (semantic) → cloud/mock

移植自 ljsk router.py，精简掉 distill/local（依赖 embedding + 本地模型，MVP 不引入）。
保留 4 级骨架与接口，后续按需补层。

路由顺序：
  L1 精确缓存命中 → 直接返回
  L2 云层（真实国产模型，未配置则 Mock）

Phase 3 关键：生成侧回答统一走 router.generate()，便于缓存与降级。
"""
from __future__ import annotations

import hashlib
import logging
from typing import Optional

from core.llm.base import LLMRequest, LLMResponse
from core.llm.cache import CacheLayer
from core.llm.cloud import CloudLayer

logger = logging.getLogger(__name__)

# 配置变更后递增：让所有已存在的 LLMRouter 实例的精确缓存自动失效，
# 避免换模型/换密钥后仍返回旧模型的回答。
_CACHE_EPOCH = 0


def bump_cache_epoch() -> int:
    global _CACHE_EPOCH
    _CACHE_EPOCH += 1
    return _CACHE_EPOCH


class LLMRouter:
    """LLM 路由器"""

    def __init__(
        self,
        cache: Optional[CacheLayer] = None,
        cloud: Optional[CloudLayer] = None,
    ) -> None:
        self.cache = cache or CacheLayer()
        self.cloud = cloud or CloudLayer()

    @staticmethod
    def _key(prompt: str) -> str:
        return hashlib.sha256(f"{_CACHE_EPOCH}\x00{prompt}".encode("utf-8")).hexdigest()[:32]

    async def generate(
        self, prompt: str, task: str = "general", complexity: float = 0.5,
        interactive: bool = False,
    ) -> LLMResponse:
        """生成入口"""
        key = self._key(prompt)
        req = LLMRequest(key=key, prompt=prompt, task=task, complexity=complexity)

        # L1 精确缓存
        if (cached := self.cache.get(key)) is not None:
            return LLMResponse(text=cached, source="cache", cached=True)

        # L4 云（未配置则 Mock）；interactive 由 WebSocket 对话传入，收紧云端等待
        resp = await self.cloud.run(req, interactive=interactive)
        self.cache.set(key, resp.text)
        return resp
