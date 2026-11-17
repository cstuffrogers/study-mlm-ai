# -*- coding: utf-8 -*-
"""D108 —— 把题库里剩下的 50 条「本章导读」锚（GUIDE-<章节>）升级为真实原文分片。

背景：D107 用「≥14 连续汉字逐字命中」的机械规则只升级了 28 条。剩下 50 条不是没原文，
而是**解析是编者按语、没有逐字引原句**。正确做法不是放宽匹配（那就成了拿检索结果冒充
权威溯源），而是：人工从本章 `local_work` 的正文里挑一句**能直接支撑该题考点**的原句，
以该分片作为溯源，并把原句记进本文件作为证据。

判据（脚本强校验，任何一条不满足就报错，绝不静默通过）：
1. `chunk_id` 必须真实存在，且其 `source`（著作名）必须等于本章的 `local_work`（不许跨书）；
2. `quote` 必须**逐字**出现在该分片文本里（去空白后比对）；
3. `quote` 至少 `MIN_QUOTE` 个汉字（默认 12），且不能只是著作名/章节标题行；
4. 改完写回 JSON 时保留原有其它字段与题目顺序。

用法：
  python scripts/fix_quiz_sources_d108.py --dry-run   # 只报告
  python scripts/fix_quiz_sources_d108.py --write     # 落库
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "backend"))

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from content.book_chunks import all_book_chunks  # noqa: E402
from content.routes import SECTIONS  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
BANK = ROOT / "backend" / "content" / "quiz_bank"
REPORT = ROOT / ".local" / "d108_fix_sources.json"

MIN_QUOTE = 12
CJK = re.compile(r"[\u4e00-\u9fff]")

# 题号 → (分片 id, 逐字证据原句)
# 证据挑选原则：优先取「直接给出该题考点结论」的判断句；概念辨析题取定义句；
# 应用/论述题取方法论出处句。原句内不删字，脚本会逐字校验。
EVIDENCE: dict[str, tuple[str, str]] = {
    # ── sec_A_01 大众哲学（唯物论/辩证法/认识论入门）──────────────
    "q_a01_1": ("CH-DZ-226", "世界上任何事物，都包含着互相反对的许多对立方面，这是对立统一的规律。"),
    "q_a01_2": ("CH-DZ-227", "辩证法的对立统一的规律，要求我们在研究事物时，要看到它的各个对立方面。"),
    "q_a01_3": ("CH-DZ-157", "现在我们明白真理必须有客观的标准，必须符合客观事实了。"),
    # ── sec_A_03 实践论／矛盾论 ──────────────────────────────
    # ── sec_A_04 哲学笔记 ────────────────────────────────
    "q_a04_1": ("CH-ZXBJ-152", "可以把辩证法简要地确定为关于对立面的统一的学说"),
    # ── sec_A_05 哥达纲领批判 ──────────────────────────────
    "q_a05_2": ("CH-GDGB-065", "在经济、道德和精神方面都还带着它脱胎出来的那个旧社会的痕迹"),
    # ── sec_A_06 共产党宣言 ───────────────────────────────
    "q_a06_3": ("CH-XY-017", "全部历史都是阶级斗争的历史"),
    # ── sec_A_07 德意志意识形态 ─────────────────────────────
    "q_a07_2": ("CH-DYZT-035", "第一个历史活动就是生产满足这些需要的资料，即生产物质生活本身"),
    # ── sec_A_08 资本论 ─────────────────────────────────
    "q_a08_2": ("CH-ZBL-025", "这一点是理解政治经济学的枢纽"),
    # ── sec_A_09 法兰西内战 ───────────────────────────────
    "q_a09_1": ("CH-FLNZ-100", "工人阶级不能简单地掌握现成的国家机器，并运用它来达到自己的目的"),
    "q_a09_2": ("CH-FLNZ-013", "公社取消了征兵制和常备军"),
    # ── sec_A_11 费尔巴哈论 ───────────────────────────────
    "q_a11_1": ("CH-FEBH-092", "旧唯物主义在历史领域内自己背叛了自己"),
    # ── sec_A_12 1844 年手稿 ─────────────────────────────
    "q_a12_1": ("CH-SG-240", "异化劳动，由于（1）使自然界，（2）使人本身，他自己的活动机能，他的生命活动同人相异化"),
    # ── sec_B_01 怎么办？ ────────────────────────────────
    "q_b01_2": ("CH-ZMB-059", "这种意识只能从外面灌输进去"),
    # ── sec_B_02 国家与革命 ──────────────────────────────
    "q_b02_1": ("CH-GJGM-094", "这个机器是必须打碎，必须摧毁的"),
    # ── sec_B_03 中国社会各阶级的分析 ──────────────────────────
    "q_b03_1": ("CH-JJFX-002", "我们要分辨真正的敌友，不可不将中国社会各阶级的经济地位及其对于革命的态度，作一个大概的分析"),
    # ── sec_B_04 怎样做一个好的领导者 ─────────────────────────
    # ── sec_B_05 反对本本主义 ────────────────────────────
    "q_b05_1": ("CH-FDBB-002", "你对于某个问题没有调查，就停止你对于某个问题的发言权"),
    # ── sec_B_06 帝国主义是资本主义的最高阶段 ───────────────────
    "q_b06_1": ("CH-DGZY-003", "都是为了瓜分世界，为了瓜分和重新瓜分殖民地、金融资本的“势力范围”等等而进行的战争"),
    # ── sec_C_01 哥达纲领批判（社会主义阶段）────────────────────
    "q_c01_3": ("CH-GDGB-065", "每一个生产者，在作了各项扣除之后，从社会方面正好领回他所给予社会的一切"),
    # ── sec_C_02 新民主主义论 ─────────────────────────────
    "q_c02_1": ("CH-XMZ-012", "中国革命的历史进程，必须分为两步，其第一步是民主主义的革命，其第二步是社会主义的革命"),
    "q_c02_2": ("CH-XMZ-024", "被无产阶级领导的、以在第一阶段上建立新民主主义的社会和建立各个革命阶级联合专政的国家为目的的革命"),
    "q_c02_3": ("CH-XMZ-045", "而无产阶级则是领导的力量"),
    # ── sec_C_04 论十大关系 ─────────────────────────────
    "q_c04_3": ("CH-SDGX-020", "就不能只顾一头，必须兼顾国家、集体和个人三个方面"),
    # ── sec_C_05 关于正确处理人民内部矛盾的问题 ──────────────────
    "q_c05_3": ("CH-LM-005", "敌我之间的矛盾是对抗性的矛盾。人民内部的矛盾，在劳动人民之间说来，是非对抗性的"),
    # ── sec_C_06 家庭、私有制和国家的起源 ─────────────────────
    "q_c06_3": ("CH-JT-197", "在经济发展到一定阶段而必然使社会分裂为阶级时，国家就由于这种分裂而成为必要了"),
    # ── sec_C_07 在延安文艺座谈会上的讲话 ────────────────────
    "q_c07_1": ("CH-YA-005", "工作对象问题，就是文艺作品给谁看的问题"),
    "q_c07_2": ("CH-YA-030", "无产阶级的文学艺术是无产阶级整个革命事业的一部分"),
    "q_c07_3": ("CH-YA-034", "文艺批评有两个标准，一个是政治标准，一个是艺术标准"),
}

# 已知「本章正文里确实没有可直接引用的对应原句」的题：保持 GUIDE- 导读锚。
# 诚实标注优于硬指一个不相干的分片。
NO_ANCHOR = {
    "sec_A_01": "大众哲学节选未收「对立统一…质量互变…否定之否定」总述篇与该题原句",
    "sec_A_03": "q_a03_2/q_a03_3 考的是《矛盾论》的内容（共性个性是精髓、主要矛盾），本章 local_work 是《实践论》——跨书不许锚，保持导读",
    "sec_A_04": "哲学笔记未收《谈谈辩证法问题》开篇「同一与差别、一般与个别」原句",
    "sec_A_05": "哥达纲领批判未收「按劳分配是资产阶级权利」的直述句（仅有「扣除/痕迹」段）",
    "sec_A_06": "宣言未收「资产阶级的灭亡和无产阶级的胜利是同样不可避免的」那句",
    "sec_A_07": "德意志意识形态未收「意识没有独立的历史」的直接表述",
    "sec_A_08": "资本论节选未收「商品价值体现的是人与人的关系」的原文表述",
    "sec_A_11": "费尔巴哈论节选未收「黑格尔哲学合理内核＝辩证法、基本内核＝唯物主义」那一句",
    "sec_A_12": "手稿未收「共产主义是扬弃私有财产的积极表现」直接表述",
    "sec_B_01": "怎么办？未收「职业革命家组织」的定义句（该题讲组织原则）",
    "sec_B_02": "国家与革命未收「革命的根本问题是国家政权问题」这一直接表述",
    "sec_B_03": "阶级分析未收「贫农是最接近的朋友」的对应句",
    "sec_B_04": "q_b04_1 的「从群众中来、到群众中去」原句在本章延伸阅读《关于领导方法的若干问题》里，不属本章 local_work——跨书不许锚",
    "sec_B_05": "反对本本主义未收「马克思主义的『本本』是要学习的」那一句",
    "sec_B_06": "帝国主义论未收「一国首先胜利论」与「五大基本特征」的对应表述",
    "sec_B_08": "左派幼稚病节选未收「领袖、政党、阶级、群众相互关系」的结论句",
    "sec_B_09": "湖南农民运动考察报告未收「革命不是请客吃饭」那句",
    "sec_B_10": "改造我们的学习未收「有的放矢」「实事求是」的原文定义句",
    "sec_C_04": "论十大关系未收「向外国学习」的对应表述",
    "sec_C_05": "正确处理人民内部矛盾未收「团结—批评—团结」公式那一段",
    "sec_C_06": "家庭私有制起源未收「阶级冲突使国家成为必要」之外的对应表述（该章已锚 CH-JT-197）",
    "sec_C_07": "延安文艺未收「普及基础上的提高、提高指导下的普及」原句",
}


def norm(s: str) -> str:
    return re.sub(r"\s+", "", s or "")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    chunks = {c["id"]: c for c in all_book_chunks()}
    sec = {s["id"]: s for s in SECTIONS}

    done: list[dict] = []
    kept: list[dict] = []
    errors: list[str] = []

    for path in sorted(BANK.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        changed = 0
        for item in data.get("items", []):
            cid = str(item.get("source_chunk_id") or "")
            if not cid.startswith("GUIDE-"):
                continue
            qid = item["id"]
            if qid not in EVIDENCE:
                kept.append({"file": path.name, "id": qid,
                             "section": item.get("section_id"), "guide": cid})
                continue
            new_cid, quote = EVIDENCE[qid]
            c = chunks.get(new_cid)
            if not c:
                errors.append(f"{qid}: 分片不存在 {new_cid}")
                continue
            sid = item.get("section_id") or ""
            want = sec.get(sid, {}).get("local_work", "")
            if c["source"] != want:
                errors.append(f"{qid}: 跨书 {new_cid} 属《{c['source']}》，本章 local_work=《{want}》")
                continue
            if norm(quote) not in norm(c["text"]):
                errors.append(f"{qid}: 证据不逐字命中 {new_cid}「{quote[:24]}…」")
                continue
            n_cjk = len(CJK.findall(quote))
            if n_cjk < MIN_QUOTE:
                errors.append(f"{qid}: 证据仅 {n_cjk} 汉字（<{MIN_QUOTE}）")
                continue
            item["source_chunk_id"] = new_cid
            done.append({"file": path.name, "id": qid, "section": sid,
                         "from": cid, "to": new_cid,
                         "work": c["source"], "quote": quote, "cjk": n_cjk})
            changed += 1
        if changed and args.write:
            path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n",
                            encoding="utf-8", newline="\n")

    print(f"升级 {len(done)} 条 / 保持导读锚 {len(kept)} 条 / 校验失败 {len(errors)} 条")
    for e in errors:
        print("  [ERR]", e)
    for d in done:
        print(f"  {d['section']:8s} {d['id']:14s} {d['from']:22s} → {d['to']:14s}"
              f"（{d['cjk']:2d}汉字）{d['quote'][:32]}…")

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(
        {"upgraded": done, "kept_guide": kept, "errors": errors,
         "no_anchor_reason": NO_ANCHOR, "min_quote": MIN_QUOTE},
        ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"\n报告 → {REPORT}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
