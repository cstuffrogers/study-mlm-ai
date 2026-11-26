@echo off
REM ============================================================
REM  One-click START - Marxist Philosophy Learning System
REM ============================================================
chcp 65001 >nul
cd /d "%~dp0"

where python >nul 2>nul
if errorlevel 1 goto nopython

REM  可选：一键启动.bat --rebuild   即使 build/web 已存在也强制重建一次
python "%~dp0scripts\oneclick.py" start %*
echo.
pause
exit /b 0

:nopython
echo [ERROR] Python not found. Please run the installer first.
echo.
pause
exit /b 1
