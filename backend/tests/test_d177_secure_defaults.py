"""D177 门禁（CORS 部分）：通配符来源必须强制关闭带凭证请求。

原 D177 还锁了 JWT 签名密钥（SECRET_KEY）的弱默认值；认证子系统已随
cut 1 删除（无登录页、无 token 签发），密钥不再存在，对应测试随之移除。
这里保留与认证无关、仍然成立的安全护栏：

  · `CORS_ORIGINS` 设为通配符 `*` → 必须强制关闭 `allow_credentials`
    （浏览器规范禁止 credentials + "*" 并存）；
  · 「/api/* 不做身份校验」这条告警不许被后来的改动顺手删掉。
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
from core.config import CORS_ALLOW_CREDENTIALS, CORS_ORIGINS, security_warnings
print(json.dumps({
    "cors": CORS_ORIGINS,
    "credentials": CORS_ALLOW_CREDENTIALS,
    "warnings": security_warnings(),
}, ensure_ascii=False))
"""


def _probe(**env_over: str) -> dict:
    """按指定环境变量导入一次 config（每次都是全新进程，不受本进程缓存干扰）。"""
    env = {k: v for k, v in os.environ.items() if k not in ("CORS_ORIGINS",)}
    env.update(env_over)
    proc = subprocess.run(
        [PY, "-c", _PROBE], cwd=str(BACKEND), env=env,
        capture_output=True, text=True, encoding="utf-8", timeout=120,
    )
    assert proc.returncode == 0, proc.stderr[-2000:]
    line = [ln for ln in proc.stdout.splitlines() if ln.strip().startswith("{")][-1]
    return json.loads(line)


def test_wildcard_cors_disables_credentials():
    """`CORS_ORIGINS=*`：任何来源都能调，但必须强制关闭带凭证请求。"""
    out = _probe(CORS_ORIGINS="*")
    assert out["cors"] == ["*"]
    assert out["credentials"] is False
    assert any("通配符" in w for w in out["warnings"]), out["warnings"]


def test_explicit_origins_keep_credentials():
    """显式白名单（无通配符）：允许带凭证请求。"""
    out = _probe(CORS_ORIGINS="http://localhost:8190")
    assert out["cors"] == ["http://localhost:8190"]
    assert out["credentials"] is True


def test_no_identity_check_warning_survives():
    """「/api/* 不做身份校验」这条告警不许被后来的改动顺手删掉。"""
    assert any("身份校验" in w for w in _probe()["warnings"])


def test_db_default_password_warning_survives():
    """数据库默认弱口令告警不许被后来的改动顺手删掉（本机回环使用，仅告警）。"""
    assert any("默认弱口令" in w for w in _probe()["warnings"])
