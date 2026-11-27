"""Configuration — 环境变量加载"""
from __future__ import annotations

import os
import secrets

from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql+asyncpg://marxism:marxism_pass@localhost:5432/marxism_learning")
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
NEO4J_URL = os.getenv("NEO4J_URL", "bolt://localhost:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD", "marxism_pass")

# ---- 密钥：未显式设置时**随机生成**，不再给固定默认值 ----
# 旧默认值 `change-me-in-production` 是写死的公开串：一旦有人把服务从回环地址
# 挪出去，任何人都能照默认值伪造 JWT。而单机自用也根本不需要这个固定值，
# 所以未设置时直接随机生成一把强密钥（进程级；重启后旧 token 失效 ——
# 本项目无登录页、前端固定 `demo_user`，不存在「重启要重登」的问题）。
# 显式设成弱值仍只告警、不阻断启动（不打断本地开发与测试）。
_ENV_SECRET_KEY = os.getenv("SECRET_KEY", "").strip()
SECRET_KEY_IS_GENERATED = not _ENV_SECRET_KEY
SECRET_KEY = _ENV_SECRET_KEY or secrets.token_urlsafe(32)

# ---- 弱口令护栏 ----
# 口径：单机自用不管；**一旦对外提供服务（非 localhost 访问）就必须改掉**。
# 真正要对公网开服务时，把 SECRET_KEY 设为 32 字节以上的随机值（或干脆不设）。
_INSECURE_SECRETS = {"", "change-me-in-production", "dev-secret-change-me",
                     "secret", "changeme", "test"}
SECRET_KEY_IS_WEAK = not SECRET_KEY_IS_GENERATED and (
    SECRET_KEY in _INSECURE_SECRETS or len(SECRET_KEY) < 32)

LLM_API_KEY = os.getenv("LLM_API_KEY", "")
LLM_BASE_URL = os.getenv("LLM_BASE_URL", "https://dashscope.aliyuncs.com/compatible-mode/v1")
LLM_MODEL = os.getenv("LLM_MODEL", "qwen-plus")
LLM_MAX_CONCURRENT = int(os.getenv("LLM_MAX_CONCURRENT", "3"))
LLM_MAX_RETRIES = int(os.getenv("LLM_MAX_RETRIES", "2"))
# 单次调用超时（秒）。缺省 30s：真实模型端点无响应时必须快速失败并降级 Mock，
# 不得无限挂起（此前无 timeout，端点不通时调用会永久阻塞）。
# 交互式会话（WebSocket）另受 WS_DIALOGUE_TIMEOUT 与
# LLM_INTERACTIVE_TIMEOUT 约束；交互路径不重试，单次上限即总等待上限。
LLM_TIMEOUT = float(os.getenv("LLM_TIMEOUT", "60"))

EMBED_API_KEY = os.getenv("EMBED_API_KEY", "")
EMBED_BASE_URL = os.getenv("EMBED_BASE_URL", "")
EMBED_MODEL = os.getenv("EMBED_MODEL", "")

ENABLE_SEMANTIC_CACHE = os.getenv("ENABLE_SEMANTIC_CACHE", "true").lower() == "true"
AUTO_CREATE_TABLES = os.getenv("AUTO_CREATE_TABLES", "1") == "1"

# ---- CORS（安全硬化）：逗号分隔的来源白名单；默认仅本地开发地址 ----
# 生产请通过环境变量 CORS_ORIGINS 指定明确来源，勿使用 "*"。
_DEFAULT_CORS_ORIGINS = (
    "http://localhost:8190,http://127.0.0.1:8190,"
    "http://localhost:3000,http://127.0.0.1:3000,"
    "http://localhost:8080,http://127.0.0.1:8080"
)
CORS_ORIGINS = [o.strip() for o in
                os.getenv("CORS_ORIGINS", _DEFAULT_CORS_ORIGINS).split(",") if o.strip()]
# 浏览器规范禁止 credentials + "*" 同时使用；仅当无通配符来源时才开启 credentials
_WILDCARD = "*"
CORS_ALLOW_CREDENTIALS = _WILDCARD not in CORS_ORIGINS

# 学习闭环引擎 DB 模式：auto=有 DATABASE_URL 用 postgres 否则内存；memory=强制内存（默认，无 PG 也可跑测试/demo）；postgres=强制 PG
LEARNING_DB_MODE = os.getenv("LEARNING_DB_MODE", "memory").lower()

# 学情闭环可配置参数（可在路线/章节级覆盖）
UNLOCK_THRESHOLD = float(os.getenv("UNLOCK_THRESHOLD", "0.8"))
QUIZ_SIZE_MIN = int(os.getenv("QUIZ_SIZE_MIN", "8"))
QUIZ_SIZE_MAX = int(os.getenv("QUIZ_SIZE_MAX", "12"))

