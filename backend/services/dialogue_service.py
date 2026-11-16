"""对话服务 — 核心对话编排

MVP 编排流：
  用户输入
    → PromptSanitizer 输入侧防注入（已就绪，移植自 ljsk）
    → RAG 三路混合召回 + 五层过滤（Phase 2 留接口，当前空 RAGContext）
    → PromptRenderer 渲染 + LLMRouter 4级路由生成（Phase 3）
    → TripleCheck 生成后三重校验：事实一致性 + 术语一致性 + 立场分类（Phase 3）
    → 通过 → AiMessageOut（含溯源）
      不通过 → BlockedOut（含 fallback）
"""
from __future__ import annotations

import logging
import sys
import os
import threading
from functools import lru_cache
from typing import Any

# 复用现有原型脚本（在项目根目录）
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from prompt_sanitizer import PromptSanitizer  # noqa: E402
from core.guard.orthodoxy import OrthodoxyGuard  # noqa: E402
from core.prompt.renderer import (  # noqa: E402
    PromptRenderer, UserContext, RAGContext,
    TextChunk, TermDefinition,
)
from core.llm.router import LLMRouter  # noqa: E402
from core.verify.triple_check import TripleCheck  # noqa: E402
from core.rag.retriever import HybridRetriever  # noqa: E402

from websocket.protocol import UserMessageIn, ActionIn
from services.source_metadata import (
    strip_citations, cited_chunk_ids, merge_source_chunks,
)

logger = logging.getLogger(__name__)


def _digest(text: str) -> str:
    """用户输入的不可逆短摘要（8 位）——用于日志定位，不泄露原文。"""
    import hashlib
    return hashlib.sha256(text.encode("utf-8", "replace")).hexdigest()[:8]


@lru_cache(maxsize=1)
def _load_stance_classifier():
    """加载 ML 立场分类器——模型文件存在才加载，缺失回退 None（规则兜底）

    保持轻量模式可跑：未训练时不阻塞对话流。
    sklearn/joblib 反序列化约 4s，进程内缓存一份即可；分类器只读，可共享。
    """
    try:
        from ml.train_stance import StanceClassifier
        return StanceClassifier()
    except FileNotFoundError:
        logger.info("ML 立场分类器未训练，使用规则版兜底（运行 python -m ml.train_stance 训练）")
        return None
    except Exception as e:
        logger.warning("ML 立场分类器加载失败，规则兜底: %s", e)
        return None


def _build_retriever() -> HybridRetriever:
    """构造 HybridRetriever——默认 in-memory，Docker 集成后注入真实 store

    切换策略（环境驱动）：
      - 无 EMBED_API_KEY / DATABASE_URL 连不上 → in-memory（当前）
      - 配齐 EMBED_API_KEY + PG 可达 → PgvectorStore（待 Docker 集成后实现 search）
      - 配齐 NEO4J_URL + driver → Neo4jGraphStore
    """
    from content.theses_annotations import build_chunks
    from content.theses_concepts import CONCEPTS

    retriever = HybridRetriever()
    retriever.index_chunks(build_chunks())
    try:  # 追加已入正文的原著分片（大众哲学 / 哲学笔记 …），使对话可检索真实原文
        from content.book_chunks import retrievable_chunks

        retriever.index_chunks(list(retrievable_chunks()))
    except Exception:  # pragma: no cover
        pass

    # 注册概念间关联（图召回用）——基于 CONCEPTS 的 equivalent_terms 建边
    for c in CONCEPTS:
        for eq in c.get("equivalent_terms", []):
            retriever.add_concept_relation(c["name"], eq)

    return retriever


# 全库索引（约 1.59 万分片）构建一次要 10s 以上；每个 WebSocket 连接都重建
# 会让「选中文字 → 释义」在首条消息前就卡住。进程内共享只读检索器：
# 召回本身不写状态（只有 renderer.session_history 是会话态），共享是安全的。
_shared_retriever: HybridRetriever | None = None
_retriever_lock = threading.Lock()


def shared_retriever() -> HybridRetriever:
    """惰性构建并复用全库检索器（供 /ws/dialogue 与 DialogueService 共用）"""
    global _shared_retriever
    if _shared_retriever is None:
        with _retriever_lock:
            if _shared_retriever is None:
                logger.info("构建共享全库检索器（一次性）...")
                _shared_retriever = _build_retriever()
                logger.info("共享全库检索器就绪")
    return _shared_retriever


def warm_dialogue_service() -> None:
    """应用启动时预热：把 12s 索引构建 + 4s 立场模型加载挪出首条对话。

    DialogueService 的其余组件都是轻量只读对象；renderer 的会话历史必须按
    连接独立保存，不能共享整个 service。
    """
    shared_retriever()
    _load_stance_classifier()


