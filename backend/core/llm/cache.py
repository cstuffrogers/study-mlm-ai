"""缓存层 — 进程内 LRU 精确缓存

MVP 精简：仅精确命中（语义缓存需 embedding 依赖，Phase 3 暂不引入）。
后续接入 Redis 时替换 dict 实现即可，接口不变。
"""
from __future__ import annotations

from collections import OrderedDict


class CacheLayer:
    """进程内 LRU 缓存"""

    def __init__(self, maxsize: int = 512) -> None:
        self._store: OrderedDict[str, str] = OrderedDict()
        self._maxsize = maxsize

    def get(self, key: str) -> str | None:
        if key in self._store:
            self._store.move_to_end(key)
            return self._store[key]
        return None

    def set(self, key: str, value: str) -> None:
        if key in self._store:
            self._store.move_to_end(key)
        self._store[key] = value
        if len(self._store) > self._maxsize:
            self._store.popitem(last=False)

    def clear(self) -> None:
        self._store.clear()
