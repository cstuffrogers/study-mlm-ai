# -*- coding: utf-8 -*-
"""D141 门禁：毛泽东思想三项基本点（两类矛盾 / 群众路线 / 独立自主）。

为什么要有这组门禁：D140 之前 `STANCE_PATTERNS` 10 条规则**零覆盖毛泽东思想**——
全部集中在马恩列（经济决定论、反映论、阶级斗争、无产阶级专政、劳动价值论）。
库内毛的著作用了 48 部（著作权未届满），而守门规则里没有一条能识别
「否认两类矛盾」「否认群众路线」「否认独立自主」。

写规则的边界（两条都实测过）：
  - 只拦**否认 / 替换**的断言，不拦正统论述本身：
    「必须严格区分和正确处理两类不同性质的矛盾」不命中；
    「照搬苏联模式的教训必须记取」不命中（毛本人批评的就是照搬）。
  - 与后端/前端同口径：规则写在 `core/guard/orthodoxy.py` 的 STANCE_PATTERNS，
    由 `scripts/export_offline_assets.py` 导出到 `frontend/assets/offline/knowledge.json`，
    单机版 `OfflineGuard` 读同一份数据，不另写一套。
"""
from __future__ import annotations

import pytest

from core.guard.orthodoxy import OrthodoxyGuard, STANCE_PATTERNS

RULE_KEYS = ("deny_two_kinds_contradiction", "deny_mass_line", "deny_independence")


@pytest.fixture(scope="module")
def guard() -> OrthodoxyGuard:
    return OrthodoxyGuard()


def _blocked(result: dict) -> bool:
    return result["action"] == "block"


# ------------------------------------------------------------------ 否认 → 必须拦
DENIALS = [
    "两类矛盾的区分是虚构的。",
    "不存在两类矛盾，都是阶级斗争。",
    "人民内部矛盾就是敌我矛盾。",
    "群众路线已经过时了。",
    "不必依靠群众，靠制度就行。",
    "群众都是愚昧落后的。",
    "精英必须管理群众。",
    "独立自主已经过时，全球化时代不必自力更生。",
    "中国革命胜利主要归功于苏联援助。",
    "照搬苏联模式才能成功。",
]


@pytest.mark.parametrize("text", DENIALS)
def test_denials_blocked(guard: OrthodoxyGuard, text: str) -> None:
    assert _blocked(guard.check(text)), guard.check(text)


# ------------------------------------------------------------------ 正统论述 → 放过
ORTHODOX = [
    "必须严格区分和正确处理两类不同性质的矛盾。",
    "人民内部矛盾只能用民主的、说服教育的方法解决。",
    "必须坚持群众路线，一切为了群众，一切依靠群众，从群众中来，到群众中去。",
    "必须坚持独立自主、自力更生，同时学习外国先进经验。",
    "照搬苏联模式的教训必须记取。",
    "毛泽东批评了照搬苏联模式的做法。",
    "敌我之间和人民内部这两类矛盾的性质不同，解决的方法也不同。",
]


@pytest.mark.parametrize("text", ORTHODOX)
def test_orthodox_statements_pass(guard: OrthodoxyGuard, text: str) -> None:
    r = guard.check(text)
    assert not _blocked(r), (text, [f.get("rule") for f in r["flags"]])


def test_rules_registered_with_reason() -> None:
    """三条规则必须带 reason（UI 要展示「错在哪」），且都进 STANCE_PATTERNS。"""
    for key in RULE_KEYS:
        rule = STANCE_PATTERNS[key]
        assert rule["label"] == "deviation"
        assert rule["reason"].strip(), key
        assert rule["pattern"].strip(), key


def test_chunk_check_does_not_flag_orthodox_chunks(guard: OrthodoxyGuard) -> None:
    """L2 分片级校验：正统原话不得被降权。"""
    for text in ORTHODOX:
        got = guard.check_chunk(text, orthodoxy_tag="正统")
        assert not got.get("flagged"), (text, got)
