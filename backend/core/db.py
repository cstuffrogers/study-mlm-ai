"""异步数据库连接 — PostgreSQL + pgvector

engine/session 采用懒加载：仅在 init_db() 或 get_session() 首次调用时创建。
轻量模式（AUTO_CREATE_TABLES=0 且不调 auth/chunk 路由）完全不碰 asyncpg，
因此无 Docker / 无 PG 也能启动 app 跑对话核心闭环。
"""
from __future__ import annotations

import sys
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from core.config import DATABASE_URL, AUTO_CREATE_TABLES

# Windows: 用 SelectorEventLoop 兼容 asyncpg
if sys.platform == "win32":
    import asyncio
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())


class Base(DeclarativeBase):
    """所有 ORM 模型的基类"""
    pass


# 学情闭环引擎专用独立 Base（避免与主 app 的 async 模型 metadata 冲突；
# 引擎可在内存(SQLite)或独立 PG schema 上运行，与主系统解耦）
class LearningBase(DeclarativeBase):
    """学习闭环（路线/测验/学情/推荐）引擎的 ORM 基类"""
    pass


_engine = None
_session_factory = None


def _ensure_engine():
    """懒加载 engine（首次访问 DB 时才创建，避免轻量模式强依赖 asyncpg）"""
    global _engine, _session_factory
    if _engine is None:
        _engine = create_async_engine(DATABASE_URL, echo=False, pool_pre_ping=True, future=True)
        _session_factory = async_sessionmaker(_engine, class_=AsyncSession, expire_on_commit=False)
    return _session_factory


async def get_session() -> AsyncSession:
    """FastAPI 依赖注入：获取异步 DB session"""
    factory = _ensure_engine()
    async with factory() as session:
        yield session


async def init_db() -> None:
    """建表（AUTO_CREATE_TABLES=1 时调用）"""
    from model import models  # noqa: F401 — 触发模型注册
    factory = _ensure_engine()
    async with _engine.begin() as conn:
        # 启用 pgvector 扩展
        from sqlalchemy import text
        await conn.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))
        await conn.run_sync(Base.metadata.create_all)
