"""认证路由 — 注册/登录（bcrypt + JWT，轻量进程内用户库，无需 PG）

演示模式用 services.user_store（进程内，重启清空）；生产可切 DB。
"""
from __future__ import annotations

import jwt
import bcrypt
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from core.config import SECRET_KEY
from services import user_store

router = APIRouter()
JWT_ALGO = "HS256"
JWT_TTL_HOURS = 72


class RegisterIn(BaseModel):
    email: str
    password: str
    nickname: str = ""


class LoginIn(BaseModel):
    email: str
    password: str


class AuthOut(BaseModel):
    token: str
    user_id: str
    email: str
    nickname: str
    role: str


def _hash_pw(pw: str) -> str:
    return bcrypt.hashpw(pw.encode(), bcrypt.gensalt()).decode()


def _verify_pw(pw: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(pw.encode(), hashed.encode())
    except Exception:
        return False


def _issue_token(user_id: str) -> str:
    payload = {
        "sub": user_id,
        "exp": datetime.now(timezone.utc) + timedelta(hours=JWT_TTL_HOURS),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=JWT_ALGO)


@router.post("/register", response_model=AuthOut)
async def register(body: RegisterIn) -> AuthOut:
    if not body.email or not body.password:
        raise HTTPException(status_code=422, detail="邮箱和密码不能为空")
    if user_store.get_by_email(body.email):
        raise HTTPException(status_code=409, detail="邮箱已注册")
    user = user_store.create(
        email=body.email, password_hash=_hash_pw(body.password),
        nickname=body.nickname or body.email.split("@")[0], role="learner")
    return AuthOut(token=_issue_token(user["id"]), user_id=user["id"],
                   email=user["email"], nickname=user["nickname"], role=user["role"])


@router.post("/login", response_model=AuthOut)
async def login(body: LoginIn) -> AuthOut:
    user = user_store.get_by_email(body.email)
    if not user or not _verify_pw(body.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="邮箱或密码错误")
    return AuthOut(token=_issue_token(user["id"]), user_id=user["id"],
                   email=user["email"], nickname=user["nickname"], role=user["role"])
