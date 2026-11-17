"""SC-007 标记豁免测试（FR-006）

验证目标（spec SC-007：标记豁免 100% 生效 / 未标记 100% 拦截）：
  - debate 模式 + 偏离内容用【反方观点·仅供批判】...【/反方观点】包裹 → pass（豁免）
  - 非 debate 模式 + 同样包裹 → 仍 block（豁免只在辩难模式生效）
  - debate 模式 + 偏离内容 **未包裹** → block（未标记应拦截）
  - debate 模式 + 标记 **未闭合**（只有开/只有关）→ block（防绕过）

这是产品命门——豁免机制不能成为绕过立场校验的后门。
"""
from __future__ import annotations

import pytest

from core.guard.orthodoxy import (
    OrthodoxyGuard,
    EXEMPT_MARKER_OPEN,
    EXEMPT_MARKER_CLOSE,
)

# 一条典型的偏离文本（mutual_determination 命中）
DEVIATION_TEXT = "社会存在与社会意识是相互决定的，不存在谁决定谁。"


@pytest.fixture(scope="module")
def guard() -> OrthodoxyGuard:
    return OrthodoxyGuard()


class TestExemptMarkerEfficacy:
    """SC-007：标记豁免机制的四象限验证"""

    def test_exempt_in_debate_mode_passes(self, guard: OrthodoxyGuard) -> None:
        """SC-007 正向：debate 模式 + 完整豁免标记 → 放行（豁免 100% 生效）"""
        wrapped = f"{EXEMPT_MARKER_OPEN}{DEVIATION_TEXT}{EXEMPT_MARKER_CLOSE}"
        result = guard.check(wrapped, mode="debate")
        assert result["action"] == "pass", f"豁免标记未生效: flags={result['flags']}"
        assert result["exempt"] is True

    def test_exempt_in_non_debate_mode_blocks(self, guard: OrthodoxyGuard) -> None:
        """豁免仅在 debate 模式生效——非 debate 模式即使包裹仍 block"""
        wrapped = f"{EXEMPT_MARKER_OPEN}{DEVIATION_TEXT}{EXEMPT_MARKER_CLOSE}"
        result = guard.check(wrapped, mode="explain")
        assert result["action"] == "block", "非辩难模式不应豁免偏离内容"

    def test_unwrapped_in_debate_mode_blocks(self, guard: OrthodoxyGuard) -> None:
        """SC-007 反向：debate 模式但未加标记 → 必须拦截（未标记 100% 拦截）"""
        result = guard.check(DEVIATION_TEXT, mode="debate")
        assert result["action"] == "block", "辩难模式未标记的偏离内容未被拦截"

    def test_unclosed_marker_blocks(self, guard: OrthodoxyGuard) -> None:
        """防绕过：豁免标记未闭合（只有开标记）→ block，不降级为正常校验"""
        unclosed = f"{EXEMPT_MARKER_OPEN}{DEVIATION_TEXT}"  # 缺闭合标记
        result = guard.check(unclosed, mode="debate")
        assert result["action"] == "block", "未闭合的豁免标记未触发绕过拦截"
        assert any(f.get("type") == "unclosed_exempt_marker" for f in result["flags"])

    def test_only_close_marker_blocks(self, guard: OrthodoxyGuard) -> None:
        """防绕过：只有闭合标记（数量不平衡）→ block"""
        only_close = f"{DEVIATION_TEXT}{EXEMPT_MARKER_CLOSE}"
        result = guard.check(only_close, mode="debate")
        assert result["action"] == "block"

    def test_exemption_does_not_leak_across_segments(self, guard: OrthodoxyGuard) -> None:
        """豁免段之外的偏离内容仍被拦截——标记不能跨段保护"""
        text = (
            f"{EXEMPT_MARKER_OPEN}{DEVIATION_TEXT}{EXEMPT_MARKER_CLOSE}"
            f"另一段：意识决定物质，精神创造客观世界。"  # 这段不在豁免段内
        )
        result = guard.check(text, mode="debate")
        assert result["action"] == "block", "豁免标记段外的偏离内容未被拦截"


class TestUnclosedMarkerFallbackWording:
    """用户实报：单机版把「标记没闭合」报成「涉及与本课程立场不一致的框架」。

    标记未闭合是**格式**问题（模型漏写 `【/反方观点】`），内容往往完全合规；
    报成立场偏离会误导用户以为回答内容错了。后端 fallback 文案必须区分。
    """

    def test_marker_flag_gets_format_wording(self) -> None:
        from services.dialogue_service import _marker_fallback

        msg = _marker_fallback([{"type": "unclosed_exempt_marker", "reason": "x"}])
        assert "标记没有成对闭合" in msg
        assert "格式问题" in msg
        assert "立场" not in msg, "格式问题不能报成立场偏离"

    def test_stance_flag_keeps_default(self) -> None:
        from services.dialogue_service import _marker_fallback

        assert _marker_fallback([{"type": "deviation"}]) == ""
        assert _marker_fallback([]) == ""
        # detail 可能是字符串（ML 分类器分支），不能炸
        assert _marker_fallback("ML 分类为偏离（conf=0.91）") == ""  # type: ignore[arg-type]
