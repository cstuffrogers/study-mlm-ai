"""D107：把题目溯源从「导读锚」升级为真实原文分片（只做逐字可证的升级）。

背景
----
审计发现三类溯源问题：
  1) 3 个章节的 local_work《关于费尔巴哈的提纲》根本不在库内 —— 本轮已补入库
     （`0-关于费尔巴哈的提纲.txt`，35 个分片，id 前缀 CH-MLTH-）。
  2) 早期知识点/题目用的 `CH-ME-TH-{条}-{层}` 是历史占位 id，库内从来没有这些分片
     —— 已按「条号 → 真实分片」重新指向 CH-MLTH-###。
  3) 其余题目溯源写成 `GUIDE-<section_id>`（锚在导读，不是原著正文）。

本脚本只处理第 3 类，且**只做可证的升级**：只有当题干的解析（explanation）或题干里
存在 ≥14 个连续汉字、且该片段逐字出现在本章主文的某个真实分片里时，才把
`source_chunk_id` 换成该分片 id，并把证据写进报告。凑不够逐字证据的题目保持
`GUIDE-<section_id>` 不动 —— 宁可标「导读溯源」，也不拿关键词检索结果冒充权威溯源
（`content/source_links.py` 的同一条红线）。

用法：
    python scripts/upgrade_guide_links_d107.py            # 只出报告
    python scripts/upgrade_guide_links_d107.py --write    # 落库（改 quiz_bank/*.json）
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parent.parent / "backend"
sys.path.insert(0, str(BACKEND))
sys.stdout.reconfigure(encoding="utf-8")

from content.book_chunks import all_book_chunks  # noqa: E402
from content.routes import SECTIONS  # noqa: E402

BANK = BACKEND / "content" / "quiz_bank"
REPORT = BACKEND.parent / ".local" / "d107_link_upgrade.json"
MIN_FRAG = 14  # 逐字证据最短长度（汉字）；再短就容易撞上通用表述

_WS = re.compile(r"\s+")


def norm(text: str) -> str:
    return _WS.sub("", text or "")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true", help="写回 quiz_bank/*.json")
    args = ap.parse_args()

    chunks = all_book_chunks()
    by_book: dict[str, list[dict]] = {}
    for c in chunks:
        by_book.setdefault(c["source"], []).append(c)
    alias_book = {norm(c["source"]): c["source"] for c in chunks}
    secs = {s["id"]: s for s in SECTIONS}

    upgraded: list[dict] = []
    keep_guide: list[dict] = []
    dead: list[dict] = []
    real_ids = {c["id"] for c in chunks}

    for path in sorted(BANK.glob("*.json")):
        doc = json.loads(path.read_text(encoding="utf-8"))
        default_sid = doc.get("section_id")
        touched = False
        for it in doc.get("items", []):
            cid = str(it.get("source_chunk_id") or "")
            sid = it.get("section_id") or default_sid
            it.setdefault("section_id", sid)
            if not cid.startswith("GUIDE-"):
                if cid and cid not in real_ids:
                    dead.append({"bank": path.name, "id": it["id"], "chunk": cid})
                continue
            sec = secs.get(sid) or {}
            book = alias_book.get(norm(sec.get("local_work", "")))
            cands = by_book.get(book, []) if book else []
            # 证据片段：解析优先（更接近原文），其次题干；只取 ≥MIN_FRAG 连续汉字
            texts = [norm(it.get("explanation", "")), norm(it.get("stem", ""))]
            hit = None
            for q in texts:
                for i in range(0, max(1, len(q) - MIN_FRAG + 1)):
                    frag = q[i : i + MIN_FRAG]
                    if len(frag) < MIN_FRAG:
                        break
                    for c in cands:
                        if frag in norm(c["text"]):
                            hit = (c, frag, i)
                            break
                    if hit:
                        break
                if hit:
                    break
            if hit:
                c, frag, i = hit
                # 证据不能只是著作名/标题行（如「《家庭、私有制和国家的起源》」）
                if norm(frag) in norm(c["source"]) or norm(frag) in norm(sec.get("title", "")):
                    hit = None
            if hit:
                upgraded.append({
                    "bank": path.name, "id": it["id"], "section_id": sid,
                    "from": cid, "to": c["id"], "work": c["source"],
                    "evidence": frag,
                })
                it["source_chunk_id"] = c["id"]
                touched = True
            else:
                keep_guide.append({"bank": path.name, "id": it["id"], "section_id": sid, "chunk": cid})
        if touched and args.write:
            path.write_text(
                json.dumps(doc, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8", newline="\n",
            )

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps({
        "upgraded": upgraded, "kept_guide": keep_guide, "dead": dead,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")

    print(f"逐字可证 → 升级为真实分片：{len(upgraded)} 条")
    print(f"无逐字证据 → 保留 GUIDE- 导读锚：{len(keep_guide)} 条")
    print(f"死链（CH- 但库内不存在）：{len(dead)} 条 {dead if dead else ''}")
    print(f"报告：{REPORT}")
    if not args.write:
        print("\n（只出报告；加 --write 才写回 quiz_bank/*.json）")
    return 0 if not dead else 1


if __name__ == "__main__":
    raise SystemExit(main())
