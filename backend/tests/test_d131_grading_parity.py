"""D131 门禁：客观题选项归一化口径（单机版 `LocalQuiz.normChoice` 必须与这里一致）。

配套前端口径测试：`frontend/test/quiz_grading_parity_test.dart`。
两处任一改动，另一边必须同步，否则同一道题在联网版/单机版给出相反结论。
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from services.quiz_service import _norm_choice  # noqa: E402


def test_norm_choice_takes_first_char() -> None:
    for raw in ("A", "a", " A ", "A.", "A．", "A、", "A 因为生产关系"):
        assert _norm_choice(raw) == "A", raw
    assert _norm_choice("") == ""
    assert _norm_choice("   ") == ""
    assert _norm_choice("B") == "B"
    assert _norm_choice("d") == "D"
