"""学习闭环引擎 DB session — 支持内存(SQLite) / 独立 PG

模式（config.LEARNING_DB_MODE）：
  - memory   : sqlite+aiosqlite 内存库（StaticPool 共享连接），默认，无 PG 也能跑测试/demo
  - postgres : 复用主 DATABASE_URL（同库不同 metadata，表名 lr_ 前缀）
  - auto     : 有可解析 DATABASE_URL 尝试 postgres，否则回退 memory

内存模式下 aiosqlite 未安装时自动回退 sqlalchemy.sync 引擎（同步），
由 `learning_engine_is_async()` 判定，服务层据此选择 await 或同步调用。
"""
from __future__ import annotations

import logging

from sqlalchemy.pool import StaticPool

from core.config import LEARNING_DB_MODE, DATABASE_URL

logger = logging.getLogger(__name__)

_engine = None
_session_factory = None
_is_async = True


def _build():
    global _engine, _session_factory, _is_async
    mode = LEARNING_DB_MODE
    if mode == "auto":
        mode = "postgres" if DATABASE_URL else "memory"

    if mode == "postgres":
        from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
        _engine = create_async_engine(DATABASE_URL, echo=False, pool_pre_ping=True, future=True)
        _session_factory = async_sessionmaker(_engine, expire_on_commit=False)
        _is_async = True
        logger.info("学习闭环引擎: postgres(async)")
        return

    # memory：优先 async sqlite
    try:
        from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
        _engine = create_async_engine(
            "sqlite+aiosqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
            future=True,
        )
        _session_factory = async_sessionmaker(_engine, expire_on_commit=False)
        _is_async = True
        logger.info("学习闭环引擎: sqlite 内存(async)")
    except Exception as e:  # aiosqlite 缺失 → 同步 sqlite
        logger.warning("aiosqlite 不可用(%s)，回退同步 SQLite 引擎", e)
        from sqlalchemy import create_engine
        from sqlalchemy.orm import sessionmaker
        _engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
            future=True,
        )
        _session_factory = sessionmaker(_engine, expire_on_commit=False)
        _is_async = False


def learning_engine_is_async() -> bool:
    if _engine is None:
        _build()
    return _is_async


def get_session_factory():
    if _engine is None:
        _build()
    return _session_factory


async def init_learning_db() -> None:
    """建表：l r_ 前缀全部表。异步/同步引擎自适应。"""
    from model import models_learning  # noqa: F401 — 注册元数据
    from core.db import LearningBase
    if _engine is None:
        _build()
    if _is_async:
        async with _engine.begin() as conn:
            await conn.run_sync(LearningBase.metadata.create_all)
    else:
        LearningBase.metadata.create_all(_engine)


def reset_learning_engine() -> None:
    """测试用：重置引擎（丢弃内存库）

    必须先把旧 engine dispose 掉：内存库走 StaticPool + aiosqlite，连接会起一个
    非守护 worker 线程；不 dispose 就丢引用，该线程会一直挂在 threading._shutdown 里，
    导致 pytest 跑完「70 passed in 2.5s」后进程无法退出（命令行看起来像卡死）。
    """
    global _engine, _session_factory, _is_async
    import asyncio
    import warnings

    old = _engine
    if old is not None:
        try:
            try:
                asyncio.get_running_loop()
                in_loop = True
            except RuntimeError:
                in_loop = False
            if in_loop:
                # 事件循环内无法 run；至少把同步连接池关掉
                old.sync_engine.dispose()
            else:
                asyncio.run(old.dispose())
        except Exception as e:  # pragma: no cover - dispose 失败不应影测试
            warnings.warn(f"reset_learning_engine: engine dispose 失败: {e}")
    _engine = None
    _session_factory = None
    _is_async = True
