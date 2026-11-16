@echo off
REM ============================================================
REM  One-click INSTALL - Marxist Philosophy Learning System
REM  (English-only text in .bat to avoid GBK console issues;
REM   all Chinese UI text is printed by scripts\oneclick.py)
REM ============================================================
chcp 65001 >nul
cd /d "%~dp0"

where python >nul 2>nul
if errorlevel 1 goto nopython

python "%~dp0scripts\oneclick.py" install
echo.
pause
exit /b 0

:nopython
echo [ERROR] Python not found. Please install Python 3.10+ and add it to PATH.
echo         Download: https://www.python.org/downloads/
echo.
pause
exit /b 1
