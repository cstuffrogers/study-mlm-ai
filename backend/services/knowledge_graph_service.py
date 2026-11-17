"""KnowledgeGraphService — 知识点依赖图查询（P0 基于 content 模块，DAG 校验）

提供：
  - prereq_closure(node_id)          前置闭包（传递依赖的所有 prereq）
  - dependents(node_id)              直接依赖它的下游节点
  - dependents_count(node_id)        依赖出度（用于薄弱点排序 D4）
  - blocking_sections(node_id)       被其前置闭包阻塞的后续章节数（P0：跨章节下游覆盖数）
  - check_dag()                      环检测
后续接 Neo4j 时仅替换本实现，接口不变（research D3）。
"""
from __future__ import annotations

from content.knowledge_graph import KNOWLEDGE_NODES, PREREQUISITES


class KnowledgeGraphService:
    def __init__(self) -> None:
        self.nodes = {n["id"]: n for n in KNOWLEDGE_NODES}
        # prereq_map: node -> [prereq...]
        self.prereq_map: dict[str, list[str]] = {nid: [] for nid in self.nodes}
        # dependents_map: prereq -> [node...]
        self.dependents_map: dict[str, list[str]] = {nid: [] for nid in self.nodes}
        for node_id, prereq_id in PREREQUISITES:
            self.prereq_map.setdefault(node_id, []).append(prereq_id)
            self.dependents_map.setdefault(prereq_id, []).append(node_id)

    # -- 前置闭包（传递依赖）
    def prereq_closure(self, node_id: str) -> set[str]:
        seen: set[str] = set()
        stack = list(self.prereq_map.get(node_id, []))
        while stack:
            cur = stack.pop()
            if cur in seen:
                continue
            seen.add(cur)
            stack.extend(self.prereq_map.get(cur, []))
        return seen

    def dependents(self, node_id: str) -> list[str]:
        return list(self.dependents_map.get(node_id, []))

    def dependents_count(self, node_id: str) -> int:
        """依赖出度：直接+传递依赖它的下游节点数（含跨章节）"""
        seen: set[str] = set()
        stack = list(self.dependents_map.get(node_id, []))
        while stack:
            cur = stack.pop()
            if cur in seen:
                continue
            seen.add(cur)
            stack.extend(self.dependents_map.get(cur, []))
        return len(seen)

    def blocking_sections(self, node_id: str) -> int:
        """该节点未掌握会阻塞多少『其他章节』的下游知识点（P0 数据均在同章，多为 0-1）"""
        node = self.nodes.get(node_id)
        if not node:
            return 0
        sections: set[str] = set()
        for dep in self._all_dependents(node_id):
            d = self.nodes.get(dep)
            if d and d["section_id"] != node["section_id"]:
                sections.add(d["section_id"])
        return len(sections)

    def _all_dependents(self, node_id: str) -> set[str]:
        seen: set[str] = set()
        stack = list(self.dependents_map.get(node_id, []))
        while stack:
            cur = stack.pop()
            if cur in seen:
                continue
            seen.add(cur)
            stack.extend(self.dependents_map.get(cur, []))
        return seen

    def check_dag(self) -> bool:
        """拓扑序检测环"""
        visited: dict[str, int] = {}

        def dfs(n: str) -> bool:
            if visited.get(n) == 1:
                return False  # 环
            if visited.get(n) == 2:
                return True
            visited[n] = 1
            for p in self.prereq_map.get(n, []):
                if not dfs(p):
                    return False
            visited[n] = 2
            return True

        return all(dfs(n) for n in list(self.nodes))


def get_kg() -> KnowledgeGraphService:
    return _KG


_KG = KnowledgeGraphService()
