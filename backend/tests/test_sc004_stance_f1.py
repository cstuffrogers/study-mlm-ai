"""SC-004 立场分类 F1 测试（规则版，BERT 接口位）

验证目标（spec SC-004：立场分类器 F1）：
  - 规则版 OrthodoxyGuard 当作立场二分类器（orthodox / deviation）
  - 用全部 53 样本（正/负/困难负）计算 precision / recall / F1
  - 困难负样本（hard_negative）专项验证 P0-2 修复：批判性引用西马概念的正统文本应 pass

注：spec SC-004 生产目标 F1 由 BERT 分类器达成（需标注数据，Phase 6 后续）。
本测试给规则版基线 F1，BERT 训练完成后注入 stance_classifier 即可对比提升。
"""
from __future__ import annotations

import pytest

from core.guard.orthodoxy import OrthodoxyGuard
from tests.deviation_dataset import (
    ORTHODOX_SAMPLES,
    DEVIATION_SAMPLES,
    HARD_NEGATIVE_SAMPLES,
)

# 正类 = deviation（应被 block）；负类 = orthodox（应 pass）
# 规则版 P/R/F1 用全部样本——bert_only 困难样本的漏判会反映在 recall 里，是 BERT 的提升空间
POS = DEVIATION_SAMPLES  # label=deviation
NEG = ORTHODOX_SAMPLES + HARD_NEGATIVE_SAMPLES  # label=orthodox


@pytest.fixture(scope="module")
def guard() -> OrthodoxyGuard:
    return OrthodoxyGuard()


def _predict(guard: OrthodoxyGuard, text: str) -> str:
    """规则版二分类：block→deviation，pass→orthodox"""
    return "deviation" if guard.check(text, mode="explain")["action"] == "block" else "orthodox"


def _prf(tp: int, fp: int, fn: int) -> tuple[float, float, float]:
    p = tp / (tp + fp) if (tp + fp) else 0.0
    r = tp / (tp + fn) if (tp + fn) else 0.0
    f1 = 2 * p * r / (p + r) if (p + r) else 0.0
    return p, r, f1


class TestStanceF1:
    """SC-004：规则版立场二分类的 P/R/F1"""

    def test_f1_baseline(self, guard: OrthodoxyGuard) -> None:
        tp = sum(1 for s in POS if _predict(guard, s["text"]) == "deviation")
        fp = sum(1 for s in NEG if _predict(guard, s["text"]) == "deviation")
        fn = sum(1 for s in POS if _predict(guard, s["text"]) == "orthodox")
        p, r, f1 = _prf(tp, fp, fn)
        # 规则版基线门槛：F1 ≥ 0.85（含 bert_only 困难样本的漏判，留 BERT 提升空间）
        assert f1 >= 0.85, (
            f"规则版立场 F1={f1:.3f}（P={p:.3f} R={r:.3f} tp={tp} fp={fp} fn={fn}）未达 0.85 基线"
        )

    def test_precision_no_false_positive(self, guard: OrthodoxyGuard) -> None:
        """误报（正统被判 deviation）——规则版有 hard_negative 的已知漏判（无批判词句式），
        接受 ≤2 条误报作为基线，BERT 训练后应收敛到 0。"""
        fps = [s["text"] for s in NEG if _predict(guard, s["text"]) == "deviation"]
        assert len(fps) <= 2, f"正统样本误判超过 2 条（BERT 待收敛）: {fps}"


# 无显式批判词、规则版无法放行的困难负样本（BERT 专属）
_HN_BERT_ONLY_TEXTS = {
    "韦伯的新教伦理是文化决定论，无法解释资本主义的全球扩张。",
    "哈贝马斯的生活世界概念是现象学残余，不符合唯物史观。",
}


def _hn_expect(sample: dict):
    """困难负样本：含 BERT 专属句式 → xfail（规则版已知误杀），否则应 pass"""
    if sample["text"] in _HN_BERT_ONLY_TEXTS:
        return pytest.xfail("规则版无法判定隐式批判（文化决定论/现象学残余），BERT 专属")
    return None


