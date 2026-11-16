@echo off
chcp 65001 >nul
REM Launched by the one-click launcher: serve built frontend on 8080.
REM Uses scripts/serve_frontend.py which sends no-cache headers, so the
REM browser always loads the current build (no stale main.dart.js / fonts).
cd /d "%~dp0..\frontend\build\web"
"%~dp0..\backend\.venv\Scripts\python.exe" "%~dp0serve_frontend.py" 8080
