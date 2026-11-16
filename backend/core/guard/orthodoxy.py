"""防偏离引擎 — 正统马哲立场校验核心

重构自原型 retrieval_filter_pipeline.py 的 MetaRuleEngine，修复两个命门漏洞：
  P0-1: stance_patterns 缺"共同决定"等变体 + 黑名单按字面 in 匹配 → 改语义匹配 + 扩充变体
  P0-2: L2 对所有 chunk 跑内容检测会误杀批判性教科书文本 → 区分"批判引用 vs 宣扬"

并实现：
  FR-006: 辩难模式标记豁免（`【反方观点·仅供批判】`包裹段跳过校验）
  FR-007(收紧): 批判对象模式——西马/修正主义等不作中立对照，AI以批判姿态呈现

三层职责（与 PromptSanitizer 分工）：
  PromptSanitizer (输入侧) → 本引擎 (生成侧内容校验) → BERT分类器 (生成后深度校验)
"""
from __future__ import annotations

import re
import logging
from typing import Any

logger = logging.getLogger(__name__)


# ============================================================
# 1. 批判对象清单（按 学习顺序2.md §严格禁止）— FR-007 收紧
# ============================================================
# 这些概念/人物 **不作中立对照**，只能作批判对象
CRITICAL_OBJECTS: dict[str, dict] = {
    # 西方马克思主义
    "多元决定": {"school": "阿尔都塞", "orthodox_ref": "经济基础决定上层建筑", "error": "反对经济决定论的结构主义马克思主义"},
    "认识论断裂": {"school": "阿尔都塞", "orthodox_ref": "认识是螺旋上升的反映过程", "error": "全盘否定早期马克思"},
    "物化": {"school": "卢卡奇", "orthodox_ref": "商品拜物教（马克思原义）", "error": "卢卡奇物化=异化，丢失实践-革命维度"},
    "总体性": {"school": "卢卡奇", "orthodox_ref": "辩证唯物主义的全面性", "error": "总体性遮蔽阶级斗争"},
    "文化领导权": {"school": "葛兰西", "orthodox_ref": "无产阶级专政", "error": "偏离暴力革命与无产阶级专政"},
    "生活世界": {"school": "哈贝马斯", "orthodox_ref": "社会存在决定社会意识", "error": "现象学-解释学概念，非唯物史观"},
    # 修正主义
    "和平长入社会主义": {"school": "伯恩斯坦", "orthodox_ref": "无产阶级革命与专政", "error": "修正主义鼻祖观点"},
    "运动就是一切": {"school": "伯恩斯坦", "orthodox_ref": "最终目的与运动统一", "error": "取消革命目标"},
    # 后马克思/后现代
    "话语建构": {"school": "拉克劳/福柯", "orthodox_ref": "社会存在决定意识", "error": "解构主义，否定客观实在"},
    "生产之镜": {"school": "鲍德里亚", "orthodox_ref": "劳动价值论", "error": "后马克思主义概念"},
    "宏大叙事": {"school": "利奥塔", "orthodox_ref": "历史唯物主义的科学性", "error": "否定历史必然性"},
    "延异": {"school": "德里达", "orthodox_ref": "唯物辩证法的否定", "error": "解构主义核心概念"},
    # 资产阶级/反马
    "新教伦理": {"school": "韦伯", "orthodox_ref": "原始积累（资本论）", "error": "文化决定论，对抗经济决定论"},
    "历史决定论": {"school": "波普尔", "orthodox_ref": "历史唯物主义的科学性", "error": "歪曲马克思主义为宿命论"},
}