class TestHardNegativeP02:
    """P0-2 修复验证：批判性引用西马概念的正统文本应 pass（不误杀）

    规则版通过 _has_critical_context（批判语境词放行）处理 6/8 困难负样本。
    2 条无显式批判词的句式（'是文化决定论''不符合唯物史观'）规则版仍误杀，
    xfail 标记为 BERT 专属，待 Phase 6 BERT 训练后转 pass。
    """

    @pytest.mark.parametrize("sample", HARD_NEGATIVE_SAMPLES, ids=lambda s: s["text"][:24])
    def test_critical_citation_passes(self, guard: OrthodoxyGuard, sample: dict) -> None:
        _hn_expect(sample)  # BERT 专属样本 xfail
        result = guard.check(sample["text"], mode="explain")
        assert result["action"] == "pass", (
            f"批判性引用被误杀（P0-2）: {sample['text']!r} | flags={result['flags']}"
        )

    def test_hard_negative_pass_rate(self, guard: OrthodoxyGuard) -> None:
        passed = sum(
            1 for s in HARD_NEGATIVE_SAMPLES
            if _predict(guard, s["text"]) == "orthodox"
        )
        rate = passed / len(HARD_NEGATIVE_SAMPLES)
        # 规则版基线 6/8=75%，BERT 注入后应达 100%
        assert rate >= 0.75, f"困难负样本放行率 {rate:.1%}（{passed}/{len(HARD_NEGATIVE_SAMPLES)}），规则版基线应 ≥75%"


# ============================================================
# ML 立场分类器验证 — 解除规则版 4 条 xfailed
# ============================================================
# 规则版无法判定的 4 类语义方向样本（type-A 批判对象攻击正统 / type-B 隐式批判）
# ML 分类器（logreg + confidence 阈值）注入 TripleCheck 后应全部正确
ML_XFAILED_SAMPLES = [
    {"text": "鲍德里亚的生产之镜批判了马克思的劳动价值论。", "label": "deviation", "was_xfail": True},
    {"text": "波普尔证明历史决定论是错误的。", "label": "deviation", "was_xfail": True},
    {"text": "韦伯的新教伦理是文化决定论，无法解释资本主义的全球扩张。", "label": "orthodox", "was_xfail": True},
    {"text": "哈贝马斯的生活世界概念是现象学残余，不符合唯物史观。", "label": "orthodox", "was_xfail": True},
]


def _ml_available() -> bool:
    """ML 模型是否已训练（未训练时跳过 ML 测试，不阻塞规则版基线）"""
    try:
        from ml.train_stance import StanceClassifier, MODEL_PATH
        import os
        return os.path.exists(MODEL_PATH)
    except Exception:
        return False


@pytest.fixture(scope="module")
def triple_check_ml():
    """TripleCheck + ML 分类器（模型缺失时 skip）"""
    if not _ml_available():
        pytest.skip("ML 立场分类器未训练（运行 python -m ml.train_stance）")
    from core.verify.triple_check import TripleCheck
    from core.guard.orthodoxy import OrthodoxyGuard
    from ml.train_stance import StanceClassifier
    return TripleCheck(guard=OrthodoxyGuard(), stance_classifier=StanceClassifier())


