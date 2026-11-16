"""立场分类训练数据合成 — 模板扩充

基于 deviation_dataset 的 53 条种子 + 模板生成 ~300 条扩充样本。
重点生成 4 条 xfailed 的两类变体：
  type-A (deviation): 批判对象攻击正统 — {批判对象}{攻击动词}{正统锚点}
  type-B (hard_negative): 批判对象被批判（隐式）— {批判对象}是{贬义定性词}

模板复用 orthodoxy.py 的 CRITICAL_OBJECTS 清单，避免重复定义。
不调外部 API，纯本地模板组合。
"""
from __future__ import annotations

import random
import sys
import os

# 复用 orthodoxy 清单
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from core.guard.orthodoxy import CRITICAL_OBJECTS  # noqa: E402
from tests.deviation_dataset import (  # noqa: E402
    ORTHODOX_SAMPLES,
    DEVIATION_SAMPLES,
    HARD_NEGATIVE_SAMPLES,
)

random.seed(42)

# ============================================================
# 模板组
# ============================================================

# type-A: 批判对象攻击正统（deviation，应 block）
# 句式：{school}的{term}{attack_verb}{orthodox_anchor}
ATTACK_VERBS = ["批判了", "否定了", "驳斥了", "推翻了", "证伪了", "解构了", "攻击了", "歪曲了", "证明了",
                "宣称推翻了", "揭示...的矛盾", "挑战了", "颠覆了", "拆解了", "质疑了"]
# "证明...是错误/过时"句式（覆盖"波普尔证明历史决定论是错误的"类）
PROVE_WRONG_TEMPLATES = [
    "{school}证明{anchor}是错误的。",
    "{school}证明{anchor}已经过时。",
    "{school}指出{anchor}不成立。",
    "{school}论证{anchor}是谬误。",
    "{school}揭示了{anchor}的内在矛盾。",
    "{school}表明{anchor}不再适用于当代。",
]
# "宣称/断言"句式（更隐蔽的攻击姿态）
CLAIM_ATTACK_TEMPLATES = [
    "{school}宣称{anchor}存在根本缺陷。",
    "{school}断言{anchor}已经失效。",
    "{school}认为{anchor}只是一种历史局限。",
    "{school}主张{anchor}应当被超越。",
]
ORTHODOX_ANCHORS = [
    "马克思的劳动价值论", "剩余价值理论", "历史唯物主义", "唯物史观",
    "阶级斗争理论", "无产阶级专政", "经济基础决定上层建筑",
    "社会存在决定社会意识", "马克思主义", "辩证唯物主义",
    "剥削理论", "共产主义必然性", "资本积累规律",
]

# type-B: 批判对象被批判（hard_negative，应 pass）——隐式/显式批判
# 句式：{school}的{term}{贬义定性}
DETRACTING_QUALIFIERS = [
    "是文化决定论", "是现象学残余", "是修正主义谬误", "是错误路线",
    "是唯心主义变种", "是资产阶级意识形态", "偏离了唯物史观",
    "不符合马克思主义", "是对马克思主义的歪曲", "丢失了实践-革命维度",
    "遮蔽了阶级斗争", "取消了革命目标", "是抽象人道主义",
    "是结构主义歪曲", "是解构主义游戏", "是后现代虚无主义",
    "背离了无产阶级立场", "陷入了唯心史观", "抹杀了阶级对立",
]
# 显式批判前缀（保证 hard_negative 多样性）
EXPLICIT_CRITIQUE_PREFIX = [
    "{school}的{term}是错误的，", "{school}的{term}是谬误，",
    "必须批判{school}的{term}，", "{school}的{term}必须反对，",
    "{school}的{term}站不住脚，", "我们要揭露{school}的{term}，",
    "{school}的{term}背离了马克思主义，",
]

# deviation: 立场模式变体（覆盖 stance_patterns 各规则）
STANCE_DEVIATION_TEMPLATES = [
    # mutual_determination
    "社会存在与社会意识{verb}，不存在谁决定谁。",
    "经济基础与上层建筑{verb}，二者互为因果。",
    "社会发展由多种因素{verb}，经济并非唯一决定力量。",
]
MUTUAL_VERBS = ["相互决定", "互为决定", "双向决定", "共同决定", "交互决定"]

