"""WebSocket 服务端 — 会话入口

MVP 阶段：接收用户消息 → (Phase 2-3 接入 RAG/防偏离/LLM) → 回复
当前为骨架，chat 流程在 services/dialogue_service.py
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from websocket.protocol import (
    ClientMessageType, ServerMessageType,
    UserMessageIn, ActionIn,
    AiMessageOut, BlockedOut, ErrorOut, StateTransitionOut, StruggleDetectedOut,
    BadgesAwardedOut,
)
from services.dialogue_service import DialogueService
from services import dialogue_store

logger = logging.getLogger(__name__)
router = APIRouter()


# 一条对话链路的总等待上限：真实云模型端点不通时快速降级/报错，
# 不让前端浮窗无限转圈。可用 WS_DIALOGUE_TIMEOUT 覆盖（秒）。
# 默认 55s：交互单次云端 30s + RAG 召回 + 三重校验，留足余量；
# 旧的 40s 会在云端 30s 超时后几乎立刻把整个链路一并掐断。
_DIALOGUE_TIMEOUT = float(os.getenv("WS_DIALOGUE_TIMEOUT", "55"))


def _chunk_ids(ai: dict) -> list[str]:
    """落库用的分片 id 列表（结构化 source_chunks 优先，回退溯源卡片）"""
    ids: list[str] = []
    seen: set[str] = set()
    for item in ai.get("source_chunks") or ():
        cid = item.get("chunk_id") if isinstance(item, dict) else item
        cid = str(cid or "").strip()
        if cid and cid not in seen:
            seen.add(cid)
            ids.append(cid)
    if not ids:
        for p in ai.get("provenance") or ():
            cid = str((p or {}).get("chunk_id", "")).strip()
            if cid and cid not in seen:
                seen.add(cid)
                ids.append(cid)
    return ids


@router.websocket("/ws/dialogue")
async def dialogue_ws(ws: WebSocket) -> None:
    """对话 WebSocket 端点"""
    await ws.accept()
    # 检索器已在进程内共享（见 dialogue_service.shared_retriever），这里构造
    # 只初始化轻量组件；renderer 的会话历史仍按连接独立保存。
    service = DialogueService()
    logger.info("WS connected")

    try:
        while True:
            raw = await ws.receive_text()
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                await ws.send_text(ErrorOut(code="bad_json", message="无效JSON").model_dump_json())
                continue

            mtype = msg.get("type")

            if mtype == ClientMessageType.PING:
                await ws.send_text(json.dumps({"type": ServerMessageType.PONG}))
                continue

            if mtype == ClientMessageType.USER_MESSAGE:
                try:
                    u = UserMessageIn(**msg)
                except Exception as e:
                    await ws.send_text(ErrorOut(code="bad_message", message=str(e)).model_dump_json())
                    continue

                # 核心对话流程（Phase 2-3 逐步接入防偏离+RAG+LLM）
                # 超时/异常都必须回一条显式 error，前端才能显示「失败 + 重试」，
                # 而不是永远停在「正在生成」。
                try:
                    result = await asyncio.wait_for(
                        service.chat(u), timeout=_DIALOGUE_TIMEOUT
                    )
                except asyncio.TimeoutError:
                    logger.warning(
                        "对话生成超时（%.0fs）dialogue=%s",
                        _DIALOGUE_TIMEOUT, u.dialogue_id,
                    )
                    await ws.send_text(ErrorOut(
                        code="dialogue_timeout",
                        message=f"生成超时（{_DIALOGUE_TIMEOUT:.0f} 秒），请点「重试」或稍后再试",
                    ).model_dump_json())
                    continue
                except Exception as e:
                    logger.exception("对话生成失败 dialogue=%s", u.dialogue_id)
                    await ws.send_text(ErrorOut(
                        code="dialogue_error",
                        message=f"生成失败：{e}",
                    ).model_dump_json())
                    continue

                # 轻量对话历史落库（进程内），供前端「对话历史页」回看
                try:
                    dialogue_store.ensure_dialogue(
                        u.dialogue_id, user_id=getattr(u, "user_id", "demo_user") or "demo_user",
                        mode=u.mode)
                    dialogue_store.append_message(
                        u.dialogue_id, "user", u.content, mode=u.mode,
                        selected_text=u.selected_text, paragraph_id=u.paragraph_id)
                    if result.get("blocked"):
                        dialogue_store.append_message(
                            u.dialogue_id, "assistant",
                            "[已拦截] " + str(result["blocked"].get("reason", "内容不合规")),
                            mode=u.mode, is_safe=False, guard_result=result["blocked"])
                    else:
                        ai = result["ai_message"]
                        dialogue_store.append_message(
                            u.dialogue_id, "assistant", ai.get("content", ""), mode=ai.get("mode", u.mode),
                            source_chunks=_chunk_ids(ai),
                            is_safe=ai.get("is_safe", True), guard_result=ai.get("guard", {}))
                except Exception:
                    logger.warning("对话历史落库失败（忽略，不影响对话）", exc_info=True)

                if result.get("blocked"):
                    await ws.send_text(BlockedOut(**result["blocked"]).model_dump_json())
                else:
                    await ws.send_text(AiMessageOut(**result["ai_message"]).model_dump_json())

                if result.get("state_transition"):
                    await ws.send_text(StateTransitionOut(**result["state_transition"]).model_dump_json())

                # 勋章系统（spec 001）：对话完成检测新勋章，随本轮对话下发通知
                try:
                    uid = getattr(u, "user_id", "demo_user") or "demo_user"
                    from services import badge_service
                    awarded = await badge_service.evaluate(uid, source_event="dialogue_complete")
                    if awarded:
                        await ws.send_text(BadgesAwardedOut(badges=awarded).model_dump_json())
                except Exception as e:  # 勋章异常不阻断对话主链路
                    logger.warning("勋章评估失败（不影响对话）: %s", e)

                if result.get("struggle"):
                    try:
                        await ws.send_text(StruggleDetectedOut(**result["struggle"]).model_dump_json())
                    except Exception:
                        pass

            elif mtype == ClientMessageType.ACTION:
                try:
                    a = ActionIn(**msg)
                except Exception as e:
                    await ws.send_text(ErrorOut(code="bad_action", message=str(e)).model_dump_json())
                    continue
                # 快捷操作处理（切模式/回到原文等）
                await service.handle_action(a, ws)

            else:
                await ws.send_text(ErrorOut(code="unknown_type", message=f"未知类型: {mtype}").model_dump_json())

    except WebSocketDisconnect:
        logger.info("WS disconnected")
    except Exception as e:
        logger.exception("WS error")
        try:
            await ws.send_text(ErrorOut(code="server_error", message=str(e)).model_dump_json())
        except Exception:
            pass
