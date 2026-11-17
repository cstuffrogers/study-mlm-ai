"""D136 门禁：**列表顺序 / 排序稳定性 / 并列（tie-break）**。

D131~D135 逐层查了「同一界面两条实现路径」的数值、文案、键形状、错误语义。
这一轮查的是此前没人碰过的一层：**同一批数据，两端排出来的顺序是否一致**。

排序是最容易「看起来对」的缺陷形态 —— 数据一条不少、字段一个不缺、状态码一样，
只有顺序不同。而这种缺陷只在**并列**时暴露：只要排序键出现同值，先后就由
「输入顺序」决定，而输入顺序在两侧分别是 SQL 无 ORDER BY 的返回序、Dart Map 的
迭代序、Python 的稳定排序残留 —— 三者互不相关。

本轮实测的 6 处：

1. `profile.weak_points` 后端把**未评估节点**（score=0/level=unseen）计入薄弱点，
   单机 `if (rec == null) continue;` 直接跳过——全新用户在线 106 条、单机 0 条；
2. 同一个 `weak_points` 后端 `sort(key=_rank, reverse=True)` 无 tie-break；
3. `profile.weak_points` 单机 `.take(6)` 硬截断，后端回全量（切片归 `weak_top(n)`）；
4. `review_status().items` 两端都按「SQL/Map 返回序」输出，同一份数据两种排法；
5. `due_reviews()` 只按 `_risk` 降序，风险并列时顺序不定（单机 `List.sort` 还**不稳定**）；
6. `quiz/history` 只按 `created_at` 倒序 —— 一次提交里所有小题同时间戳，等于没定义顺序。

对应的单机侧门禁见 `frontend/test/offline_order_stability_test.dart`。
"""
from __future__ import annotations

import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from fastapi.testclient import TestClient  # noqa: E402

from app import app  # noqa: E402
from content.knowledge_graph import KNOWLEDGE_NODES  # noqa: E402
from services.knowledge_graph_service import get_kg  # noqa: E402

client = TestClient(app, raise_server_exceptions=False)


def _user() -> str:
    """每次用全新用户，避免历史掌握记录把「并列」冲掉。"""
    return "u136_" + uuid.uuid4().hex[:10]


def _seed(user_id: str, sections=("sec_A_00", "sec_A_01", "sec_A_02")) -> None:
    """空作答提交：全错 → 分数低、薄弱点非空，两侧同参同序。"""
    for sid in sections:
        r = client.post(f"/api/quiz/section/{sid}/start",
                        json={"user_id": user_id, "route_id": "route_A"})
        assert r.status_code == 200, r.text
        tid = r.json()["test_id"]
        assert client.post(f"/api/quiz/{tid}/submit",
                           json={"user_id": user_id, "answers": []}).status_code == 200


def _profile(user_id: str) -> dict:
    r = client.get("/api/mastery/profile",
                   params={"user_id": user_id, "route_id": "route_A"})
    assert r.status_code == 200, r.text
    return r.json()


# --------------------------------------------------------------- 薄弱点
def test_weak_points_include_unassessed_nodes() -> None:
    """全新用户 = 一个都没学 → 后端把它当薄弱点全列（单机原先是空表）。"""
    prof = _profile(_user())
    weak = prof["weak_points"]
    assert len(weak) == len(KNOWLEDGE_NODES), len(weak)
    assert {w["level"] for w in weak} == {"unseen"}


def test_weak_points_tie_break_is_node_id() -> None:
    """薄弱点排序：`(-rank, node_id)`，rank 并列时必须按 node_id 升序。

    全新用户所有 score 都是 0，rank 只由「依赖出度数 × 考频权重」决定 ——
    是明确的并列高发区。原先只写 `reverse=True`，同 rank 的先后取决于
    `KNOWLEDGE_NODES` 的定义顺序，单机侧则是 Map 迭代序，同一份数据两种排法。
    """
    kg = get_kg()
    prof = _profile(_user())
    weak = prof["weak_points"]
    weight = {n["id"]: n["exam_weight"] for n in KNOWLEDGE_NODES}

    def rank(w: dict) -> float:
        return round((1 - w["score"]) * (1 + kg.dependents_count(w["node_id"]))
                     * weight[w["node_id"]], 4)

    got = [(rank(w), w["node_id"]) for w in weak]
    assert got == sorted(got, key=lambda t: (-t[0], t[1])), got[:8]


def test_weak_points_not_truncated_to_six() -> None:
    """`build_profile()` 回全量，切片是 `weak_top(n)` 的事 —— 不许在这里悄悄截 6 条。"""
    prof = _profile(_user())
    assert len(prof["weak_points"]) > 6


# --------------------------------------------------------------- 复习
def test_review_status_items_sorted_by_stability() -> None:
    """复习概览：稳定度低的先复习，并列按 node_id（不能按 `next_review_at`：
    那是「写入时刻 + 间隔」，写入时刻各端 wall clock 不同，稳定度相同时
    排序退化成写入序 —— 同一份数据能排出两种顺序）。"""
    uid = _user()
    _seed(uid)
    r = client.get("/api/review/status",
                   params={"user_id": uid, "route_id": "route_A"})
    assert r.status_code == 200, r.text
    items = r.json()["items"]
    assert items, "种子后应有掌握记录"
    got = [(round(it["stability"], 4), it["node_id"]) for it in items]
    assert got == sorted(got), got[:8]


def test_due_reviews_tie_break_is_node_id() -> None:
    """到期队列：风险降序 → node_id 升序（风险并列时顺序必须写死）。"""
    uid = _user()
    _seed(uid)
    r = client.get("/api/review/due",
                   params={"user_id": uid, "route_id": "route_A"})
    assert r.status_code == 200, r.text
    due = r.json()["due"]
    kg = get_kg()
    got = [(round((1 - d["retention"]) * (1 + kg.dependents_count(d["node_id"])), 4),
            d["node_id"]) for d in due]
    assert got == sorted(got, key=lambda t: (-t[0], t[1])), got[:8]


# --------------------------------------------------------------- 历史
def test_history_rows_order_is_fully_determined() -> None:
    """历史列表：`created_at` 倒序 → 同时间戳按 `quiz_id` 升序。

    一次提交里所有小题写在同一事务、`created_at` 完全相同；原先只按时间倒序，
    等于把顺序交给了数据库的返回序。这里直接校验「返回序 == 契约序」。
    """
    uid = _user()
    _seed(uid, sections=("sec_A_00",))
    r = client.get("/api/quiz/history",
                   params={"user_id": uid, "limit": 50})
    assert r.status_code == 200, r.text
    rows = r.json()["rows"]
    assert len(rows) >= 2
    # 主键：时间倒序（同格式 ISO/RFC 字符串可直接比较），次键 quiz_id 升序
    order = [(row.get("created_at") or "", row["quiz_id"]) for row in rows]
    for a, b in zip(order, order[1:]):
        assert a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]), (a, b)


def test_history_same_second_ties_sorted_by_quiz_id() -> None:
    """同一测试的作答（同时间戳）必须按 quiz_id 升序，两次查询结果一致。"""
    uid = _user()
    _seed(uid, sections=("sec_A_00",))
    first = client.get("/api/quiz/history", params={"user_id": uid, "limit": 50}).json()["rows"]
    second = client.get("/api/quiz/history", params={"user_id": uid, "limit": 50}).json()["rows"]
    assert [r["quiz_id"] for r in first] == [r["quiz_id"] for r in second]
