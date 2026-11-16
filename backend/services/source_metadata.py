"""AI 输出清洗与结构化相关原文元数据。

模型输出里的 `[CH-...]` / `[GUIDE-...]` 编码只用于服务端事实一致性校验：
  · 校验阶段保留原文（triple_check 要识别 cited_chunks）；
  · 发给客户端 / 写入对话历史 / 进入下一轮会话历史前全部剥离；
  · 编码转为结构化 `source_chunks`，界面只显示一个「相关原文」按钮。

不改变权威/相关口径：RAG 召回卡片是相关原文片段，不冒充逐条权威溯源。
"""
from __future__ import annotations

import re
from typing import Iterable

# 与后端校验 / 前端兼容解析保持同一套编码规则。
CITATION_RE = re.compile(r"\[((?:CH|GUIDE)-[A-Za-z0-9-]+)\]")


def strip_citations(text: str | None) -> str:
    """去掉 AI 正文里的内部编码，并收拾剥离后留下的多余空格。"""
    if not text:
        return ""
    cleaned = CITATION_RE.sub("", text)
    cleaned = re.sub(r"[ \t]{2,}", " ", cleaned)
    cleaned = re.sub(r" *\n *", "\n", cleaned)
    return cleaned.strip()


def cited_chunk_ids(text: str | None) -> list[str]:
    """从模型原始输出提取编码，去重保序。"""
    if not text:
        return []
    seen: set[str] = set()
    out: list[str] = []
    for m in CITATION_RE.finditer(text):
        cid = m.group(1)
        if cid not in seen:
            seen.add(cid)
            out.append(cid)
    return out


def merge_source_chunks(*groups: Iterable) -> list[dict]:
    """合并模型显式引用与 RAG 召回卡片，生成结构化相关原文元数据。

    每条只含数据层所需字段：`chunk_id` / `source` / `source_location` / `kind`。
    `kind=related` 明确表示关键词/RAG 检索片段，不是逐条权威溯源。
    """
    by_id: dict[str, dict] = {}
    for group in groups:
        for item in group or ():
            if isinstance(item, str):
                cid = item.strip()
                if not cid:
                    continue
                by_id.setdefault(cid, {"chunk_id": cid, "kind": "related"})
                continue
            if not isinstance(item, dict):
                continue
            cid = str(item.get("chunk_id") or item.get("id") or "").strip()
            if not cid:
                continue
            row = by_id.setdefault(cid, {
                "chunk_id": cid,
                "source": str(item.get("source") or ""),
                "source_location": str(item.get("source_location") or item.get("location") or ""),
                "kind": str(item.get("kind") or "related"),
            })
            if not row.get("source") and item.get("source"):
                row["source"] = str(item["source"])
            loc = item.get("source_location") or item.get("location")
            if not row.get("source_location") and loc:
                row["source_location"] = str(loc)
            if not row.get("kind") and item.get("kind"):
                row["kind"] = str(item["kind"])
    return list(by_id.values())
