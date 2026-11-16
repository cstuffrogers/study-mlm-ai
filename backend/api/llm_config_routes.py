"""「LLM 大模型 API 配置」HTTP 接口 — 功能中心配置页用。

GET  /api/llm-config          当前状态（密钥只回掩码）
POST /api/llm-config          保存配置（立即对当前进程生效）
POST /api/llm-config/test     用当前配置真实测一次连接
"""
from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from services import llm_config_service as svc

logger = logging.getLogger(__name__)
router = APIRouter()


class ConfigIn(BaseModel):
    # 空字符串 = 保留已有密钥；"__CLEAR__" = 明确清空
    api_key: str = ""
    base_url: str | None = None
    model: str | None = None
    max_concurrent: int | float | None = None
    max_retries: int | float | None = None
    timeout: int | float | None = None
    interactive_timeout: int | float | None = None
    max_tokens: int | float | None = None
    # 推理型模型关闭思维链（默认开启，避免正文为空/超时）
    disable_thinking: bool | None = None


@router.get("")
async def get_config() -> dict:
    return svc.current_status()


@router.post("")
async def save_config(body: ConfigIn) -> dict:
    try:
        return svc.save(body.model_dump())
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e


@router.post("/test")
async def test_config() -> dict:
    return await svc.test_connection()
