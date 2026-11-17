"""概念关键词表 — 应用/案例题论证评分（P1-②）与错因归类复用。

每个知识节点给出「必须出现的核心术语」与「常见错误表述」，
用于应用题的『概念运用』维度与主观题的正统性判定。术语均取自提纲原文/权威注解。
"""
from __future__ import annotations

# node_id -> {"terms": [必含核心术语], "misconceptions": [常见错误话术]}
CONCEPT_KEYWORDS: dict[str, dict] = {
    "kn_practice": {
        "terms": ["实践", "感性", "对象性", "物质活动", "改造"],
        "misconceptions": ["道德践履", "内心修养", "纯粹理论", "主观精神"],
    },
    "kn_object_activity": {
        "terms": ["对象性活动", "主体", "客体的", "感性的人的活动"],
        "misconceptions": ["直观", "被动反映", "抽象思维"],
    },
    "kn_cishixing": {
        "terms": ["此岸性", "实践", "检验", "真理性", "现实性"],
        "misconceptions": ["经院哲学", "纯理论争论", "离开实践"],
    },
    "kn_rev_practice": {
        "terms": ["革命的实践", "环境", "改变", "自我改变"],
        "misconceptions": ["环境决定论", "教育万能", "英雄史观"],
    },
    "kn_secbasis": {
        "terms": ["世俗基础", "自我分裂", "自我矛盾", "宗教世界"],
        "misconceptions": ["归结为世俗", "停留于解释"],
    },
    "kn_intuition": {
        "terms": ["直观", "实践", "感性活动"],
        "misconceptions": ["抽象思维", "纯直观"],
    },
    "kn_humannature": {
        "terms": ["人的本质", "社会关系", "总和", "现实性"],
        "misconceptions": ["抽象人性", "类本质", "孤立个人"],
    },
    "kn_socialsum": {
        "terms": ["社会关系的总和", "人的本质", "一定社会形式"],
        "misconceptions": ["抽象物", "固有属性", "自然联系"],
    },
    "kn_civilsociety": {
        "terms": ["市民社会", "立脚点", "旧唯物主义"],
        "misconceptions": ["抽象社会", "单个人直观"],
    },
    "kn_humansociety": {
        "terms": ["人类社会", "社会的人类", "社会化了的人类", "立脚点"],
        "misconceptions": ["市民社会", "孤立个人"],
    },
    "kn_standpoint": {
        "terms": ["立脚点", "市民社会", "人的社会"],
        "misconceptions": ["抽象个人", "自然状态"],
    },
    # 《资本论》第一卷（sec_A_08）——应用题判分的概念运用维度
    "kn_a08_commodity": {
        "terms": ["使用价值", "价值", "具体劳动", "抽象劳动", "社会必要劳动时间"],
        "misconceptions": ["价值由效用决定", "价值由供求决定", "劳动本身即价值"],
    },
    "kn_a08_surplus": {
        "terms": ["剩余价值", "必要劳动时间", "剩余劳动时间", "相对剩余价值", "劳动生产力", "机器", "协作", "分工"],
        "misconceptions": ["机器创造价值", "机器是剩余价值的源泉", "利润来自流通", "反对技术进步", "工资是劳动的完整报酬"],
    },
    "kn_a08_accumulation": {
        "terms": ["资本积累", "剩余价值资本化", "资本有机构成", "相对过剩人口", "两极分化", "剥夺者被剥夺"],
        "misconceptions": ["积累使全体成员共同富裕", "资本积累提高工人工资是规律", "人口过剩是自然规律"],
    },
    "kn_changeworld": {
        "terms": ["改变世界", "解释世界", "实践"],
        "misconceptions": ["仅解释世界", "理论至上"],
    },
}


def terms_for(node_ids: list[str]) -> list[str]:
    out: list[str] = []
    for nid in node_ids:
        out.extend(CONCEPT_KEYWORDS.get(nid, {}).get("terms", []))
    # 去重保序
    seen = set()
    res = []
    for t in out:
        if t not in seen:
            seen.add(t)
            res.append(t)
    return res


def misconceptions_for(node_ids: list[str]) -> list[str]:
    out: list[str] = []
    for nid in node_ids:
        out.extend(CONCEPT_KEYWORDS.get(nid, {}).get("misconceptions", []))
    return out
