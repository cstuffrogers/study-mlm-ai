"""学习闭环引擎 ORM 模型 — 路线 / 章节 / 知识点 / 掌握度 / 题目 / 进度 / 推荐

与主系统 `model/models.py` 解耦，使用独立 `LearningBase`：
  - 内存模式（SQLite :memory:）可直接建表跑测试与 demo，无需 PostgreSQL；
  - 生产接入 PG 时同库不同 metadata，不影响既有 async 表（users/text_chunks 等）。

枚举统一用 String 存储，便于 SQLite/MySQL/PG 跨库与迁移。
"""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (
    String, Text, Integer, Float, Boolean, DateTime, ForeignKey, JSON, Index, func,
)
from sqlalchemy.orm import Mapped, mapped_column

from core.db import LearningBase


def _uuid() -> str:
    return uuid.uuid4().hex


# ---------------------------------------------------------------- 路线 / 章节
class LearningRoute(LearningBase):
    __tablename__ = "lr_routes"

    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    name: Mapped[str] = mapped_column(String(64))
    goal: Mapped[str] = mapped_column(Text, default="")
    est_duration: Mapped[str] = mapped_column(String(64), default="")
    shares_foundation: Mapped[bool] = mapped_column(Boolean, default=True)
    foundation_ref: Mapped[str] = mapped_column(String(256), default="")


class RouteSection(LearningBase):
    __tablename__ = "lr_route_sections"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    route_id: Mapped[str] = mapped_column(String(32), index=True)
    order_index: Mapped[int] = mapped_column(Integer, default=0)
    stage_no: Mapped[int] = mapped_column(Integer, default=0)
    work: Mapped[str] = mapped_column(String(128), default="")
    title: Mapped[str] = mapped_column(String(128), default="")
    unlock_threshold: Mapped[float] = mapped_column(Float, default=0.8)
    is_foundation: Mapped[bool] = mapped_column(Boolean, default=False)

    __table_args__ = (Index("ix_lr_section_route_order", "route_id", "order_index"),)


# ---------------------------------------------------------------- 知识点（依赖图）
class KnowledgeNode(LearningBase):
    __tablename__ = "lr_knowledge_nodes"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    section_id: Mapped[str] = mapped_column(String(64), index=True)
    name: Mapped[str] = mapped_column(String(128))
    definition: Mapped[str] = mapped_column(Text, default="")
    ability_dim: Mapped[str] = mapped_column(String(32), default="epistemology")
    exam_weight: Mapped[float] = mapped_column(Float, default=0.5)
    source_chunk_id: Mapped[str] = mapped_column(String(64), default="")


class NodePrerequisite(LearningBase):
    __tablename__ = "lr_node_prerequisites"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    node_id: Mapped[str] = mapped_column(String(64), index=True)
    prereq_id: Mapped[str] = mapped_column(String(64), index=True)
    strength: Mapped[float] = mapped_column(Float, default=1.0)


# ---------------------------------------------------------------- 测验
class QuizItem(LearningBase):
    __tablename__ = "lr_quiz_items"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    section_id: Mapped[str] = mapped_column(String(64), index=True)
    node_id: Mapped[str] = mapped_column(String(64), index=True)
    type: Mapped[str] = mapped_column(String(32))  # 四类题型
    stem: Mapped[str] = mapped_column(Text)
    options: Mapped[list] = mapped_column(JSON, default=list)
    answer: Mapped[str] = mapped_column(String(256))  # 客观题标准答案；主观题为空
    explanation: Mapped[str] = mapped_column(Text, default="")
    difficulty: Mapped[float] = mapped_column(Float, default=0.5)
    source_chunk_id: Mapped[str] = mapped_column(String(64))  # 溯源必填（FR-022）
    authority_status: Mapped[str] = mapped_column(String(16), default="pending")  # pending/reviewed
    exempt_marked: Mapped[bool] = mapped_column(Boolean, default=False)  # 错误诊断故意错误项（FR-023）
    trial_only: Mapped[bool] = mapped_column(Boolean, default=True)  # 未审题仅练习，不计正式掌握度
    subjective: Mapped[bool] = mapped_column(Boolean, default=False)  # 主观题（费曼/论述）


