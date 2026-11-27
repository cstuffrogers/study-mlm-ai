"""D177 门禁：密钥不许再有固定的弱默认值（CORS / 弱口令告警同锁）。

review 工作流（`claude-scene start review`）的 insecure-defaults 扫描把
`core/config.py` 里 `os.getenv(..., "change-me-in-production")` 一类兜底值
全部标了出来。其中真正的缺陷只有一条：**JWT 签名密钥有写死的默认值** ——
公开串等于没有密钥，谁都能照着伪造 token；一旦服务从回环地址挪出去就是真漏洞。

修法不是「未设就报错」（那会打断一键安装 / 本地开发 / 测试），而是：
  · 未设置 → 每次启动 `secrets.token_urlsafe(32)` 随机生成（默认值不再是弱口令）；
  · 显式设成弱值 → 仍然只告警，不阻断启动；
  · `CORS_ORIGINS` 设为通配符 → 强制关闭 `allow_credentials`（浏览器规范本也不许两者并存）。

own「采样值」故意写在本文件里（`SECRET_KEY=<旧默认值>`），安全扫描器会把它
当成硬编码密钥报 critical —— 那行带 `nosec` 并写明理由，见用例内注释。

数据库 / Neo4j 的默认口令按设计保留：docker-compose 已把端口绑到 127.0.0.1，
只有告警。`ENABLE_SEMANTIC_CACHE` / `AUTO_CREATE_TABLES` 是功能开关，属扫描误报。
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
PY = sys.executable

# 探测脚本：在子进程里按给定环境变量导入 config，把观测量打成 JSON
_PROBE = """
import json
from core.config import (
    CORS_ALLOW_CREDENTIALS, CORS_ORIGINS, SECRET_KEY,
    SECRET_KEY_IS_GENERATED, SECRET_KEY_IS_WEAK, security_warnings,
)
print(json.dumps({
    "secret": SECRET_KEY,
    "generated": SECRET_KEY_IS_GENERATED,
    "weak": SECRET_KEY_IS_WEAK,
    "cors": CORS_ORIGINS,
    "credentials": CORS_ALLOW_CREDENTIALS,
    "warnings": security_warnings(),
}, ensure_ascii=False))
"""


def _probe(**env_over: str) -> dict:
    """按指定环境变量导入一次 config（每次都是全新进程，不受本进程缓存干扰）。

    `SECRET_KEY=""` 就是「未设置」：python-dotenv 默认不覆盖已存在的键，
    所以在这里显式给空值，可以不受各机器 `backend/.env` 里是否有旧值影响。
    """
    env = {k: v for k, v in os.environ.items() if k not in ("SECRET_KEY", "CORS_ORIGINS")}
    env.update({"SECRET_KEY": ""})
    env.update(env_over)
    proc = subprocess.run(
        [PY, "-c", _PROBE], cwd=str(BACKEND), env=env,
        capture_output=True, text=True, encoding="utf-8", timeout=120,
    )
    assert proc.returncode == 0, proc.stderr[-2000:]
    line = [ln for ln in proc.stdout.splitlines() if ln.strip().startswith("{")][-1]
    return json.loads(line)


def _secret_warnings(out: dict) -> list[str]:
    return [w for w in out["warnings"] if "SECRET_KEY" in w]


def test_unset_secret_becomes_random_strong_key():
    """未设置 SECRET_KEY（或留空）：自动生成，且不再是那个公开的固定串。"""
    out = _probe()
    assert out["generated"] is True
    assert out["weak"] is False
    assert out["secret"] != "change-me-in-production"
    assert len(out["secret"]) >= 32
    # 告警口径：告知「本次随机生成」，而不是「你用了弱口令」
    warns = _secret_warnings(out)
    assert len(warns) == 1 and "随机生成" in warns[0], warns


def test_two_processes_get_different_keys():
    """随机密钥确实随机：两个进程拿到的不是同一把。"""
    a, b = _probe()["secret"], _probe()["secret"]
    assert a != b


def test_explicit_weak_secret_only_warns():
    """显式设成旧的默认值：不阻断启动，但必须告警（并说明怎么改）。"""
    # 断言对象就是这个旧默认值本身：少了它这条护栏无法验证
    out = _probe(SECRET_KEY="change-me-in-production")  # nosec: 弱值样本，非真密钥
    assert out["generated"] is False
    assert out["weak"] is True
    warns = _secret_warnings(out)
    assert len(warns) == 1 and "弱值" in warns[0], warns


def test_short_secret_is_flagged():
    """短于 32 字节也算弱值（32 字节以下不足以当 HS256 密钥）。"""
    assert _probe(SECRET_KEY="a" * 31)["weak"] is True
    assert _probe(SECRET_KEY="a" * 32)["weak"] is False


def test_strong_secret_has_no_secret_warning():
    out = _probe(SECRET_KEY="x" * 64)
    assert out["weak"] is False
    assert _secret_warnings(out) == []


def test_wildcard_cors_disables_credentials():
    """`CORS_ORIGINS=*`：任何来源都能调，但必须强制关闭带凭证请求。"""
    out = _probe(CORS_ORIGINS="*")
    assert out["cors"] == ["*"]
    assert out["credentials"] is False
    assert any("通配符" in w for w in out["warnings"]), out["warnings"]


def test_no_identity_check_warning_survives():
    """「/api/* 不做身份校验」这条告警不许被后来的改动顺手删掉。"""
    assert any("身份校验" in w for w in _probe()["warnings"])


def test_default_secret_is_not_hardcoded_in_config_source():
    """源码层面兜住：`SECRET_KEY` 不许再出现字面量默认值。"""
    src = (BACKEND / "core" / "config.py").read_text(encoding="utf-8")
    assert 'os.getenv("SECRET_KEY", "change-me-in-production")' not in src
    assert "secrets.token_urlsafe" in src
