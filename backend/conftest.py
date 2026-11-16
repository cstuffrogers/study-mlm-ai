"""pytest 配置 — 把 backend/ 加入 sys.path，使 `from core...` / `from content...` 可导入。

也把项目根目录加入 sys.path（dialogue_service 复用根目录的 prompt_sanitizer.py）。
"""
import os
import sys

_BACKEND = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(_BACKEND)

for p in (_BACKEND, _ROOT):
    if p not in sys.path:
        sys.path.insert(0, p)


# ---------------------------------------------------------------------------
# 进程退出收尾：把测试期创建的内存库（aiosqlite）引擎 dispose 掉。
#
# 不处理会怎样：内存库用 StaticPool + aiosqlite，连接会起一个**非守护** worker
# 线程；pytest 跑完全部用例后，解释器退出时 threading._shutdown 死等这个线程
# → 命令行看起来「卡死」（实际用例早已全部通过）。在 session 结束时 dispose
# 引擎即可让连接关闭、worker 线程退出。
# ---------------------------------------------------------------------------
def pytest_sessionfinish(session, exitstatus):  # noqa: ARG001
    try:
        from core import db_learning
        db_learning.reset_learning_engine()
    except Exception:
        pass


# ---------------------------------------------------------------------------
# 「需要原著正文」的用例。正文**默认随仓库分发**（见 CONTENT-NOTICE.md），
# 所以正常 clone 下来是全量照跑；但有人可能只取代码、或删掉正文跑纯后端，
# 那时这 28 个文件会一次红 278 个，看起来像项目坏了 —— 实际是数据缺失。
# 因此仍保留这道守卫：sources/texts/ 无 .txt 时统一 skip 并给出补齐指路。
#
# 有正文时行为不变（全量照跑），因此不会掩盖真问题。
# ---------------------------------------------------------------------------
def _has_source_texts() -> bool:
    texts = os.path.join(_ROOT, "sources", "texts")
    return os.path.isdir(texts) and any(
        f.endswith(".txt") for f in os.listdir(texts)
    )


def pytest_configure(config):
    config.addinivalue_line(
        "markers",
        "needs_texts: 依赖 sources/texts/ 原著正文的用例（无正文时自动跳过）",
    )


def pytest_collection_modifyitems(config, items):
    if _has_source_texts():
        return
    import pytest

    marker = pytest.mark.skip(
        reason="未发现原著正文（sources/texts/ 为空）："
        "补齐方式见 README「原著正文数据」一节"
    )
    for item in items:
        if "needs_texts" in item.keywords:
            item.add_marker(marker)
