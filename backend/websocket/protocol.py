"""WebSocket 消息协议 — 正统马哲学习系统

基于 ljsk 协议，增加马哲场景字段：
  - selected_text  用户选中的原文锚点
  - provenance      溯源卡片
  - blocked         防偏离拦截
  - state_transition 六步状态机映射（马哲六步：精读→追问→辩难→关联→费曼→贯通）

所有消息为 JSON。客户端→服务端 (C→S) 与 服务端→客户端 (S→C) 共用一套类型字段。
"""
from __future__ import annotations

from enum import Enum
from pydantic import BaseModel, Field


class ClientMessageType(str, Enum):
    """C→S 消息类型"""
    USER_MESSAGE = "user_message"      # 用户消息（含选中文本锚点）
    ACTION = "action"                 # 快捷操作（切模式/回到原文/结束）
    PING = "ping"


class ServerMessageType(str, Enum):
    """S→C 消息类型"""
    AI_MESSAGE = "ai_message"            # AI 回复
    STATE_TRANSITION = "state_transition"  # 步骤/模式变更
    PROGRESSION = "progression"           # 评分 + 进度（费曼/掌握度）
    PROVENANCE = "provenance"            # 溯源卡片
    BLOCKED = "blocked"                  # 防偏离拦截
    STRUGGLE_DETECTED = "struggle_detected"  # 卡顿检测
    DIALOGUE_ENDED = "dialogue_ended"
    BADGES_AWARDED = "badges_awarded"  # 新勋章授予（spec 001）
    ERROR = "error"
    PONG = "pong"


# ============================================================
# C→S 消息
# ============================================================

class UserMessageIn(BaseModel):
    """用户消息 — 核心交互"""
    type: ClientMessageType = ClientMessageType.USER_MESSAGE
    dialogue_id: str
    content: str                            # 用户问题
    selected_text: str = ""                 # 选中的原文锚点（FR-003 锚点保持）
    paragraph_id: str = ""                  # 原文段落ID
    mode: str = "explain"                   # explain/dig/debate/connect/test
    critical_reading: bool = False          # 是否切换批判性阅读模式（双轨制 FR-007）

    class Config:
        use_enum_values = True


class ActionIn(BaseModel):
    """快捷操作"""
    type: ClientMessageType = ClientMessageType.ACTION
    dialogue_id: str
    action: str = Field(description="switch_mode / back_to_text / end / exempt_toggle")
    payload: dict = Field(default_factory=dict)


# ============================================================
# S→C 消息
# ============================================================

class ProvenanceCard(BaseModel):
    """溯源卡片 — 精确到句子级 (FR-017)"""
    chunk_id: str
    source: str
    location: str
    authority_score: float
    layer: int                              # 1词条/2命题/3论证/4语境
    excerpt: str = ""                       # 句子级摘录
    fact_check: str = "pass"                # pass/flag
    terminology_check: str = "pass"
    stance_check: str = "pass"


class GuardResult(BaseModel):
    """防偏离三重校验结果"""
    sanitizer: str = "pass"                 # 输入侧 PromptSanitizer
    meta_rule: str = "pass"                 # 生成侧 MetaRuleEngine
    stance_classifier: str = "pass"         # 生成后 BERT
    flags: list = Field(default_factory=list)
    exempt: bool = False                    # 辩难模式标记豁免是否生效 (FR-006)


class AiMessageOut(BaseModel):
    """AI 回复

    编码不进入 content：`[CH-...]` / `[GUIDE-...]` 只用于服务端事实校验，
    生成后剥离，改由结构化的 source_chunks 携带（界面只显示「相关原文」按钮）。
    """
    type: ServerMessageType = ServerMessageType.AI_MESSAGE
    content: str
    mode: str
    is_safe: bool = True
    guard: GuardResult = Field(default_factory=GuardResult)
    provenance: list[ProvenanceCard] = Field(default_factory=list)
    source_chunks: list[dict] = Field(default_factory=list)  # 结构化相关原文（非逐条权威溯源）
    instant_summary: dict = Field(default_factory=dict)  # US2 每轮即时小结+检验问题
    # 作答引擎标注（与单机版同口径）：cloud:<模型> / local / cache
    engine: str = ""
    engine_note: str = ""   # source=mock 时：not-configured / failed:<原因>
    llm_source: str = ""    # 原始路由层：cache / mock / cloud（排查用）


class StruggleDetectedOut(BaseModel):
    """卡顿/学情信号检测（US2）"""
    type: ServerMessageType = ServerMessageType.STRUGGLE_DETECTED
    node_id: str = ""
    signal_type: str = ""
    dialogue_component: float = 1.0
    signal_count: int = 0


class StateTransitionOut(BaseModel):
    """状态变更 — 马哲六步状态机"""
    type: ServerMessageType = ServerMessageType.STATE_TRANSITION
    step: str = Field(description="intensive_reading/socratic/debate/connect/feynman/mastery")
    mode: str
    attempts: int = 0
    angle_index: int = 0                    # 引导角度轮换


class BlockedOut(BaseModel):
    """防偏离拦截 — UI 显示 blocked 状态"""
    type: ServerMessageType = ServerMessageType.BLOCKED
    reason: str
    layer: str = Field(description="input/content/stance")  # 哪一层拦截
    fallback: str = ""                      # fallback 回复
    allow_critical_reading: bool = False   # 是否允许切批判性模式


class ErrorOut(BaseModel):
    type: ServerMessageType = ServerMessageType.ERROR
    code: str
    message: str


class BadgesAwardedOut(BaseModel):
    """新勋章授予通知（spec 001）：对话完成后检测到新勋章时下发。"""
    type: ServerMessageType = ServerMessageType.BADGES_AWARDED
    badges: list[dict] = Field(default_factory=list)