class TestMLStanceResolvesXfailed:
    """ML 立场分类器解除规则版 4 条 xfailed 的语义方向误判

    规则版 OrthodoxyGuard 对这 4 条 0/4 正确（4 类语义方向无法靠正则判定）；
    ML（logreg + confidence ≥0.6 覆盖，低置信回退规则）应 4/4 正确。
    """

    @pytest.mark.parametrize("sample", ML_XFAILED_SAMPLES, ids=lambda s: s["text"][:20])
    def test_ml_resolves_semantic_direction(self, triple_check_ml, sample: dict) -> None:
        """4 条 xfailed 经 TripleCheck(ML) 应全部正确判定"""
        want = "block" if sample["label"] == "deviation" else "pass"
        r = triple_check_ml.check(sample["text"], mode="explain", allow_critical=False)
        assert r["action"] == want, (
            f"ML 未解除 xfailed: {sample['text']!r} | 期望 {want} | 实际 {r['action']} | "
            f"source={r['stance']['source']} | detail={r['stance'].get('detail')}"
        )

    def test_ml_no_false_block_on_neutral(self, triple_check_ml) -> None:
        """ML 不应误伤中性/系统占位文本（低置信回退规则 = pass）"""
        neutral = "【Mock LLM】真实国产模型未配置（缺 LLM_API_KEY）。收到 prompt 末尾: …请解释实践概念"
        r = triple_check_ml.check(neutral, mode="explain", allow_critical=False)
        assert r["action"] == "pass", f"中性文本被 ML 误判 block: {r['stance']}"

    def test_ml_source_used_for_high_confidence(self, triple_check_ml) -> None:
        """高置信样本应走 ml source（非 ml_low_conf_rule）"""
        # type-A 高置信 deviation
        r = triple_check_ml.check(
            "鲍德里亚的生产之镜批判了马克思的劳动价值论。", mode="explain"
        )
        assert r["stance"]["source"] == "ml", f"高置信样本应走 ml，实际 {r['stance']['source']}"


class TestCriticalContextBoundaries:
    """「自指批判语境」豁免的边界（P0-2 延伸修复）

    背景：修复「用户明明在批判错误观点却被拦截」时引入了两个新风险，
    这里把两条线都钉死，避免以后放宽过头。
    """

    def test_marker_literal_is_not_critical_context(self, guard: OrthodoxyGuard) -> None:
        """标记字面内含「批判」二字，不得充当批判语境证据

        「【反方观点·仅供批判】<裸断言>【/反方观点】」在 **非辩难模式** 下本来
        应该被拦截（豁免只在 debate 生效）；如果标记里的「批判」被当成语境词，
        用户只要写个标记就能让裸断言直接过——等于开了一个免费后门。
        """
        from core.guard.orthodoxy import EXEMPT_MARKER_OPEN, EXEMPT_MARKER_CLOSE

        wrapped = f"{EXEMPT_MARKER_OPEN}社会存在与社会意识是相互决定的，不存在谁决定谁。{EXEMPT_MARKER_CLOSE}"
        result = guard.check(wrapped, mode="explain")
        assert result["action"] == "block", (
            f"标记字面被当成批判语境，裸断言被豁免: flags={result['flags']}"
        )

    def test_same_clause_critical_passes(self, guard: OrthodoxyGuard) -> None:
        """同句内有批判语境词 → 放行（这是本次修复的正题）"""
        for text in (
            "阶级斗争已经过时的错误论调，应当批判。",
            "有人主张经济基础不是唯一决定因素，这种观点是错误的。",
            "意识决定物质的说法属于唯心主义谬误，必须批判。",
        ):
            r = guard.check(text, mode="explain")
            assert r["action"] == "pass", f"正确的批判性表述被误杀: {text!r} | {r['flags']}"

    def test_bare_assertion_still_blocks(self, guard: OrthodoxyGuard) -> None:
        """无批判语境的裸断言仍必须拦截（不能因为修复而放过真偏离）"""
        for text in (
            "阶级斗争已经过时了。",
            "经济基础不是唯一决定因素。",
        ):
            r = guard.check(text, mode="explain")
            assert r["action"] == "block", f"裸断言未被拦截: {text!r} | {r['flags']}"

    def test_no_cross_clause_bleed(self, guard: OrthodoxyGuard) -> None:
        """前句批判、后句裸断言 → 仍拦截（语境不跨句串味）"""
        text = "阶级斗争已经过时的错误论调，应当批判。但是意识决定物质。"
        r = guard.check(text, mode="explain")
        assert r["action"] == "block", f"跨句串味导致偏离被豁免: flags={r['flags']}"