# 掌握度五级阈值（D1）：score 分档
MASTERY_THRESHOLDS = {
    "unseen": 0.2,
    "beginner": 0.45,
    "familiar": 0.7,
    "proficient": 0.85,
    # >0.85 -> mastered
}
# 掌握度加权（D1）：测试正确率/难度校正/稳定度/对话信号/费曼
MASTERY_WEIGHTS = {
    "accuracy": 0.60,
    "difficulty": 0.15,
    "stability": 0.10,
    "dialogue": 0.10,
    "feynman": 0.05,
}

# ---- P1-① 间隔复习调度（FSRS-lite，D8）----
# reviewed 后 stability 起始值随掌握度分档；复习间隔 = base × 2^(stability/0.3)，封顶 MAX
REVIEW_BASE_INTERVAL_DAYS = float(os.getenv("REVIEW_BASE_INTERVAL_DAYS", "1"))
REVIEW_MAX_INTERVAL_DAYS = float(os.getenv("REVIEW_MAX_INTERVAL_DAYS", "60"))
# 记忆保持率衰减：propensity = 0.5 ** (elapsed_days / half_life_days)，half_life = 3 + 12*stability 天
REVIEW_HALF_LIFE_MIN_DAYS = float(os.getenv("REVIEW_HALF_LIFE_MIN_DAYS", "3"))
REVIEW_HALF_LIFE_MAX_DAYS = float(os.getenv("REVIEW_HALF_LIFE_MAX_DAYS", "15"))
# 到期判定：保持率低于该阈值即视为该复习（否则按 next_reviews_at 到点）
REVIEW_DUE_RETENTION = float(os.getenv("REVIEW_DUE_RETENTION", "0.9"))
# 复习成功 → stability 提升步长；失败 → 回落到较低 stability
REVIEW_GAIN = float(os.getenv("REVIEW_GAIN", "0.15"))
REVIEW_REGRESS = float(os.getenv("REVIEW_REGRESS", "0.2"))

# ---- P2-④ 元认知校准（D9）----
# 自评把握度映射到预期正确概率：低/中/高 → 0.3/0.6/0.9
CALIBRATION_CONFIDENCE_MAP = {
    "low": 0.3,
    "mid": 0.6,
    "high": 0.9,
}
# 过自信判定阈值：预期概率 - 实际正确率 > 该值 → overconfident
CALIBRATION_OVERCONFIDENT_GAP = float(os.getenv("CALIBRATION_OVERCONFIDENT_GAP", "0.25"))

# ---- P2-⑤ 交错练习（interleaving，D11）----
# 混合复习队列中「不过期但已掌握」知识点的目标占比（避免块状重复）
INTERLEAVE_MIX_RATIO = float(os.getenv("INTERLEAVE_MIX_RATIO", "0.4"))
# 默认一轮交错复习的题量
INTERLEAVE_SIZE = int(os.getenv("INTERLEAVE_SIZE", "8"))


def security_warnings() -> list[str]:
    """启动期安全告警（只告警，不阻断启动）。

    单机自用场景这些默认值完全够用；但一旦把服务暴露到本机之外，
    下面每一条都会变成真实风险。所以只做提示，不改默认行为，
    免得打断开发与测试。
    """
    warns: list[str] = []
    if SECRET_KEY_IS_GENERATED:
        warns.append(
            "SECRET_KEY 未设置：本进程已随机生成一把强弱密钥（重启后旧 token 失效，属正常）；"
            "要把服务提供给本机之外前，请在 .env 里显式设成 32 字节以上随机值")
    elif SECRET_KEY_IS_WEAK:
        warns.append(
            "SECRET_KEY 是弱值或过短（<32 字节）：仅可用于本机自用，"
            "对外提供服务前必须改成随机值，或直接删掉这一行让程序自生成")
    if "*" in CORS_ORIGINS:
        warns.append(
            "CORS_ORIGINS 含通配符 '*'：任何网页都能调用本服务（已强制关闭带凭证请求），"
            "请改为明确的来源白名单")
    if "marxism_pass" in DATABASE_URL or NEO4J_PASSWORD in {"marxism_pass", "neo4j", "password"}:
        warns.append(
            "数据库/Neo4j 使用默认弱口令：仅适合本机回环使用，"
            "docker-compose 已把端口绑定到 127.0.0.1，请勿改成 0.0.0.0")
    warns.append(
        "本服务所有 /api/* 路由均**不做身份校验**，user_id 由调用方自报："
        "只可部署在本机回环地址，不要直接暴露到公网")
    return warns
