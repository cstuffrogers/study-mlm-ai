"""D176 门禁：一个知识点只出一道题，费曼自述每卷必出。

用户实报（接 D169）：「所谓不同难度实际上就换了一种表述而已。」

D169 曾把章节测试改成按「易 / 中 / 难 / 拓展」分档出题（每知识点生成 5 个变体，
按难度名额抽 12 题）。但题库里同知识点的各档共用同一张「概念—定义」对照表：
`_easy` 从四段定义里挑一条、`_med` 给定义反查概念名、`_hard` 四条「定义—概念名」
配对找张冠李戴 —— 同一句定义被问三遍，88 个知识点连题干模板都一样。
一章本来只有 3 个知识点，却被问成 12 道题，重复感就是这么来的。

D176 口径：
  · 取消难度分档（`band_of` / `band_quota` / `_order_by_tier` 全部删除）；
  · `_select_items` 按 `node_id` 分组，**每个知识点只出一道**，题量 = 知识点数
    （上限 `QUIZ_SIZE_MAX`），不再为了凑 8 题把同知识点问三四遍；
  · 同知识点的几个变体只用于**重考轮换**（避开最近两次做过的题）；
  · 费曼自述题每卷必出（≥2 个知识点时），知识点 ≥6 时再配一道应用题，均排卷末。
"""
from __future__ import annotations

import json
import re
from collections import defaultdict
from pathlib import Path

import pytest

from model.models_learning import QuizItem
from services import quiz_service

ROOT = Path(__file__).resolve().parents[2]
BANK = ROOT / "backend" / "content" / "quiz_bank"
OFFLINE_QUIZ = ROOT / "frontend" / "assets" / "offline" / "quiz.json"

OBJ_DEFAULT = ["a", "b", "c", "d"]


def _item(i: int, *, node: int | None = None, kind: str = "objective",
          stem: str = "", type_: str = "concept_discrimination") -> QuizItem:
    """kind: objective / feyn（主观费曼）/ apply（案例应用）"""
    return QuizItem(
        id=f"q_t{i}",
        section_id="sec_X",
        node_id=f"kn_{i if node is None else node}",
        type="application" if kind == "apply" else type_,
        stem=stem or f"题 {i}",
        options=OBJ_DEFAULT,
        answer="" if kind != "objective" else "A",
        explanation="",
        difficulty=0.5,
        source_chunk_id="CH-1",
        authority_status="reviewed",
        exempt_marked=False,
        trial_only=False,
        subjective=kind in ("feyn", "apply"),
    )


def _node_of(it: QuizItem) -> str:
    return it.node_id


# ---------------------------------------------------------------- 选题口径
def test_select_items_one_question_per_node():
    """3 个知识点各 5 个变体 → 只出 3 题，而不是按旧「至少 8 题」凑成 8 题。"""
    items = []
    n = 0
    for node in range(3):
        for _ in range(5):
            items.append(_item(n, node=node))
            n += 1
    chosen = quiz_service._select_items(items, seed=7)
    assert len(chosen) == 3, [it.id for it in chosen]
    assert len({_node_of(it) for it in chosen}) == 3


def test_select_items_caps_at_quiz_size_max():
    """知识点多于上限时按上限截断，且仍是「一节点一题」。"""
    from core.config import QUIZ_SIZE_MAX

    items = [_item(i, node=i) for i in range(QUIZ_SIZE_MAX + 8)]
    chosen = quiz_service._select_items(items, seed=1)
    assert len(chosen) == QUIZ_SIZE_MAX
    assert len({_node_of(it) for it in chosen}) == QUIZ_SIZE_MAX


def test_select_items_never_repeats_a_node():
    """同一节点有多个变体时，卷内绝不能出现两道（这是用户看到的「重复」）。"""
    items = []
    for node in range(4):
        for k in range(4):
            items.append(_item(node * 10 + k, node=node))
    chosen = quiz_service._select_items(items, seed=3)
    nodes = [_node_of(it) for it in chosen]
    assert len(nodes) == len(set(nodes))


