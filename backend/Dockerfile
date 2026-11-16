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

# backend/ 映射到 /app/backend，根目录 prompt_sanitizer.py 映射到 /app
COPY backend/ ./backend/
COPY prompt_sanitizer.py ./

WORKDIR /app/backend

EXPOSE 8190

# 默认完整模式：连 docker-compose 内的 postgres/redis/neo4j
# 轻量模式（无 DB）：覆盖为 AUTO_CREATE_TABLES=0
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8190"]