# deviation: 否定核心原理
DENY_PRINCIPLE_TEMPLATES = [
    "阶级斗争{neg}历史的动力。",
    "无产阶级专政{neg}马克思主义的核心。",
    "自然辩证法{neg}，辩证法只在主体客体之间。",
    "反映论{neg}，认识不是对客观的反映。",
    "劳动价值论{neg}，知识经济已超越它。",
    "计划经济{neg}，是通往奴役之路。",
]
DENY_NEGS = ["已经过时不再是", "不再是", "不是", "已经消亡不是", "应当被否定不是"]

# orthodox: 经典原理表述变体
ORTHODOX_TEMPLATE_FRAGMENTS = [
    ("{anchor}是马克思主义的基本原理。", "anchor"),
    ("坚持{anchor}，反对一切修正主义。", "anchor"),
    ("{anchor}，这是历史唯物主义的科学结论。", "anchor"),
    ("马克思主义认为，{anchor}。", "anchor"),
]
ORTHODOX_ANCHORS_SHORT = [
    "物质决定意识", "社会存在决定社会意识", "经济基础决定上层建筑",
    "实践是检验真理的唯一标准", "生产力决定生产关系",
    "阶级斗争是阶级社会发展的直接动力", "人民群众是历史的创造者",
    "对立统一规律是唯物辩证法的核心", "无产阶级专政是马克思主义核心",
]


def _build_type_a_deviation() -> list[dict]:
    """批判对象攻击正统（deviation）"""
    out = []
    for term, info in CRITICAL_OBJECTS.items():
        for verb in ATTACK_VERBS:
            for anchor in ORTHODOX_ANCHORS:
                # 每个批判对象只生成部分组合，避免过多（控制 ~120 条）
                if random.random() < 0.06:
                    text = f"{info['school']}的{term}{verb}{anchor}。"
                    out.append({"text": text, "label": "deviation", "source": "type_a"})
        # "证明...是错误"句式变体（少量，覆盖波普尔类）
        for tmpl in PROVE_WRONG_TEMPLATES:
            for anchor in ORTHODOX_ANCHORS:
                if random.random() < 0.04:
                    out.append({"text": tmpl.format(school=info["school"], anchor=anchor),
                                "label": "deviation", "source": "type_a_prove"})
        # "宣称/断言"隐蔽攻击句式
        for tmpl in CLAIM_ATTACK_TEMPLATES:
            for anchor in ORTHODOX_ANCHORS:
                if random.random() < 0.04:
                    out.append({"text": tmpl.format(school=info["school"], anchor=anchor),
                                "label": "deviation", "source": "type_a_claim"})
    return out


def _build_type_b_hard_negative() -> list[dict]:
    """批判对象被批判（hard_negative，应 pass）"""
    out = []
    for term, info in CRITICAL_OBJECTS.items():
        for qual in DETRACTING_QUALIFIERS:
            if random.random() < 0.3:
                text = f"{info['school']}的{term}{qual}。"
                out.append({"text": text, "label": "orthodox", "source": "type_b_implicit"})
        # 显式批判变体
        for prefix_tmpl in EXPLICIT_CRITIQUE_PREFIX:
            if random.random() < 0.3:
                prefix = prefix_tmpl.format(school=info["school"], term=term)
                # 后接正统结论
                tail = random.choice(ORTHODOX_ANCHORS_SHORT)
                out.append({"text": f"{prefix}必须坚持{tail}。", "label": "orthodox", "source": "type_b_explicit"})
    return out


def _build_stance_deviation() -> list[dict]:
    """立场模式变体（deviation）"""
    out = []
    for tmpl in STANCE_DEVIATION_TEMPLATES:
        for verb in MUTUAL_VERBS:
            out.append({"text": tmpl.format(verb=verb), "label": "deviation", "source": "stance"})
    for tmpl in DENY_PRINCIPLE_TEMPLATES:
        for neg in DENY_NEGS:
            out.append({"text": tmpl.format(neg=neg), "label": "deviation", "source": "stance"})
    return out


