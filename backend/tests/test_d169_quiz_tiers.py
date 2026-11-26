"""D169 门禁：章节测试必须按「易 / 中 / 难 / 拓展」三档出题，且不允许重复题。

用户实报：「测试题目重复的好多，根本就没有体现易中难三个层次。」
根因两条：
  1. `_select_items` 只看「特殊题型限额 + 每知识点保底 + 顺序补齐」，从不看难度 ——
     抽出来的 12 题可能全是易题，也可能全是论述题；
  2. 题库生成器（`content/expand_quiz_bank.py`）每档的干扰项都是套话
     （「将「X」与其他概念混淆，并未准确表述其含义」），四选项里只有一句像正确答案，
     等于不认识知识点也能选对 —— 于是 103 个知识点生成出 103 道几乎一样的题。
"""
from __future__ import annotations

import json
import re
from pathlib import Path

import pytest

from model.models_learning import QuizItem
from services import quiz_service

ROOT = Path(__file__).resolve().parents[2]
BANK = ROOT / "backend" / "content" / "quiz_bank"
OFFLINE_QUIZ = ROOT / "frontend" / "assets" / "offline" / "quiz.json"


def _item(i: int, band: str, *, stem: str = "", subjective: bool = False) -> QuizItem:
    diff = {"easy": 0.30, "medium": 0.50, "hard": 0.70, "challenge": 0.70}[band]
    return QuizItem(
        id=f"q_t{i}", section_id="sec_X", node_id=f"kn_{i}",
        type="application" if band == "challenge" else "concept_discrimination",
        stem=stem or f"题 {i}", options=["a", "b", "c", "d"], answer="A",
        explanation="", difficulty=diff, source_chunk_id="CH-1",
        authority_status="reviewed", exempt_marked=False, trial_only=False,
        subjective=subjective,
    )


def test_band_of_matches_thresholds():
    assert quiz_service.band_of(_item(1, "easy")) == "easy"
    assert quiz_service.band_of(_item(2, "medium")) == "medium"
    assert quiz_service.band_of(_item(3, "hard")) == "hard"
    # 主观/应用题单列「拓展」，不能混进「难」档
    assert quiz_service.band_of(_item(4, "challenge", subjective=True)) == "challenge"


@pytest.mark.parametrize("cap", [8, 9, 10, 11, 12])
def test_band_quota_sums_to_cap(cap):
    q = quiz_service.band_quota(cap)
    assert sum(q.values()) == cap
    assert all(v >= 1 for v in q.values())


def test_select_items_covers_all_three_bands():
    """池子里三档都够时，一套卷子必须三档都有，且按名额分配。"""
    items = [_item(i, "easy") for i in range(10)]
    items += [_item(100 + i, "medium") for i in range(10)]
    items += [_item(200 + i, "hard") for i in range(10)]
    items += [_item(300 + i, "challenge", subjective=True) for i in range(3)]

    chosen = quiz_service._select_items(items, seed=7)
    assert len(chosen) == 12
    bands = [quiz_service.band_of(it) for it in chosen]
    quota = quiz_service.band_quota(12)
    for b in ("easy", "medium", "hard", "challenge"):
        assert bands.count(b) == quota[b], f"{b} 档题数不对：{bands}"
    assert len({it.id for it in chosen}) == 12


def test_select_items_dedupes_same_stem():
    """同一道题在题库里重复登记时，一套卷子里只出一次。"""
    items = [_item(1, "easy", stem="关于「实践」，下列说法正确的是？"),
             _item(2, "easy", stem="关于「实践」 ， 下列说法正确的是？"),  # 仅空白不同
             _item(3, "easy")]
    chosen = quiz_service._select_items(items, seed=1)
    stems = [re.sub(r"\s+", "", it.stem) for it in chosen]
    assert len(stems) == len(set(stems))


