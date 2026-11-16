@echo off
setlocal enableextensions enabledelayedexpansion
cd /d "%~dp0"

echo ============================================================
echo  Stopping the learning system services
echo  Backend : port 8190
echo  Frontend: port 8080
echo ============================================================

set "ANY=0"

for %%P in (8190 8080) do call :kill_port %%P

call :clean_pid ".xxmz-backend.pid"
call :clean_pid ".xxmz-frontend.pid"
call :clean_pid ".xxmz-backend.log.pid"
call :clean_pid ".xxmz-frontend.log.pid"
call :clean_pid ".run\backend.pid"
call :clean_pid ".run\frontend.pid"

echo.
echo Done. Ports 8190 / 8080 have been released.
echo.
echo Press any key to close this window.
pause >nul
endlocal
exit /b 0

:kill_port
set "PORT=%~1"
set "FOUND="
for /f "tokens=5" %%A in ('netstat -ano ^| findstr ":%PORT% " ^| findstr /C:"LISTENING"') do (
    set "FOUND=1"
    set "ANY=1"
    echo   - port %PORT%: killing PID %%A
    taskkill /F /PID %%A >nul 2>nul
)
if not defined FOUND echo   - port %PORT%: not in use
exit /b 0

:clean_pid
if exist "%~1" del /q "%~1" >nul 2>nul
exit /b 0
