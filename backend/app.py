"""FastAPI 应用工厂 — 正统马哲学习系统

移植自 ljsk app.py，精简为 MVP 骨架。
"""
from __future__ import annotations

import asyncio
import logging
import sys
import os

from dotenv import load_dotenv
load_dotenv()

# Windows asyncpg 兼容
if sys.platform == "win32":
    import asyncio
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from core.config import AUTO_CREATE_TABLES, CORS_ORIGINS, CORS_ALLOW_CREDENTIALS
from core.db import init_db
from api.auth_routes import router as auth_router
from api.dialogue_routes import router as dialogue_router
from api.chunk_routes import router as chunk_router
from api.route_routes import router as route_router
from api.quiz_routes import router as quiz_router
from api.mastery_routes import router as mastery_router
from api.recommendation_routes import router as recommendation_router
from api.sync_routes import router as sync_router
from api.review_routes import router as review_router
from api.analytics_routes import router as analytics_router
from api.motivation_routes import router as motivation_router
from api.tts_routes import router as tts_router
from api.llm_config_routes import router as llm_config_router
from websocket.server import router as ws_router

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger(__name__)


def create_app() -> FastAPI:
    app = FastAPI(title="正统马哲深度学习系统", version="0.1.0-mvp")

    # CORS（Flutter 端开发联调）——来源白名单，默认仅本地开发地址；生产用 CORS_ORIGINS 显式指定
    app.add_middleware(
        CORSMiddleware,
        allow_origins=CORS_ORIGINS,
        allow_credentials=CORS_ALLOW_CREDENTIALS,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # 路由挂载
    app.include_router(auth_router, prefix="/api/auth", tags=["auth"])
    app.include_router(dialogue_router, prefix="/api/dialogue", tags=["dialogue"])
    app.include_router(chunk_router, prefix="/api/chunks", tags=["chunks"])
    app.include_router(route_router, prefix="/api/routes", tags=["routes"])
    app.include_router(quiz_router, prefix="/api/quiz", tags=["quiz"])
    app.include_router(mastery_router, prefix="/api/mastery", tags=["mastery"])
    app.include_router(recommendation_router, prefix="/api/recommendation", tags=["recommendation"])
    app.include_router(sync_router, prefix="/api/sync", tags=["sync"])
    app.include_router(review_router, prefix="/api/review", tags=["review"])
    app.include_router(analytics_router, prefix="/api/analytics", tags=["analytics"])
    app.include_router(motivation_router, prefix="/api/motivation", tags=["motivation"])
    app.include_router(tts_router, prefix="/api/tts", tags=["tts"])
    app.include_router(llm_config_router, prefix="/api/llm-config", tags=["llm-config"])
    app.include_router(ws_router, tags=["websocket"])

    @app.on_event("startup")
    async def _startup() -> None:
        # 安全告警（只提示，不阻断）：默认弱口令 / CORS 通配 / 无鉴权。
        # 单机自用无影响；看到这些告警说明该服务只能跑在本机回环地址。
        try:
            from core.config import security_warnings
            for _w in security_warnings():
                logger.warning("[安全] %s", _w)
        except Exception as e:  # 永不因告警失败阻断启动
            logger.debug("安全告警检查失败: %s", e)
        if AUTO_CREATE_TABLES:
            logger.info("建表中...")
            await init_db()
            logger.info("建表完成")
        # 学习闭环引擎（内存/独立库，不影响主 PG 连接）
        # 功能中心保存的配置写在 backend/.llm_config.json；进程启动时就把它
        # 覆盖到 os.environ，否则重启后要等用户访问配置页才生效，期间一直 Mock。
        try:
            from services.llm_config_service import apply_to_environment
            apply_to_environment()
        except Exception as e:  # 不阻断主服务
            logger.warning("应用页面 LLM 配置失败（不影响主服务）: %s", e)
        # 学习闭环引擎（内存/独立库，不影响主 PG 连接）
        try:
            from services.learning_startup import ensure_learning_ready
            await ensure_learning_ready()
        except Exception as e:  # 不阻断主服务
            logger.warning("学习闭环引擎初始化失败（不影响主服务）: %s", e)
        # 预热全库 RAG 索引（约 12s）：放到启动阶段，用户点「释义」时不再等待。
        # 内容分片索引（约 1.8 万条）也一并预热，首次打开阅读页/溯源卡不再付构建成本。
        # 两者互不依赖，并行跑；失败也不阻断主服务，首次访问会惰性重建。
        async def _warm_dialogue() -> None:
            try:
                from services.dialogue_service import warm_dialogue_service
                await asyncio.to_thread(warm_dialogue_service)
            except Exception as e:  # 不阻断主服务
                logger.warning("对话检索器预热失败（首次对话会重建）: %s", e)

        async def _warm_content() -> None:
            try:
                from services.content_provider import warm_index
                await asyncio.to_thread(warm_index)
            except Exception as e:  # 不阻断主服务
                logger.warning("内容分片索引预热失败（首次访问会重建）: %s", e)

        await asyncio.gather(_warm_dialogue(), _warm_content())

    @app.get("/health")
    async def health() -> dict:
        return {"status": "ok", "service": "marxism-learning", "version": "0.1.0-mvp"}

    return app


app = create_app()


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app:app", host="0.0.0.0", port=8190, reload=True)
