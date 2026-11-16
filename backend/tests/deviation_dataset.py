"""防偏离测试集 — SC-003/SC-004/SC-007 用

三类样本（label: orthodox=正/ deviation=负）：
  - orthodox: 正统马哲表述（应 pass，防误拦截 R-1）
  - deviation: 西马/修正主义/后马克思/唯心主义话术（应 block）
  - hard_negative: 困难负样本——批判性引用西马概念的正统文本（应 pass，修 P0-2）

内测样本集，非全量（spec SC-003 目标 500 条 / SC-004 目标 2000 条，生产补全）。
当前规模足以验证拦截率/F1/豁免机制的基线。
"""
from __future__ import annotations

# ============================================================
# 正统样本（应 pass）— 防误拦截
# ============================================================
ORTHODOX_SAMPLES: list[dict] = [
    {"text": "社会存在决定社会意识，经济基础决定上层建筑。", "label": "orthodox"},
    {"text": "实践是检验真理的唯一标准，人应当在实践中证明自己思维的真理性。", "label": "orthodox"},
    {"text": "物质是标志客观实在的哲学范畴，这种客观实在是人通过感觉感知的。", "label": "orthodox"},
    {"text": "人的本质在其现实性上是一切社会关系的总和。", "label": "orthodox"},
    {"text": "对立统一规律是唯物辩证法的实质和核心。", "label": "orthodox"},
    {"text": "阶级斗争是历史唯物主义的灵魂，阶级分析是马克思主义的根本方法。", "label": "orthodox"},
    {"text": "无产阶级专政是马克思主义的核心，是向共产主义过渡的必经阶段。", "label": "orthodox"},
    {"text": "马克思把黑格尔辩证法颠倒过来，变成唯物辩证法。", "label": "orthodox"},
    {"text": "市民社会指与政治国家相对的物质生活关系总和，是资产阶级社会的同义语。", "label": "orthodox"},
    {"text": "认识是主体对客体的能动的反映，包含创造性。", "label": "orthodox"},
    {"text": "生产力决定生产关系，生产关系反作用于生产力。", "label": "orthodox"},
    {"text": "理论必须与实践统一，哲学必须为无产阶级政治服务。", "label": "orthodox"},
    {"text": "商品拜物教是资本主义生产关系在观念上的反映。", "label": "orthodox"},
    {"text": "认识过程是螺旋式上升的反映过程。", "label": "orthodox"},
    {"text": "国家是阶级压迫的工具，是阶级矛盾不可调和的产物。", "label": "orthodox"},
]