class QuizAttempt(LearningBase):
    __tablename__ = "lr_quiz_attempts"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(32), index=True)
    quiz_id: Mapped[str] = mapped_column(String(64), index=True)
    test_id: Mapped[str] = mapped_column(String(32), index=True)
    answer: Mapped[str] = mapped_column(Text, default="")
    is_correct: Mapped[bool] = mapped_column(Boolean, default=False)
    score: Mapped[float] = mapped_column(Float, default=0.0)
    duration_ms: Mapped[int] = mapped_column(Integer, default=0)
    error_category: Mapped[str] = mapped_column(String(32), default="")
    confidence: Mapped[str] = mapped_column(String(8), default="")  # P2-④ 元认知校准：low/mid/high
    subjective_feedback: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())  # 学习分析看板：连续性/趋势


class SectionTest(LearningBase):
    __tablename__ = "lr_section_tests"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(32), index=True)
    section_id: Mapped[str] = mapped_column(String(64), index=True)
    route_id: Mapped[str] = mapped_column(String(32), index=True)
    item_ids: Mapped[list] = mapped_column(JSON, default=list)
    total_score: Mapped[float] = mapped_column(Float, default=0.0)
    mastery_snapshot: Mapped[dict] = mapped_column(JSON, default=dict)
    status: Mapped[str] = mapped_column(String(16), default="in_progress")
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    submitted_at: Mapped[datetime] = mapped_column(DateTime, nullable=True)


class DiagnosticTest(LearningBase):
    __tablename__ = "lr_diagnostic_tests"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(32), index=True)
    route_id: Mapped[str] = mapped_column(String(32), index=True)
    item_ids: Mapped[list] = mapped_column(JSON, default=list)
    result: Mapped[dict] = mapped_column(JSON, default=dict)
    skipped: Mapped[bool] = mapped_column(Boolean, default=False)


# ---------------------------------------------------------------- 学情
class MasteryRecord(LearningBase):
    __tablename__ = "lr_mastery_records"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(32), index=True)
    node_id: Mapped[str] = mapped_column(String(64), index=True)
    route_id: Mapped[str] = mapped_column(String(32), index=True)
    level: Mapped[str] = mapped_column(String(16), default="unseen")
    score: Mapped[float] = mapped_column(Float, default=0.0)
    basis: Mapped[dict] = mapped_column(JSON, default=dict)
    source_flags: Mapped[dict] = mapped_column(JSON, default=dict)
    # ---- spec 003 FR-115/117：证据置信度与冲突标记 ----
    confidence: Mapped[float] = mapped_column(Float, default=0.0)
    conflict_flag: Mapped[bool] = mapped_column(Boolean, default=False)
    # ---- P1-① 间隔复习调度（D8）----
    review_count: Mapped[int] = mapped_column(Integer, default=0)
    last_reviewed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    next_review_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())

    __table_args__ = (Index("ix_lr_mastery_uxr", "user_id", "node_id", "route_id", unique=True),)


