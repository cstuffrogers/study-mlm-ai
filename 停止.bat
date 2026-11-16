@echo off
REM  Stop the Marxist Philosophy Learning System (frees ports 8190 / 8080)
chcp 65001 >nul
cd /d "%~dp0"
where python >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Python not found.
  pause
  exit /b 1
)
python "%~dp0scripts\oneclick.py" stop
echo.
pause
