"""学习闭环内容种子 — 将 routes / knowledge_graph / quiz_bank 灌入 DB（幂等）

启动时与测试前置调用。路线、章节、知识点、依赖边、题库均按主键 upsert。
"""
from __future__ import annotations

import json
import os
import logging

from sqlalchemy import select

from services.learning_db import session_scope
from model.models_learning import (
    LearningRoute, RouteSection, KnowledgeNode, NodePrerequisite, QuizItem,
)
from content.routes import ROUTES, SECTIONS
from content.knowledge_graph import KNOWLEDGE_NODES, PREREQUISITES

logger = logging.getLogger(__name__)

_QUIZ_DIR = os.path.join(os.path.dirname(__file__), "..", "content", "quiz_bank")


def _load_quiz_items() -> list[dict]:
    """加载 quiz_bank 目录下所有 *.json 的题目（每题自带 section_id）。"""
    import glob
    items: list[dict] = []
    for path in sorted(glob.glob(os.path.join(_QUIZ_DIR, "*.json"))):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        for it in data.get("items", []):
            # 缺省用顶层 section_id 回填（键存在但值为 null 时也要回填：
            # `outline_chapter.json` 的题逐条写了 "section_id": null）
            if not it.get("section_id"):
                it["section_id"] = data.get("section_id") or it["section_id"]
            items.append(it)
    return items


async def seed_all() -> None:
    async with session_scope() as s:
        # 路线
        existing_routes = {r.id for r in (await _all(s, LearningRoute))}
        for r in ROUTES:
            if r["id"] not in existing_routes:
                s.add(LearningRoute(**r))

        # 章节
        existing_secs = {x.id for x in (await _all(s, RouteSection))}
        for sec in SECTIONS:
            if sec["id"] not in existing_secs:
                s.add(RouteSection(
                    id=sec["id"], route_id=sec["route_id"],
                    order_index=sec["order_index"], stage_no=sec["stage_no"],
                    work=sec["work"], title=sec["title"],
                    unlock_threshold=sec.get("unlock_threshold", 0.8),
                    is_foundation=sec.get("is_foundation", False),
                ))

        # 知识点
        existing_nodes = {n.id for n in (await _all(s, KnowledgeNode))}
        for n in KNOWLEDGE_NODES:
            if n["id"] not in existing_nodes:
                s.add(KnowledgeNode(
                    id=n["id"], section_id=n["section_id"], name=n["name"],
                    definition=n.get("definition", ""), ability_dim=n["ability_dim"],
                    exam_weight=n["exam_weight"], source_chunk_id=n["source_chunk_id"],
                ))

        # 依赖边（去重）
        existing_edges = {
            (e.node_id, e.prereq_id) for e in (await _all(s, NodePrerequisite))
        }
        for node_id, prereq_id in PREREQUISITES:
            if (node_id, prereq_id) not in existing_edges:
                s.add(NodePrerequisite(node_id=node_id, prereq_id=prereq_id))

        # 题库
        existing_q = {q.id for q in (await _all(s, QuizItem))}
        for it in _load_quiz_items():
            if it["id"] in existing_q:
                continue
            s.add(QuizItem(
                id=it["id"], section_id=it.get("section_id") or "sec_A_02", node_id=it["node_id"],
                type=it["type"], stem=it["stem"], options=it.get("options", []),
                answer=it.get("answer", ""), explanation=it.get("explanation", ""),
                difficulty=it.get("difficulty", 0.5),
                source_chunk_id=it["source_chunk_id"],
                authority_status=it.get("authority_status", "pending"),
                exempt_marked=it.get("exempt_marked", False),
                trial_only=it.get("trial_only", True),
                subjective=it.get("subjective", False),
            ))
    logger.info("学习闭环内容种子完成")


async def _all(s, model):
    if hasattr(s, "execute") and _is_async_session(s):
        res = await s.execute(select(model))
        return res.scalars().all()
    return s.execute(select(model)).scalars().all()


def _is_async_session(s) -> bool:
    try:
        from sqlalchemy.ext.asyncio import AsyncSession
        return isinstance(s, AsyncSession)
    except Exception:
        return False
