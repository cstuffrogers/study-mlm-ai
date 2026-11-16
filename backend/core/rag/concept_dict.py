"""概念词典 — 正统术语标准化与概念锁定（L1 层）

重构自原型 retrieval_filter_pipeline.py 的 ConceptDictionary，修复 P1-2：
  原问题：用 term.lower() in text 子串匹配，"存在"会命中"社会存在"、
          "经济"命中"经济社会"，产生大量误命中，削弱 L1 过滤精度。
  修复：按术语长度降序做最长匹配 + 已匹配区间去重（中文），
        英文变体用词边界匹配。无新依赖（不引入 jieba）。
"""
from __future__ import annotations

import re
from typing import List


# 标准术语 → [同义变体, 常见误写, 英文对照]
CONCEPT_MAP: dict[str, list[str]] = {
    "物质": ["客观实在", "matter", "material"],
    "意识": ["思维", "精神", "consciousness"],
    "实践": ["感性活动", "对象性活动", "practical activity"],
    "矛盾": ["对立统一", "contradiction"],
    "社会存在": ["物质生活", "生产方式", "social being"],
    "社会意识": ["精神生活", "social consciousness"],
    "市民社会": ["资产阶级社会", "civil society"],
    "生产力": ["生产能力", "productive forces"],
    "生产关系": ["经济关系", "relations of production"],
    "经济基础": ["经济结构", "economic base"],
    "上层建筑": ["政治法律制度", "superstructure"],
    "真理": ["客观真理", "truth"],
    "认识": ["cognition", "knowledge"],
    "辩证法": ["dialectics", "辩证方法"],
    "唯物史观": ["历史唯物主义", "historical materialism"],
    "唯物论": ["唯物主义", "materialism"],
    "唯心论": ["唯心主义", "idealism"],
    "阶级斗争": ["class struggle", "阶级矛盾"],
    "剩余价值": ["surplus value"],
    "商品": ["commodity", "劳动产品"],
    "价值": ["劳动价值", "value"],
    "使用价值": ["use value", "有用性"],
    "自然辩证法": ["dialectics of nature"],
    "反映论": ["theory of reflection", "摹写论"],
    "商品拜物教": ["reification", "物化"],  # 正统语境：物化特指商品拜物教
    "无产阶级专政": ["dictatorship of the proletariat"],
    "辩证唯物主义": ["dialectical materialism"],

    # ===== D117：群众路线 / 组织领导 / 工人运动 词族 =====
    # 背景：原词典只覆盖 29 个哲学—政治经济学概念，`工会`／`罢工`／`群众路线`／
    # `民主集中制`／`妇女解放` 这些组织领导线的高频词全部抽不出概念，导致
    # 图召回与关键词召回两条路对「党怎样领导工会」「党内斗争怎么做」这类提问
    # 直接返回空（只剩 3-gram 向量浮出泛泛段落）。原有 29 条一字未改。
    # 约定：标准术语本身就是分片 mention 里出现的原文用词（见 book_chunks
    # 的 _GENERIC_TERMS），标准名与 mention 名一致才能让图召回连上。
    "工会": ["职工会", "劳动组合", "赤色工会", "黄色工会", "工会组织"],
    "职工运动": ["工人运动", "劳动运动", "工运"],
    "罢工": ["同盟罢工", "总罢工", "怠工"],
    "工人俱乐部": ["工人夜校", "工人补习学校"],
    "群众路线": ["群众工作", "群众运动", "群众斗争"],
    "群众组织": ["群众团体", "人民团体", "农民协会", "农会"],
    "工农联盟": ["工人与农民的联盟", "工人阶级与农民的联盟"],
    "民主集中制": ["民主制与集中制", "集中制"],
    "党内斗争": ["党内两条路线斗争", "党内思想斗争"],
    "先锋队": ["工人阶级先锋队", "先锋队作用"],
    "统一战线": ["联合战线", "民族统一战线", "人民阵线", "抗日民族统一战线"],
    "整风": ["整风运动", "整顿三风", "整顿学风党风文风"],
    "批评与自我批评": ["自我批评", "批评和自我批评", "批评与自我批评的作风"],
    "调查研究": ["社会调查", "实际调查", "典型调查"],
    "妇女解放": ["妇女运动", "妇女问题"],
    "合作社": ["生产合作社", "消费合作社", "农业合作社", "供销合作社"],
    "白区工作": ["白区", "白区党", "秘密工作"],
    "领导方法": ["工作方法", "一般号召与个别指导"],
    "阶级分析": ["阶级估量", "阶级关系", "各阶级的分析"],
    "组织起来": ["组织合作社", "变工队", "合作社经济"],

    # ===== D119：建党文献（纲领／章程／组织决议）词族 =====
    # 约定同 D117：标准名必须是分片 mention 里真实出现的原文用词。1922 年章程
    # 正文只写「章程」「本章程」，从不用「党章」，故标准名取「章程」，
    # 「党章」作变体（提问侧照样能命中）。
    "党纲": ["党的纲领", "本党纲领", "最高纲领", "最低纲领"],
    "章程": ["党章", "党的章程", "组织章程", "修正章程", "本章程"],
    "党的组织": ["党的组织问题", "组织问题", "党的组织工作", "组织工作"],

    # ===== D120：知识分子／政权形态／文艺／思想改造词族 =====
    # 约定同 D117/D119：标准名必须是分片 mention 里真实出现的原文用词。
    # 1956/1962 两份知识分子报告通篇用「知识分子」，没有「知识阶层」一类改写；
    # 「人民民主专政」是 1956 年讲话的原词（不作「民主专政」归并，避免与
    # 「无产阶级专政」词族混淆）；「文艺」是 1961 年讲话的原词。
    "知识分子": ["知识分子问题", "知识界", "高级知识分子", "脑力劳动者"],
    "人民民主专政": ["民主专政", "人民民主"],
    "文艺": ["文学艺术", "文艺工作", "文艺创作", "文艺界"],
    "自我改造": ["思想改造", "自我教育", "改造思想"],

    # ===== D121：普列汉诺夫前期两篇的唯物史观术语 =====
    # 标准名「个人在历史上的作用」是《个人在历史上的作用问题》的原题用词（正文 8 次），
    # 「杰出人物」是该文批驳「英雄崇拜」时用的原词（3 次）；不做「英雄史观」一类改写。
    "个人在历史上的作用": ["杰出人物", "历史人物", "伟人"],

    # ===== D122：妇女运动文献词族 =====
    # 「妇女解放」「妇女运动」已有（D117 建）。本批只补一个变体「劳动妇女」：
    # 它是向警予、蔡特金两批正文里的原词（42 次），语义上正是「妇女解放要靠
    # 劳动妇女而不是资产阶级女权」的主语；「女工」「女权运动」与之不等价，
    # 只进 book_chunks._GENERIC_TERMS 做图召回 mention，不往概念层拉。
    "劳动妇女": ["劳动妇女运动", "劳动妇女群众"],

    # ===== D123：恽代英文献词族 =====
    # 四个标准名都是分片 mention 里的原文用词：帝国主义 188 次、国民革命 68 次、
    # 苏维埃 112 次、五卅 55 次。变体只取原文里实际出现的同义写法
    # （「帝国主义者」「国民革命运动」「苏维埃政府」「五月三十日」），
    # 不造「反帝」「大革命」一类后世概括词。
    "帝国主义": ["帝国主义者", "帝国主义的压迫", "imperialism"],
    "国民革命": ["国民革命运动", "national revolution"],
    "苏维埃": ["苏维埃政府", "苏维埃政权", "soviet"],
    "五卅运动": ["五卅", "五月三十日"],
}


