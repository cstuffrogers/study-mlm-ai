"""用户存储 — 轻量进程内实现（无 PG 也可注册/登录）

演示模式：进程内保存用户，重启清空。bcrypt 哈希 + JWT 签发不依赖数据库。
后续可替换为 DB 实现而不影响路由契约。
"""
from __future__ import annotations

import threading
import uuid

_lock = threading.Lock()
_users: dict[str, dict] = {}          # user_id -> user
_by_email: dict[str, str] = {}        # email -> user_id


def get_by_email(email: str) -> dict | None:
    with _lock:
        uid = _by_email.get(email)
        return dict(_users[uid]) if uid else None


def get_by_id(user_id: str) -> dict | None:
    with _lock:
        u = _users.get(user_id)
        return dict(u) if u else None


def create(email: str, password_hash: str, nickname: str, role: str = "learner") -> dict:
    with _lock:
        uid = "u_" + uuid.uuid4().hex[:10]
        u = {"id": uid, "email": email, "password_hash": password_hash,
             "nickname": nickname, "role": role, "is_active": True}
        _users[uid] = u
        _by_email[email] = uid
        return dict(u)


def clear() -> None:
    with _lock:
        _users.clear()
        _by_email.clear()