def _build_orthodox_variants() -> list[dict]:
    """经典原理表述变体（orthodox）"""
    out = []
    for tmpl, _ in ORTHODOX_TEMPLATE_FRAGMENTS:
        for anchor in ORTHODOX_ANCHORS_SHORT:
            out.append({"text": tmpl.format(anchor=anchor), "label": "orthodox", "source": "orthodox_variant"})
    return out


# 第 6 阶段具名话术（deviation）— 真实西马/修正主义/反马命题，原话或近原话
NAMED_DEVIATION_TEMPLATES = [
    # 伯恩斯坦修正主义
    "伯恩斯坦主张和平长入社会主义，最终目的是微不足道的，运动就是一切。",
    "伯恩斯坦认为资本主义可以通过民主改良实现社会主义，无需革命。",
    "运动就是一切，最终目的是微不足道的，这是伯恩斯坦的修正主义主张。",
    # 卢卡奇西马
    "卢卡奇的物化理论揭示了资本主义异化的本质，是马克思主义的真正继承。",
    "卢卡奇的总体性方法是把握资本主义整体的根本方法，超越了经济决定论。",
    "卢卡奇正确地恢复了黑格尔辩证法，重新统一了主体与客体。",
    # 葛兰西
    "葛兰西的文化领导权理论表明，意识形态斗争比暴力革命更重要。",
    "葛兰西的市民社会理论证明，西方国家的无产阶级不能走暴力革命道路。",
    # 阿尔都塞
    "阿尔都塞的多元决定论表明，经济基础不是唯一决定上层建筑的力量。",
    "阿尔都塞的认识论断裂证明，早期马克思与晚期马克思是根本对立的。",
    "阿尔都塞正确地指出意识形态没有历史，它永恒存在于一切社会。",
    # 哈贝马斯/法兰克福
    "哈贝马斯的交往行为理论为马克思主义提供了新的规范性基础。",
    "哈贝马斯正确地用生活世界和系统二元论超越了历史唯物主义。",
    "法兰克福学派的批判理论揭示了工具理性的统治，超越了马克思的生产逻辑。",
    # 后现代/后马克思
    "鲍德里亚证明生产之镜是马克思的盲点，劳动价值论已经失效。",
    "利奥塔宣告宏大叙事终结，马克思主义的历史必然性不复存在。",
    "德里达的延异概念解构了唯物辩证法的同一性，揭示了差异的优先性。",
    "福柯的权力话语理论表明，真理只是权力的话语建构。",
    # 资产阶级/反马
    "韦伯证明新教伦理是资本主义的起源，文化决定经济。",
    "波普尔证明历史决定论是错误的，历史没有规律可言。",
    "哈耶克证明计划经济是通往奴役之路，社会主义必然导致极权。",
    "萨特用存在主义补充马克思主义，恢复了人的主体性自由。",
    # 第二国际/考茨基
    "考茨基认为无产阶级只需通过议会民主取得政权，无需暴力革命。",
    "米勒兰主张社会主义者可以参加资产阶级政府，从内部改良资本主义。",
]


def _build_named_deviation() -> list[dict]:
    """第 6 阶段具名话术（deviation）— 真实西马/修正主义/反马命题"""
    return [{"text": t, "label": "deviation", "source": "named_deviation"} for t in NAMED_DEVIATION_TEMPLATES]