def _is_ascii(s: str) -> bool:
    return all(ord(c) < 128 for c in s)


class ConceptDictionary:
    """正统术语词典 — L1 概念锁定与术语标准化"""

    def __init__(self) -> None:
        self.concept_map = CONCEPT_MAP
        # 反向索引：变体 → 标准术语
        self.variant_to_standard: dict[str, str] = {}
        for standard, variants in self.concept_map.items():
            self.variant_to_standard[standard] = standard
            for v in variants:
                self.variant_to_standard[v] = standard

        # P1-2 修复：所有术语按长度降序排，做最长匹配
        # 中文术语走区间匹配，英文术语走词边界
        self._cn_terms = sorted(
            {t for t in self.variant_to_standard if not _is_ascii(t)},
            key=len, reverse=True,
        )
        self._en_terms = sorted(
            {t for t in self.variant_to_standard if _is_ascii(t)},
            key=len, reverse=True,
        )

    def extract_concepts(self, text: str) -> List[str]:
        """从文本提取概念（最长匹配，修复 P1-2 误命中）

        中文：按术语长度降序扫描，已匹配区间不再参与后续短术语匹配
              （如"社会存在"匹配后，"存在"不会重复命中同一位置）
        英文：词边界匹配（\\b），避免 economy 命中 economic
        """
        if not text:
            return []
        found: set[str] = set()
        occupied: list[tuple[int, int]] = []  # 已匹配区间

        def _overlaps(s: int, e: int) -> bool:
            return any(s < oe and e > os for os, oe in occupied)

        # 中文最长匹配
        for term in self._cn_terms:
            start = 0
            while True:
                idx = text.find(term, start)
                if idx < 0:
                    break
                if not _overlaps(idx, idx + len(term)):
                    found.add(self.variant_to_standard[term])
                    occupied.append((idx, idx + len(term)))
                start = idx + 1

        # 英文词边界匹配
        text_lower = text.lower()
        for term in self._en_terms:
            if re.search(r"\b" + re.escape(term.lower()) + r"\b", text_lower):
                found.add(self.variant_to_standard[term])

        return list(found)

    def normalize(self, term: str) -> str:
        """将变体术语标准化为标准术语"""
        return self.variant_to_standard.get(term, term)