def test_feynman_item_always_included():
    """费曼自述题是「能不能用自己的话讲清」的唯一信号，每卷必出。"""
    items = [
        _item(1, node=1),
        _item(2, node=2),
        _item(3, node=3, kind="feyn"),
    ]
    chosen = quiz_service._select_items(items, seed=5)
    kinds = [quiz_service.challenge_kind(it) for it in chosen]
    assert kinds.count(quiz_service.CHALLENGE_FEYN) == 1, kinds


def test_application_only_when_nodes_are_many():
    """知识点少时不塞应用题（写两道主观题太费时），够多时费曼 + 应用各一道。"""
    few = [_item(i, node=i) for i in range(4)]
    few.append(_item(100, node=0, kind="apply"))
    few.append(_item(101, node=1, kind="feyn"))
    kinds = [quiz_service.challenge_kind(it) for it in quiz_service._select_items(few, seed=2)]
    assert quiz_service.CHALLENGE_APPLY not in kinds
    assert kinds.count(quiz_service.CHALLENGE_FEYN) == 1

    many = []
    for node in range(8):
        many.append(_item(node, node=node))
        many.append(_item(100 + node, node=node, kind="feyn"))
        many.append(_item(200 + node, node=node, kind="apply"))
    chosen = quiz_service._select_items(many, seed=2)
    kinds = [quiz_service.challenge_kind(it) for it in chosen]
    assert kinds.count(quiz_service.CHALLENGE_FEYN) == 1
    assert kinds.count(quiz_service.CHALLENGE_APPLY) == 1


def test_challenge_items_come_last():
    """客观题在前、要自己写的题在卷末。"""
    items = [_item(0, node=0, kind="feyn")]
    items += [_item(i, node=i) for i in range(1, 6)]
    kinds = [quiz_service.challenge_kind(it) for it in quiz_service._select_items(items, seed=4)]
    assert kinds[-1] == quiz_service.CHALLENGE_FEYN
    assert all(k == "" for k in kinds[:-1])


def test_select_items_dedupes_same_stem():
    """同一道题在题库里重复登记时，一套卷子里只出一次。"""
    items = [
        _item(1, node=1, stem="关于「实践」，下列说法正确的是？"),
        _item(2, node=2, stem="关于「实践」 ， 下列说法正确的是？"),  # 仅空白不同
        _item(3, node=3),
    ]
    chosen = quiz_service._select_items(items, seed=1)
    stems = [re.sub(r"\s+", "", it.stem) for it in chosen]
    assert len(stems) == len(set(stems))


def test_select_items_prefers_unseen_items():
    """重考时同知识点的另一个变体优先（否则重考原样重复）。"""
    items = []
    for node in range(4):
        for k in range(3):
            it = _item(node * 10 + k, node=node)
            if k == 0:
                it.subjective = False
            items.append(it)
    done = {it.id for it in items if it.id.endswith("0")}  # 每节点第一道都做过
    chosen = quiz_service._select_items(items, exclude_ids=done, seed=3)
    assert len(chosen) == 4
    assert not [it for it in chosen if it.id in done]


def test_tier_machinery_is_gone():
    """D176：难度分档的入口不许偷偷回来（回来就等于同知识点问三遍）。"""
    for name in ("band_of", "band_quota", "_order_by_tier", "_interleave_items",
                 "BAND_ORDER", "BAND_LABELS"):
        assert not hasattr(quiz_service, name), f"`{name}` 不应再存在"


def test_public_item_has_no_band():
    pub = quiz_service._public_item(_item(1))
    assert "difficulty_band" not in pub
    assert "answer" not in pub and "explanation" not in pub
    assert pub["id"] == "q_t1"


# ---------------------------------------------------------------- 题库内容门禁
def _bank_rows() -> list[dict]:
    out = []
    for f in sorted(BANK.glob("*.json")):
        data = json.loads(f.read_text(encoding="utf-8"))
        default_sid = data.get("section_id")
        for it in data.get("items", []):
            it["section_id"] = it.get("section_id") or default_sid
            it["_file"] = f.name
            out.append(it)
    return out