# ============================================================
# 2. 立场模式识别（正则，扩充变体修复 P0-1）
# ============================================================
STANCE_PATTERNS: dict[str, dict] = {
    "deny_natural_dialectics": {
        # 扩充：原缺"否认自然界""辩证法只存在于主体客体"等变体
        "pattern": r"自然(界)?(没有|不存在|否认)(辩证法)|辩证法只存在于(主体|人)|自然辩证法是机械唯物主义",
        "label": "deviation",
        "reason": "否认自然辩证法，属卢卡奇等非正统立场",
    },
    "mutual_determination": {
        # 扩充 P0-1 核心修复：原只匹配"相互决定"，漏"共同决定""多种因素决定""非经济唯一决定"
        "pattern": r"(相互决定|互为决定|双向决定|决定是相互的|多种?因素.*共同决定|多种因素.*决定|经济(基础)?不是(唯一)?决定|并非.*经济.*决定)",
        "label": "deviation",
        "reason": "社会存在与社会意识不是相互/共同决定，而是前者决定后者（经济基础决定上层建筑）",
    },
    "consciousness_determines": {
        "pattern": r"意识决定(物质|存在|社会)|精神(产生|创造)物质|思维(先于|决定)存在",
        "label": "deviation",
        "reason": "唯心主义立场，意识第二性",
    },
    "reject_reflection": {
        "pattern": r"(反对反映论|反映论是机械的|认识不是反映|反映论是被动的)",
        "label": "deviation",
        "reason": "反对反映论属非正统认识论",
    },
    "class_as_discourse": {
        "pattern": r"阶级是(话语|建构|想象的|符号的)|阶级.*想象的共同体",
        "label": "deviation",
        "reason": "阶级是客观经济范畴，非话语建构",
    },
    "reject_class_struggle": {
        # 新增：原教旨核心——阶级斗争是历史唯物主义灵魂
        "pattern": r"阶级斗争(已经|已经)?(消亡|过时|不再是)|历史(已经)?终结(于|了).*阶级",
        "label": "deviation",
        "reason": "阶级斗争是历史唯物主义灵魂，否认即背叛原教旨",
    },
    "deny_dictatorship": {
        # 新增：无产阶级专政是原教旨红线
        "pattern": r"无产阶级专政(是|已经)?(过时|不必要|错误)|只需(民主|改良)不需要专政",
        "label": "deviation",
        "reason": "无产阶级专政是马克思主义核心，修正主义才否认",
    },
    "deny_planned_economy": {
        # 哈耶克/新自由主义话术——否定计划经济与社会主义道路
        "pattern": r"计划经济.{0,6}(奴役|奴役之路|通向奴役)|计划经济(必然|已经)?(失败|破产)|(市场|自由市场)(优越于|胜过)计划",
        "label": "deviation",
        "reason": "否定计划经济是哈耶克新自由主义话术，与社会主义政治经济学根本对立",
    },
    "deny_labor_value_theory": {
        # 否定劳动价值论——修正主义与后现代共同话术
        "pattern": r"劳动价值论(已经)?(过时|失效|错误)|知识经济(超越|否定|颠覆)(了)?(劳动价值论|马克思.*价值论)|剩余价值(理论)?(不成立|错误)",
        "label": "deviation",
        "reason": "劳动价值论是马克思政治经济学基石，否定它即否定剩余价值与剥削理论",
    },
}

# ============================================================
# 3. 辩难模式豁免标记（FR-006）
# ============================================================
EXEMPT_MARKER_OPEN = "【反方观点·仅供批判】"
EXEMPT_MARKER_CLOSE = "【/反方观点】"
# 批判对象展示标记（FR-007 收紧：批判对象内容必须包裹此标记，AI 以批判姿态呈现）
CRITICAL_MARKER_OPEN = "【批判对象·非借鉴】"
CRITICAL_MARKER_CLOSE = "【/批判对象】"

_EXEMPT_RE = re.compile(re.escape(EXEMPT_MARKER_OPEN) + r".*?" + re.escape(EXEMPT_MARKER_CLOSE), re.DOTALL)
_CRITICAL_RE = re.compile(re.escape(CRITICAL_MARKER_OPEN) + r".*?" + re.escape(CRITICAL_MARKER_CLOSE), re.DOTALL)

# 批判语境词——出现这些词说明批判对象术语是被批判性引用（P0-2 修复依据）
_CRITICAL_CONTEXT_WORDS = ("批判", "错误", "反对", "歪曲", "否定", "揭露", "驳斥", "谬误", "攻击", "背离", "修正主义")

# 句读边界：自指批判语境判定只在**同一句内**做，不跨句串味
_CLAUSE_TERMINATORS = "。！？；!?;\n"

# 标记字面本身的内含词：标记里有「批判」二字，若不做掩码，
# 「【反方观点·仅供批判】<裸断言>」会被误认为处于批判语境而豁免。
_MARKER_LITERALS = (EXEMPT_MARKER_OPEN, EXEMPT_MARKER_CLOSE,
                    CRITICAL_MARKER_OPEN, CRITICAL_MARKER_CLOSE)


def _mask_markers(text: str) -> str:
    """把标记字面替换为等长占位符（**保持下标不变**）。

    目的：标记本身不得充当「批判语境词」的证据。
    等长替换让后续 `_clause_bounds` / 命中位置继续有效，不需重算偏移。
    """
    for lit in _MARKER_LITERALS:
        if lit in text:
            text = text.replace(lit, "\u25a1" * len(lit))
    return text