def test_select_items_prefers_unseen_items():
    """重考时优先换一批：最近做过的题排在后面。"""
    items = [_item(i, "easy") for i in range(24)]
    done = {it.id for it in items[:8]}
    chosen = quiz_service._select_items(items, exclude_ids=done, seed=3)
    assert len(chosen) == 12
    # 池子 24 题、卷子 12 题：做过的 8 题应当被避开（剩 8 题会被补进来，最多 4 道）
    assert len([it for it in chosen if it.id in done]) <= 4


def test_order_by_tier_is_ascending():
    items = [_item(1, "hard"), _item(2, "easy"), _item(3, "challenge", subjective=True),
             _item(4, "medium")]
    ordered = [quiz_service.band_of(it) for it in quiz_service._order_by_tier(items)]
    rank = {b: i for i, b in enumerate(quiz_service.BAND_ORDER)}
    assert [rank[b] for b in ordered] == sorted(rank[b] for b in ordered)


def test_public_item_carries_band():
    pub = quiz_service._public_item(_item(1, "easy"))
    assert pub["difficulty_band"] == "easy"
    assert "answer" not in pub and "explanation" not in pub


# ---------------------------------------------------------------- 题库内容门禁
def _bank_items():
    out = []
    for f in sorted(BANK.glob("*.json")):
        data = json.loads(f.read_text(encoding="utf-8"))
        for it in data.get("items", []):
            it["_file"] = f.name
            out.append(it)
    return out


def test_bank_has_all_three_bands_per_section():
    """每个章节的题库都必须覆盖 易/中/难 —— 否则「分层出题」在那一章落空。"""
    from collections import Counter, defaultdict
    per = defaultdict(Counter)
    for it in _bank_items():
        if it.get("subjective"):
            continue
        d = it.get("difficulty", 0.5)
        band = "easy" if d < 0.45 else ("medium" if d < 0.65 else "hard")
        per[it.get("section_id") or "DEFAULT"][band] += 1
    missing = {sec: dict(c) for sec, c in per.items()
               if not (c["easy"] and c["medium"] and c["hard"])}
    assert not missing, f"这些章节缺难度层次：{missing}"


def test_bank_has_no_duplicate_question():
    """同一份题库里不许出现「题干 + 选项」完全相同的题。"""
    def norm(s):
        return re.sub(r"\s+", "", s or "")

    seen, dups = {}, []
    for it in _bank_items():
        key = (norm(it["stem"]), tuple(norm(o) for o in it.get("options") or []))
        if key in seen:
            dups.append((seen[key], it["id"]))
        seen[key] = it["id"]
    assert not dups, f"重复题：{dups}"


BOILERPLATE = (
    "与其他概念混淆，并未准确表述其含义",
    "认为「",  # 旧版否定型干扰项：「认为「X」的含义与实际定义相反」
    "应当完整把握「",
    "对「{}」的运用偏离了其核心原理",
)


def test_bank_has_no_boilerplate_options():
    """选项不许再是套话：那种不看知识点也能选对的填充项是「题目重复感」的根因。"""
    bad = []
    for it in _bank_items():
        for opt in it.get("options") or []:
            if "与其他概念混淆，并未准确表述其含义" in opt:
                bad.append((it["id"], opt))
            elif opt.startswith("认为「") and "的含义与实际定义相反" in opt:
                bad.append((it["id"], opt))
            elif "在学习和运用中，应当完整把握「" in opt:
                bad.append((it["id"], opt))
    assert not bad, f"仍是套话选项：{bad[:5]}"


def test_offline_quiz_asset_synced_with_bank():
    """题库改了必须重跑 `scripts/export_offline_assets.py`，否则单机版还是旧题。"""
    bank = len(_bank_items())
    data = json.loads(OFFLINE_QUIZ.read_text(encoding="utf-8"))
    offline = sum(len(v) for v in data["sections"].values())
    assert offline == bank, f"题库 {bank} 题，离线资产 {offline} 题 —— 请重跑导出脚本"
