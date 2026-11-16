"""学习闭环启动初始化 — 建表 + 种子（幂等，进程内只跑一次）

并发保护：应用启动预热与首批请求可能同时触发；没有锁时两个协程会同时跑
建表/种子，既重复写库也可能互相冲突（SQLite 下表现为 database is locked）。
这里用 asyncio.Lock 做单飞，后到者等先到者完成后直接返回。
"""
from __future__ import annotations

import asyncio
import logging

from core.db_learning import init_learning_db
from services.learning_bootstrap import seed_all

logger = logging.getLogger(__name__)
_ready = False
_lock: asyncio.Lock | None = None


def _get_lock() -> asyncio.Lock:
    """惰性建锁：避免在无事件循环时（import 阶段）构造。"""
    global _lock
    if _lock is None:
        _lock = asyncio.Lock()
    return _lock


async def ensure_learning_ready() -> None:
    global _ready
    if _ready:
        return
    async with _get_lock():
        if _ready:  # 双检：等锁期间别人已经初始化完
            return
        await init_learning_db()
        await seed_all()
        _ready = True
        logger.info("学习闭环引擎就绪（建表+种子）")