def _has_critical_context(text: str, term: str, window: int = 40) -> bool:
    """术语 term 在 text 中是否处于批判语境（附近 ±window 字符有批判语境词）。

    P0-2：区分"批判性引用 vs 宣扬"——
      "卢卡奇的物化概念是错误的" → 附近有"错误"→ 批判引用 → 不算偏离
      "卢卡奇的物化理论揭示了资本主义异化" → 无批判语境词 → 宣扬 → 偏离

    局限（规则版已知边界）：当批判对象作为主体"批判了马克思的劳动价值论"
    这类句式时，'批判'语境词同样出现，规则版无法区分批判方向。
    这类困难样本留待 BERT 立场分类器（Phase 6 训练后注入）解决。
    """
    idx = text.find(term)
    masked = _mask_markers(text)
    while idx != -1:
        # 窗口从掩码后的文本取：标记字面（如「【反方观点·仅供批判】」）不得冒充批判语境
        ctx = masked[max(0, idx - window): idx + len(term) + window]
        if any(w in ctx for w in _CRITICAL_CONTEXT_WORDS):
            return True
        idx = text.find(term, idx + 1)
    return False


def _clause_bounds(text: str, start: int, end: int) -> tuple[int, int]:
    """返回 [start, end) 所在句子的边界（按句读切分）。"""
    left = max(text.rfind(ch, 0, start) for ch in _CLAUSE_TERMINATORS)
    right_candidates = [text.find(ch, end) for ch in _CLAUSE_TERMINATORS]
    right_candidates = [i for i in right_candidates if i != -1]
    right = min(right_candidates) if right_candidates else len(text)
    return left + 1, right


def _all_matches_critical(text: str, pattern: str) -> bool:
    """立场模式的**每一次**命中是否都处于自指批判语境。

    修复前：把"阶级斗争已经过时的错误论调，应当批判"这类**正确的批判性表述**
    也判成偏离，导致用户明明在批判错误观点却被拦截。

    做法与 `_has_critical_context`（P0-2 对批判对象术语的处理）是**同一个思路**，
    只是把同一标准用到立场模式上，不新增任何"抓偏离"的规则：
      "阶级斗争已经过时"                      → 无语境词 → 仍判偏离
      "阶级斗争已经过时的错误论调，应当批判"    → 同一句有语境词 → 判批判性引用，放行

    保守约束（两条都不能放宽）：
      1. **必须全部命中都带语境词**才豁免；只要有一处裸断言就仍判偏离。
      2. 语境词必须与命中**同处一句**，不跨句串味 ——
         否则"XX 应当批判。但是意识决定物质"会把后一句也一并豁免。
    局限同 `_has_critical_context`：规则版分不清批判方向，留待 BERT 分类器。
    """
    hits = list(re.finditer(pattern, text))
    if not hits:
        return False
    # 标记字面不得充当批判语境证据（其内含「批判」二字）
    masked = _mask_markers(text)
    for m in hits:
        l, r = _clause_bounds(masked, m.start(), m.end())
        clause = masked[l:r]
        if not any(w in clause for w in _CRITICAL_CONTEXT_WORDS):
            return False
    return True


def _strip_exempt_segments(text: str) -> str:
    """剥离豁免/批判标记段——这些段不参与立场校验"""
    text = _EXEMPT_RE.sub("", text)
    text = _CRITICAL_RE.sub("", text)
    return text


def _has_unclosed_exempt_marker(text: str) -> bool:
    """检测豁免标记是否闭合——未闭合的豁免不生效（防绕过）"""
    o = text.count(EXEMPT_MARKER_OPEN)
    c = text.count(EXEMPT_MARKER_CLOSE)
    return o != c


