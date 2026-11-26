# -*- coding: utf-8 -*-
"""D171 门禁：整体立场判读（不能只靠关键词就拦）。

为什么要有这组门禁——真实体检结论
----------------------------------
旧实现「命中即拦」，只要回答里出现批判对象术语（物化/总体性/历史决定论…）
或偏离句式，就整段 block。实测：

  · 常规马哲规范回答 12 条 → 0/12 拦（OK）
  · 项目自带章节导读 140 段 → 0/140 拦（OK）
  · **涉及批判对象术语的教学式回答 8 条 → 7/8 被拦**（严重误杀）
  · **真正的偏离断言 7 条 → 0/7 拦**（严重漏拦）
  · 单机版把输出侧规则拿去审**用户提问** → 13 条里 4 条被拒答

用户的原话是「不能只靠关键词就拦截了，应该是整体的回答符不符合马列毛思想。
要是指出反面例子，不就被拦截了？」——这一条就是本门禁的正题：
**引述 / 反驳 / 举例 / 中性教学使用 ≠ 作者自己在主张偏离**。

三档判定（`core/guard/orthodoxy.py:_assess_occurrence`）
-----------------------------------------------------
    citation  引号内、带引述框架、同句有转折纠偏词、或（输入侧）用户在提问
    deviation 作者自己的结论句（唯一会触发拦截的一类）
    neutral   批判对象术语的定义/比较/教学式使用 → 标注，不拦
"""
from __future__ import annotations

import pytest

from core.guard.orthodoxy import OrthodoxyGuard

# --------------------------------------------------------------------------
# 正例：必须放行（含「指出反面例子」「引述后反驳」「术语中性使用」）
# --------------------------------------------------------------------------
MUST_PASS = [
    # 批判性引用批判对象术语（旧实现在这里 7/8 误杀）
    "卢卡奇的物化概念是错误的，它把商品拜物教等同于异化。",
    "伯恩斯坦的和平长入社会主义是修正主义谬误，必须批判。",
    "葛兰西的文化领导权理论偏离了无产阶级专政，是错误路线。",
    "阿尔都塞的多元决定论歪曲了经济基础决定上层建筑的原理。",
    "哈贝马斯的生活世界概念是现象学残余，不符合唯物史观。",
    "德勒兹的延异无非是把差异绝对化，和唯物辩证法相对立。",
    "利奥塔的宏大叙事终结论本身就是一种唯心主义叙事，不能照搬。",
    "波普尔所谓「历史决定论」是对马克思的曲解，马克思讲的是历史规律。",
    # 术语的中性/教学式使用（定义、比较、读法指导）
    "物化劳动指凝结在产品中的劳动，活劳动指正在进行的劳动。",
    "从总体性上把握这一节，就是说不要把某一句孤立起来读。",
    "物化劳动和活劳动的区别，是理解剩余价值来源的入口。",
    "这里说的「物化」是马克思的原义（人受自己产品的支配），不是卢卡奇的异化。",
    # 引述 + 反驳（学生提问式、教材式）
    "有人说经济基础与上层建筑相互决定，这种说法错在哪里？",
    "「阶级斗争已经过时」是资产阶级的论调，必须驳斥。",
    "错误观点认为意识决定物质，我们要用实践论把它顶回去。",
    "历史决定论（把历史看成宿命）不是马克思的观点。",
    "多元决定论属于后马克思主义，和唯物史观不是一回事。",
    "文化决定论是唯心史观，不能用来解释社会形态更替。",
    "至于「运动就是一切」，那是伯恩斯坦的口号，我们恰恰要反对。",
    # 正统表述（不能被补登记的新规则误伤）
    "按毛泽东的说法，两类矛盾性质不同，解决的方法也不同。",
    "群众路线是一切为了群众，一切依靠群众，从群众中来，到群众中去。",
    "独立自主、自力更生是我们的立足点，同时要学习外国先进经验。",
    "剩余价值不存在于流通领域，它产生于生产过程。",
    "资本主义不是历史的终点，两个必然仍然是我们的结论。",
    "经济不是唯一决定性的因素，但归根到底还是经济决定历史。",
    "机械反映论是错误的，马克思主义的反映论是能动的革命的反映论。",
    "文化不能决定社会的发展方向，是社会存在决定社会意识。",
    "党的领导是社会主义事业的核心，不能否定。",
    "阶级斗争是阶级社会发展的直接动力，不是话术。",
    "马克思主义不是众多「宏大叙事」中的一种，它是科学的世界观。",
]

