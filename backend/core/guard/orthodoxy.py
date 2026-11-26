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
        # 正统限定语豁免：恩格斯本人就是这么写的——「决定性因素归根到底是现实生活的
        # 生产和再生产」「并非只有经济状况才是原因，还有上层建筑的各种因素」。
        # 缺这些限定语的「相互决定/共同决定」照样判偏离。
        "exempt": r"(反作用|归根到底|最终|唯一决定性的?因素|决定性的因素)",
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
        # 正统限定语豁免：毛泽东《实践论》的提法是「能动的革命的反映论」，
        # 「机械反映论是错误的」本身就是正统表述（反对的是机械的、被动的反映论）。
        "exempt": r"(能动的|革命的反映论|机械(的)?反映论|不是机械)",
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
    # ---- D141：毛泽东思想三项基本点（以前 10 条规则零覆盖）------------------
    # 写作口径：只拦「否认/替换」的**断言**，不拦正常论述。
    #   正统表述「必须严格区分和正确处理两类不同性质的矛盾」→ 不命中；
    #   正统表述「人民内部矛盾只能用民主的、说服教育的方法解决」→ 不命中。
    "deny_two_kinds_contradiction": {
        "pattern": r"(否认|不存在|没有)(两类(不同性质的)?矛盾|敌我矛盾和人民内部矛盾)"
                   r"|两类矛盾(的区分)?(是虚构的?|不存在|没有必要|已经过时)"
                   r"|人民内部矛盾(就是|等于|都属于|统统是)(敌我矛盾|阶级斗争)",
        "label": "deviation",
        "reason": "毛泽东《关于正确处理人民内部矛盾的问题》：两类矛盾性质不同、处理方法不同，不得否认或合并",
    },
    "deny_mass_line": {
        "pattern": r"群众路线(已经)?(过时|不适用|不必要|没必要)"
                   r"|(不必|不需要|不用)(再)?(依靠群众|走群众路线)"
                   r"|群众(都是|是)(愚昧|落后|盲从)的?"
                   r"|(精英|少数人|上面)(才|必须|应该)(管理|领导|统治)(群众|人民)",
        "label": "deviation",
        "reason": "群众路线（一切为了群众、一切依靠群众，从群众中来、到群众中去）是立场红线",
    },
    "deny_independence": {
        "pattern": r"(独立自主|自力更生)(已经)?(过时|不必要|不必|没用)"
                   r"|(不必|不需要|不用)(再)?(坚持)?(独立自主|自力更生)"
                   r"|革命(的)?胜利(完全|全靠|主要)(依靠|归功于)?(苏联|外援|外国|外来模式)"
                   r"|(照搬|移植)(苏联模式|外国模式)(才|才能)(成功|胜利)",
        "label": "deviation",
        "reason": "独立自主、自力更生是立场红线；照搬外来模式的教训本身即毛泽东所批评",
    },
    # ---- D171：漏拦断言补登记 ----------------------------------------------
    # 背景（真实体检）：旧规则靠关键词，下面这些**真正的偏离断言**一条都没命中——
    #   「文化决定社会发展方向」「技术决定社会形态的更替」
    #   「地理环境决定社会制度的性质」「剩余价值并不存在」
    #   「阶级斗争只是话术」「资本主义是历史的终点」
    # 反过来，一条正常教学回答里提了「物化」就被整段拦。这里补的是**断言级**
    # （主语+谓语+宾语），不是单个关键词。
    "deny_surplus_value": {
        "pattern": r"剩余价值(?:理论)?(?:是|并|根本|完全)?不(?:存在|成立)(?!于)"
                   r"|不存在(?:什么)?剩余价值"
                   r"|利润(?:完全)?来自(?:企业家|资本家)(?:的)?(?:才能|贡献|冒险)",
        "label": "deviation",
        "reason": "剩余价值理论是马克思政治经济学基石，否认它即否认剥削",
    },
    "capitalism_eternal": {
        "pattern": r"资本主义(?:是|才是)(?:历史|人类)的?(?:终点|终结|最终形态|最后阶段)"
                   r"|资本主义(?:将|会)?永(?:恒|远|世)(?:存在|延续|长存)",
        "label": "deviation",
        "reason": "资本主义不是历史的终点；两个必然（灭亡与胜利）是历史唯物主义结论",
    },
    "class_struggle_dismissed": {
        "pattern": r"阶级斗争(?:只|仅|不过)?(?:是|不过是)(?:话术|口号|修辞|虚构|想象)"
                   r"|现实(?:中)?(?:早已|已经)?(?:没有|不存在)阶级(?:斗争|矛盾)",
        "label": "deviation",
        "reason": "阶级斗争是历史唯物主义灵魂，不能降为话术或宣布已消失",
    },
    "culture_techno_determinism": {
        "pattern": r"(?:文化|技术|地理环境|地理|人口)\s*(?:决定|最终决定)\s*"
                   r"(?:社会|历史|制度|形态|发展)",
        # 反驳句式（「不是文化决定社会」）不能当偏离
        "exempt": r"(不是|并非|反对|批判|驳斥|否认|错)(?:这种|所谓|上述)?.{0,6}"
                  r"(文化|技术|地理|人口)",
        "label": "deviation",
        "reason": "文化/技术/地理决定论与唯物史观的「经济基础决定上层建筑」相对立",
    },
    "deny_party_leadership": {
        "pattern": r"(?:不需要|不必要|反对|否定|取消)(?:共产党|中国共产党|党的)(?:领导)"
                   r"|(?:多党制|多党轮替|轮流执政)(?:才是|才能|更)",
        "label": "deviation",
        "reason": "党的领导是社会主义事业的核心，否定党的领导属立场红线",
    },
    "deconstruct_orthodox_core": {
        "pattern": r"(?:解构|拆解|祛魅)(?:了)?(?:唯物辩证法|马克思主义|历史唯物主义|阶级斗争|无产阶级专政)",
        "label": "deviation",
        "reason": "解构主义把马克思主义当作待拆的文本，与唯物辩证法相对立",
    },
    "discourse_constructs_reality": {
        "pattern": r"话语.{0,4}(?:建构|塑造|决定)(?:了)?(?:社会现实|现实|社会存在)",
        "label": "deviation",
        "reason": "社会存在决定意识；把现实当成话语建构属后马克思主义立场",
    },
    "movement_is_everything": {
        "pattern": r"运动就是一切"
                   r"|最终目的(?:是)?(?:微不足道|算不了什么|无关紧要)",
        "label": "deviation",
        "reason": "伯恩斯坦「运动就是一切，最终目的是微不足道的」是修正主义名言",
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

# ------------------------------------------------------------------
# 4. 主张归属层（D171）——从「字串命中」升级到「这句话到底是谁在主张」
# ------------------------------------------------------------------
# 为什么要有这一层：旧实现「命中即拦」，只要回答里出现批判对象术语
# （物化/总体性/历史决定论…）或偏离句式，就整段 block。可「指出反面例子」
# 和「自己主张反面观点」在字面上完全一样 ——
#   用户提问「『阶级斗争已经过时』这种说法错在哪？」→ 被判宣扬，直接拒答
#   回答「卢卡奇的物化错在把异化泛化」→ 缺一个「错误」就被整段拦截
# 唯一的出路是让模型自己写机器标记 `【批判对象·非借鉴】`，正常回答不会这么写。
# 现在按**句子**判断归属：引号内、带引述框架、带转折/纠偏词、或用户在提问
# （仅输入侧）→ 判为「引述」，不算作者主张；批判对象术语只在**宣扬谓语**下
# 才判偏离，其余（定义/比较/中性使用）一律降为标注，不拦整段。

# 提问标记：用户在自己提问里引述一种错误说法 ≠ 用户自己主张它（只对输入侧生效）
_QUESTION_MARKERS = ("？", "?", "为什么", "为何", "怎么理解", "如何理解", "如何看待",
                     "是否", "对不对", "错在哪", "错在哪里", "这种说法", "这一说法",
                     "这个观点", "这句话", "什么是", "何谓", "凭什么", "何以")

# 引述框架：出现这些词说明该句是在复述别人的观点，而不是作者自己的结论
# 注意：**不能**把「主张 / 声称 / 称为」这类词当引述框架 ——
# 「伯恩斯坦主张和平长入社会主义是合理的」里「主张」是作者的推介，不是引述，
# 收了它就等于给宣扬句式开后门（SC-003 实测漏拦）。
_QUOTE_FRAME_WORDS = ("有人说", "有人认为", "有观点", "有人主张", "有人问", "错误观点",
                      "所谓", "据说", "据称", "被说成", "被描述为", "归结为", "贴上")

# 转折/纠偏词：同句内出现即视为「引述 + 反驳」，不算宣扬
# 注意：**不得**加入「唯物」（常见于西马自我标榜：「解构唯物辩证法」），
# 也不得加入「但」这类纯连接词（会把跨句串味的裸断言一并放过）。
_REBUTTAL_WORDS = ("错", "谬", "荒谬", "唯心", "不是一回事", "不能混", "区别于",
                   "不同", "相对立", "非正统", "误区", "曲解", "庸俗", "恰恰相反",
                   "问题在于", "这说明", "应当指出", "不属于", "不是马克思主义",
                   "无法", "不能", "并非")

# 成对引号（含书名号）：引号内的字是「被引用的说法」，不是作者表态
_QUOTE_PAIRS = (("「", "」"), ("『", "』"), ("“", "”"), ("‘", "’"), ('"', '"'), ("《", "》"))

# 「宣扬」谓语：批判对象术语被当成**有效理论**推介时才判偏离。
# 这是 D171 的关键收窄：术语本身（物化/总体性/生活世界…）是教材词汇，
# 出现不等于偏离；只有「丰富了马克思主义」「揭示了…本质」「超越…局限」这种
# 抬高/采纳句式才算宣扬（SC-004 的 deviation 样本正是这一类）。
_ENDORSE_RE = re.compile(
    r"(丰富|超越|发展|补充|完善|提供|奠定|揭示|证明|印证|深化|拓展).{0,10}"
    r"(马克思主义|唯物史观|历史唯物主义|辩证唯物主义|正统|真谛|本质|新境界|新基础|新视野)"
    r"|(解释|说明|表明|标志着|揭示)(了)?.{0,16}(起源|根源|秘密|本质|规律|根本对立|两个马克思)"
    r"|(是|乃|堪称|属于).{0,8}(合理|科学|正确|真理|根本方法|核心|精髓)"
    r"|(超越|摆脱|替代|取代).{0,8}(局限|束缚|无产阶级专政|暴力革命|阶级斗争|剩余价值)"
    r"|(已经|正在)(终结|解体|失效|破产)"
    r"|(只是|不过是|仅是).{0,8}(一种|之一)"
    r"|比.{0,10}(更重要|更根本|更为根本)"
    r"|(根本方法|核心病症|唯一出路|真正出路)"
)


def _in_quotes(text: str, start: int, end: int) -> bool:
    """命中是否落在成对引号内（引述材料，不是作者表态）。"""
    for lq, rq in _QUOTE_PAIRS:
        lo = text.rfind(lq, 0, start)
        if lo == -1:
            continue
        # 该开引号还没被闭合，且命中后能找到闭合符 → 命中在引号内
        if text.find(rq, lo + len(lq), start) == -1 and text.find(rq, end) != -1:
            return True
    return False


def _is_question(clause: str) -> bool:
    return any(t in clause for t in _QUESTION_MARKERS)


def _assess_occurrence(text: str, start: int, end: int, *, kind: str,
                       context: str = "output") -> str:
    """判定单处命中属于哪种主张类型。

    返回：
      "citation"  —— 引述/复述/被批判/用户在提问，不算作者主张
      "deviation" —— 作者自己主张（唯一会触发拦截的一类）
      "neutral"   —— 中性使用（仅 critical 术语有此类：定义、比较、教学口径）
    """
    if _in_quotes(text, start, end):
        return "citation"
    masked = _mask_markers(text)
    l, r = _clause_bounds(masked, start, end)
    clause = masked[l:r]
    if any(w in clause for w in _CRITICAL_CONTEXT_WORDS):
        return "citation"
    if any(w in clause for w in _REBUTTAL_WORDS):
        return "citation"
    if any(w in clause for w in _QUOTE_FRAME_WORDS):
        return "citation"
    if context == "input" and _is_question(clause):
        # 输入侧：用户提问/追问里引用错误说法，不等于用户自己主张它
        return "citation"
    if kind == "critical":
        if _ENDORSE_RE.search(clause):
            return "deviation"
        return "neutral"
    return "deviation"


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


# 正统限定语豁免的否决词：同句出现这些说法就不是「反作用」而是**并列决定**
EXEMPT_VETO_WORDS = ("同样决定", "同等", "并列", "一样决定", "共同决定",
                     "相互决定", "互为决定")


def _all_matches_exempt(text: str, pattern: str, exempt: str) -> bool:
    """每一次偏离命中是否都落在**带正统限定语**的同一句里。

    与 `_all_matches_critical` 同一思路，只把「批判语境词」换成「正统限定语」：
      "经济状况是基础……并非只有经济状况才是唯一决定性的因素"
          → 同句含「唯一决定性的因素」→ 正统原话，放行
      "经济基础与上层建筑相互决定"
          → 无限定语 → 仍判偏离
    保守约束同 `_all_matches_critical`：必须**每一处**命中都带限定语。
    """
    hits = list(re.finditer(pattern, text))
    if not hits:
        return False
    ex = re.compile(exempt)
    for m in hits:
        l, r = _clause_bounds(text, m.start(), m.end())
        clause = text[l:r]
        if not ex.search(clause):
            return False
        # 否决词：同句里只要出现「同样决定/并列/共同决定」这类**真偏离**的并列说法，
        # 就不给豁免——否则「经济不是唯一决定，文化同样决定」会被「不是唯一」放过。
        if any(v in clause for v in EXEMPT_VETO_WORDS):
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

    def check(self, text: str, mode: str = "explain", allow_critical: bool = False,
              context: str = "output") -> dict[str, Any]:
        """
        校验生成文本的立场

        Args:
            text: 待校验文本（AI 回答，或 context="input" 时的用户提问）
            mode: 会话模式（debate 模式触发豁免逻辑）
            allow_critical: 是否允许批判对象模式展示（FR-007，研究路径/批判性阅读开启）
            context: "output"（AI 回答）|"input"（用户提问）——输入侧额外把提问语气
                视为引述：用户在问「这种说法错在哪」，不是自己在主张它。

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

        # (a) 批判对象术语检测——D171：术语本身不再判偏离，只有「宣扬谓语」才判
        critical_used = []
        for term, info in CRITICAL_OBJECTS.items():
            if term not in check_text:
                continue
            critical_used.append(term)
            # FR-007 收紧：批判对象包裹了 CRITICAL_MARKER（或显式开了批判性阅读）→ 通过
            wrapped = (CRITICAL_MARKER_OPEN in text and
                       text.find(CRITICAL_MARKER_OPEN) < text.find(term) < text.find(CRITICAL_MARKER_CLOSE, text.find(term)))
            if wrapped or allow_critical:
                continue
            verdicts = [
                _assess_occurrence(check_text, m.start(), m.end(), kind="critical", context=context)
                for m in re.finditer(re.escape(term), check_text)
            ]
            if "deviation" in verdicts:
                flags.append({
                    "type": "critical_object_endorsed",
                    "term": term,
                    "school": info["school"],
                    "label": "deviation",
                    "reason": (f"把批判对象'{term}'当有效理论推介（{info['error']}），"
                               f"属偏离原教旨"),
                })
            elif verdicts and all(v == "citation" for v in verdicts):
                flags.append({
                    "type": "critical_citation",
                    "term": term,
                    "school": info["school"],
                    "reason": f"批判性引用批判对象'{term}'（语境含批判词/引述框架），保留",
                })
            else:
                # D171：教学口径的中性使用（定义、比较、举例）→ 只标注，不拦整段。
                # 拦截留给定罪更明确的情形（宣扬谓语、裸偏离断言）或语义判定器。
                flags.append({
                    "type": "critical_object_unwrapped",
                    "term": term,
                    "school": info["school"],
                    "label": "annotate",
                    "reason": (f"涉及批判对象'{term}'（{info['school']}），未见明确批判姿态；"
                               f"按标注处理，不拦截"),
                })

        # (b) 立场模式检测
        for rule_name, rule in STANCE_PATTERNS.items():
            hits = list(re.finditer(rule["pattern"], check_text))
            if not hits:
                continue
            if rule.get("exempt") and _all_matches_exempt(
                    check_text, rule["pattern"], rule["exempt"]):
                # 正统原话（恩格斯「归根到底」、毛「能动的革命的反映论」）→ 不判偏离
                flags.append({
                    "type": "stance_pattern_orthodox_exempt",
                    "rule": rule_name,
                    "label": "citation",
                    "reason": f"正统限定语豁免（同句含正统表述），保留：{rule['reason']}",
                })
                continue
            verdicts = [
                _assess_occurrence(check_text, m.start(), m.end(), kind="stance", context=context)
                for m in hits
            ]
            if all(v == "citation" for v in verdicts):
                # 自指批判语境/引述框架：在批判或复述这个错误论调，不是宣扬 → 只记录
                flags.append({
                    "type": "stance_pattern_critical_citation",
                    "rule": rule_name,
                    "label": "citation",
                    "reason": f"批判性引用偏离表述（语境含批判词/引述框架），保留：{rule['reason']}",
                })
            else:
                flags.append({
                    "type": "stance_pattern",
                    "rule": rule_name,
                    "label": rule["label"],
                    "reason": rule["reason"],
                })

        # 判定动作：只有**作者自己主张**的偏离才拦（D171 之前 critical_object_unwrapped
        # 也算偏离，一个术语就能整段 block，是「过严」的主要来源）
        deviation_flags = [f for f in flags if f.get("label") == "deviation"]
        action = "block" if deviation_flags else "pass"

        return {
            "is_orthodox": action == "pass",
            "action": action,
            "flags": flags,
            "annotations": [f for f in flags if f.get("label") == "annotate"],
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
            if not re.search(rule["pattern"], chunk_text):
                continue
            if rule.get("exempt") and _all_matches_exempt(
                    chunk_text, rule["pattern"], rule["exempt"]):
                continue  # 正统原话，不降权不拦
            flags.append({"type": "stance_pattern", "rule": rule_name, "label": rule["label"]})

        if any(f.get("label") == "deviation" for f in flags):
            return {"action": "block", "reason": "stance_pattern", "flags": flags}
        if any(f.get("action") == "demote" for f in flags):
            return {"action": "demote", "reason": "critical_term_no_context", "flags": flags}
        return {"action": "pass", "flags": flags}
