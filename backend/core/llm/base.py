"""LLM 请求/响应抽象 — 移植自 ljsk base.py，保持接口兼容"""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class LLMRequest:
    key: str                        # 缓存键（prompt 哈希）
    prompt: str
    task: str = "general"           # general/stance_classify/fact_check/...
    complexity: float = 0.5         # [0,1] 复杂度，路由决策依据
    params: dict = field(default_factory=dict)


@dataclass
class LLMResponse:
    text: str
    source: str                     # cache/mock/cloud
    cached: bool = False
    model: str = ""                 # source=cloud 时的模型名（界面徽标用）
    note: str = ""                  # source=mock 时降级原因：not-configured / failed:<原因>
