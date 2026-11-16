"""ORM 模型 — 正统马哲学习系统数据层

参考 ljsk 19表精简为 MVP 所需核心表：
  users / dialogues / dialogue_messages / text_chunks / concepts /
  propositions / conversation_threads

pgvector 用于 text_chunks.embedding 语义检索。
"""
from __future__ import annotations

import uuid
from datetime import datetime
from sqlalchemy import (
    String, Text, Integer, Float, Boolean, DateTime, ForeignKey,
    JSON, Index, Enum as SAEnum, func
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from pgvector.sqlalchemy import Vector

from core.db import Base


def _uuid() -> str:
    return uuid.uuid4().hex


class User(Base):
    """用户"""
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    nickname: Mapped[str] = mapped_column(String(64), default="")
    password_hash: Mapped[str] = mapped_column(String(255))
    role: Mapped[str] = mapped_column(String(16), default="learner")  # learner/expert/admin
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    dialogues: Mapped[list["Dialogue"]] = relationship(back_populates="user")


class Dialogue(Base):
    """对话会话 — 绑定一部原著 + 当前阅读位置"""
    __tablename__ = "dialogues"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(32), ForeignKey("users.id"), index=True)
    current_work: Mapped[str] = mapped_column(String(128))  # 当前著作
    current_chapter: Mapped[str] = mapped_column(String(64), default="")
    current_mode: Mapped[str] = mapped_column(String(16), default="explain")  # 五模式
    current_state: Mapped[dict] = mapped_column(JSON, default=dict)  # 状态机快照
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())

    user: Mapped["User"] = relationship(back_populates="dialogues")
    messages: Mapped[list["DialogueMessage"]] = relationship(back_populates="dialogue", order_by="DialogueMessage.seq")


class DialogueMessage(Base):
    """对话消息 — 含选中文本锚点 + 溯源 + 校验结果"""
    __tablename__ = "dialogue_messages"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    dialogue_id: Mapped[str] = mapped_column(String(32), ForeignKey("dialogues.id"), index=True)
    seq: Mapped[int] = mapped_column(Integer)  # 轮次序号
    role: Mapped[str] = mapped_column(String(16))  # user/assistant
    content: Mapped[str] = mapped_column(Text)
    mode: Mapped[str] = mapped_column(String(16))  # 当时模式
    selected_text: Mapped[str] = mapped_column(Text, default="")  # 用户选中的原文锚点
    paragraph_id: Mapped[str] = mapped_column(String(64), default="")  # 原文段落ID（锚点保持）
    source_chunks: Mapped[list] = mapped_column(JSON, default=list)  # 溯源 Chunk ID 列表
    guard_result: Mapped[dict] = mapped_column(JSON, default=dict)  # 防偏离校验结果
    is_safe: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    dialogue: Mapped["Dialogue"] = relationship(back_populates="messages")

    __table_args__ = (
        Index("ix_dialogue_messages_dialogue_seq", "dialogue_id", "seq"),
    )


class TextChunk(Base):
    """原著原子化分块 — RAG 检索单元

    layer: 1=词条 2=命题 3=论证 4=语境
    orthodoxy_tag: 正统/经典原著/非正统/待审
    """
    __tablename__ = "text_chunks"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)  # 如 CH-ME-TH-001-010
    text: Mapped[str] = mapped_column(Text)
    source: Mapped[str] = mapped_column(String(128))  # 著作名
    source_location: Mapped[str] = mapped_column(String(64))  # 位置
    layer: Mapped[int] = mapped_column(Integer)  # 1-4
    orthodoxy_tag: Mapped[str] = mapped_column(String(16), default="正统")
    authority_score: Mapped[float] = mapped_column(Float, default=0.9)
    concept_mentions: Mapped[list] = mapped_column(JSON, default=list)
    logical_type: Mapped[str] = mapped_column(String(32), default="")  # definition/critique/determination...
    embedding: Mapped[list] = mapped_column(Vector(768), nullable=True)  # pgvector 向量

    __table_args__ = (
        Index("ix_text_chunks_source", "source"),
        Index("ix_text_chunks_layer", "layer"),
    )


class Concept(Base):
    """概念节点 — 标准术语及其变体/近义/禁止关联"""
    __tablename__ = "concepts"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(64), unique=True, index=True)  # 标准术语
    canonical_definition: Mapped[str] = mapped_column(Text)
    source_id: Mapped[str] = mapped_column(String(64), default="")  # 溯源
    authority_score: Mapped[float] = mapped_column(Float, default=1.0)
    equivalent_terms: Mapped[list] = mapped_column(JSON, default=list)  # 精确同义
    near_synonyms: Mapped[list] = mapped_column(JSON, default=list)  # 近义但不同（纠错用）
    strictly_not: Mapped[list] = mapped_column(JSON, default=list)  # 严格禁止关联（防偏离红线）
    relations: Mapped[dict] = mapped_column(JSON, default=dict)  # determines/is_opposed_to/manifests_as
    versions: Mapped[list] = mapped_column(JSON, default=list)  # 版本控制


class Proposition(Base):
    """命题节点 — 哲学命题及其逻辑结构/等价表述/常见误读"""
    __tablename__ = "propositions"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    text: Mapped[str] = mapped_column(Text)
    source: Mapped[str] = mapped_column(String(128))
    source_location: Mapped[str] = mapped_column(String(64))
    logical_form: Mapped[dict] = mapped_column(JSON, default=dict)  # 逻辑结构
    equivalent_propositions: Mapped[list] = mapped_column(JSON, default=list)
    common_misreadings: Mapped[list] = mapped_column(JSON, default=list)


class ConversationThread(Base):
    """会话线程 — 绑定 document+paragraph+mode 的多轮会话

    用于"思考批注"附着原文位置 + 锚点保持
    """
    __tablename__ = "conversation_threads"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    dialogue_id: Mapped[str] = mapped_column(String(32), ForeignKey("dialogues.id"), index=True)
    document_id: Mapped[str] = mapped_column(String(64))  # 著作
    paragraph_id: Mapped[str] = mapped_column(String(64))  # 原文段落
    mode: Mapped[str] = mapped_column(String(16))  # 会话模式
    annotation_color: Mapped[str] = mapped_column(String(16), default="")  # 思考批注彩色竖线
    is_exempt: Mapped[bool] = mapped_column(Boolean, default=False)  # 辩难模式豁免标记
    messages: Mapped[list] = mapped_column(JSON, default=list)  # 多轮历史
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    __table_args__ = (
        Index("ix_conv_thread_anchor", "document_id", "paragraph_id"),
    )