# ============================================================
# 4. 防偏离引擎
# ============================================================
class OrthodoxyGuard:
    """
    生成侧立场校验引擎

    用法：
        guard = OrthodoxyGuard()
        result = guard.check(generated_text, mode="debate")
        if result["action"] == "block": → 走 fallback
    """

    def check(self, text: str, mode: str = "explain", allow_critical: bool = False) -> dict[str, Any]:
        """
        校验生成文本的立场

        Args:
            text: AI 生成的回答
            mode: 会话模式（debate 模式触发豁免逻辑）
            allow_critical: 是否允许批判对象模式展示（FR-007，研究路径/批判性阅读开启）

        Returns:
            {is_orthodox, action, flags, exempt, critical_objects_used}
        """
        # FR-006: 辩难模式豁免——剥离标记段后再校验
        exempt_active = mode == "debate"
        if _has_unclosed_exempt_marker(text):
            # 标记未闭合 → 视为绕过尝试，直接拦截（不降级为正常校验）
            logger.warning("辩难豁免标记未闭合，判定为绕过尝试: %s", text[:60])
            return {
                "is_orthodox": False,
                "action": "block",
                "flags": [{"type": "unclosed_exempt_marker",
                           "reason": "辩难豁免标记未闭合，疑似绕过立场校验"}],
                "exempt": False,
                "critical_objects_used": [],
            }

        check_text = _strip_exempt_segments(text) if exempt_active else text

        flags = []

        # (a) 批判对象术语检测
        critical_used = []
        for term, info in CRITICAL_OBJECTS.items():
            if term in check_text:
                # FR-007 收紧：批判对象必须包裹 CRITICAL_MARKER，否则视为"中立引用"→ 偏离
                wrapped = (CRITICAL_MARKER_OPEN in text and
                           text.find(CRITICAL_MARKER_OPEN) < text.find(term) < text.find(CRITICAL_MARKER_CLOSE, text.find(term)))
                if not wrapped and not allow_critical:
                    # P0-2 修复：检查批判语境——批判性引用（"XXX 是错误的/谬误/歪曲"）
                    # 不算偏离，降级为记录；无批判语境的宣扬/中立引用才 block
                    if _has_critical_context(check_text, term):
                        flags.append({
                            "type": "critical_citation",
                            "term": term,
                            "school": info["school"],
                            "reason": f"批判性引用批判对象'{term}'（语境含批判词），保留",
                        })
                    else:
                        flags.append({
                            "type": "critical_object_unwrapped",
                            "term": term,
                            "school": info["school"],
                            "reason": f"批判对象'{term}'未以批判姿态呈现（缺{CRITICAL_MARKER_OPEN}标记或批判语境），属中立引用，偏离原教旨",
                        })
                critical_used.append(term)

        # (b) 立场模式检测
        for rule_name, rule in STANCE_PATTERNS.items():
            if not re.search(rule["pattern"], check_text):
                continue
            if _all_matches_critical(check_text, rule["pattern"]):
                # 自指批判语境：用户在批判这个错误论调本身，不是宣扬它 → 只记录
                flags.append({
                    "type": "stance_pattern_critical_citation",
                    "rule": rule_name,
                    "label": "citation",
                    "reason": f"批判性引用偏离表述（语境含批判词），保留：{rule['reason']}",
                })
            else:
                flags.append({
                    "type": "stance_pattern",
                    "rule": rule_name,
                    "label": rule["label"],
                    "reason": rule["reason"],
                })

        # 判定动作
        deviation_flags = [f for f in flags if f.get("label") == "deviation" or f.get("type") == "critical_object_unwrapped"]
        if deviation_flags:
            action = "block"
        else:
            action = "pass"

        return {
            "is_orthodox": action == "pass",
            "action": action,
            "flags": flags,
            "exempt": exempt_active,
            "critical_objects_used": critical_used,
        }

    def check_chunk(self, chunk_text: str, orthodoxy_tag: str) -> dict[str, Any]:
        """
        L2 立场校验——用于 RAG 过滤层（修复 P0-2）

        P0-2 修复：区分"批判性引用" vs "宣扬"
          - orthodoxy_tag="非正统" 的 chunk：直接拦截（不需内容检测，tag 已标）
          - orthodoxy_tag="正统"/"经典原著" 的 chunk：若文本含批判对象术语，
            检查是否在批判语境（如"批判""错误""反对"附近）→ 是则保留，否则降权
        """
        # tag 级拦截
        if orthodoxy_tag == "非正统":
            return {"action": "block", "reason": f"tag={orthodoxy_tag}", "flags": []}

        # 正统 chunk 的内容检测（P0-2：不再无脑拦截含批判术语的正统文本）
        flags = []
        for term, info in CRITICAL_OBJECTS.items():
            if term in chunk_text:
                # 检查批判语境——附近是否有"批判/错误/反对/歪曲"等词
                idx = chunk_text.find(term)
                context = chunk_text[max(0, idx - 30): idx + len(term) + 30]
                critical_context = any(w in context for w in ["批判", "错误", "反对", "歪曲", "否定", "揭露", "驳斥"])
                if critical_context:
                    # 批判性引用 → 保留，仅记录
                    flags.append({"type": "critical_citation", "term": term, "action": "keep"})
                else:
                    # 无批判语境 → 降权但不直接拦（正统 chunk 仍可能是有价值的）
                    flags.append({"type": "critical_term_no_context", "term": term, "action": "demote"})

        # 立场模式仍按原逻辑
        for rule_name, rule in STANCE_PATTERNS.items():
            if re.search(rule["pattern"], chunk_text):
                flags.append({"type": "stance_pattern", "rule": rule_name, "label": rule["label"]})

        if any(f.get("label") == "deviation" for f in flags):
            return {"action": "block", "reason": "stance_pattern", "flags": flags}
        if any(f.get("action") == "demote" for f in flags):
            return {"action": "demote", "reason": "critical_term_no_context", "flags": flags}
        return {"action": "pass", "flags": flags}
