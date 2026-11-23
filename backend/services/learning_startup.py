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


async def _tables_exist() -> bool:
    """轻量验证学习表存在。

    aiosqlite 连接绑定在创建它的事件循环上；测试/热重载中事件循环切换会让
    StaticPool 的连接被失效替换，新连接指向空内存库→表全部消失。
    这里用一次「查已知表」探测，失败即返回 False，触发重建。
    """
    from sqlalchemy import text
    from core.db_learning import get_session_factory, learning_engine_is_async
    try:
        factory = get_session_factory()
        if learning_engine_is_async():
            async with factory() as s:
                await s.execute(text("SELECT 1 FROM lr_mastery_records LIMIT 1"))
        else:
            with factory() as s:
                s.execute(text("SELECT 1 FROM lr_mastery_records LIMIT 1"))
        return True
    except Exception:
        return False


async def ensure_learning_ready() -> None:
    global _ready
    if _ready:
        # 连接可能已失效（aiosqlite 连接被替换→空库→表缺失）；轻量探测
        if await _tables_exist():
            return
        logger.warning("学习库表缺失（连接失效），重新初始化")
    async with _get_lock():
        if _ready and await _tables_exist():  # 双检：等锁期间别人已重建
            return
        await init_learning_db()
        await seed_all()
        _ready = True
        logger.info("学习闭环引擎就绪（建表+种子）")
