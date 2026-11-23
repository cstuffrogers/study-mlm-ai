"""对话历史存储 — 主库持久化 + 进程内缓存（无 PG 时降级纯内存）

改造目标：消除「后端重启后对话勋章进度归零」。
- 有主库（AUTO_CREATE_TABLES=1）：对话会话与消息落 ``dialogues``/``dialogue_messages``
  表，进程内 dict 作读加速；重启后从 DB 回填，对话计数不再丢失。
- 无主库（AUTO_CREATE_TABLES=0）：纯进程内内存（保持原轻量模式行为）。

接口全部 async，调用方需 await；返回 dict 结构与改造前一致，
前端（对话历史页读本机 LocalDb，不读本接口）与勋章系统（badge_service）不感知改造。
"""
from __future__ import annotations

import asyncio
import time
from datetime import datetime

# 注：AUTO_CREATE_TABLES 在 _db_enabled() 内动态读取，避免静态绑定导致
# 测试时无法切换 DB/内存模式。

# 进程内缓存：读加速 + 无 PG 降级存储
_dialogues: dict[str, dict] = {}
_messages: dict[str, list[dict]] = {}

# title 存入 Dialogue.current_state（JSON），避免改表结构
_TITLE_KEY = "title"

# append 串行化锁：seq 计算 + 写入需原子（async 下多协程可能并发 append）
_append_lock: asyncio.Lock | None = None


def _get_append_lock() -> asyncio.Lock:
    """惰性建锁：避免在无事件循环时（import 阶段）构造。"""
    global _append_lock
    if _append_lock is None:
        _append_lock = asyncio.Lock()
    return _append_lock


def _db_enabled() -> bool:
    """是否走主库持久化：AUTO_CREATE_TABLES=1 时启用（动态读取，支持运行时切换）。"""
    from core.config import AUTO_CREATE_TABLES as _atc
    return _atc


def _ensure_engine():
    """懒加载主库 engine（复用 core.db._ensure_engine，不触发建表）。"""
    from core.db import _ensure_engine as _ee
    return _ee()


# ---------- ORM → dict 转换 ----------

def _dlg_to_dict(d) -> dict:
    """Dialogue ORM → 对外 dict（title 从 current_state 取，结构与原内存版一致）。"""
    title = ""
    if d.current_state:
        title = d.current_state.get(_TITLE_KEY, "") or ""
    return {
        "id": d.id,
        "user_id": d.user_id,
        "current_mode": d.current_mode,
        "current_work": d.current_work,
        "title": title,
        "updated_at": d.updated_at.timestamp() if d.updated_at else 0.0,
    }


def _msg_to_dict(m) -> dict:
    """DialogueMessage ORM → 对外 dict（id 用 dialogue_id-seq 保持兼容）。"""
    return {
        "id": f"{m.dialogue_id}-{m.seq}",
        "seq": m.seq,
        "role": m.role,
        "content": m.content,
        "mode": m.mode,
        "selected_text": m.selected_text or "",
        "paragraph_id": m.paragraph_id or "",
        "source_chunks": m.source_chunks or [],
        "is_safe": bool(m.is_safe),
        "guard_result": m.guard_result or {},
        "created_at": m.created_at.timestamp() if m.created_at else 0.0,
    }


# ---------- DB 回填 ----------

async def _load_from_db(dialogue_id: str) -> None:
    """从主库回填单条会话与消息到缓存（缓存未命中时调用，不创建）。"""
    from model.models import Dialogue, DialogueMessage
    from sqlalchemy import select
    factory = _ensure_engine()
    async with factory() as s:
        d = await s.get(Dialogue, dialogue_id)
        if not d:
            return
        _dialogues[dialogue_id] = _dlg_to_dict(d)
        msgs = await s.execute(
            select(DialogueMessage)
            .where(DialogueMessage.dialogue_id == dialogue_id)
            .order_by(DialogueMessage.seq)
        )
        _messages[dialogue_id] = [_msg_to_dict(m) for m in msgs.scalars().all()]


async def _load_all_from_db(user_id: str) -> None:
    """从主库回填该用户全部会话与消息到缓存。"""
    from model.models import Dialogue, DialogueMessage
    from sqlalchemy import select
    factory = _ensure_engine()
    async with factory() as s:
        ds = await s.execute(
            select(Dialogue)
            .where(Dialogue.user_id == user_id)
            .order_by(Dialogue.updated_at.desc())
        )
        for d in ds.scalars().all():
            _dialogues[d.id] = _dlg_to_dict(d)
            msgs = await s.execute(
                select(DialogueMessage)
                .where(DialogueMessage.dialogue_id == d.id)
                .order_by(DialogueMessage.seq)
            )
            _messages[d.id] = [_msg_to_dict(m) for m in msgs.scalars().all()]


