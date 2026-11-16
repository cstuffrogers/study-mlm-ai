@echo off
chcp 65001 >nul
REM Launched by "一键启动.bat": start backend API (lightweight mode, no Docker/PG)
cd /d "%~dp0..\backend"
set "LEARNING_DB_MODE=memory"
set "AUTO_CREATE_TABLES=0"
"%~dp0..\backend\.venv\Scripts\python.exe" -m uvicorn app:app --host 0.0.0.0 --port 8190
