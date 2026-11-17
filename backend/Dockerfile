# 后端 FastAPI — 正统马哲深度学习系统
# 构建上下文须为项目根（xxmz/），见 docker-compose 的 build.context
FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# 系统依赖：asyncpg 编译需要
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY backend/requirements.txt ./requirements.txt
RUN pip install -r requirements.txt

# backend/ 映射到 /app/backend（含 core/prompt/sanitizer.py，不再单独 COPY 根目录原型脚本）
COPY backend/ ./backend/

# 运行时数据（缺了会直接坏，别省这两行）：
#   * prompt_engineering.yaml —— PromptRenderer.__init__ 里直接 open()，缺了则每次 WS 连接
#     DialogueService() 都抛 FileNotFoundError（容器能起来，但一问就崩）。
#   * sources/texts/*.txt     —— content/book_chunks.py 只扫这个目录，缺了原文分片为 0，
#     RAG 检索、章节原文、题库溯源全部落空。
# 只带正文，不带 sources/_backup*（裁剪前备份，14MB，运行时不读）。
COPY prompt_engineering.yaml ./
COPY sources/texts/ ./sources/texts/

WORKDIR /app/backend

EXPOSE 8190

# 默认完整模式：连 docker-compose 内的 postgres/redis/neo4j
# 轻量模式（无 DB）：覆盖为 AUTO_CREATE_TABLES=0
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8190"]
