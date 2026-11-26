"""语义立场判定器（D171）——规则只负责「召回疑点」，整体是否站得住由它下结论。

为什么必须有这一层
------------------
`orthodoxy.py` 的规则是**字串/句式**匹配，判不出「这句话到底是谁在主张」。
两种在字面上完全相同的句子，立场恰恰相反：

    卢卡奇的物化概念是错误的，它把商品拜物教等同于异化。   ← 正确的批判
    卢卡奇的物化理论揭示了资本主义异化的本质。             ← 宣扬

规则层只能靠「同句有没有『错误』这个字」来区分，于是：
  · 用户问「『阶级斗争已经过时』这种说法错在哪？」→ 缺一个「错误」就被拒答；
  · 回答里举反面例子 → 缺一个机器标记就被整段拦截。
D171 把规则降级为「召回 + 标注」，把**整体结论**交给判定器：它读整段回答，
逐条抽出「作者自己的主张」（排除引述、反驳、举例、假定），再判这些主张
是否违背马列毛基本原理。

设计约束（很关键）
------------------
1. **只判疑点**：只有当规则层出了 annotations（有可疑字串但不是明确偏离）时才调用，
   正常回答不付这次调用成本。
2. **失败不拦人**：未配置模型 / 超时 / 返回不可解析 → 降级为 ``annotate``
   （回答照常展示 + 标注待核）。判定器不可用绝不能变成「什么都拦」。
3. **可测试**：模型调用通过 ``generator`` 注入，单测用假模型，不需要真实网络。
4. **熔断**：连续失败 3 次后 300 秒内不再尝试（避免每次对话都白等一次超时）。
"""
from __future__ import annotations

import hashlib
import json
import logging
import os
import re
import time
from typing import Any, Awaitable, Callable, Optional

logger = logging.getLogger(__name__)

# 判定器输出必须是这个结构；解析失败一律视为不可用（→ annotate），
# 绝不把「解析不出来」当成「偏离」。
_JUDGE_SCHEMA_HINT = """{
  "verdict": "orthodox | citation | deviation",
  "claims": [
    {"quote": "原文片段（<=40 字）", "role": "assertion | quotation | rebuttal | example",
     "conflicts_with": "若与马列毛基本原理冲突，写冲突点；否则空字符串"}
  ],
  "reason": "一句话说明结论依据"
}"""

_JUDGE_PROMPT = """你是马克思主义理论课的立场审读员。请判断下面这段**回答**整体上是否站在马列毛立场。

判读口径（按顺序执行，不要跳步）：
1. 先把文本拆成句子，逐句标出说话人：是作者**自己在主张**（assertion），还是
   **引述/复述别人的说法**（quotation，如「有人说…」「伯恩斯坦主张…」「所谓…」），
   还是**反驳/纠偏**（rebuttal，如「这种说法是错的」「其实不然」「恰恰相反」），
   还是**举例/假定**（example，如「假设你是一个19世纪工人」「以韦伯为例」）。
2. 只有 role=assertion 的句子进入立场判断。引述、反驳、举例中的错误观点
   **是教学材料，不是立场偏离**，必须放行。
3. 对每条 assertion，检查是否与下列基本原理冲突（冲突才算 deviation）：
   · 物质第一性、意识第二性；社会存在决定社会意识
   · 经济基础决定上层建筑（上层建筑有反作用，但归根到底是前者决定后者）
   · 实践是认识的基础和检验真理的唯一标准；反映论是能动的革命的反映论
   · 劳动价值论与剩余价值理论；资本主义必然灭亡、两个必然
   · 阶级斗争是阶级社会发展的直接动力；无产阶级专政；党的领导
   · 人民群众是历史的创造者；群众路线；独立自主、自力更生
   · 两类不同性质矛盾的区分（敌我矛盾 / 人民内部矛盾）
4. 若全文都是引述+反驳，或只是对错误观点的**介绍与批判**，判 citation。
5. 只要有一条 assertion 实质性否定上述原理，判 deviation，并在 claims 里指出是哪一条。

回答（记住：只输出 JSON，不要解释文字，不要代码块）：
{schema}

待审文本：
<<<
{text}
>>>

规则层召回的疑点（供参考，可能是误报，最终以你的整段判断为准）：
{annotations}
"""

_JSON_RE = re.compile(r"\{.*\}", re.DOTALL)


