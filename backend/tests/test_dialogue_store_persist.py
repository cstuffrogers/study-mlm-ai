"""对话历史存储持久化测试 — 验证主库持久化 + 重启不丢。

用 SQLite 内存库模拟主库（仅建 dialogues/dialogue_messages/users 三表，
避开 text_chunks 的 pgvector 列），验证：
1. 写入对话后清空进程内缓存，从 DB 回填，数据完整
2. 对话完成计数在「重启」（清缓存）后不归零
3. seq 在重启后连续，不重复计数
"""
import pytest


@pytest.mark.asyncio
async def test_dialogue_store_persists_across_cache_clear():
    """写入对话 → 清缓存（模拟重启）→ 从 DB 回填 → 数据完整、计数不丢。"""
    import core.db as db_mod
    from core.db import Base
    from model.models import User, Dialogue, DialogueMessage  # noqa: F401
    from services import dialogue_store

    # ---- 用 SQLite 内存库模拟主库 ----
    from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
    from sqlalchemy.pool import StaticPool

    old_engine = db_mod._engine
    old_factory = db_mod._session_factory
    eng = create_async_engine(
        "sqlite+aiosqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
        future=True,
    )
    # 仅建对话域三表（users 供外键，避开 pgvector 的 text_chunks）
    async with eng.begin() as conn:
        await conn.run_sync(
            Base.metadata.create_all,
            tables=[User.__table__, Dialogue.__table__, DialogueMessage.__table__],
        )
    db_mod._engine = eng
    db_mod._session_factory = async_sessionmaker(
        eng, class_=db_mod.AsyncSession, expire_on_commit=False
    )

    # 启用 DB 模式（dialogue_store 动态读取 core.config.AUTO_CREATE_TABLES）
    import core.config
    old_atc = core.config.AUTO_CREATE_TABLES
    core.config.AUTO_CREATE_TABLES = True

    try:
        d_id = "dlg_persist_test"
        dialogue_store.clear()

        # 写入会话 + 用户提问 + AI 回复
        await dialogue_store.ensure_dialogue(
            d_id, user_id="demo_user", mode="explain", work="实践论")
        await dialogue_store.append_message(d_id, "user", "什么是实践？")
        await dialogue_store.append_message(
            d_id, "assistant", "实践是认识的基础。", source_chunks=["CH-1"])

        # 模拟重启：清空进程内缓存
        dialogue_store.clear()

        # 从 DB 回填
        lst = await dialogue_store.list_dialogues("demo_user")
        assert any(d["id"] == d_id for d in lst), "重启后会话应从 DB 回填"

        msgs = await dialogue_store.get_messages(d_id)
        assert len(msgs) == 2, f"重启后应有 2 条消息，实际 {len(msgs)}"
        assert msgs[0]["content"] == "什么是实践？"
        assert msgs[1]["content"] == "实践是认识的基础。"
        assert msgs[1]["source_chunks"] == ["CH-1"]

        # 对话完成计数不归零
        from services.badge_service import _dialogues_completed
        n = await _dialogues_completed("demo_user")
        assert n >= 1, f"重启后对话完成计数应 >=1，实际 {n}"

        # 重启后追加消息，seq 连续（不从 1 开始，避免重复计数）
        await dialogue_store.append_message(d_id, "user", "再解释一下？")
        msgs2 = await dialogue_store.get_messages(d_id, limit=50)
        assert len(msgs2) == 3, f"追加后应有 3 条消息，实际 {len(msgs2)}"
        assert msgs2[2]["seq"] == 3, f"第三条 seq 应为 3，实际 {msgs2[2]['seq']}"

    finally:
        # 恢复
        db_mod._engine = old_engine
        db_mod._session_factory = old_factory
        core.config.AUTO_CREATE_TABLES = old_atc
        dialogue_store.clear()
        await eng.dispose()


@pytest.mark.asyncio
async def test_dialogue_store_memory_fallback_when_db_disabled():
    """AUTO_CREATE_TABLES=0 时降级纯内存：不碰 DB，数据在进程内可用。"""
    import core.config
    from services import dialogue_store

    old_atc = core.config.AUTO_CREATE_TABLES
    core.config.AUTO_CREATE_TABLES = False
    try:
        dialogue_store.clear()
        d_id = "dlg_mem_test"
        await dialogue_store.ensure_dialogue(d_id, user_id="demo_user", mode="explain")
        await dialogue_store.append_message(d_id, "user", "测试内存降级")
        await dialogue_store.append_message(d_id, "assistant", "内存降级可用。")

        lst = await dialogue_store.list_dialogues("demo_user")
        assert any(d["id"] == d_id for d in lst)
        msgs = await dialogue_store.get_messages(d_id)
        assert len(msgs) == 2
    finally:
        core.config.AUTO_CREATE_TABLES = old_atc
        dialogue_store.clear()
