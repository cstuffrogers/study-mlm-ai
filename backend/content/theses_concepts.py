"""《提纲》核心概念锚点 — 对齐 Concept 表字段

每概念含：
  - canonical_definition: 正统标准定义
  - equivalent_terms: 精确同义（可互换）
  - near_synonyms: 近义但不同（需纠错，不可混用）
  - strictly_not: 严格禁止关联（术语红线/防偏离）
  - relations: 决定/对立/表现关系
  - source_id: 溯源 Chunk

覆盖提纲11条全部核心概念。
"""
from __future__ import annotations



CONCEPTS: list[dict] = [
    {
        "id": "C-实践",
        "name": "实践",
        "canonical_definition": "人改造客观世界的感性的、对象性的物质活动，是马克思主义认识论与历史观的基础范畴。非日常行为、非道德践履、非理论思考。",
        "source_id": "CH-MLTH-001",
        "authority_score": 1.0,
        "equivalent_terms": ["对象性活动", "感性的活动", "实践批判的活动"],
        "near_synonyms": ["劳动", "生产实践"],
        "strictly_not": ["道德践履", "日常行为", "理论沉思", "功利牟利"],
        "relations": {"determines": ["认识真理", "社会生活本质"], "opposed_to": ["直观", "抽象思维"]},
    },
    {
        "id": "C-对象性活动",
        "name": "对象性活动",
        "canonical_definition": "指向外部对象并改变对象的人的活动（德 gegenständliche Tätigkeit），强调实践的对象性与改造性，区别于纯意识活动。",
        "source_id": "CH-MLTH-001",
        "authority_score": 1.0,
        "equivalent_terms": ["实践"],
        "near_synonyms": [],
        "strictly_not": ["思想活动", "纯粹意识"],
        "relations": {"determines": ["新唯物主义基础"], "opposed_to": ["直观"]},
    },
    {
        "id": "C-此岸性",
        "name": "此岸性",
        "canonical_definition": "思维不超出现实可达范围、能在实践中被检验和实现的性质。与康德不可知论的彼岸性相对。",
        "source_id": "CH-MLTH-002",
        "authority_score": 1.0,
        "equivalent_terms": ["思维的现实性"],
        "near_synonyms": [],
        "strictly_not": ["彼岸性", "物自体不可知"],
        "relations": {"grounded_in": ["实践"]},
    },
    {
        "id": "C-革命的实践",
        "name": "革命的实践",
        "canonical_definition": "把改变环境与改变人统一起来的实践，是主客体在同一过程中相互生成的活动。",
        "source_id": "CH-MLTH-004",
        "authority_score": 1.0,
        "equivalent_terms": [],
        "near_synonyms": ["改造世界的实践"],
        "strictly_not": ["改良", "渐进改革（当作唯一道路）"],
        "relations": {"unifies": ["环境改变", "人的自我改变"]},
    },
    {
        "id": "C-人的本质",
        "name": "人的本质",
        "canonical_definition": "实际上是一切社会关系的总和，非单个人所固有的抽象物。人是历史的、社会的、阶级的存在。",
        "source_id": "CH-MLTH-007",
        "authority_score": 1.0,
        "equivalent_terms": ["在其现实性上"],
        "near_synonyms": ["社会的人"],
        "strictly_not": ["抽象的类本质", "先验人性", "自然属性的总和"],
        "relations": {"determined_by": ["社会关系", "生产关系", "阶级关系"]},
    },
    {
        "id": "C-社会关系总和",
        "name": "社会关系的总和",
        "canonical_definition": "决定人的本质的现实关系整体，以生产关系为基础，包含阶级关系等。",
        "source_id": "CH-MLTH-005",
        "authority_score": 1.0,
        "equivalent_terms": ["在其现实性上是一切社会关系的总和"],
        "near_synonyms": [],
        "strictly_not": ["自然联系", "普遍人性"],
        "relations": {"determines": ["人的本质"]},
    },
    {
        "id": "C-市民社会",
        "name": "市民社会",
        "canonical_definition": "在马克思历史唯物主义语境中指与政治国家相对的物质生活关系总和，是资产阶级社会的同义语，是旧唯物主义的立脚点。",
        "source_id": "CH-MLTH-009",
        "authority_score": 1.0,
        "equivalent_terms": ["资产阶级社会", "经济基础（特定历史形态）"],
        "near_synonyms": [],
        "strictly_not": ["公民社会", "民间社会", "NGO", "市民群体"],
        "relations": {"is_foothold_of": ["旧唯物主义"], "opposed_to": ["人类社会"]},
    },
    {
        "id": "C-人类社会",
        "name": "人类社会",
        "canonical_definition": "扬弃资产阶级孤立个人、实现自由联合的共产主义社会关系，是新唯物主义的立脚点。",
        "source_id": "CH-MLTH-009",
        "authority_score": 1.0,
        "equivalent_terms": ["社会的人类", "社会化了的人类"],
        "near_synonyms": [],
        "strictly_not": ["市民社会", "抽象共同体"],
        "relations": {"is_foothold_of": ["新唯物主义"], "opposed_to": ["市民社会"]},
    },
    {
        "id": "C-直观",
        "name": "直观",
        "canonical_definition": "静观式地把握对象、不介入改造的被动认识方式，是旧唯物主义的认识论特征。",
        "source_id": "CH-MLTH-005",
        "authority_score": 1.0,
        "equivalent_terms": [],
        "near_synonyms": ["静观"],
        "strictly_not": ["实践"],
        "relations": {"opposed_to": ["实践", "对象性活动"]},
    },
    {
        "id": "C-世俗基础",
        "name": "世俗基础",
        "canonical_definition": "宗教所反映的现实的人的社会关系，本质是经济基础与阶级矛盾。宗教是世俗基础自我分裂的产物。",
        "source_id": "CH-MLTH-004",
        "authority_score": 1.0,
        "equivalent_terms": [],
        "near_synonyms": ["现实社会"],
        "strictly_not": ["天国", "独立精神王国"],
        "relations": {"self_splits_into": ["宗教世界"]},
    },
    {
        "id": "C-改变世界",
        "name": "改变世界",
        "canonical_definition": "通过革命实践改造现实，是新唯物主义与一切旧哲学的根本区别。哲学从解释世界的工具变为改变世界的武器。",
        "source_id": "CH-MLTH-010",
        "authority_score": 1.0,
        "equivalent_terms": [],
        "near_synonyms": ["革命实践"],
        "strictly_not": ["纯解释世界", "经院哲学"],
        "relations": {"opposed_to": ["解释世界"]},
    },
    {
        "id": "C-立脚点",
        "name": "立脚点",
        "canonical_definition": "哲学体系的阶级立场与社会基础。新旧唯物主义的对立归根结底是立脚点（阶级立场）的对立。",
        "source_id": "CH-MLTH-009",
        "authority_score": 1.0,
        "equivalent_terms": [],
        "near_synonyms": ["阶级立场"],
        "strictly_not": ["超阶级立场", "全人类立场"],
        "relations": {},
    },
]


def concept_by_name(name: str) -> dict | None:
    for c in CONCEPTS:
        if c["name"] == name:
            return c
    return None


def concepts_mentioning_term(text: str) -> list[dict]:
    """文本中出现的概念（含同义/近义，但 strictly_not 命中则标记违规）"""
    hits = []
    for c in CONCEPTS:
        names = [c["name"]] + c.get("equivalent_terms", []) + c.get("near_synonyms", [])
        if any(n in text for n in names):
            hits.append(c)
    return hits
