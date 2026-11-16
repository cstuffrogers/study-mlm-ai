"""学习闭环 DB 会话辅助 — 统一 async/sync 引擎差异

服务层统一用 `async with session_scope() as s:`；内部根据引擎类型选择异步或同步会话，
并在退出时提交。读多写少，简单可靠。
"""
from __future__ import annotations

from contextlib import asynccontextmanager

from core.db_learning import get_session_factory, learning_engine_is_async


@asynccontextmanager
async def session_scope():
    factory = get_session_factory()
    if learning_engine_is_async():
        session = factory()
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()
    else:
        session = factory()
        try:
            yield session
            session.commit()
        except Exception:
            session.rollback()
            raise
        finally:
            session.close()
