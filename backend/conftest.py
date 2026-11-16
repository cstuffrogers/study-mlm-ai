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
