"""D135 门禁：**异常输入的错误语义** —— 不许 500、不许把野值原样回显。

D131~D134 逐层查了「同一界面两条实现路径」的正常路径（数值 / 文案 / 键形状）。
这一层查反面：同一组非法/越界/缺失输入，两侧给的状态码与语义是否一致。

本轮实测挖出 4 个真缺陷（都在后端）：
1. `GET /api/routes/{r}/sections/{sid}/guide` 未知章节 → `AttributeError`
   （`block_links(None, ...)`），生产上是 **500**；
2. `POST /api/routes/diagnostic/{id}/submit` 未知诊断 → `diag.route_id` 属 **500**；
3. `POST /api/recommendation/next` 传不存在的 `current_section_id` 时**原样回显**
   → 推荐指向一张不存在的章节页（点进去空白）；
4. `weak_top(n=-1)`：Python 切片 `[: -1]` 是「除末条外全部」，与单机 `take(-1)`
   （空表）语义相反 —— 同一请求两侧两种结果。

对应的单机侧修复见 `frontend/test/offline_error_semantics_test.dart`。
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from fastapi.testclient import TestClient  # noqa: E402

from app import app  # noqa: E402

client = TestClient(app, raise_server_exceptions=False)

MIN = {"str": "zz_bogus_id", "integer": 0, "number": 0.0, "boolean": False,
       "array": [], "object": {}}


def _seed() -> dict:
    """开一份 sec_A_00 并空作答提交：让掌握记录存在，复习回写才不是「尚无记录」。"""
    r = client.post("/api/quiz/section/sec_A_00/start",
                    json={"user_id": "demo_user", "route_id": "route_A"})
    assert r.status_code == 200, r.text
    tid = r.json()["test_id"]
    assert client.post(f"/api/quiz/{tid}/submit",
                       json={"user_id": "demo_user", "answers": []}).status_code == 200
    return r.json()


def test_guide_unknown_section_is_404_not_500() -> None:
    """未知章节导读没有兜底内容，事实就是 404 —— 绝不能是 500。"""
    r = client.get("/api/routes/route_A/sections/sec_Z_99/guide")
    assert r.status_code == 404, r.text


def test_diagnostic_submit_unknown_is_404() -> None:
    r = client.post("/api/routes/diagnostic/zz_bogus/submit",
                    json={"user_id": "demo_user", "answers": []})
    assert r.status_code == 404, r.text
    assert "不存在" in r.json()["detail"]


def test_next_step_never_echoes_unknown_section() -> None:
    """传入不存在的 current_section_id，推荐目标必须是真章节（不能原样回显）。"""
    from content.routes import get_section

    r = client.post("/api/recommendation/next",
                    json={"user_id": "demo_user", "route_id": "route_A",
                          "current_section_id": "sec_Z_99"})
    assert r.status_code == 200, r.text
    target = r.json().get("target_section_id")
    assert target != "sec_Z_99", r.json()
    assert get_section(target) is not None, r.json()


def test_weak_top_negative_n_is_empty_not_slice_trick() -> None:
    """n<0 与 n=0 都必须回空表（Python `[: -1]` 会回除末条外全部）。"""
    for n in (-1, 0):
        r = client.get(f"/api/recommendation/weak-top?user_id=demo_user"
                       f"&route_id=route_A&n={n}")
        assert r.status_code == 200, r.text
        assert r.json()["weak_points"] == [], (n, len(r.json()["weak_points"]))


def test_history_limit_is_clamped_to_at_least_one() -> None:
    _seed()
    for lim in (-1, 0):
        r = client.get(f"/api/quiz/history?user_id=demo_user&route_id=route_A&limit={lim}")
        assert r.status_code == 200, r.text
        body = r.json()
        assert len(body["rows"]) == 1, (lim, len(body["rows"]))
        assert body.get("total", 1) >= 1


def test_no_endpoint_500_on_bogus_input() -> None:
    """全接口野值扫描：把每个 path 参数换成不存在的 id、必填体给最小值，不许 5xx。

    这是 D135 的「总闸」：以后任何接口新增了对 id 的直接解引用，都会在这里挂。
    """
    spec = app.openapi()
    bad: list[str] = []
    for path, ops in sorted(spec["paths"].items()):
        for method, op in ops.items():
            if method not in ("get", "post", "put", "patch", "delete"):
                continue
            url = path
            for p in op.get("parameters", []):
                if p.get("in") == "path":
                    url = url.replace("{" + p["name"] + "}", "zz_bogus_id")
            kwargs = {}
            if method in ("post", "put", "patch"):
                schema = ((op.get("requestBody") or {}).get("content", {})
                          .get("application/json", {}).get("schema", {}) or {})
                ref = schema.get("$ref")
                if ref:
                    schema = spec["components"]["schemas"][ref.split("/")[-1]]
                kwargs["json"] = {
                    k: MIN.get(v.get("type", "str"), "zz_bogus_id")
                    for k, v in (schema.get("properties") or {}).items()
                    if k in (schema.get("required") or [])
                }
            try:
                r = client.request(method.upper(), url, **kwargs)
            except Exception as e:  # noqa: BLE001
                bad.append(f"{method.upper()} {url} → {type(e).__name__}: {e}")
                continue
            if r.status_code >= 500:
                bad.append(f"{method.upper()} {url} → {r.status_code} {r.text[:80]}")
    assert not bad, "野值输入打出了 5xx：\n" + "\n".join(bad)
