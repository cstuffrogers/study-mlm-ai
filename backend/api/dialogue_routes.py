"""对话历史路由 — 会话列表 + 消息历史（轻量进程内存储，无需 PG）

数据来自 services.dialogue_store（WS 对话时写入）。重启清空，演示可接受。
"""
from __future__ import annotations

from fastapi import APIRouter, Query

from services import dialogue_store

router = APIRouter()


@router.get("/list/{user_id}")
async def list_dialogues(user_id: str) -> dict:
    return {"user_id": user_id, "dialogues": dialogue_store.list_dialogues(user_id)}


@router.get("/{dialogue_id}/messages")
async def get_messages(dialogue_id: str, limit: int = Query(50, le=200)) -> dict:
    return {"dialogue_id": dialogue_id, "messages": dialogue_store.get_messages(dialogue_id, limit)}
