"""知识点树 + 依赖图（内容层，P0=提纲章节 sec_A_02）

12 个知识点对齐 theses_concepts.CONCEPTS，挂到提纲段落，并给出 DAG 依赖关系。
用于：掌握度关联、薄弱点排序（依赖出度）、门控阻塞章节计算。

KnowledgeGraphService（services/knowledge_graph_service.py）负责查询：
  - prereq_closure(node)         前置闭包
  - dependents_count(node)       被多少后续节点依赖（出度）
  - blocking_sections(node)      阻塞的后续章节数（P0 简化：同章内下游节点覆盖的其他章节）
"""
from __future__ import annotations

# node: id / name / section_id / paragraph / ability_dim / exam_weight / source_chunk_id
KNOWLEDGE_NODES: list[dict] = [
    {"id": "kn_practice", "name": "实践", "section_id": "sec_A_02", "paragraph": "th1",
     "ability_dim": "epistemology", "exam_weight": 1.00, "source_chunk_id": "CH-MLTH-001"},
    {"id": "kn_object_activity", "name": "对象性活动", "section_id": "sec_A_02", "paragraph": "th1",
     "ability_dim": "materialism", "exam_weight": 0.70, "source_chunk_id": "CH-MLTH-001"},
    {"id": "kn_cishixing", "name": "思维的此岸性", "section_id": "sec_A_02", "paragraph": "th2",
     "ability_dim": "epistemology", "exam_weight": 0.75, "source_chunk_id": "CH-MLTH-002"},
    {"id": "kn_rev_practice", "name": "革命的实践", "section_id": "sec_A_02", "paragraph": "th3",
     "ability_dim": "historical_materialism", "exam_weight": 0.85, "source_chunk_id": "CH-MLTH-004"},
    {"id": "kn_secbasis", "name": "世俗基础", "section_id": "sec_A_02", "paragraph": "th4",
     "ability_dim": "historical_materialism", "exam_weight": 0.70, "source_chunk_id": "CH-MLTH-004"},
    {"id": "kn_intuition", "name": "直观", "section_id": "sec_A_02", "paragraph": "th5",
     "ability_dim": "materialism", "exam_weight": 0.65, "source_chunk_id": "CH-MLTH-005"},
    {"id": "kn_humannature", "name": "人的本质", "section_id": "sec_A_02", "paragraph": "th6",
     "ability_dim": "historical_materialism", "exam_weight": 0.95, "source_chunk_id": "CH-MLTH-007"},
    {"id": "kn_socialsum", "name": "社会关系的总和", "section_id": "sec_A_02", "paragraph": "th6",
     "ability_dim": "historical_materialism", "exam_weight": 0.90, "source_chunk_id": "CH-MLTH-005"},
    {"id": "kn_civilsociety", "name": "市民社会", "section_id": "sec_A_02", "paragraph": "th10",
     "ability_dim": "historical_materialism", "exam_weight": 0.80, "source_chunk_id": "CH-MLTH-009"},
    {"id": "kn_humansociety", "name": "人类社会", "section_id": "sec_A_02", "paragraph": "th10",
     "ability_dim": "historical_materialism", "exam_weight": 0.70, "source_chunk_id": "CH-MLTH-009"},
    {"id": "kn_standpoint", "name": "立脚点", "section_id": "sec_A_02", "paragraph": "th10",
     "ability_dim": "historical_materialism", "exam_weight": 0.65, "source_chunk_id": "CH-MLTH-009"},
    {"id": "kn_changeworld", "name": "改变世界", "section_id": "sec_A_02", "paragraph": "th11",
     "ability_dim": "historical_materialism", "exam_weight": 0.90, "source_chunk_id": "CH-MLTH-010"},
]

# 依赖边：node -> prereq（node 依赖 prereq）。必须为 DAG。
PREREQUISITES: list[tuple[str, str]] = [
    ("kn_object_activity", "kn_practice"),
    ("kn_cishixing", "kn_practice"),
    ("kn_rev_practice", "kn_practice"),
    ("kn_intuition", "kn_practice"),
    ("kn_secbasis", "kn_practice"),
    ("kn_humannature", "kn_practice"),
    ("kn_socialsum", "kn_humannature"),
    ("kn_civilsociety", "kn_socialsum"),
    ("kn_humansociety", "kn_civilsociety"),
    ("kn_standpoint", "kn_civilsociety"),
    ("kn_changeworld", "kn_rev_practice"),
    ("kn_changeworld", "kn_standpoint"),
]


def nodes_by_section(section_id: str) -> list[dict]:
    return [n for n in KNOWLEDGE_NODES if n["section_id"] == section_id]


def get_node(node_id: str) -> dict | None:
    for n in KNOWLEDGE_NODES:
        if n["id"] == node_id:
            return n
    return None


# ---------------------------------------------------------------------------
# 全路线知识点合并（P0 内容补齐）
# 在既有 sec_A_02 的 12 个节点基础上，追加 content/chapter_content.py 定义的其余
# 15 个章节的知识点与依赖边，使三条路线都能走「学习→测验→掌握→门控→推荐」闭环。
# 保留 sec_A_02 原有 id / 段落 / source_chunk_id 不动（其题库已锚定这些节点）。
# ---------------------------------------------------------------------------
def _merge_route_nodes() -> None:
    try:
        from content.chapter_content import build_route_nodes
    except Exception:
        return
    extra_nodes, extra_edges = build_route_nodes()
    existing_ids = {n["id"] for n in KNOWLEDGE_NODES}
    for n in extra_nodes:
        if n["id"] not in existing_ids:
            KNOWLEDGE_NODES.append(n)
            existing_ids.add(n["id"])
    existing_edges = set(PREREQUISITES)
    for e in extra_edges:
        if e not in existing_edges:
            PREREQUISITES.append(e)
            existing_edges.add(e)


_merge_route_nodes()