# --------------------------------------------------------------------------
# 负例：作者自己的偏离断言，必须拦（≥90%）
# --------------------------------------------------------------------------
MUST_BLOCK = [
    "经济基础与上层建筑相互决定。",
    "意识决定物质，精神创造客观世界。",
    "阶级斗争已经过时了。",
    "文化决定社会的发展方向。",
    "技术决定社会形态的更替。",
    "地理环境决定社会制度的性质。",
    "剩余价值并不存在，利润来自企业家的才能。",
    "阶级斗争只是话术，现实里早已消失。",
    "资本主义是历史的终点，不会灭亡。",
    "卢卡奇的物化理论揭示了资本主义异化的本质。",
    "阿尔都塞的多元决定概念丰富了马克思主义。",
    "葛兰西的文化领导权理论超越了无产阶级专政的局限。",
    "哈贝马斯的生活世界理论为马克思主义提供了新基础。",
    "伯恩斯坦主张和平长入社会主义是合理的。",
    "运动就是一切，最终目的是微不足道的。",
    "利奥塔指出宏大叙事已经终结，马克思主义也只是一套宏大叙事。",
    "话语建构塑造了社会现实，超越经济决定论。",
    "德勒兹的延异概念解构了唯物辩证法的同一性。",
    "新教伦理解释了资本主义的起源。",
    "总体性是把握社会整体的根本方法。",
    "物化等同于异化，是资本主义的核心病症。",
    "文化领导权比暴力革命更重要，应放弃专政。",
    "认识论断裂表明早期马克思与晚期马克思根本对立。",
    "马克思主义只是众多宏大叙事中的一种。",
    "阶级是话语建构的产物，是想象的共同体。",
    "反映论是机械的，认识不是对客观的反映。",
    "自然辩证法不存在，辩证法只存在于主体与客体的关系中。",
    "计划经济是通往奴役之路。",
    "马克思的劳动价值论已经过时，知识经济超越了它。",
]

# --------------------------------------------------------------------------
# 输入侧：用户在**提问**里引用一种错误说法，不是用户自己在主张
# （旧单机版拿输出侧规则审提问，13 条里 4 条被拒答）
# --------------------------------------------------------------------------
USER_QUESTIONS = [
    "为什么说「阶级斗争已经过时」这种说法是错的？",
    "阶级斗争已经过时的论调错在哪里？",
    "卢卡奇的物化理论讲了什么？我要写作业。",
    "从总体性上把握这一段，应该怎么读？",
    "物化劳动和活劳动的区别是什么？",
    "意识决定物质这句话错在哪里？",
    "有老师说历史决定论是错的，可我读着马克思像是这个意思？",
    "文化领导权和文化自信是一回事吗？",
    "伯恩斯坦的和平长入社会主义为什么是修正主义？",
    "无产阶级专政和人民民主专政有区别吗？",
    "剩余价值是怎么被资本家拿走的？",
]


@pytest.fixture(scope="module")
def guard() -> OrthodoxyGuard:
    return OrthodoxyGuard()


@pytest.mark.parametrize("text", MUST_PASS)
def test_positive_not_blocked(guard: OrthodoxyGuard, text: str) -> None:
    """正例（含指出反面例子）必须 100% 放行——误杀是用户最直接的痛点。"""
    r = guard.check(text, mode="explain")
    assert r["action"] == "pass", (
        f"正确的批判性表述被拦截: {text!r} | "
        f"{[(f.get('type'), f.get('rule'), f.get('term')) for f in r['flags']]}"
    )


def test_negative_block_rate(guard: OrthodoxyGuard) -> None:
    """负例（作者自述的偏离断言）拦截率 ≥90%。"""
    blocked = [t for t in MUST_BLOCK
               if guard.check(t, mode="explain")["action"] == "block"]
    missed = [t for t in MUST_BLOCK if t not in blocked]
    rate = len(blocked) / len(MUST_BLOCK)
    assert rate >= 0.90, f"偏离断言拦截率不足: {rate:.1%}，漏拦: {missed}"


@pytest.mark.parametrize("text", MUST_BLOCK)
def test_single_negative_blocked(guard: OrthodoxyGuard, text: str) -> None:
    assert guard.check(text, mode="explain")["action"] == "block", text


@pytest.mark.parametrize("text", USER_QUESTIONS)
def test_user_question_is_not_stance(guard: OrthodoxyGuard, text: str) -> None:
    """输入侧：提问里引用错误说法不得被当成「用户在宣扬」，必须放行。"""
    r = guard.check(text, mode="input")
    assert r["action"] == "pass", f"用户提问被拒答: {text!r} | {r['flags']}"


