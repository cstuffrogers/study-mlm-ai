"""生成后三重校验 — 规则版

职责（生成侧防线，接在 OrthodoxyGuard 之后做更细的生成内容校验）：
  1. 事实一致性 — 生成内容是否有检索上下文支撑（防 LLM 编造来源/论断）
  2. 术语一致性 — 是否误用术语红线（如"市民社会"被当"公民社会"用）
  3. 立场二分类 — 复用 OrthodoxyGuard，保留 BERT 接口位（Phase 6 训练后替换）

返回统一结构，供 dialogue_service 决定 pass / block。
"""
from __future__ import annotations

import logging
import re
from typing import Any

from core.guard.orthodoxy import OrthodoxyGuard

logger = logging.getLogger(__name__)

# ML 置信度阈值——只在高置信时覆盖规则，低置信回退规则（防误伤边界/Mock 文本）
ML_CONFIDENCE_THRESHOLD = 0.6


# 术语红线：标准术语 vs 常见误用（取自 prompt_engineering.yaml 术语红线）
TERM_REDLINES: list[dict[str, Any]] = [
    {"term": "市民社会", "forbidden": ["公民社会", "民间社会", "NGO"], "reason": "市民社会≠公民社会/民间社会/NGO"},
    {"term": "物化", "forbidden": ["卢卡奇式异化"], "reason": "正统物化仅指商品拜物教，非卢卡奇异化"},
    {"term": "反映", "forbidden": ["镜像复制"], "reason": "反映含能动创造性，非镜像复制"},
    {"term": "决定", "forbidden": ["唯一原因"], "reason": "决定是一元最终决定性，但允许反作用"},
]


class TripleCheck:
    """生成后三重校验（规则版）"""

    def __init__(self, guard: OrthodoxyGuard | None = None, stance_classifier=None) -> None:
        self.guard = guard or OrthodoxyGuard()
        # 立场分类器（ML 版，注入后优先于规则；None = 规则兜底）
        # 注入 ml.train_stance.StanceClassifier 实例；模型文件缺失时保持 None
        self.stance_classifier = stance_classifier

    def check(
        self,
        generated: str,
        retrieved_context: str = "",
        mode: str = "explain",
        allow_critical: bool = False,
    ) -> dict[str, Any]:
        """
        三重校验

        Returns:
            {
                fact_consistency: {status: pass/flag, reason},
                terminology: {status: pass/flag, issues},
                stance: {status: pass/block, source: rule/bert, detail},
                action: pass/block,
            }
        """
        fact = self._check_fact_consistency(generated, retrieved_context)
        term = self._check_terminology(generated)
        stance = self._check_stance(generated, mode=mode, allow_critical=allow_critical)

        action = "pass"
        if stance["status"] == "block":
            action = "block"
        elif fact["status"] == "flag" or term["status"] == "flag":
            # 事实/术语 flag 不直接 block，但标记问题（降级策略）
            action = "flag"

        return {
            "fact_consistency": fact,
            "terminology": term,
            "stance": stance,
            "action": action,
        }

    # --------------------------------------------------
    # 1. 事实一致性：检查生成内容是否声称了无上下文支撑的来源
    # --------------------------------------------------
    def _check_fact_consistency(self, generated: str, retrieved_context: str) -> dict[str, Any]:
        if not retrieved_context:
            # 无检索上下文时不做事实校验（信息不足）
            return {"status": "pass", "reason": "no_retrieved_context"}

        # 抽取生成内容中声称的 Chunk ID（形如 [CH-XXX] 或 [著作名 页码]）
        cited_chunks = re.findall(r'\[([A-Z]{2,}-[A-Z0-9-]+)\]', generated)
        if not cited_chunks:
            return {"status": "pass", "reason": "no_citation"}

        # 检查声称的来源是否在检索上下文中出现
        unsupported = [c for c in cited_chunks if c not in retrieved_context]
        if unsupported:
            return {
                "status": "flag",
                "reason": f"引用了未检索到的来源: {unsupported[:3]}",
                "issues": unsupported,
            }
        return {"status": "pass", "reason": "all_citations_supported"}

    # --------------------------------------------------
    # 2. 术语一致性：检查术语红线误用
    # --------------------------------------------------
    def _check_terminology(self, generated: str) -> dict[str, Any]:
        issues = []
        for rule in TERM_REDLINES:
            if rule["term"] in generated:
                for forbidden in rule["forbidden"]:
                    if forbidden in generated:
                        issues.append({
                            "term": rule["term"],
                            "forbidden_use": forbidden,
                            "reason": rule["reason"],
                        })
        if issues:
            return {"status": "flag", "issues": issues}
        return {"status": "pass", "issues": []}

    # --------------------------------------------------
    # 3. 立场二分类：规则版（BERT 留接口）
    # --------------------------------------------------
    def _check_stance(self, generated: str, mode: str, allow_critical: bool) -> dict[str, Any]:
        # 规则版始终跑（提供 flags 细节 + 辩难豁免标记处理）
        guard_result = self.guard.check(generated, mode=mode, allow_critical=allow_critical)
        source = "rule"

        # ML 分类器可用：高置信时覆盖规则，低置信回退规则（防误伤边界文本）
        if self.stance_classifier is not None:
            try:
                ml_label = self.stance_classifier.classify(generated)
                # 取概率（SVM 用 decision_function 近似，logreg 用 predict_proba）
                proba = self.stance_classifier.predict_proba(generated)
                ml_conf = float(proba.get(ml_label, 0.5))
                source = "ml"
                if ml_conf >= ML_CONFIDENCE_THRESHOLD:
                    if ml_label == "deviation":
                        return {"status": "block", "source": source,
                                "detail": f"ML 分类为偏离（conf={ml_conf:.2f}）", "guard_detail": guard_result}
                    # ML 高置信 orthodox → 覆盖规则误判（如批判性引用）
                    return {"status": "pass", "source": source,
                            "detail": f"ML 分类为正统（conf={ml_conf:.2f}）", "guard_detail": guard_result,
                            "annotations": guard_result.get("annotations", [])}
                # 低置信 → 回退规则（source 标记 ml_low_conf）
                source = "ml_low_conf_rule"
            except Exception as e:
                logger.warning("ML 立场分类器异常，降级规则: %s", e)
                source = "rule_fallback"

        return {
            "status": "block" if guard_result["action"] == "block" else "pass",
            "source": source,
            "detail": guard_result["flags"],
            "exempt": guard_result["exempt"],
            # D171：可疑但不构成自述偏离的命中（术语中性使用、被引述的反面例子）。
            # status 仍是 pass —— 调用方把它展示给用户看，不拦回答。
            "annotations": guard_result.get("annotations", []),
        }
