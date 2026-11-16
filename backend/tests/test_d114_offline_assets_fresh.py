"""D114 门禁：单机版离线资产必须与当前内容层同步。

背景（真实故障）：D103–D110 陆续把原著库从 90 部扩到 122 部，但没人重跑
`scripts/export_offline_assets.py`，`frontend/assets/offline/meta.json` 一直停在
2026-11-13 的 78 部 —— App 里「共 78 部著作」，新增的 46 部（《反杜林论》
《唯物主义和经验批判主义》《国家与革命》等）根本搜不到、读不到。

因此导出脚本在 manifest 里写了 `fingerprint`（著作名集合 + 分片总数的 sha1 前 12 位），
这里重算一遍比对：不一致就说明「内容层改了但资产没重新导出」。
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "frontend" / "assets" / "offline" / "manifest.json"
EXPORTER = ROOT / "scripts" / "export_offline_assets.py"

FIX_HINT = (
    "离线资产已过期：请重跑 `python scripts/export_offline_assets.py`，"
    "否则单机版 App 里看不到新入库的原著（只会在后端 API 里可见）。"
)


def _load_exporter():
    spec = importlib.util.spec_from_file_location("export_offline_assets", EXPORTER)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture(scope="module")
def manifest() -> dict:
    if not MANIFEST.exists():
        pytest.skip("离线资产尚未生成（首次开发环境可跳过）")
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def test_fixture_is_loaded(manifest: dict) -> None:
    assert manifest["fingerprint"], "manifest 缺 fingerprint 字段，请重跑导出脚本"


def test_offline_assets_match_content(manifest: dict) -> None:
    exporter = _load_exporter()
    meta = exporter.build_meta()
    expected = exporter.content_fingerprint(meta)
    assert manifest["fingerprint"] == expected, (
        f"{FIX_HINT}\n"
        f"  manifest: works={manifest['works']} chunks={manifest['chunks']} "
        f"fp={manifest['fingerprint']}\n"
        f"  当前内容: works={len(meta['works'])} chunks={meta['chunk_count']} fp={expected}"
    )


def test_offline_works_cover_all_books(manifest: dict) -> None:
    """双重保险：著作数量也得对上（防止有人手工改了 fingerprint 却没导出）。"""
    from content.book_chunks import BOOKS

    meta = json.loads((ROOT / "frontend" / "assets" / "offline" / "meta.json").read_text(encoding="utf-8"))
    exported = {str(w.get("work")) for w in meta["works"]}
    registered = {b["work"] for b in BOOKS}
    missing = sorted(registered - exported)
    assert not missing, f"{FIX_HINT}\n  资产缺少 {len(missing)} 部：{missing[:8]}"
    assert manifest["works"] == len(exported)


def test_work_sections_index_covers_routes(manifest: dict) -> None:
    """反向索引（书 → 章节）必须覆盖全部著作，且章节都真实存在。

    App 的阅读器用它在书里回答「这本书该在哪一章学」；
    索引缺书 → 那部书进来就看不到任何路径。
    """
    from content.book_chunks import BOOKS
    from content.routes import SECTIONS

    index_path = ROOT / "frontend" / "assets" / "offline" / "work_sections.json"
    assert index_path.exists(), f"{FIX_HINT}\n  缺少 work_sections.json（书 → 章节反向索引）"

    index = json.loads(index_path.read_text(encoding="utf-8"))
    books = {b["work"] for b in BOOKS}
    section_ids = {s["id"] for s in SECTIONS}

    assert set(index) == books, (
        f"{FIX_HINT}\n  索引缺 {len(books - set(index))} 部：{sorted(books - set(index))[:6]}\n"
        f"  索引多 {len(set(index) - books)} 部：{sorted(set(index) - books)[:6]}"
    )
    for work, rows in index.items():
        assert rows, f"{work} 在索引里是空列表"
        for r in rows:
            assert r["section_id"] in section_ids, f"{work} 指向不存在的章节 {r['section_id']}"
            assert r["kind"] in ("main", "ext"), f"{work} 出现未知类型 {r['kind']}"
            assert r["section_title"], f"{work} 的章节标题为空"