class EvidenceEvent(LearningBase):
    """证据事件 — 学情唯一写入源（spec 003 FR-113/114/115）

    一次可观察的学习行为（答对/答错/费曼通过/对话中讲清/读完）即一条证据；
    证据可撤销，撤销后按剩余有效证据重放重算掌握度（顺序无关）。
    `dedupe_key` 全局唯一 → 同一行为重复提交只算一次（幂等，FR-114）。
    """
    __tablename__ = "lr_evidence_events"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(32), index=True)
    route_id: Mapped[str] = mapped_column(String(32), index=True)
    node_id: Mapped[str] = mapped_column(String(64), index=True)
    # quiz / feynman / dialogue / reading / manual
    source: Mapped[str] = mapped_column(String(16), index=True)
    # correct / partial / wrong / engaged
    judgement: Mapped[str] = mapped_column(String(16), default="correct")
    # 来源引用：quiz_item_id / dialogue_id#turn / annotation_id
    ref: Mapped[str] = mapped_column(String(128), default="")
    confidence: Mapped[float] = mapped_column(Float, default=1.0)
    strength: Mapped[float] = mapped_column(Float, default=1.0)
    error_type: Mapped[str] = mapped_column(String(32), default="")
    counts_toward_mastery: Mapped[bool] = mapped_column(Boolean, default=True)
    dedupe_key: Mapped[str] = mapped_column(String(64), unique=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    __table_args__ = (
        Index("ix_lr_evidence_user_time", "user_id", "created_at"),
        Index("ix_lr_evidence_user_node", "user_id", "node_id"),
    )


class StruggleSignal(LearningBase):
    __tablename__ = "lr_struggle_signals"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(32), index=True)
    node_id: Mapped[str] = mapped_column(String(64), index=True)
    signal_type: Mapped[str] = mapped_column(String(32))
    intensity: Mapped[float] = mapped_column(Float, default=0.3)
    source: Mapped[str] = mapped_column(String(16), default="dialogue")  # dialogue/quiz/feynman
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class ReviewLog(LearningBase):
    """复习日志（D15 FSRS 参数拟合）：记录每次复习的 stability 变化与遗忘窗口。"""
    __tablename__ = "lr_review_logs"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(32), index=True)
    route_id: Mapped[str] = mapped_column(String(32), index=True)
    node_id: Mapped[str] = mapped_column(String(64), index=True)
    stability_before: Mapped[float] = mapped_column(Float, default=0.0)
    stability_after: Mapped[float] = mapped_column(Float, default=0.0)
    interval_days: Mapped[float] = mapped_column(Float, default=0.0)
    correct_ratio: Mapped[float] = mapped_column(Float, default=0.0)
    elapsed_days: Mapped[float] = mapped_column(Float, default=0.0)
    correct: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class LearningProfile(LearningBase):
    __tablename__ = "lr_learning_profiles"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(32), index=True)
    route_id: Mapped[str] = mapped_column(String(32), index=True)
    ability_radar: Mapped[dict] = mapped_column(JSON, default=dict)
    weak_points: Mapped[list] = mapped_column(JSON, default=list)
    summary_text: Mapped[str] = mapped_column(Text, default="")
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())

    __table_args__ = (Index("ix_lr_profile_ur", "user_id", "route_id", unique=True),)


# ---------------------------------------------------------------- 进度 / 推荐
class LearningProgress(LearningBase):
    __tablename__ = "lr_learning_progress"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(32), index=True)
    route_id: Mapped[str] = mapped_column(String(32), index=True)
    section_id: Mapped[str] = mapped_column(String(64), index=True)
    status: Mapped[str] = mapped_column(String(16), default="locked")
    current_anchor: Mapped[str] = mapped_column(String(64), default="")
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())

    __table_args__ = (Index("ix_lr_progress_urs", "user_id", "route_id", "section_id", unique=True),)


class Recommendation(LearningBase):
    __tablename__ = "lr_recommendations"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(32), index=True)
    route_id: Mapped[str] = mapped_column(String(32), index=True)
    rec_type: Mapped[str] = mapped_column(String(24))  # start/next_section/review/reinforce
    target_section_id: Mapped[str] = mapped_column(String(64), default="")
    target_node_id: Mapped[str] = mapped_column(String(64), default="")
    reason: Mapped[str] = mapped_column(Text, default="")
    consumed: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class FeedbackReport(LearningBase):
    __tablename__ = "lr_feedback_reports"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(32), index=True)
    route_id: Mapped[str] = mapped_column(String(32), index=True)
    period: Mapped[str] = mapped_column(String(16), default="week")
    mastered: Mapped[list] = mapped_column(JSON, default=list)
    to_reinforce: Mapped[list] = mapped_column(JSON, default=list)
    next_step: Mapped[str] = mapped_column(Text, default="")
    source_tags: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
