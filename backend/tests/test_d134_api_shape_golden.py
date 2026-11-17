"""D134 门禁：联网后端 `/api/*` 的**返回键形状**必须仍等于黄金样本。

为什么需要这层：D131~D133 修的是「同一界面两条实现路径」（联网 FastAPI vs
单机 `frontend/lib/offline/`）的数值/文案/行为不一致；这一层查的是**键形状**。
单机少一个键，界面就静默少一块内容，REST 冒烟（只看状态码）和内容审计都查不到。

两侧共用一份黄金样本 `frontend/test/fixtures/api_shape_golden.json`，由
`.local/p189_api_shape_golden.py` 从本进程实测生成；本测试是「反向锁」：
后端若悄悄改名/删键，这里失败 → 必须重新生成并人工确认，顺带提醒同步单机侧
（`frontend/test/offline_api_shape_parity_test.dart` 用同一份样本要求单机覆盖）。
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from fastapi.testclient import TestClient  # noqa: E402

from app import app  # noqa: E402

GOLDEN = ROOT.parent / "frontend" / "test" / "fixtures" / "api_shape_golden.json"

client = TestClient(app)


def shape(v, prefix: str = "", depth: int = 0) -> dict[str, list[str]]:
    """键集合（深度 2）：顶层键 + 一级子对象键 + 一级列表首项的键。"""
    out: dict[str, list[str]] = {}
    if isinstance(v, list):
        if v:
            out.update(shape(v[0], prefix + "[]", depth))  # 列表不算一层
        return out
    if isinstance(v, dict):
        if depth > 1:
            return out
        out[prefix or "."] = sorted(str(k) for k in v.keys())
        for k, val in v.items():
            out.update(shape(val, f"{k}" if not prefix else f"{prefix}.{k}", depth + 1))
    return out


def _seed() -> None:
    """与 `.local/p189_api_shape_golden.py` 逐字同种子。

    「空作答」提交：全错，叶子分 < 0.8，`weak_points` 非空——否则两侧列表都空，
    列表项的形状根本比不到。
    """
    r = client.post("/api/quiz/section/sec_A_00/start",
                    json={"user_id": "demo_user", "route_id": "route_A"})
    r.raise_for_status()
    if r.json().get("items"):
        sub = client.post(f"/api/quiz/{r.json()['test_id']}/submit",
                          json={"user_id": "demo_user", "answers": []})
        sub.raise_for_status()


def _golden() -> dict:
    assert GOLDEN.exists(), f"缺少黄金样本 {GOLDEN}，重跑 .local/p189_api_shape_golden.py"
    return json.loads(GOLDEN.read_text(encoding="utf-8"))


POST_BODIES = {
    "/api/quiz/section/sec_A_02/start": {"user_id": "demo_user", "route_id": "route_A"},
    "/api/recommendation/next": {"user_id": "demo_user", "route_id": "route_A",
                                 "current_section_id": "sec_A_00"},
    "/api/mastery/summary": {"user_id": "demo_user", "route_id": "route_A",
                             "period": "week"},
}


def test_backend_shape_matches_golden() -> None:
    golden = _golden()
    _seed()
    problems: list[str] = []
    for key, want in golden["paths"].items():
        method, path = key.split(" ", 1)
        if method == "GET":
            resp = client.get(path + "?user_id=demo_user&route_id=route_A")
        else:
            resp = client.post(path, json=POST_BODIES.get(path, {}))
        assert resp.status_code == 200, (key, resp.status_code, resp.text[:200])
        got = shape(resp.json())
        for scope, keys in want.items():
            mine = got.get(scope)
            if mine is None:
                problems.append(f"{key} :: 联网后端没有层级 {scope} 了（样本有 {keys}）")
                continue
            missing = [k for k in keys if k not in mine]
            added = [k for k in mine if k not in keys]
            if missing:
                problems.append(f"{key} :: {scope} 少了 {missing}（会连带单机侧失配）")
            if added:
                problems.append(f"{key} :: {scope} 多了 {added}")
        extra_scopes = sorted(set(got) - set(want))
        for scope in extra_scopes:
            if got[scope]:
                problems.append(f"{key} :: 新增层级 {scope}{got[scope]}")
    assert not problems, (
        "后端返回形状与黄金样本不一致。若是有意改动，请重新生成样本并确认单机侧同步：\n"
        "  cd backend && python ../.local/p189_api_shape_golden.py\n"
        "  cd frontend && flutter test test/offline_api_shape_parity_test.dart\n"
        + "\n".join("  · " + p for p in problems))