class StanceJudge:
    """整体立场判定器（LLM 版）。

    用法::

        judge = StanceJudge()                       # 默认走 LLMRouter
        judge = StanceJudge(generator=fake)         # 单测注入假模型
        result = await judge.judge(text, annotations=[...])
        result["verdict"]  # orthodox | citation | deviation | unavailable
    """

    def __init__(
        self,
        generator: Optional[Callable[[str], Awaitable[str]]] = None,
        *,
        enabled: Optional[bool] = None,
        max_chars: int = 4000,
        cache_size: int = 256,
        breaker_threshold: int = 3,
        breaker_seconds: float = 300.0,
    ) -> None:
        self._generator = generator
        self._enabled_override = enabled
        self.max_chars = max_chars
        self._cache: dict[str, dict] = {}
        self._cache_size = cache_size
        self._fails = 0
        self._open_until = 0.0
        self._breaker_threshold = breaker_threshold
        self._breaker_seconds = breaker_seconds

    # ---------------- 可用性 ----------------
    @property
    def enabled(self) -> bool:
        if self._enabled_override is not None:
            return self._enabled_override
        if os.getenv("STANCE_JUDGE", "1").strip() in ("0", "false", "False", "off"):
            return False
        return time.time() >= self._open_until

    @staticmethod
    def _key(text: str) -> str:
        return hashlib.sha256(text.encode("utf-8")).hexdigest()[:32]

    def _default_generator(self) -> Callable[[str], Awaitable[str]]:
        if self._generator is not None:
            return self._generator

        async def _run(prompt: str) -> str:
            from core.llm.router import LLMRouter

            router = getattr(self, "_router", None)
            if router is None:
                router = LLMRouter()
                self._router = router
            resp = await router.generate(prompt, task="verify", complexity=0.3,
                                         interactive=True)
            return getattr(resp, "text", "") or ""

        return _run

    # ---------------- 主入口 ----------------
    async def judge(self, text: str, annotations: Optional[list] = None,
                    *, mode: str = "explain") -> dict[str, Any]:
        """返回 {verdict, claims, reason, source, available}。

        verdict: orthodox | citation | deviation | unavailable
        任何异常路径都返回 unavailable —— 调用方据此「标注而不拦截」。
        """
        text = (text or "").strip()
        if not text:
            return {"verdict": "unavailable", "reason": "空文本", "available": False,
                    "claims": [], "source": "judge"}
        key = self._key(text)
        if (hit := self._cache.get(key)) is not None:
            return {**hit, "cached": True}
        if not self.enabled:
            return {"verdict": "unavailable", "reason": "判定器未启用或熔断中",
                    "available": False, "claims": [], "source": "judge"}

        note = "；".join(
            f"{a.get('term') or a.get('rule') or a.get('type')}（{a.get('school', '')}）"
            for a in (annotations or [])[:6]
        ) or "无"
        prompt = (_JUDGE_PROMPT
                  .replace("{schema}", _JUDGE_SCHEMA_HINT)
                  .replace("{annotations}", note)
                  .replace("{text}", text[: self.max_chars]))
        try:
            raw = await self._default_generator()(prompt)
        except Exception as e:  # noqa: BLE001 —— 判定器任何异常都不能影响对话
            self._record_failure(f"调用失败: {e}")
            return {"verdict": "unavailable", "reason": f"判定器调用失败: {e}",
                    "available": False, "claims": [], "source": "judge"}

        parsed = self._parse(raw)
        if parsed is None:
            self._record_failure(f"返回不可解析: {raw[:60]!r}")
            return {"verdict": "unavailable", "reason": "判定器返回不可解析",
                    "available": False, "claims": [], "source": "judge"}

        self._fails = 0
        result = {**parsed, "available": True, "source": "judge"}
        if len(self._cache) >= self._cache_size:
            self._cache.clear()
        self._cache[key] = result
        return result

    # ---------------- 解析 ----------------
    @staticmethod
    def _parse(raw: str) -> Optional[dict[str, Any]]:
        if not raw:
            return None
        m = _JSON_RE.search(raw)
        if not m:
            return None
        try:
            data = json.loads(m.group())
        except json.JSONDecodeError:
            return None
        if not isinstance(data, dict):
            return None
        verdict = str(data.get("verdict", "")).strip().lower()
        if verdict not in ("orthodox", "citation", "deviation"):
            return None
        claims = data.get("claims")
        if not isinstance(claims, list):
            claims = []
        return {
            "verdict": verdict,
            "claims": [c for c in claims if isinstance(c, dict)][:12],
            "reason": str(data.get("reason", ""))[:200],
        }

    def _record_failure(self, reason: str) -> None:
        self._fails += 1
        logger.warning("立场判定器降级（第 %d 次）: %s", self._fails, reason)
        if self._fails >= self._breaker_threshold:
            self._open_until = time.time() + self._breaker_seconds
            self._fails = 0
            logger.warning("立场判定器熔断 %.0fs（模型不可用），期间只标注不拦截",
                           self._breaker_seconds)