def _bank_items() -> list[QuizItem]:
    return [
        QuizItem(
            id=r["id"], section_id=r["section_id"], node_id=r.get("node_id", ""),
            type=r["type"], stem=r["stem"], options=r.get("options") or [],
            answer=r.get("answer", ""), explanation=r.get("explanation", ""),
            difficulty=r.get("difficulty", 0.5),
            source_chunk_id=r.get("source_chunk_id", ""),
            authority_status=r.get("authority_status", "reviewed"),
            exempt_marked=r.get("exempt_marked", False),
            trial_only=r.get("trial_only", True),
            subjective=r.get("subjective", False),
        )
        for r in _bank_rows()
    ]


def _by_section() -> dict[str, list[QuizItem]]:
    per: dict[str, list[QuizItem]] = defaultdict(list)
    for it in _bank_items():
        per[it.section_id].append(it)
    return dict(per)


@pytest.mark.parametrize("seed", [0, 7, 42])
def test_real_bank_selects_one_per_node(seed):
    """真题库逐章跑一遍：题量 = 知识点数（≤ 上限），一节点一题，费曼必有一道。"""
    from core.config import QUIZ_SIZE_MAX

    for sid, items in _by_section().items():
        nodes = {it.node_id for it in items}
        chosen = quiz_service._select_items(items, seed=seed)
        assert len(chosen) == min(len(nodes), QUIZ_SIZE_MAX), (sid, len(chosen), len(nodes))
        got = [it.node_id for it in chosen]
        assert len(got) == len(set(got)), f"{sid} 同一知识点出了两次：{got}"
        kinds = [quiz_service.challenge_kind(it) for it in chosen]
        if len(nodes) >= 2:
            assert kinds.count(quiz_service.CHALLENGE_FEYN) == 1, f"{sid} 缺费曼自述题：{kinds}"
        assert kinds.count(quiz_service.CHALLENGE_APPLY) <= 1, f"{sid} 应用题超过一道"


def test_bank_every_section_has_feynman_and_objective():
    """题库层面兜住：每章都要有客观题节点 + 费曼节点，否则选题补不齐。"""
    bad = {}
    for sid, items in _by_section().items():
        kinds = defaultdict(set)
        for it in items:
            kinds[quiz_service.challenge_kind(it)].add(it.node_id)
        if not kinds[quiz_service.CHALLENGE_FEYN] or not kinds[""]:
            bad[sid] = {k: sorted(v) for k, v in kinds.items()}
    assert not bad, f"这些章节选题会缺口：{bad}"


def test_bank_has_no_duplicate_question():
    """同一章节里不许出现「题干 + 选项」完全相同的题。

    只在章内查：一张卷子只从一章抽题；跨章的 kn_a01_practice（路线 A）与
    kn_a03_practice（概述章）是**不同章节的同名知识点**，费曼题干天然相同。
    """
    def norm(s):
        return re.sub(r"\s+", "", s or "")

    seen, dups = {}, []
    for it in _bank_rows():
        key = (it["section_id"], norm(it["stem"]),
               tuple(norm(o) for o in it.get("options") or []))
        if key in seen:
            dups.append((seen[key], it["id"]))
        seen[key] = it["id"]
    assert not dups, f"重复题：{dups}"


def test_bank_has_no_boilerplate_options():
    """选项不许是套话：那种不看知识点也能选对的填充项是「题目重复感」的根因。"""
    bad = []
    for it in _bank_rows():
        for opt in it.get("options") or []:
            if "与其他概念混淆，并未准确表述其含义" in opt:
                bad.append((it["id"], opt))
            elif opt.startswith("认为「") and "的含义与实际定义相反" in opt:
                bad.append((it["id"], opt))
            elif "在学习和运用中，应当完整把握「" in opt:
                bad.append((it["id"], opt))
    assert not bad, f"仍是套话选项：{bad[:5]}"


def test_offline_quiz_asset_synced_with_bank():
    """题库改了必须重跑导出脚本，否则单机版还是旧题。"""
    bank = len(_bank_rows())
    data = json.loads(OFFLINE_QUIZ.read_text(encoding="utf-8"))
    offline = sum(len(v) for v in data["sections"].values())
    assert offline == bank, f"题库 {bank} 题，离线资产 {offline} 题 —— 请重跑 export_offline_assets.build_quiz()"
