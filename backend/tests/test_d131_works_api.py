"""D131 门禁：`/api/chunks/works` 必须同时给 `works` 与 `items`，
且我们自己的注释层（第 3/4 层合成片）不许冒充原著摆进书单。

回归点有两个，都是真实发生过的：
- 路由文档写了 `items`（带作者/分片数），实现只回名字数组 → 前端
  `worksWithMeta()` 永远拿到空表，在线模式静默退回离线包（数据可能过期）。
- 「正典注释（艾思奇·统编教材）」「正典解析（统编教材）」是内部合成层，
  却因为和其它书一样有 `source` 而排进了原著书店的第 2、3 位。
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from fastapi.testclient import TestClient  # noqa: E402

from app import app  # noqa: E402
from services import content_provider as cp  # noqa: E402

client = TestClient(app)


def _works_json() -> dict:
    res = client.get("/api/chunks/works")
    assert res.status_code == 200
    return res.json()


def test_works_endpoint_returns_meta_items() -> None:
    j = _works_json()
    assert j["total"] == len(j["works"]) == len(j["items"])
    first = j["items"][0]
    for key in ("work", "author", "chunk_count", "first_chunk_id"):
        assert key in first, f"items 缺字段 {key}"
    assert first["chunk_count"] > 0 and first["first_chunk_id"]


def test_every_work_count_matches_chunks() -> None:
    for it in _works_json()["items"]:
        assert it["chunk_count"] == len(cp.chunks_by_work(it["work"])), it["work"]
        assert it["first_chunk_id"] == cp.chunks_by_work(it["work"])[0]["id"], it["work"]


def test_internal_annotation_layers_are_not_books() -> None:
    names = set(_works_json()["works"])
    for bad in ("正典注释（艾思奇·统编教材）", "正典解析（统编教材）"):
        assert bad not in names, f"内部注释层被当成原著书：{bad}"
        # 仍然能按 id 取到（对话/溯源卡片要用），只是不进书单
        got = client.get(f"/api/chunks/{'CH-ME-TH-01-3' if '注释' in bad else 'CH-ME-TH-01-4'}")
        assert got.status_code == 200 and got.json().get("text")


def test_book_authors_present_for_known_works() -> None:
    by_work = {it["work"]: it for it in _works_json()["items"]}
    assert by_work["大众哲学"]["author"] == "艾思奇"
    assert by_work["关于费尔巴哈的提纲"]["author"] == "马克思"
    # 查不到就留空，由前端显示「作者未标注」——不猜、不编
    assert all("author" in it for it in by_work.values())