def test_input_shorthand_still_blocks_bare_assertion(guard: OrthodoxyGuard) -> None:
    """输入侧放宽只针对**提问/引述**，直陈式表态仍要拦。"""
    r = guard.check("经济基础与上层建筑相互决定。", mode="input")
    assert r["action"] == "block"


def test_neutral_term_is_annotation_not_block(guard: OrthodoxyGuard) -> None:
    """术语中性使用 → 标注（annotate），不是 block，也不能当没看见。"""
    r = guard.check("物化劳动指凝结在产品中的劳动。")
    assert r["action"] == "pass"
    types = [f.get("type") for f in r["flags"]]
    assert "critical_object_unwrapped" in types
    assert r["annotations"], "标注必须回传，UI 要据此提示「立场待核」"


def test_hard_redline_single_term_no_longer_blocks(guard: OrthodoxyGuard) -> None:
    """D171 回归：一个「物化」不再能整段拦掉回答。"""
    text = "我来解释这一节：卢卡奇的物化讲的是商品关系变成物与物的关系。"
    assert guard.check(text)["action"] == "pass"


def test_quote_framed_deviation_is_citation(guard: OrthodoxyGuard) -> None:
    wrapped = "有人说「经济基础与上层建筑相互决定」，这是错误的。"
    r = guard.check(wrapped)
    assert r["action"] == "pass"
    assert any(f.get("label") == "citation" for f in r["flags"])


def test_cross_clause_still_blocks(guard: OrthodoxyGuard) -> None:
    """前句批判、后句裸断言 → 仍拦（语境不跨句串味）。"""
    r = guard.check("阶级斗争已经过时的错误论调，应当批判。但是意识决定物质。")
    assert r["action"] == "block"


# --------------------------------------------------------------------------
# 判定器（core/guard/judge.py）：只对疑点调用，失败只标注
# --------------------------------------------------------------------------
import asyncio  # noqa: E402

from core.guard.judge import StanceJudge  # noqa: E402


def _run(coro):
    return asyncio.run(coro)


def test_judge_flags_holistic_deviation() -> None:
    async def fake(prompt: str) -> str:
        return '{"verdict": "deviation", "claims": [{"quote": "文化决定社会", ' \
               '"role": "assertion", "conflicts_with": "社会存在决定社会意识"}], ' \
               '"reason": "把文化当作社会发展决定因素"}'

    judge = StanceJudge(generator=fake)
    r = _run(judge.judge("文化决定社会的发展方向。", [{"term": "文化决定论"}]))
    assert r["verdict"] == "deviation"
    assert r["available"] is True
    assert r["claims"][0]["role"] == "assertion"


def test_judge_passes_quoted_example() -> None:
    async def fake(prompt: str) -> str:
        assert "有人说" in prompt or "引述" in prompt  # 口径必须进 prompt
        return '{"verdict": "citation", "claims": [], "reason": "整段是引述后反驳"}'

    judge = StanceJudge(generator=fake)
    r = _run(judge.judge("有人说「阶级斗争已经过时」，这是错的。", [{"rule": "x"}]))
    assert r["verdict"] == "citation"


def test_judge_unavailable_never_blocks() -> None:
    """模型挂了/返回垃圾 → unavailable，调用方据此「标注不拦」。"""
    async def boom(prompt: str) -> str:
        raise RuntimeError("connection refused")

    async def garbage(prompt: str) -> str:
        return "我觉得这段还行吧。"

    assert _run(StanceJudge(generator=boom).judge("文本"))["verdict"] == "unavailable"
    assert _run(StanceJudge(generator=garbage).judge("文本"))["verdict"] == "unavailable"


def test_judge_caches_and_circuit_breaks() -> None:
    calls = {"n": 0}

    async def counting(prompt: str) -> str:
        calls["n"] += 1
        return '{"verdict": "orthodox", "claims": [], "reason": "ok"}'

    judge = StanceJudge(generator=counting)
    _run(judge.judge("同一段文本"))
    _run(judge.judge("同一段文本"))
    assert calls["n"] == 1, "同文必须命中缓存（避免每次对话都花一次调用）"

    async def boom(prompt: str) -> str:
        raise RuntimeError("down")

    j2 = StanceJudge(generator=boom, breaker_threshold=2)
    _run(j2.judge("a"))
    _run(j2.judge("b"))
    assert not j2.enabled, "连续失败后必须熔断，否则每次对话都白等一次超时"


def test_judge_disabled_by_env(monkeypatch) -> None:
    monkeypatch.setenv("STANCE_JUDGE", "0")
    judge = StanceJudge(generator=lambda p: None)  # 不会走到生成
    assert _run(judge.judge("文本"))["verdict"] == "unavailable"