# 经典原著命题（orthodox）— 提纲/共产党宣言/国家与革命等正典表述
CLASSIC_ORTHODOX_PROPOSITIONS = [
    # 提纲命题
    "旧唯物主义的立脚点是市民社会，新唯物主义的立脚点则是人类社会或社会的人类。",
    "哲学家们只是用不同的方式解释世界，问题在于改变世界。",
    "环境的改变和人的活动或自我改变的一致，只能被看作是并合理地理解为革命的实践。",
    "人的本质不是单个人所固有的抽象物，在其现实性上，它是一切社会关系的总和。",
    # 共产党宣言
    "至今一切社会的历史都是阶级斗争的历史。",
    "资产阶级首先生产的是它自身的掘墓人，资产阶级的灭亡和无产阶级的胜利同样不可避免。",
    "无产阶级的运动是绝大多数人的、为绝大多数人谋利益的独立的运动。",
    "共产党人可以把自己的理论概括为一句话：消灭私有制。",
    # 国家与革命
    "国家是阶级矛盾不可调和的产物和表现，是阶级统治的机关。",
    "无产阶级专政是向共产主义的过渡阶段，国家在这个阶段逐渐消亡。",
    # 资本论
    "商品是资本主义财富的细胞，包含着资本主义一切矛盾的萌芽。",
    "劳动的二重性决定商品的二因素，这是理解政治经济学的枢纽。",
    "资本的本质不是物，而是在物的外壳下掩盖的人与人之间的生产关系。",
    # 哥达纲领批判
    "在共产主义社会高级阶段，各尽所能，按需分配。",
    "权利决不能超出社会的经济结构以及由经济结构所制约的社会的文化发展。",
    # 辩证法
    "对立统一规律是宇宙的根本规律，是唯物辩证法的实质和核心。",
    "量变是质变的必要准备，质变是量变的必然结果。",
    "否定之否定规律揭示了事物发展的前进性与曲折性的统一。",
    # 认识论
    "实践是检验真理的唯一标准。",
    "认识的辩证运动是从实践到认识，再从认识到实践的循环往复、螺旋上升。",
    "感性认识和理性认识是辩证统一的，理性认识依赖于感性认识。",
]


def _build_classic_orthodox() -> list[dict]:
    """经典原著命题（orthodox）— 正典原文/近原文"""
    return [{"text": t, "label": "orthodox", "source": "classic_orthodox"} for t in CLASSIC_ORTHODOX_PROPOSITIONS]


def _load_llm_samples() -> list[dict]:
    """加载 LLM 合成样本（若 ml/llm_samples.json 存在）

    python -m ml.synthesize_llm 生成；不存在则返回空。
    """
    import json
    p = os.path.join(os.path.dirname(__file__), "llm_samples.json")
    if not os.path.exists(p):
        return []
    with open(p, encoding="utf-8") as f:
        data = json.load(f)
    # 规范化字段
    out = []
    for d in data:
        if "text" in d and "label" in d:
            out.append({"text": d["text"], "label": d["label"],
                        "source": d.get("source", "llm")})
    return out


def build_synthesized_dataset() -> list[dict]:
    """合成全部数据：种子 53 + 模板扩充 + LLM 样本（若存在）"""
    # 种子样本（统一 source 标记）
    seeds = []
    for s in ORTHODOX_SAMPLES:
        seeds.append({"text": s["text"], "label": s["label"], "source": "seed"})
    for s in DEVIATION_SAMPLES:
        seeds.append({"text": s["text"], "label": s["label"], "source": "seed"})
    for s in HARD_NEGATIVE_SAMPLES:
        seeds.append({"text": s["text"], "label": s["label"], "source": "seed"})

    synthesized = (
        _build_type_a_deviation()
        + _build_type_b_hard_negative()
        + _build_stance_deviation()
        + _build_orthodox_variants()
        + _build_named_deviation()
        + _build_classic_orthodox()
    )
    # LLM 样本（配置 key 生成后自动合并）
    llm_samples = _load_llm_samples()
    if llm_samples:
        synthesized = synthesized + llm_samples
    return seeds + synthesized


def dataset_stats(data: list[dict]) -> dict:
    from collections import Counter
    label_c = Counter(d["label"] for d in data)
    source_c = Counter(d["source"] for d in data)
    return {
        "total": len(data),
        "by_label": dict(label_c),
        "by_source": dict(source_c),
    }


if __name__ == "__main__":
    data = build_synthesized_dataset()
    stats = dataset_stats(data)
    print(f"合成数据集: {stats['total']} 条")
    print(f"  按标签: {stats['by_label']}")
    print(f"  按来源: {stats['by_source']}")
    # 验证 4 条 xfailed 的同类变体已生成
    type_a = [d for d in data if d["source"] == "type_a"]
    type_b = [d for d in data if d["source"].startswith("type_b")]
    print(f"\n  type-A (批判对象攻击正统, deviation): {len(type_a)} 条")
    print(f"    示例: {type_a[0]['text'] if type_a else '无'}")
    print(f"  type-B (批判对象被批判, hard_negative): {len(type_b)} 条")
    print(f"    示例: {type_b[0]['text'] if type_b else '无'}")