# ============================================================
# 偏离样本（应 block）— 西马/修正主义/后马克思/唯心
# ============================================================
DEVIATION_SAMPLES: list[dict] = [
    {"text": "社会存在与社会意识是相互决定的，不存在谁决定谁。", "label": "deviation"},
    {"text": "多种因素共同决定社会发展，经济不是唯一决定因素。", "label": "deviation"},
    {"text": "经济基础不是唯一决定上层建筑的力量。", "label": "deviation"},
    {"text": "意识决定物质，精神创造客观世界。", "label": "deviation"},
    {"text": "阶级是话语建构的产物，是想象的共同体。", "label": "deviation"},
    {"text": "阶级斗争已经过时，不再是历史的动力。", "label": "deviation"},
    {"text": "无产阶级专政已经不必要，只需民主改良即可。", "label": "deviation"},
    {"text": "自然辩证法不存在，辩证法只存在于主体与客体的关系中。", "label": "deviation"},
    {"text": "反映论是机械的，认识不是对客观的反映。", "label": "deviation"},
    {"text": "卢卡奇的物化理论揭示了资本主义异化的本质。", "label": "deviation"},
    {"text": "阿尔都塞的多元决定概念丰富了马克思主义。", "label": "deviation"},
    {"text": "葛兰西的文化领导权理论超越了无产阶级专政的局限。", "label": "deviation"},
    {"text": "哈贝马斯的生活世界理论为马克思主义提供了新基础。", "label": "deviation"},
    {"text": "伯恩斯坦主张和平长入社会主义是合理的。", "label": "deviation"},
    {"text": "运动就是一切，最终目的是微不足道的。", "label": "deviation"},
    {"text": "鲍德里亚的生产之镜批判了马克思的劳动价值论。", "label": "deviation", "bert_only": True},
    {"text": "利奥塔指出宏大叙事已经终结，历史必然性不复存在。", "label": "deviation"},
    {"text": "韦伯的新教伦理解释了资本主义的起源。", "label": "deviation"},
    {"text": "波普尔证明历史决定论是错误的。", "label": "deviation", "bert_only": True},
    {"text": "总体性是把握社会整体的根本方法。", "label": "deviation"},
    {"text": "认识论断裂表明早期马克思与晚期马克思根本对立。", "label": "deviation"},
    {"text": "话语建构塑造了社会现实，超越经济决定论。", "label": "deviation"},
    {"text": "马克思主义只是众多宏大叙事中的一种。", "label": "deviation"},
    {"text": "德勒兹的延异概念解构了唯物辩证法的同一性。", "label": "deviation"},
    {"text": "哈耶克证明了计划经济是通往奴役之路。", "label": "deviation"},
    {"text": "思维先于存在，理念是世界的本原。", "label": "deviation"},
    {"text": "历史已经终结于自由民主制度，阶级对立不复存在。", "label": "deviation"},
    {"text": "马克思的劳动价值论已经过时，知识经济超越了它。", "label": "deviation"},
    {"text": "物化等同于异化，是资本主义的核心病症。", "label": "deviation"},
    {"text": "文化领导权比暴力革命更重要，应放弃专政。", "label": "deviation"},
]

# 规则版可判定的偏离样本（排除 bert_only 困难样本）
DEVIATION_RULE_SAMPLES: list[dict] = [s for s in DEVIATION_SAMPLES if not s.get("bert_only")]

# ============================================================
# 困难负样本（应 pass）— 批判性引用西马概念的正统文本（修 P0-2）
# ============================================================
HARD_NEGATIVE_SAMPLES: list[dict] = [
    {"text": "卢卡奇的物化概念是错误的，它把商品拜物教等同于异化，丢失了实践-革命维度。", "label": "orthodox"},
    {"text": "伯恩斯坦的和平长入社会主义是修正主义谬误，必须批判。", "label": "orthodox"},
    {"text": "葛兰西的文化领导权理论偏离了无产阶级专政，是错误路线。", "label": "orthodox"},
    {"text": "阿尔都塞的多元决定论歪曲了经济基础决定上层建筑的原理。", "label": "orthodox"},
    {"text": "波普尔把马克思主义歪曲为历史决定论，这是对历史唯物主义的攻击。", "label": "orthodox"},
    {"text": "韦伯的新教伦理是文化决定论，无法解释资本主义的全球扩张。", "label": "orthodox"},
    {"text": "哈贝马斯的生活世界概念是现象学残余，不符合唯物史观。", "label": "orthodox"},
    {"text": "鲍德里亚的生产之镜是对劳动价值论的后现代歪曲。", "label": "orthodox"},
]


def all_samples() -> list[dict]:
    """全部样本（orthodox + deviation + hard_negative）"""
    return ORTHODOX_SAMPLES + DEVIATION_SAMPLES + HARD_NEGATIVE_SAMPLES


def deviation_only() -> list[dict]:
    """仅偏离样本（SC-003 黑名单拦截率用）"""
    return DEVIATION_SAMPLES


if __name__ == "__main__":
    s = all_samples()
    print(f"总样本: {len(s)} | 正统: {sum(1 for x in s if x['label']=='orthodox')} | 偏离: {sum(1 for x in s if x['label']=='deviation')}")
