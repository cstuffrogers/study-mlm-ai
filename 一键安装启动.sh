#!/usr/bin/env bash
# Marxist Philosophy Learning System - one-click installer/starter
# (Git Bash / Linux / macOS). All logic lives in scripts/oneclick.py.
#   ./一键安装启动.sh            install + start
#   ./一键安装启动.sh install    install only
#   ./一键安装启动.sh start      start only
#   ./一键安装启动.sh stop       stop
set -euo pipefail
cd "$(dirname "$0")"
PY="$(command -v python || command -v python3 || true)"
if [ -z "$PY" ]; then
  echo "[ERROR] Python not found. Please install Python 3.10+." >&2
  exit 1
fi
exec "$PY" "scripts/oneclick.py" "${1:-all}"
