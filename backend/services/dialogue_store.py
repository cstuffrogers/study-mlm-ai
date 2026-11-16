"""对话历史存储 — 轻量进程内实现（无 PG 也可用）

MVP 轻量模式用进程内单例保存「会话 + 消息」，支撑前端「对话历史页」回看。
重启即清空（演示可接受）。接口保持简单，后续可替换为 DB 实现而不影响路由。
"""
from __future__ import annotations

import threading
import time

_lock = threading.Lock()
_dialogues: dict[str, dict] = {}
_messages: dict[str, list[dict]] = {}


def ensure_dialogue(dialogue_id: str, user_id: str = "demo_user",
                    mode: str = "explain", work: str = "") -> dict:
    with _lock:
        d = _dialogues.get(dialogue_id)
        if not d:
            d = {
                "id": dialogue_id, "user_id": user_id, "current_mode": mode,
                "current_work": work, "title": "", "updated_at": time.time(),
            }
            _dialogues[dialogue_id] = d
            _messages.setdefault(dialogue_id, [])
        return dict(d)


def append_message(dialogue_id: str, role: str, content: str, mode: str = "",
                   selected_text: str = "", paragraph_id: str = "",
                   source_chunks: list | None = None, is_safe: bool = True,
                   guard_result: dict | None = None) -> dict:
    with _lock:
        _messages.setdefault(dialogue_id, [])
        seq = len(_messages[dialogue_id]) + 1
        m = {
            "id": f"{dialogue_id}-{seq}", "seq": seq, "role": role,
            "content": content, "mode": mode, "selected_text": selected_text,
            "paragraph_id": paragraph_id, "source_chunks": source_chunks or [],
            "is_safe": is_safe, "guard_result": guard_result or {},
            "created_at": time.time(),
        }
        _messages[dialogue_id].append(m)
        d = _dialogues.get(dialogue_id)
        if d:
            d["updated_at"] = time.time()
            if role == "user" and not d.get("title"):
                d["title"] = content[:24]
        return m


def list_dialogues(user_id: str = "demo_user") -> list[dict]:
    with _lock:
        ds = [d for d in _dialogues.values() if d["user_id"] == user_id]
        ds.sort(key=lambda x: x["updated_at"], reverse=True)
        return [{**d, "message_count": len(_messages.get(d["id"], []))} for d in ds]


def get_messages(dialogue_id: str, limit: int = 50) -> list[dict]:
    with _lock:
        return list(_messages.get(dialogue_id, []))[:limit]


def clear() -> None:
    with _lock:
        _dialogues.clear()
        _messages.clear()
