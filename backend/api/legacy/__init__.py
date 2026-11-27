"""学习域路由（legacy）——前端已全本地化，这些端点不再被 App 消费。

背景：前端 `api_client.dart` 已把 `/api/*` 全部走 `LocalRouter` 本机分发，
`chat_service.dart` 也不再连 WebSocket。后端只剩 `/api/tts/speak` 一个端点
被 App 真正调用（Web 端朗读走后端微软神经语音）。其余 12 个学习域路由
（dialogue / chunk / route / quiz / mastery / recommendation / sync /
review / analytics / motivation / badge / llm-config）保留在此，**默认不挂载**，
仅供开发调试、测试，或将来恢复「服务端模式」时复用。

启用方式：设环境变量 `LEGACY_ROUTERS=1`，`app.py` 会在创建应用时调用
[mount_legacy_routers] 把这批路由挂上。测试通过 `backend/conftest.py`
自动启用，运行中的服务默认只挂 TTS。
"""
from __future__ import annotations

from fastapi import FastAPI

from api.legacy import (
    analytics_routes,
    badge_routes,
    chunk_routes,
    dialogue_routes,
    llm_config_routes,
    mastery_routes,
    motivation_routes,
    quiz_routes,
    recommendation_routes,
    review_routes,
    route_routes,
    sync_routes,
)

# (router, 前缀, 标签) 三元组：与 app.py 原先的 include_router 一一对应。
_LEGACY_ROUTERS: list[tuple] = [
    (dialogue_routes.router, "/api/dialogue", "dialogue"),
    (chunk_routes.router, "/api/chunks", "chunks"),
    (route_routes.router, "/api/routes", "routes"),
    (quiz_routes.router, "/api/quiz", "quiz"),
    (mastery_routes.router, "/api/mastery", "mastery"),
    (recommendation_routes.router, "/api/recommendation", "recommendation"),
    (sync_routes.router, "/api/sync", "sync"),
    (review_routes.router, "/api/review", "review"),
    (analytics_routes.router, "/api/analytics", "analytics"),
    (motivation_routes.router, "/api/motivation", "motivation"),
    (badge_routes.router, "/api/badges", "badges"),
    (llm_config_routes.router, "/api/llm-config", "llm-config"),
]


def mount_legacy_routers(app: FastAPI) -> None:
    """把全部学习域路由挂到 [app] 上（默认不调用，需 LEGACY_ROUTERS=1 或测试启用）。"""
    for router, prefix, tag in _LEGACY_ROUTERS:
        app.include_router(router, prefix=prefix, tags=[tag])