# ---------- 写入 ----------

async def ensure_dialogue(dialogue_id: str, user_id: str = "demo_user",
                          mode: str = "explain", work: str = "") -> dict:
    """确保会话存在：缓存优先 → DB 回填 → 新建。返回 dict。"""
    if dialogue_id in _dialogues:
        return dict(_dialogues[dialogue_id])

    if _db_enabled():
        try:
            await _load_from_db(dialogue_id)
            if dialogue_id in _dialogues:
                return dict(_dialogues[dialogue_id])
        except Exception:
            pass  # 降级内存

    dct = {
        "id": dialogue_id, "user_id": user_id, "current_mode": mode,
        "current_work": work, "title": "", "updated_at": time.time(),
    }
    _dialogues[dialogue_id] = dct
    _messages.setdefault(dialogue_id, [])

    if _db_enabled():
        try:
            from model.models import Dialogue
            factory = _ensure_engine()
            async with factory() as s:
                d = Dialogue(
                    id=dialogue_id, user_id=user_id, current_work=work,
                    current_chapter="", current_mode=mode,
                    current_state={_TITLE_KEY: ""},
                )
                s.add(d)
                await s.commit()
        except Exception:
            pass  # 降级内存（主键冲突等）

    return dict(dct)


async def append_message(dialogue_id: str, role: str, content: str, mode: str = "",
                         selected_text: str = "", paragraph_id: str = "",
                         source_chunks: list | None = None, is_safe: bool = True,
                         guard_result: dict | None = None) -> dict:
    """追加一条消息：落库 + 更新缓存。返回 dict。"""
    # 缓存未命中则回填（保证 seq 正确，重启后不重复计数）
    if dialogue_id not in _messages:
        if _db_enabled():
            try:
                await _load_from_db(dialogue_id)
            except Exception:
                pass
        if dialogue_id not in _messages:
            _messages.setdefault(dialogue_id, [])
        if dialogue_id not in _dialogues:
            _dialogues[dialogue_id] = {
                "id": dialogue_id, "user_id": "demo_user",
                "current_mode": mode, "current_work": "",
                "title": "", "updated_at": time.time(),
            }

    async with _get_append_lock():
        msgs = _messages.setdefault(dialogue_id, [])
        seq = len(msgs) + 1
        m = {
            "id": f"{dialogue_id}-{seq}", "seq": seq, "role": role,
            "content": content, "mode": mode, "selected_text": selected_text,
            "paragraph_id": paragraph_id, "source_chunks": source_chunks or [],
            "is_safe": is_safe, "guard_result": guard_result or {},
            "created_at": time.time(),
        }
        msgs.append(m)
        d = _dialogues.get(dialogue_id)
        if d:
            d["updated_at"] = time.time()
            if role == "user" and not d.get("title"):
                d["title"] = content[:24]

        if _db_enabled():
            try:
                from model.models import Dialogue, DialogueMessage
                factory = _ensure_engine()
                async with factory() as s:
                    msg = DialogueMessage(
                        dialogue_id=dialogue_id, seq=seq, role=role,
                        content=content, mode=mode,
                        selected_text=selected_text, paragraph_id=paragraph_id,
                        source_chunks=source_chunks or [],
                        guard_result=guard_result or {}, is_safe=is_safe,
                    )
                    s.add(msg)
                    dl = await s.get(Dialogue, dialogue_id)
                    if dl:
                        if role == "user" and not (dl.current_state or {}).get(_TITLE_KEY):
                            state = dict(dl.current_state or {})
                            state[_TITLE_KEY] = content[:24]
                            dl.current_state = state
                        dl.updated_at = datetime.now()
                    await s.commit()
            except Exception:
                pass  # 降级内存

    return m


# ---------- 读取 ----------

async def list_dialogues(user_id: str = "demo_user") -> list[dict]:
    """列出用户会话（按 updated_at 倒序），含 message_count。"""
    if _db_enabled() and not _dialogues:
        try:
            await _load_all_from_db(user_id)
        except Exception:
            pass
    ds = [d for d in _dialogues.values() if d["user_id"] == user_id]
    ds.sort(key=lambda x: x["updated_at"], reverse=True)
    return [{**d, "message_count": len(_messages.get(d["id"], []))} for d in ds]


async def get_messages(dialogue_id: str, limit: int = 50) -> list[dict]:
    """取会话消息（按 seq 顺序，最多 limit 条）。"""
    if dialogue_id not in _messages:
        if _db_enabled():
            try:
                await _load_from_db(dialogue_id)
            except Exception:
                pass
    return list(_messages.get(dialogue_id, []))[:limit]


def clear() -> None:
    """清空进程内缓存（不删主库数据，避免误删）。"""
    _dialogues.clear()
    _messages.clear()
