#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
正统马哲RAG检索 — 五层过滤漏斗（Five-Layer Filter Funnel）
=============================================================
从原始召回（~1000条）→ 最终Prompt注入（3-5条）
精度目标：事实准确率>99%，正统性偏差率<0.1%

架构：
  用户Query + 选中上下文
      │
      ├──→ 三路混合召回（向量+关键词+图推理）
      │       └── 原始池：~1000条
      │
      └──→ 五层过滤漏斗
              ├── L1 概念锁定（Concept Lock）
              ├── L2 立场校验（Orthodoxy Guard）
              ├── L3 语境匹配（Context Match）
              ├── L4 逻辑兼容（Logic Compatible）
              └── L5 权威排序（Authority Rank）
                      └── 最终池：3-5条

依赖：
  - numpy, scikit-learn（余弦相似度计算）
  - neo4j（图数据库驱动，可选）
  - 实际生产环境需接入Milvus向量库
"""

import os
import re
import numpy as np
from typing import List, Dict, Tuple, Optional, Any
from dataclasses import dataclass, field
from collections import Counter, defaultdict

# ============================================================
# 1. 数据模型定义
# ============================================================

@dataclass
class TextChunk:
    """文本块数据模型"""
    chunk_id: str
    text: str
    source: str                    # 来源著作
    source_location: str         # 具体位置
    layer: int                   # 1=词条, 2=命题, 3=论证, 4=语境
    orthodoxy_tag: str           # "正统" / "非正统" / "待审"
    authority_score: float       # 0.0~1.0
    concept_mentions: List[str] = field(default_factory=list)
    logical_type: Optional[str] = None   # definition/critique/determination等
    adjacent_chunks: List[str] = field(default_factory=list)
    embedding: Optional[np.ndarray] = None  # 向量表示

    def to_dict(self) -> Dict:
        return {
            "chunk_id": self.chunk_id,
            "text": self.text[:100] + "..." if len(self.text) > 100 else self.text,
            "source": self.source,
            "layer": self.layer,
            "orthodoxy_tag": self.orthodoxy_tag,
            "authority_score": self.authority_score,
            "concept_mentions": self.concept_mentions,
        }

@dataclass
class UserQuery:
    """用户查询上下文"""
    raw_text: str                  # 用户选中的原文
    current_work: str              # 当前阅读的著作
    current_chapter: str           # 当前章节
    mode: str                      # explain/dig/debate/connect/test
    user_question: str             # 用户的具体问题

    # 从Query中解析出的关键信息（由NLP预处理）
    key_concepts: List[str] = field(default_factory=list)
    logical_type_hint: Optional[str] = None

@dataclass
class FilterResult:
    """过滤结果"""
    chunk: TextChunk
    filter_scores: Dict[str, float]  # 每层的得分
    final_score: float
    filter_trace: List[str]          # 过滤路径记录

# ============================================================
# 2. 概念词典（Layer 1 术语层）
# ============================================================

class ConceptDictionary:
    """
    正统术语词典
    用于L1概念锁定和术语标准化
    """
    def __init__(self):
        # 核心概念及其变体映射
        self.concept_map = {
            # 标准术语: [同义变体, 常见误写, 英文对照]
            "物质": ["客观实在", "存在", "matter", "material"],
            "意识": ["思维", "精神", "主观", "consciousness"],
            "实践": ["感性活动", "对象性活动", "practical activity", "activity"],
            "矛盾": ["对立统一", "冲突", "contradiction"],
            "社会存在": ["物质生活", "生产方式", "social being"],
            "社会意识": ["意识形态", "精神生活", "social consciousness"],
            "市民社会": ["资产阶级社会", "civil society", "经济社会"],
            "生产力": ["生产能力", "productive forces"],
            "生产关系": ["经济关系", "relations of production"],
            "经济基础": ["经济结构", "economic base"],
            "上层建筑": ["政治法律制度", "意识形态", "superstructure"],
            "真理": ["客观真理", "truth"],
            "认识": ["知识", "cognition", "knowledge"],
            "辩证法": ["dialectics", "辩证方法"],
            "唯物史观": ["历史唯物主义", "historical materialism"],
            "唯物论": ["唯物主义", "materialism"],
            "唯心论": ["唯心主义", "idealism"],
            "阶级斗争": ["class struggle", "阶级矛盾"],
            "剩余价值": ["surplus value", "剥削"],
            "商品": ["commodity", "劳动产品"],
            "价值": ["value", "劳动价值"],
            "使用价值": ["use value", "有用性"],
            "自然辩证法": ["dialectics of nature"],
            "反映论": ["theory of reflection", "摹写论"],
            "物化": ["reification", "商品拜物教"],  # 注意：正统语境下特指商品拜物教
        }

        # 反向索引：变体→标准术语
        self.variant_to_standard = {}
        for standard, variants in self.concept_map.items():
            self.variant_to_standard[standard] = standard
            for v in variants:
                self.variant_to_standard[v] = standard

    def extract_concepts(self, text: str) -> List[str]:
        """从文本中提取包含的概念（精确匹配+模糊匹配）"""
        found = set()
        text_lower = text.lower()

        # 精确匹配
        for standard, variants in self.concept_map.items():
            all_terms = [standard] + variants
            for term in all_terms:
                if term.lower() in text_lower:
                    found.add(standard)
                    break

        return list(found)

    def normalize(self, term: str) -> str:
        """将变体术语标准化"""
        return self.variant_to_standard.get(term, term)

# ============================================================
# 3. 元规则引擎（Layer 5 红线规则）
# ============================================================

class MetaRuleEngine:
    """
    正统性元规则引擎
    用于L2立场校验和生成后拦截
    """
    def __init__(self):
        # 黑名单：非正统概念及其来源
        self.blacklist = {
            "多元决定": {"source": "阿尔都塞", "action": "block", "reason": "反对经济决定论的非正统概念"},
            "话语建构": {"source": "拉克劳/福柯", "action": "block", "reason": "解构主义概念，否定客观实在"},
            "物化": {"source": "卢卡奇", "action": "warn", "reason": "卢卡奇的'物化'指异化，与马克思'商品拜物教'不同"},
            "生活世界": {"source": "哈贝马斯", "action": "block", "reason": "现象学-解释学概念，非唯物史观"},
            "认识论断裂": {"source": "阿尔都塞", "action": "block", "reason": "结构主义马克思主义概念"},
            "生产之镜": {"source": "鲍德里亚", "action": "block", "reason": "后马克思主义概念"},
            "符号政治经济学": {"source": "鲍德里亚", "action": "block", "reason": "后马克思主义概念"},
            "宏大叙事": {"source": "利奥塔", "action": "block", "reason": "后现代概念，否定历史必然性"},
            "解构": {"source": "德里达", "action": "warn", "reason": "后结构主义方法"},
            "延异": {"source": "德里达", "action": "block", "reason": "解构主义核心概念"},
            "游牧思想": {"source": "德勒兹", "action": "block", "reason": "后结构主义概念"},
            "欲望机器": {"source": "德勒兹/瓜塔里", "action": "block", "reason": "反俄狄浦斯概念"},
        }

        # 立场模式识别（正则规则）
        self.stance_patterns = {
            "deny_natural_dialectics": {
                "pattern": r"自然(界)?没有辩证法|否认自然辩证法|自然辩证法不存在",
                "label": "deviation",
                "reason": "否认自然辩证法，属于卢卡奇等非正统立场"
            },
            "mutual_determination": {
                "pattern": r"(相互决定|互为决定|双向决定|决定是相互的)",
                "label": "deviation",
                "reason": "社会存在与社会意识不是相互决定，而是前者决定后者"
            },
            "consciousness_determines": {
                "pattern": r"意识决定(物质|存在|社会)",
                "label": "deviation",
                "reason": "唯心主义立场"
            },
            "reject_reflection": {
                "pattern": r"(反对反映论|反映论是机械的|认识不是反映)",
                "label": "deviation",
                "reason": "反对反映论属于非正统认识论"
            },
            "class_as_discourse": {
                "pattern": r"阶级是(话语|建构|想象的|符号的)",
                "label": "deviation",
                "reason": "阶级是客观经济范畴，非话语建构"
            },
        }

    def check_text(self, text: str) -> Dict[str, Any]:
        """
        检查文本是否包含非正统内容
        返回: {"is_orthodox": bool, "flags": List[Dict], "action": str}
        """
        flags = []

        # 检查黑名单术语
        for term, info in self.blacklist.items():
            if term in text:
                flags.append({
                    "type": "blacklist_term",
                    "term": term,
                    "source": info["source"],
                    "action": info["action"],
                    "reason": info["reason"]
                })

        # 检查立场模式
        for rule_name, rule in self.stance_patterns.items():
            if re.search(rule["pattern"], text):
                flags.append({
                    "type": "stance_pattern",
                    "rule": rule_name,
                    "label": rule["label"],
                    "reason": rule["reason"]
                })

        # 判定动作
        if any(f["action"] == "block" for f in flags if "action" in f):
            action = "block"
        elif any(f["action"] == "warn" for f in flags if "action" in f):
            action = "warn"
        elif any(f.get("label") == "deviation" for f in flags):
            action = "block"
        else:
            action = "pass"

        return {
            "is_orthodox": action == "pass",
            "flags": flags,
            "action": action
        }

# ============================================================
# 4. 五层过滤漏斗（核心引擎）
# ============================================================

class FiveLayerFilter:
    """
    五层过滤漏斗
    每层都是一道精度闸门
    """

    def __init__(self, concept_dict: ConceptDictionary, meta_engine: MetaRuleEngine):
        self.concept_dict = concept_dict
        self.meta_engine = meta_engine

        # 各层权重（用于最终排序）
        self.layer_weights = {
            "l1_concept": 0.20,
            "l2_orthodoxy": 0.30,      # 最重要
            "l3_context": 0.15,
            "l4_logic": 0.15,
            "l5_authority": 0.20,
        }

    # --------------------------------------------------
    # L1: 概念锁定（Concept Lock）
    # --------------------------------------------------
    def layer1_concept_lock(self, query: UserQuery, chunks: List[TextChunk]) -> Tuple[List[TextChunk], Dict]:
        """
        过滤：Query中的核心概念必须在Chunk的concept_mentions中
        或Chunk的text中明确包含相关概念

        原理：消除语义相似但概念无关的文本（如都在谈"决定"但一个是哲学一个是生物学）
        """
        query_concepts = set(query.key_concepts)
        filtered = []

        for chunk in chunks:
            # 获取Chunk中的概念
            chunk_concepts = set(chunk.concept_mentions)
            # 也尝试从text中提取
            extracted = set(self.concept_dict.extract_concepts(chunk.text))
            all_chunk_concepts = chunk_concepts | extracted

            # 计算交集
            overlap = query_concepts & all_chunk_concepts

            if len(overlap) > 0:
                # 计算概念匹配得分
                concept_score = len(overlap) / max(len(query_concepts), 1)
                chunk._l1_score = concept_score
                chunk._l1_trace = f"概念匹配: {overlap}"
                filtered.append(chunk)

        stats = {
            "input": len(chunks),
            "output": len(filtered),
            "drop_reason": "Query核心概念与Chunk无交集",
            "query_concepts": list(query_concepts)
        }
        return filtered, stats

    # --------------------------------------------------
    # L2: 立场校验（Orthodoxy Guard）
    # --------------------------------------------------
    def layer2_orthodoxy_guard(self, query: UserQuery, chunks: List[TextChunk]) -> Tuple[List[TextChunk], Dict]:
        """
        过滤：Chunk的orthodoxy_tag必须为"正统"或"经典原著"
        同时运行元规则引擎检查文本内容

        原理：这是最关键的一层，确保不混入西马、后马文本
        """
        filtered = []
        blocked_samples = []

        for chunk in chunks:
            # 检查标签
            if chunk.orthodoxy_tag not in ["正统", "经典原著", "待审"]:
                blocked_samples.append({"chunk_id": chunk.chunk_id, "reason": f"标签为{chunk.orthodoxy_tag}"})
                continue

            # 运行元规则引擎检查文本内容
            check = self.meta_engine.check_text(chunk.text)
            if check["action"] == "block":
                blocked_samples.append({
                    "chunk_id": chunk.chunk_id,
                    "reason": f"内容检测非正统: {[f['reason'] for f in check['flags']]}"
                })
                continue

            # 计算立场得分
            orthodoxy_score = chunk.authority_score
            if chunk.orthodoxy_tag == "正统":
                orthodoxy_score = max(orthodoxy_score, 0.9)
            elif chunk.orthodoxy_tag == "经典原著":
                orthodoxy_score = 1.0

            chunk._l2_score = orthodoxy_score
            chunk._l2_trace = f"立场校验通过: {chunk.orthodoxy_tag}, 权威分={chunk.authority_score}"
            filtered.append(chunk)

        stats = {
            "input": len(chunks),
            "output": len(filtered),
            "blocked": blocked_samples[:5],  # 只展示前5个
            "drop_reason": "非正统标签或内容检测失败"
        }
        return filtered, stats

    # --------------------------------------------------
    # L3: 语境匹配（Context Match）
    # --------------------------------------------------
    def layer3_context_match(self, query: UserQuery, chunks: List[TextChunk]) -> Tuple[List[TextChunk], Dict]:
        """
        过滤：优先保留与用户当前阅读著作一致或逻辑关联的Chunk
        防止跨文本断章取义

        原理：如果用户在读《提纲》，解释"市民社会"时应优先用《提纲》和《德意志意识形态》的文本，
              而非《资本论》或教科书（虽然教科书也可作为阐释）
        """
        current_work = query.current_work
        filtered = []

        # 定义著作关联度矩阵
        work_relations = {
            "关于费尔巴哈的提纲": {
                "德意志意识形态": 1.0,      # 同一时期，直接关联
                "辩证唯物主义历史唯物主义": 0.7,  # 阐释性关联
                "马克思主义基本原理2023版": 0.6,
                "唯物主义和经验批判主义": 0.4,
                "实践论": 0.5,
                "矛盾论": 0.3,
            },
            "德意志意识形态": {
                "关于费尔巴哈的提纲": 1.0,
                "资本论第一卷": 0.7,
                "辩证唯物主义历史唯物主义": 0.8,
            },
            "实践论": {
                "关于费尔巴哈的提纲": 0.8,
                "唯物主义和经验批判主义": 0.9,
                "马克思主义基本原理2023版": 0.7,
            },
            "矛盾论": {
                "自然辩证法": 0.8,
                "哲学笔记": 0.9,
                "马克思主义基本原理2023版": 0.7,
            },
        }

        for chunk in chunks:
            # 计算语境匹配得分
            if chunk.source == current_work:
                context_score = 1.0
            elif current_work in work_relations and chunk.source in work_relations[current_work]:
                context_score = work_relations[current_work][chunk.source]
            else:
                # 通用关联：教科书与所有原著都有一定关联
                if "教科书" in chunk.source or "基本原理" in chunk.source:
                    context_score = 0.5
                else:
                    context_score = 0.3

            chunk._l3_score = context_score
            chunk._l3_trace = f"语境匹配: 当前著作={current_work}, Chunk来源={chunk.source}, 关联度={context_score}"
            filtered.append(chunk)

        stats = {
            "input": len(chunks),
            "output": len(filtered),
            "drop_reason": "无（本层不降采样，仅打分）"
        }
        return filtered, stats

    # --------------------------------------------------
    # L4: 逻辑兼容（Logic Compatible）
    # --------------------------------------------------
    def layer4_logic_compatible(self, query: UserQuery, chunks: List[TextChunk]) -> Tuple[List[TextChunk], Dict]:
        """
        过滤：Chunk的logical_type必须与Query的逻辑类型兼容

        原理：
        - 如果用户问"什么是物质"（定义型Query），应优先返回definition型Chunk
        - 如果用户问"为什么说旧唯物主义有缺点"（批判型Query），应优先返回critique型Chunk
        - 如果用户问"社会存在与社会意识的关系"（决定型Query），应优先返回determination型Chunk
        """
        query_logic = query.logical_type_hint
        filtered = []

        # 逻辑类型兼容性矩阵
        compatibility = {
            "definition": ["definition", "proposition", "explanation"],
            "critique": ["critique", "comparison", "analysis"],
            "determination": ["determination", "causation", "dialectical_movement"],
            "dialectical_movement": ["dialectical_movement", "development", "negation"],
            "comparison": ["comparison", "critique", "analysis"],
        }

        for chunk in chunks:
            chunk_logic = chunk.logical_type

            if query_logic is None or chunk_logic is None:
                # 如果任一缺失，给予中等分数
                logic_score = 0.6
            elif chunk_logic == query_logic:
                logic_score = 1.0
            elif query_logic in compatibility and chunk_logic in compatibility[query_logic]:
                logic_score = 0.8
            else:
                logic_score = 0.4

            chunk._l4_score = logic_score
            chunk._l4_trace = f"逻辑兼容: Query逻辑={query_logic}, Chunk逻辑={chunk_logic}, 兼容度={logic_score}"
            filtered.append(chunk)

        stats = {
            "input": len(chunks),
            "output": len(filtered),
            "drop_reason": "无（本层不降采样，仅打分）"
        }
        return filtered, stats

    # --------------------------------------------------
    # L5: 权威排序（Authority Rank）
    # --------------------------------------------------
    def layer5_authority_rank(self, query: UserQuery, chunks: List[TextChunk], top_k: int = 5) -> Tuple[List[FilterResult], Dict]:
        """
        排序：综合前四层得分 + authority_score，取Top-K

        排序公式：
        final_score = w1*L1 + w2*L2 + w3*L3 + w4*L4 + w5*L5
        其中L5 = authority_score（来源权威度）
        """
        results = []

        for chunk in chunks:
            l1 = getattr(chunk, '_l1_score', 0.5)
            l2 = getattr(chunk, '_l2_score', 0.5)
            l3 = getattr(chunk, '_l3_score', 0.5)
            l4 = getattr(chunk, '_l4_score', 0.5)
            l5 = chunk.authority_score

            final_score = (
                self.layer_weights["l1_concept"] * l1 +
                self.layer_weights["l2_orthodoxy"] * l2 +
                self.layer_weights["l3_context"] * l3 +
                self.layer_weights["l4_logic"] * l4 +
                self.layer_weights["l5_authority"] * l5
            )

            trace = [
                getattr(chunk, '_l1_trace', ''),
                getattr(chunk, '_l2_trace', ''),
                getattr(chunk, '_l3_trace', ''),
                getattr(chunk, '_l4_trace', ''),
                f"L5权威分: {l5}"
            ]

            results.append(FilterResult(
                chunk=chunk,
                filter_scores={"l1": l1, "l2": l2, "l3": l3, "l4": l4, "l5": l5},
                final_score=final_score,
                filter_trace=trace
            ))

        # 按final_score降序
        results.sort(key=lambda x: x.final_score, reverse=True)
        top_results = results[:top_k]

        stats = {
            "input": len(chunks),
            "output": len(top_results),
            "top_scores": [round(r.final_score, 4) for r in top_results],
            "drop_reason": f"取Top-{top_k}"
        }
        return top_results, stats

    # --------------------------------------------------
    # 完整过滤流程
    # --------------------------------------------------
    def filter(self, query: UserQuery, raw_chunks: List[TextChunk], top_k: int = 5) -> Dict[str, Any]:
        """
        执行完整的五层过滤流程

        Returns:
            {
                "final_results": List[FilterResult],
                "layer_stats": Dict,  # 每层统计
                "total_reduction": str,  # 压缩率
            }
        """
        print("="*60)
        print("五层过滤漏斗启动")
        print("="*60)
        print(f"输入Chunk数: {len(raw_chunks)}")
        print(f"Query: {query.user_question}")
        print(f"当前著作: {query.current_work}")
        print(f"关键概念: {query.key_concepts}")
        print()

        layer_stats = {}

        # L1: 概念锁定
        chunks_l1, stats_l1 = self.layer1_concept_lock(query, raw_chunks)
        layer_stats["L1_ConceptLock"] = stats_l1
        print(f"[L1 概念锁定] {stats_l1['input']} → {stats_l1['output']} | 保留率: {stats_l1['output']/max(stats_l1['input'],1):.1%}")

        # L2: 立场校验
        chunks_l2, stats_l2 = self.layer2_orthodoxy_guard(query, chunks_l1)
        layer_stats["L2_OrthodoxyGuard"] = stats_l2
        print(f"[L2 立场校验] {stats_l2['input']} → {stats_l2['output']} | 保留率: {stats_l2['output']/max(stats_l2['input'],1):.1%}")
        if stats_l2.get("blocked"):
            print(f"  拦截样本: {len(stats_l2['blocked'])}条")

        # L3: 语境匹配
        chunks_l3, stats_l3 = self.layer3_context_match(query, chunks_l2)
        layer_stats["L3_ContextMatch"] = stats_l3
        print(f"[L3 语境匹配] {stats_l3['input']} → {stats_l3['output']} | 打分完成")

        # L4: 逻辑兼容
        chunks_l4, stats_l4 = self.layer4_logic_compatible(query, chunks_l3)
        layer_stats["L4_LogicCompat"] = stats_l4
        print(f"[L4 逻辑兼容] {stats_l4['input']} → {stats_l4['output']} | 打分完成")

        # L5: 权威排序
        final_results, stats_l5 = self.layer5_authority_rank(query, chunks_l4, top_k=top_k)
        layer_stats["L5_AuthorityRank"] = stats_l5
        print(f"[L5 权威排序] {stats_l5['input']} → {stats_l5['output']} | Top-K选取")

        total_reduction = f"{len(raw_chunks)} → {len(final_results)} ({len(final_results)/max(len(raw_chunks),1):.1%})"
        print()
        print(f"总压缩率: {total_reduction}")
        print("="*60)

        return {
            "final_results": final_results,
            "layer_stats": layer_stats,
            "total_reduction": total_reduction
        }

# ============================================================
# 5. 混合检索器（三路召回）
# ============================================================

class HybridRetriever:
    """
    三路混合检索器
    - 向量语义检索（模拟Milvus）
    - 关键词BM25检索（模拟Elasticsearch）
    - 图推理检索（模拟Neo4j）
    """

    def __init__(self, chunks: List[TextChunk], concept_dict: ConceptDictionary):
        self.chunks = chunks
        self.concept_dict = concept_dict

        # 构建倒排索引（关键词→Chunk）
        self.inverted_index = defaultdict(list)
        for chunk in chunks:
            words = set(self._tokenize(chunk.text))
            for word in words:
                self.inverted_index[word].append(chunk.chunk_id)

    def _tokenize(self, text: str) -> List[str]:
        """简单分词（生产环境应使用jieba等）"""
        # 提取2-4字词组
        words = []
        for n in [2, 3, 4]:
            for i in range(len(text) - n + 1):
                words.append(text[i:i+n])
        return words

    def _cosine_similarity(self, a: np.ndarray, b: np.ndarray) -> float:
        """计算余弦相似度"""
        if a is None or b is None:
            return 0.0
        norm_a = np.linalg.norm(a)
        norm_b = np.linalg.norm(b)
        if norm_a == 0 or norm_b == 0:
            return 0.0
        return float(np.dot(a, b) / (norm_a * norm_b))

    def vector_search(self, query_embedding: np.ndarray, top_k: int = 100) -> List[Tuple[TextChunk, float]]:
        """向量语义检索"""
        results = []
        for chunk in self.chunks:
            if chunk.embedding is not None:
                sim = self._cosine_similarity(query_embedding, chunk.embedding)
                if sim > 0.5:  # 阈值过滤
                    results.append((chunk, sim))

        results.sort(key=lambda x: x[1], reverse=True)
        return results[:top_k]

    def keyword_search(self, query_text: str, top_k: int = 100) -> List[Tuple[TextChunk, float]]:
        """关键词BM25检索（简化版）"""
        query_words = set(self._tokenize(query_text))
        chunk_scores = Counter()

        for word in query_words:
            for chunk_id in self.inverted_index.get(word, []):
                chunk_scores[chunk_id] += 1

        # 获取Chunk对象
        chunk_map = {c.chunk_id: c for c in self.chunks}
        results = []
        for chunk_id, score in chunk_scores.most_common(top_k):
            if chunk_id in chunk_map:
                # 归一化得分
                normalized_score = min(score / len(query_words), 1.0)
                results.append((chunk_map[chunk_id], normalized_score))

        return results

    def graph_search(self, query_concepts: List[str], top_k: int = 50) -> List[Tuple[TextChunk, float]]:
        """
        图推理检索
        通过概念等价关系扩展检索
        """
        expanded_concepts = set()
        for concept in query_concepts:
            expanded_concepts.add(concept)
            # 获取等价概念（从词典）
            if concept in self.concept_dict.concept_map:
                expanded_concepts.update(self.concept_dict.concept_map[concept])

        results = []
        for chunk in self.chunks:
            chunk_concepts = set(chunk.concept_mentions)
            overlap = expanded_concepts & chunk_concepts
            if len(overlap) > 0:
                score = len(overlap) / len(expanded_concepts) if expanded_concepts else 0
                results.append((chunk, score))

        results.sort(key=lambda x: x[1], reverse=True)
        return results[:top_k]

    def retrieve(self, query: UserQuery, query_embedding: Optional[np.ndarray] = None, pool_size: int = 200) -> List[TextChunk]:
        """
        三路召回合并
        """
        # 向量召回
        vec_results = self.vector_search(query_embedding, top_k=100) if query_embedding is not None else []

        # 关键词召回
        kw_results = self.keyword_search(query.user_question + " " + query.raw_text, top_k=100)

        # 图召回
        graph_results = self.graph_search(query.key_concepts, top_k=50)

        # 合并去重（加权）
        chunk_scores = defaultdict(float)

        for chunk, score in vec_results:
            chunk_scores[chunk.chunk_id] += score * 0.6  # 向量权重

        for chunk, score in kw_results:
            chunk_scores[chunk.chunk_id] += score * 0.3  # 关键词权重

        for chunk, score in graph_results:
            chunk_scores[chunk.chunk_id] += score * 0.1  # 图权重

        # 排序取Top
        top_chunk_ids = [cid for cid, _ in sorted(chunk_scores.items(), key=lambda x: x[1], reverse=True)[:pool_size]]

        chunk_map = {c.chunk_id: c for c in self.chunks}
        return [chunk_map[cid] for cid in top_chunk_ids if cid in chunk_map]

# ============================================================
# 6. 端到端Pipeline（完整演示）
# ============================================================

def build_demo_corpus() -> List[TextChunk]:
    """构建演示语料库"""

    # 模拟Embedding（实际生产环境从Milvus获取）
    np.random.seed(42)
    def mock_emb():
        return np.random.randn(768).astype(np.float32)

    chunks = [
        # === 正统原著层 ===
        TextChunk(
            chunk_id="CH-ME-TH-001-001",
            text="从前的一切唯物主义的主要缺点是：对对象、现实、感性，只是从客体的或者直观的形式去理解，而不是把它们当作感性的人的活动，当作实践去理解。",
            source="关于费尔巴哈的提纲",
            source_location="第一条",
            layer=2,
            orthodoxy_tag="经典原著",
            authority_score=1.0,
            concept_mentions=["唯物主义", "客体", "直观", "感性", "实践"],
            logical_type="critique",
            embedding=mock_emb()
        ),
        TextChunk(
            chunk_id="CH-ME-TH-001-010",
            text="旧唯物主义的立脚点是市民社会，新唯物主义的立脚点则是人类社会或社会的人类。",
            source="关于费尔巴哈的提纲",
            source_location="第十条",
            layer=2,
            orthodoxy_tag="经典原著",
            authority_score=1.0,
            concept_mentions=["旧唯物主义", "市民社会", "新唯物主义", "人类社会"],
            logical_type="determination",
            embedding=mock_emb()
        ),
        TextChunk(
            chunk_id="CH-ME-DE-001-003",
            text="不是人们的意识决定人们的存在，相反，是人们的社会存在决定人们的意识。",
            source="德意志意识形态",
            source_location="第一章",
            layer=2,
            orthodoxy_tag="经典原著",
            authority_score=1.0,
            concept_mentions=["意识", "社会存在"],
            logical_type="determination",
            embedding=mock_emb()
        ),
        TextChunk(
            chunk_id="CH-ME-DE-001-008",
            text="市民社会这一名称始终标志着直接从生产和交往中发展起来的社会组织，这种社会组织在一切时代都构成国家的基础以及任何其他的观念的上层建筑的基础。",
            source="德意志意识形态",
            source_location="第一章",
            layer=2,
            orthodoxy_tag="经典原著",
            authority_score=1.0,
            concept_mentions=["市民社会", "生产", "交往", "国家", "上层建筑"],
            logical_type="definition",
            embedding=mock_emb()
        ),

        # === 教科书阐释层 ===
        TextChunk(
            chunk_id="CH-AISHI-1961-003-015",
            text="马克思在《提纲》第十条中指出，旧唯物主义的立脚点是市民社会。这就是说，旧唯物主义不自觉地站在了资产阶级意识形态的立场上，因为他们把抽象的、孤立的个人作为出发点，而这个个人正是资本主义市民社会的产物。",
            source="辩证唯物主义历史唯物主义",
            source_location="第三章",
            layer=4,
            orthodoxy_tag="正统",
            authority_score=0.95,
            concept_mentions=["旧唯物主义", "市民社会", "资产阶级", "意识形态", "个人"],
            logical_type="explanation",
            embedding=mock_emb()
        ),
        TextChunk(
            chunk_id="CH-TEXTBOOK-2023-001-003",
            text="实践是人类能动地改造世界的社会性的物质活动。实践具有直接现实性、自觉能动性和社会历史性三个基本特征。",
            source="马克思主义基本原理2023版",
            source_location="第一章",
            layer=4,
            orthodoxy_tag="正统",
            authority_score=1.0,
            concept_mentions=["实践", "物质活动", "直接现实性", "自觉能动性", "社会历史性"],
            logical_type="definition",
            embedding=mock_emb()
        ),
        TextChunk(
            chunk_id="CH-TEXTBOOK-2023-002-010",
            text="社会存在也称社会物质生活条件，是社会生活的物质方面，主要包括自然地理环境、人口因素和物质生产方式。",
            source="马克思主义基本原理2023版",
            source_location="第二章",
            layer=4,
            orthodoxy_tag="正统",
            authority_score=1.0,
            concept_mentions=["社会存在", "物质生活条件", "生产方式"],
            logical_type="definition",
            embedding=mock_emb()
        ),

        # === 列宁著作层 ===
        TextChunk(
            chunk_id="CH-LENIN-AEM-004-012",
            text="物质是标志客观实在的哲学范畴，这种客观实在是人通过感觉感知的，它不依赖于我们的感觉而存在，为我们的感觉所复写、摄影、反映。",
            source="唯物主义和经验批判主义",
            source_location="第四章",
            layer=2,
            orthodoxy_tag="经典原著",
            authority_score=1.0,
            concept_mentions=["物质", "客观实在", "感觉", "反映"],
            logical_type="definition",
            embedding=mock_emb()
        ),
        TextChunk(
            chunk_id="CH-LENIN-PN-001-005",
            text="辩证法也就是认识论。辩证法研究自在之物如何转化为为我之物。",
            source="哲学笔记",
            source_location="辩证法",
            layer=2,
            orthodoxy_tag="经典原著",
            authority_score=1.0,
            concept_mentions=["辩证法", "认识论", "自在之物"],
            logical_type="dialectical_movement",
            embedding=mock_emb()
        ),

        # === 毛泽东著作层 ===
        TextChunk(
            chunk_id="CH-MAO-SJ-002-001",
            text="实践、认识、再实践、再认识，这种形式，循环往复以至无穷，而实践和认识之每一循环的内容，都比较地进到了高一级的程度。",
            source="实践论",
            source_location="全文",
            layer=2,
            orthodoxy_tag="经典原著",
            authority_score=1.0,
            concept_mentions=["实践", "认识", "辩证运动"],
            logical_type="dialectical_movement",
            embedding=mock_emb()
        ),
        TextChunk(
            chunk_id="CH-MAO-MD-001-003",
            text="矛盾的普遍性和矛盾的特殊性的关系，就是矛盾的共性和个性的关系。其共性是矛盾存在于一切过程中，并贯串于一切过程的始终。",
            source="矛盾论",
            source_location="第三节",
            layer=2,
            orthodoxy_tag="经典原著",
            authority_score=1.0,
            concept_mentions=["矛盾", "普遍性", "特殊性", "共性", "个性"],
            logical_type="definition",
            embedding=mock_emb()
        ),

        # === 干扰项：非正统（应被过滤掉）===
        TextChunk(
            chunk_id="CH-LUK-HC-001-001",
            text="自然辩证法不存在，辩证法只存在于主体与客体的相互作用中。如果承认自然辩证法，就是把辩证法变成了脱离人的客观规律，退回到了机械唯物主义。",
            source="历史与阶级意识",
            source_location="什么是正统马克思主义",
            layer=2,
            orthodoxy_tag="非正统",
            authority_score=0.0,
            concept_mentions=["自然辩证法", "主体", "客体", "机械唯物主义"],
            logical_type="negation",
            embedding=mock_emb()
        ),
        TextChunk(
            chunk_id="CH-ALTHUS-PM-001-002",
            text="历史不是由经济决定的线性过程，而是由政治、意识形态、理论等多种因素复杂地共同决定的。经济基础决定上层建筑是一种经济本质主义。",
            source="保卫马克思",
            source_location="第一章",
            layer=2,
            orthodoxy_tag="非正统",
            authority_score=0.0,
            concept_mentions=["经济", "政治", "意识形态", "上层建筑"],
            logical_type="negation",
            embedding=mock_emb()
        ),
        TextChunk(
            chunk_id="CH-HABERMAS-TC-001-001",
            text="交往行为理论取代了生产力决定论，社会进化的动力是交往合理性而非物质生产的发展。",
            source="交往行为理论",
            source_location="导论",
            layer=4,
            orthodoxy_tag="非正统",
            authority_score=0.0,
            concept_mentions=["交往行为", "生产力", "社会进化"],
            logical_type="negation",
            embedding=mock_emb()
        ),

        # === 干扰项：语义相关但概念不对（应被L1过滤）===
        TextChunk(
            chunk_id="CH-BIOLOGY-001",
            text="生物的物质代谢过程决定了细胞的能量转换效率。意识活动虽然复杂，但其物质基础是神经元的电化学反应。",
            source="普通生物学",
            source_location="第三章",
            layer=4,
            orthodoxy_tag="待审",
            authority_score=0.3,
            concept_mentions=["物质", "意识", "细胞"],
            logical_type="explanation",
            embedding=mock_emb()
        ),
        TextChunk(
            chunk_id="CH-ECONOMICS-001",
            text="市民社会的经济行为遵循理性选择原则。个体在市场中通过效用最大化实现社会福利。",
            source="微观经济学原理",
            source_location="第二章",
            layer=4,
            orthodoxy_tag="待审",
            authority_score=0.2,
            concept_mentions=["市民社会", "经济", "市场"],
            logical_type="explanation",
            embedding=mock_emb()
        ),
    ]

    return chunks


def demo_pipeline():
    """端到端演示"""
    print("\n" + "="*70)
    print("正统马哲RAG检索系统 — 端到端演示")
    print("="*70 + "\n")

    # 1. 初始化组件
    concept_dict = ConceptDictionary()
    meta_engine = MetaRuleEngine()
    retriever = HybridRetriever(build_demo_corpus(), concept_dict)
    filter_funnel = FiveLayerFilter(concept_dict, meta_engine)

    # 2. 构建用户Query
    query = UserQuery(
        raw_text="旧唯物主义的立脚点是市民社会",
        current_work="关于费尔巴哈的提纲",
        current_chapter="全文",
        mode="explain",
        user_question="为什么说旧唯物主义的立脚点是市民社会？",
        key_concepts=["市民社会", "旧唯物主义", "立脚点"],
        logical_type_hint="explanation"
    )

    # 3. 混合检索（模拟向量+关键词+图）
    print("【Step 1】三路混合检索")
    print("-" * 40)
    raw_pool = retriever.retrieve(query, query_embedding=np.random.randn(768).astype(np.float32), pool_size=200)
    print(f"召回池大小: {len(raw_pool)}条")
    print(f"来源分布: {Counter([c.source for c in raw_pool])}")
    print()

    # 4. 五层过滤
    result = filter_funnel.filter(query, raw_pool, top_k=5)

    # 5. 展示最终结果
    print("\n【Step 2】最终注入Prompt的Top-5 Chunk")
    print("-" * 40)
    for i, fr in enumerate(result["final_results"], 1):
        print(f"\n[Rank {i}] 得分: {fr.final_score:.4f}")
        print(f"  ID: {fr.chunk.chunk_id}")
        print(f"  来源: {fr.chunk.source} | {fr.chunk.source_location}")
        print(f"  标签: {fr.chunk.orthodoxy_tag} | 权威分: {fr.chunk.authority_score}")
        print(f"  文本: {fr.chunk.text[:80]}...")
        print(f"  各层得分: L1={fr.filter_scores['l1']:.2f} L2={fr.filter_scores['l2']:.2f} "
              f"L3={fr.filter_scores['l3']:.2f} L4={fr.filter_scores['l4']:.2f} L5={fr.filter_scores['l5']:.2f}")

    # 6. 展示被拦截的内容
    print("\n\n【Step 3】被拦截的非正统内容（安全审计）")
    print("-" * 40)
    blocked = result["layer_stats"]["L2_OrthodoxyGuard"].get("blocked", [])
    if blocked:
        for b in blocked:
            print(f"  ❌ {b['chunk_id']}: {b['reason']}")
    else:
        print("  无（本演示中所有非正统内容已在召回前被排除）")

    # 7. 展示过滤统计
    print("\n\n【Step 4】过滤漏斗统计")
    print("-" * 40)
    for layer_name, stats in result["layer_stats"].items():
        print(f"  {layer_name}: {stats['input']} → {stats['output']} ({stats['output']/max(stats['input'],1):.0%})")

    print(f"\n总压缩率: {result['total_reduction']}")
    print("="*70)

    return result


def demo_edge_cases():
    """边界案例测试"""
    print("\n\n" + "="*70)
    print("边界案例测试")
    print("="*70)

    concept_dict = ConceptDictionary()
    meta_engine = MetaRuleEngine()

    test_cases = [
        "物质是标志客观实在的哲学范畴",  # 应通过
        "辩证法只存在于主体与客体的相互作用中",  # 应拦截
        "历史是由政治、经济、意识形态等多种因素共同决定的",  # 应拦截
        "阶级是话语建构的结果",  # 应拦截
        "实践是人类能动地改造世界的物质活动",  # 应通过
    ]

    for text in test_cases:
        result = meta_engine.check_text(text)
        status = "✅ 通过" if result["is_orthodox"] else "❌ 拦截"
        print(f"\n{status} | {text[:40]}...")
        if not result["is_orthodox"]:
            for flag in result["flags"]:
                print(f"    → {flag['type']}: {flag.get('reason', '')}")


if __name__ == "__main__":
    # 运行端到端演示
    demo_pipeline()

    # 运行边界案例测试
    demo_edge_cases()

    print("\n\n演示完成。生产环境请接入：")
    print("  - Milvus/Pinecone（向量库）")
    print("  - Neo4j（图数据库）")
    print("  - 实际Embedding模型（替代mock_emb）")
    print("  - 大规模标注语料（替代demo_corpus）")
