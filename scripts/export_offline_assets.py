#!/usr/bin/env python
"""导出「单机版」离线数据包 → frontend/assets/offline/

单机 Android App 不带 Python 后端，因此把「内容层」在后端一次性编译成静态资产：
  meta.json          路线 / 章节 / 知识点(含前置后继) / 著作清单 / 阶段标签
  sections/<id>.json 每章导读 + 知识点 + 原文链接 + 延伸阅读（与 /guide 接口同构）
  quiz.json          题库（含 answer/explanation，离线判分必需）
  chunks.json        全部原文分片（id/source/location/text/layer/authority/orthodoxy）
  manifest.json      版本、生成时间、条目数、体积

只在内容变更后重跑：python scripts/export_offline_assets.py
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BACKEND = ROOT / "backend"
OUT = ROOT / "frontend" / "assets" / "offline"
sys.path.insert(0, str(BACKEND))

# 后端依赖环境变量默认值（不影响导出结果）
os.environ.setdefault("LEARNING_DB_MODE", "memory")
os.environ.setdefault("AUTO_CREATE_TABLES", "0")


def content_fingerprint(meta: dict) -> str:
    """内容层指纹：著作名集合 + 分片总数的 sha1 前 12 位。

    用来判断 `frontend/assets/offline/` 是否落后于 `sources/texts/` + `BOOKS`：
    后端测试 `test_d114_offline_assets_fresh.py` 会重算这个值与 manifest 比对，
    入库新书却忘了重新导出时直接报错，而不是让 App 悄悄少几十部书。
    """
    import hashlib

    names = sorted({str(w.get("work", "")) for w in meta.get("works", [])})
    seed = "\n".join(names) + "|" + str(meta.get("chunk_count", 0))
    return hashlib.sha1(seed.encode("utf-8")).hexdigest()[:12]


def _dump(path: Path, obj) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
    path.write_text(data, encoding="utf-8")
    return len(data.encode("utf-8"))


def _work_authors() -> dict[str, str]:
    """著作 → 作者。

    作者只在「已登记的正文文件」里带（BOOKS 表），但原文分片的 source 可能比
    BOOKS 更细（《提纲》的原文由 theses_raw 提供、注释/解析层来自统编教材）。
    因此这里显式补齐这 3 个内存来源的署名，其余一律以 BOOKS 为准；
    查不到的留空字符串，前端显示「作者未标注」——不猜、不编。
    """
    from content.book_chunks import BOOKS
    from content.theses_raw import WORK_TITLE

    mapping = {b["work"]: b.get("author", "") for b in BOOKS}
    mapping.setdefault(WORK_TITLE, "马克思")
    # 三层正典注释/解析：艾思奇主编的统编教材与《提纲》注疏
    mapping.setdefault("正典注释（艾思奇·统编教材）", "艾思奇 等（统编教材）")
    mapping.setdefault("正典解析（统编教材）", "统编教材")
    return mapping


def build_meta() -> dict:
    from content.routes import ROUTES, SECTIONS, STAGE_LABELS, get_section
    from content.knowledge_graph import KNOWLEDGE_NODES, PREREQUISITES
    from services import content_provider as cp

    authors = _work_authors()
    prereq: dict[str, list[str]] = {}
    dependents: dict[str, list[str]] = {}
    for node, dep in PREREQUISITES:
        prereq.setdefault(node, []).append(dep)
        dependents.setdefault(dep, []).append(node)

    nodes = []
    for n in KNOWLEDGE_NODES:
        nodes.append({
            **n,
            "prerequisites": prereq.get(n["id"], []),
            "dependents": dependents.get(n["id"], []),
        })

    # 章节：补 stage_label / has_bank / unlock_threshold，供离线端直接渲染
    bank_sections = set()
    for f in sorted((BACKEND / "content" / "quiz_bank").glob("*.json")):
        d = json.loads(f.read_text(encoding="utf-8"))
        if d.get("section_id"):
            bank_sections.add(d["section_id"])
        for it in d.get("items", []):
            if it.get("section_id"):
                bank_sections.add(it["section_id"])

    sections = []
    for sec in SECTIONS:
        cur = get_section(sec["id"]) or {}
        sections.append({
            **sec,
            "stage_label": STAGE_LABELS.get(sec["stage_no"], ""),
            "has_bank": sec["id"] in bank_sections,
            "unlock_threshold": cur.get("unlock_threshold", 0.8),
        })

    from content.book_chunks import BOOKS as _BOOKS
    _book_names = {str(b.get("work", "")) for b in _BOOKS}
    works = []
    for w in cp.works():
        items = cp.chunks_by_work(w)
        works.append({
            "work": w,
            "author": authors.get(w, ""),
            "chunk_count": len(items),
            "first_chunk_id": items[0]["id"] if items else "",
            # 与 BOOKS 对齐的书才是「著作」；《提纲》原文由 theses_raw 提供、
            # 统编教材的注释/解析层也在库里，但它们不是独立著作、没有路线入口。
            "is_book": w in _book_names,
        })

    return {
        "version": 1,
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "routes": ROUTES,
        "stage_labels": {str(k): v for k, v in STAGE_LABELS.items()},
        "sections": sections,
        "nodes": nodes,
        "works": works,
        "chunk_count": len(cp.all_chunks()),
        "source": "backend/content（原著正文库 + 导读 + 知识点图）",
    }


# 读者可见文案里不允许出现的内部术语（章节 id、书单文档、入库/镜像口吻、分片编码…）
JARGON = re.compile(
    r"(路径\.txt|学习顺序\d?\.md|书籍\.md|扩展读物\.md|专读\.md|\.md|\.txt"
    r"|sec_[A-C]_\d\d|route_[A-C]|路线\s*[ABC]|[ABC]\s?路线"
    r"|(?<![A-Za-z])D\d{2,3}(?![0-9])"
    r"|CH-[A-Z]|GUIDE-|kn_[a-z]|q_[a-c]\d"
    r"|源表|未落地|镜像|本机|知识库|入库|分片"
    r"|PDF|OCR|HTML|D 盘|TRIM|import_mirror|manifest|blacklist|TODO|占位)"
)
DATA_KEYS = {
    "id", "chunk_id", "source_chunk_id", "first_chunk_id", "paragraph_id",
    "local_work", "work_short", "section_id", "node_id", "route_id", "source",
    "dependents", "prerequisites", "foundation_ref", "source_id",
    "source_location", "work", "link", "kind",
}


def _jargon_hits(obj, path=""):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in DATA_KEYS:
                continue
            yield from _jargon_hits(v, f"{path}/{k}")
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            yield from _jargon_hits(v, f"{path}[{i}]")
    elif isinstance(obj, str):
        m = JARGON.search(obj)
        if m:
            yield f"{path}: 「{m.group(0)}」 ← {obj[:60]}"


def assert_reader_copy_clean(payloads) -> None:
    """导出前置门禁：读者可见文案不得含开发期内部术语。

    这些字符串会原样出现在手机端导读 / 延伸阅读 / 题库解析里，
    一旦混入「路线 B」「路径.txt」「sec_C_03」之类字样就会误导读者。
    """
    bad = []
    for name, payload in payloads:
        bad += [f"{name} {h}" for h in _jargon_hits(payload)]
    if bad:
        raise SystemExit(
            "导出中止：读者可见文案含内部术语 → " + " ｜ ".join(bad[:40]))


def build_section_payloads() -> tuple[dict, int]:
    from content.routes import SECTIONS, get_section
    from content.chapter_content import guide_for, nodes_for_section
    from content.reading_extensions import extensions_for, blacklist
    from content.source_links import chapter_source, node_links, block_links

    total = 0
    _check = []
    for sec in SECTIONS:
        sid = sec["id"]
        guide = guide_for(sid) or {}
        nodes = nodes_for_section(sid) or []
        cur = get_section(sid) or {}
        local_work = (cur.get("local_work") or "").strip()
        payload = {
            "section_id": sid,
            "route_id": sec["route_id"],
            "section_title": cur.get("title"),
            "section_work": cur.get("work"),
            "local_work": cur.get("local_work"),
            "work_short": cur.get("work_short"),
            "guide": guide,
            "nodes": nodes,
            "source_links": {
                "chapter": chapter_source(cur),
                "nodes": node_links(nodes, local_work),
                "blocks": block_links(guide, local_work),
            },
            "extensions": extensions_for(sid),
            "extensions_blacklist": blacklist(),
        }
        _check.append((f"sections/{sid}.json", payload))
        total += _dump(OUT / "sections" / f"{sid}.json", payload)
        print(f"  · {sid} guide/nodes/links ok")
    assert_reader_copy_clean(_check)
    return {}, total


def build_quiz() -> int:
    sections: dict[str, list] = {}
    for f in sorted((BACKEND / "content" / "quiz_bank").glob("*.json")):
        d = json.loads(f.read_text(encoding="utf-8"))
        default_sid = d.get("section_id")
        for it in d.get("items", []):
            sid = it.get("section_id") or default_sid
            if not sid:
                continue
            sections.setdefault(sid, []).append(it)
    return _dump(OUT / "quiz.json", {"sections": sections})


def build_chunks() -> int:
    from services import content_provider as cp

    keep = ("id", "text", "source", "source_location", "layer",
            "authority_score", "orthodoxy_tag", "paragraph_id", "logical_type")
    rows = [{k: c.get(k) for k in keep if c.get(k) is not None} for c in cp.all_chunks()]
    return _dump(OUT / "chunks.json", rows)


def build_work_sections() -> int:
    """书 → 章节 的反向索引：某部原著在学习路线里出现在哪些章。

    阅读器顶部「学习路线」入口用它回答「这本书该在哪一章学」；
    原著浏览书卡也用它显示「N 章」，避免 94 部只挂在延伸阅读里的书
    变成找不到路径的孤儿。
    结构：{work: [{section_id, route_id, section_title, kind, main_work, chapter_title}]}
    """
    from content.routes import SECTIONS, get_section
    from content.reading_extensions import READING_EXTENSIONS

    index: dict[str, list[dict]] = {}

    def add(work: str, row: dict) -> None:
        if not work:
            return
        bucket = index.setdefault(work, [])
        if any(r["section_id"] == row["section_id"] and r["kind"] == row["kind"]
               for r in bucket):
            return
        bucket.append(row)

    for sec in SECTIONS:
        sid = sec["id"]
        cur = get_section(sid) or {}
        common = {
            "section_id": sid,
            "route_id": sec["route_id"],
            "section_title": cur.get("title") or "",
            "main_work": cur.get("local_work") or "",
        }
        add((cur.get("local_work") or "").strip(), {**common, "kind": "main",
                                                     "chapter_title": cur.get("title") or ""})
        for it in READING_EXTENSIONS.get(sid, []):
            add((it.get("local_work") or "").strip(), {**common, "kind": "ext",
                                                        "chapter_title": it.get("title") or ""})

    # 顺序：主线章节在前，再按路线/章节排序，前端直接展示
    for work, rows in index.items():
        rows.sort(key=lambda r: (0 if r["kind"] == "main" else 1, r["route_id"], r["section_id"]))
    return _dump(OUT / "work_sections.json", index)


def build_knowledge() -> int:
    """离线问答/防偏离所需的语义资产：概念锚点、苏格拉底问题池、提纲原文、立场规则。"""
    from content.theses_concepts import CONCEPTS
    from content.theses_questions import SOCRATIC_QUESTIONS
    from content.theses_raw import all_paragraphs
    from content.concept_keywords import CONCEPT_KEYWORDS
    from core.guard.orthodoxy import CRITICAL_OBJECTS, STANCE_PATTERNS
    from core.config import (MASTERY_THRESHOLDS, MASTERY_WEIGHTS, UNLOCK_THRESHOLD,
                             QUIZ_SIZE_MIN, QUIZ_SIZE_MAX, REVIEW_BASE_INTERVAL_DAYS,
                             REVIEW_MAX_INTERVAL_DAYS, REVIEW_HALF_LIFE_MIN_DAYS,
                             REVIEW_HALF_LIFE_MAX_DAYS, REVIEW_DUE_RETENTION,
                             REVIEW_GAIN, REVIEW_REGRESS, CALIBRATION_CONFIDENCE_MAP,
                             CALIBRATION_OVERCONFIDENT_GAP, INTERLEAVE_MIX_RATIO,
                             INTERLEAVE_SIZE)

    payload = {
        "concepts": CONCEPTS,
        "node_terms": CONCEPT_KEYWORDS,
        "questions": SOCRATIC_QUESTIONS,
        "theses": all_paragraphs(),
        "guard": {
            "critical_objects": CRITICAL_OBJECTS,
            "stance_patterns": STANCE_PATTERNS,
            # 「偏离关键词」只允许放**本身即构成偏移表述**的限定词组，
            # 绝不能放「资产阶级」这类马列核心术语 —— 否则正确表述
            # （"推翻资产阶级统治"）与批判性表述都会被误判为立场偏移。
            # 题库判错也复用了这份名单，放近义词会导致正确选项被判「立场偏移」。
            # 与 backend/core/guard/orthodoxy.py 的 STANCE_PATTERNS 保持同一口径：
            # 只承认修饰过的断言式表述。
            "deviation_keywords": ["市场社会主义", "宪法爱国", "交往理性",
                                   "单向度", "去革命"],
        },
        "config": {
            "unlock_threshold": UNLOCK_THRESHOLD,
            "quiz_size_min": QUIZ_SIZE_MIN,
            "quiz_size_max": QUIZ_SIZE_MAX,
            "mastery_thresholds": MASTERY_THRESHOLDS,
            "mastery_weights": MASTERY_WEIGHTS,
            "review": {
                "base_interval_days": REVIEW_BASE_INTERVAL_DAYS,
                "max_interval_days": REVIEW_MAX_INTERVAL_DAYS,
                "half_life_min_days": REVIEW_HALF_LIFE_MIN_DAYS,
                "half_life_max_days": REVIEW_HALF_LIFE_MAX_DAYS,
                "due_retention": REVIEW_DUE_RETENTION,
                "gain": REVIEW_GAIN,
                "regress": REVIEW_REGRESS,
            },
            "calibration": {
                "confidence_map": CALIBRATION_CONFIDENCE_MAP,
                "overconfident_gap": CALIBRATION_OVERCONFIDENT_GAP,
            },
            "interleave": {"mix_ratio": INTERLEAVE_MIX_RATIO, "size": INTERLEAVE_SIZE},
        },
    }
    return _dump(OUT / "knowledge.json", payload)


def main() -> None:
    t0 = time.perf_counter()
    print("[1/6] meta ...")
    meta = build_meta()
    size_meta = _dump(OUT / "meta.json", meta)
    print(f"      routes={len(meta['routes'])} sections={len(meta['sections'])} "
          f"nodes={len(meta['nodes'])} works={len(meta['works'])}")

    print("[2/6] section guides ...")
    _, size_sections = build_section_payloads()

    print("[3/6] quiz bank ...")
    size_quiz = build_quiz()

    print("[4/6] chunks ...")
    size_chunks = build_chunks()

    print("[5/6] knowledge (concepts / guard / config) ...")
    size_knowledge = build_knowledge()

    print("[6/6] work → sections index ...")
    size_index = build_work_sections()

    manifest = {
        "version": 1,
        "generated_at": meta["generated_at"],
        "routes": len(meta["routes"]),
        "sections": len(meta["sections"]),
        "nodes": len(meta["nodes"]),
        "works": len(meta["works"]),
        "chunks": meta["chunk_count"],
        "fingerprint": content_fingerprint(meta),
        "bytes": {
            "meta": size_meta, "sections": size_sections,
            "quiz": size_quiz, "chunks": size_chunks, "knowledge": size_knowledge,
            "work_sections": size_index,
            "total": (size_meta + size_sections + size_quiz + size_chunks
                      + size_knowledge + size_index),
        },
    }
    _dump(OUT / "manifest.json", manifest)
    print(f"done in {time.perf_counter() - t0:.1f}s → {OUT}")
    print(f"      total {manifest['bytes']['total'] / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