class DialogueService:
    """对话编排服务"""

    def __init__(self, retriever: HybridRetriever | None = None) -> None:
        self.sanitizer = PromptSanitizer()
        self.guard = OrthodoxyGuard()
        self.renderer = PromptRenderer()
        self.llm_router = LLMRouter()
        self.triple_check = TripleCheck(guard=self.guard, stance_classifier=_load_stance_classifier())
        # RAG 混合召回（Phase 6 集成）：默认 in-memory store
        # Docker 起来后注入 PgvectorStore + Neo4jGraphStore；
        # 未显式传入时复用进程内共享实例，避免每条 WebSocket 连接重建全库索引。
        self.retriever = retriever if retriever is not None else shared_retriever()

    async def chat(self, u: UserMessageIn) -> dict[str, Any]:
        """核心对话流程"""
        # === 输入侧：Prompt 注入防护 ===
        check = self.sanitizer.check(u.content)
        if not check["is_safe"]:
            # 隐私：**不落盘用户原文**。被拦截的输入恰恰是最敏感的一类，
            # 写进日志文件后无法回收；只记长度与不可逆摘要，够定位问题即可。
            logger.warning("输入拦截: %s | len=%d digest=%s", check["reason"],
                           len(u.content), _digest(u.content))
            return {
                "blocked": {
                    "reason": check["reason"],
                    "layer": "input",
                    "fallback": "您的提问包含不合规内容，请重新表述。",
                    "allow_critical_reading": False,
                }
            }

        # === Phase 2 RAG 召回（当前空，待 Docker 集成 pgvector+Neo4j）===
        rag_context = self._retrieve(u)  # 当前返回空 RAGContext

        # === Phase 3: Prompt 渲染 ===
        user_context = UserContext(
            current_work=u.paragraph_id or "关于费尔巴哈的提纲",
            current_chapter="全文",
            selected_text=u.selected_text or "",
            user_question=u.content,
            current_mode=u.mode,
            session_history=list(self.renderer.session_history),
        )
        rendered = self.renderer.render(user_context, rag_context, critical_reading=u.critical_reading)

        # === Phase 3: LLM 生成（4级路由，未配 key 走 Mock）===
        resp = await self.llm_router.generate(
            rendered.full_prompt, task="general", interactive=True
        )
        generated = resp.text

        # === Phase 3: 生成后三重校验 ===
        retrieved_context = self._retrieved_context_str(rag_context)
        tc = self.triple_check.check(
            generated,
            retrieved_context=retrieved_context,
            mode=u.mode,
            allow_critical=u.critical_reading,
        )

        if tc["action"] == "block":
            stance = tc["stance"]
            flags = stance.get("detail", [])
            return {
                "blocked": {
                    "reason": "；".join(
                        (f.get("reason", "") if isinstance(f, dict) else str(f))[:40]
                        for f in (flags[:3] if flags else [{"reason": "立场校验未通过"}])
                    ),
                    "layer": "stance",
                    "fallback": "该回答触发防偏离拦截，已转为正统表述。如需批判性参考，可切换批判性阅读模式。",
                    "allow_critical_reading": True,
                    # T022：被判偏离的内容标注为『需批判对象引导』，不计普通人错题
                    "not_a_normal_error": True,
                    "treat_as": "critique_target",
                }
            }

        # === 通过 → 剥离内部编码，转结构化相关原文 ===
        # `[CH-...]` / `[GUIDE-...]` 只服务上面的事实一致性校验；从这里开始
        # 会话历史、即时小结、WS 输出、对话落库一律用清洗后的正文。
        # 只保留正文库里真实存在的分片：模型可能引用了不存在的 id，
        # 结构化列表直接剔掉，前端按钮点开就不会出现空卡片。
        from services import content_provider as _cp
        cited_ids = [cid for cid in cited_chunk_ids(generated) if _cp.get_chunk(cid)]
        provenance = self._build_provenance(rag_context)
        source_chunks = merge_source_chunks(cited_ids, provenance)
        content_out = strip_citations(generated)
        if not content_out:
            # 极端情况：模型只输出了引用标记。不能发空气泡，给个中性提示。
            content_out = "（本轮回答无可展示正文，可点下方「相关原文」核对依据）"

        # === 通过 → 记录历史 ===
        self.renderer.add_to_history(u.content, content_out)

        # === US2: 隐式学情信号埋点（T020）===
        struggle = await self._detect_and_report_struggle(u, content_out)

        # === US2: 即时小结 + 检验问题（T019，轻量不阻断主回答）===
        instant = self._build_instant_summary(u, content_out)

        is_safe = tc["action"] == "pass"
        ai_message = {
            "content": content_out,
            "mode": u.mode,
            "is_safe": is_safe,
            "guard": {
                "sanitizer": "pass",
                "meta_rule": "pass",
                "stance_classifier": tc["stance"]["source"],
                "exempt": tc["stance"].get("exempt", False),
                "fact_flag": tc["fact_consistency"]["status"],
                "terminology_flag": tc["terminology"]["status"],
            },
            "provenance": provenance,
            "source_chunks": source_chunks,
            "llm_source": resp.source,
            "instant_summary": instant,
        }

        return {
            "ai_message": ai_message,
            "struggle": struggle,
            "state_transition": {
                "step": "intensive_reading",
                "mode": u.mode,
                "attempts": 0,
                "angle_index": 0,
            },
        }

    def _retrieve(self, u: UserMessageIn) -> RAGContext:
        """RAG 召回 — HybridRetriever（向量+图+关键词三路 + 五层过滤）

        默认 in-memory store（无 Docker 依赖）；
        Docker 起来后由 _build_retriever() 注入 PgvectorStore + Neo4jGraphStore。
        """
        return self.retriever.retrieve(u)

    def _build_provenance(self, rag_context: RAGContext) -> list[dict]:
        """从 RAG 结果生成溯源卡片（FR-017 句子级）"""
        cards = []
        for c in rag_context.text_chunks:
            cards.append({
                "chunk_id": c.chunk_id,
                "source": c.source,
                "location": c.source_location,
                "source_location": c.source_location,
                "kind": "related",
                "authority_score": c.authority_score,
                "layer": 1,  # 简化，实际按 chunk layer
                "excerpt": c.text[:80],
                "fact_check": "pass",
                "terminology_check": "pass",
                "stance_check": "pass",
            })
        return cards[:5]  # 溯源卡片取前5

    def _retrieved_context_str(self, rag_context: RAGContext) -> str:
        """把 RAG 上下文拼成字符串，供三重校验事实一致性比对"""
        parts = []
        for c in rag_context.text_chunks:
            parts.append(c.chunk_id)
            parts.append(c.text)
        for t in rag_context.term_definitions:
            parts.append(t.source_id)
        return "\n".join(parts)

    # --------------------------------------------------
    # US2 学情闭环：即时小结 / 卡顿信号 / 偏离不计错题
    # --------------------------------------------------
    def _build_instant_summary(self, u: UserMessageIn, generated: str) -> dict:
        """T019：每轮轻量小结 + 1 个检验问题（不阻断主回答）"""
        text = (generated or "").strip()
        first = text.split("。")[0] if text else ""
        one_line = (first + "。") if first else "本轮围绕你的问题展开。"
        # 检验问题按模式选择
        q_by_mode = {
            "explain": "你能用自己的话说清这个概念的『不是』是什么吗？",
            "dig": "这句话的依据在原文哪一层？",
            "debate": "对方最有力的反驳是什么，你如何回应？",
            "connect": "它与本提纲另一条如何相互支撑？",
            "test": "不看原文，你能复述其核心论断吗？",
        }
        return {
            "one_line": one_line[:160],
            "check_question": q_by_mode.get(u.mode, q_by_mode["explain"]),
            "paragraph_id": u.paragraph_id or "",
        }

    async def _detect_and_report_struggle(self, u: UserMessageIn, generated: str) -> dict | None:
        """T020：反复追问 / 答错被驳回 / 关联失败 → 上报 StruggleSignal"""
        try:
            from services import mastery_service as ms
            from content.knowledge_graph import KNOWLEDGE_NODES
        except Exception:
            return None
        content = u.content or ""
        signal_type = None
        if any(k in content for k in ("还是不懂", "没懂", "再说一遍", "不懂", "什么意思")):
            signal_type = "repeated_question"
        elif any(k in content for k in ("是不是", "我理解对么", "对吗")) and len(content) < 30:
            signal_type = "low_confidence"
        if signal_type is None:
            return None
        # 将提问映射到最可能的知识点（按 selected_text / paragraph / 文本包含）
        node_id = self._guess_node(u, KNOWLEDGE_NODES)
        if not node_id:
            return None
        route_id = getattr(u, "route_id", "route_A") or "route_A"
        # 对话侧无显式 user_id 时以 dialogue_id 作为会话级学情键
        user_key = getattr(u, "user_id", None) or u.dialogue_id
        try:
            sig = await ms.add_struggle_signal(user_key, node_id,
                                                signal_type, intensity=0.5, source="dialogue")
            # 同步到该用户掌握度的 dialogue 分量
            await ms.sync_dialogue_mastery(user_key, node_id, route_id)
        except Exception:
            return None
        return {"node_id": node_id, "signal_type": signal_type, **sig}

    def _guess_node(self, u: UserMessageIn, nodes: list[dict]) -> str | None:
        hay = (u.selected_text or "") + " " + (u.content or "")
        for n in nodes:
            if n.get("name") and n["name"] in hay:
                return n["id"]
        return nodes[0]["id"] if nodes else None

    async def handle_action(self, a: ActionIn, ws) -> None:
        """快捷操作：切模式/回到原文/结束"""
        import json
        await ws.send_text(json.dumps({
            "type": "action_ack",
            "action": a.action,
            "payload": a.payload,
        }))
