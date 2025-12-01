@echo off
REM run_windows.bat
REM One-Click Launcher for Windows
REM Starts Host Agent, Docker, and Dashboard

setlocal enabledelayedexpansion

title System Monitor - Windows Launcher

echo ============================================================
echo   System Monitoring Solution - Windows Launcher
echo ============================================================
echo.

REM Create metrics directory
if not exist "metrics" mkdir metrics

REM Check if Docker is running
docker info >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker is not running or not installed.
    echo Please start Docker Desktop and try again.
    pause
    exit /b 1
)

echo [1/4] Starting Host Agent in background...
start /B powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0host_agent_windows.ps1" -MetricsFile "%~dp0metrics\metrics.json"
timeout /t 2 /nobreak >nul

REM Store the PowerShell process ID for cleanup
for /f "tokens=2" %%a in ('tasklist /FI "IMAGENAME eq powershell.exe" /FO LIST ^| findstr /I "PID"') do (
    set HOST_AGENT_PID=%%a
)

echo [2/4] Building Docker container...
docker-compose build
if errorlevel 1 (
    echo [ERROR] Docker build failed.
    taskkill /F /IM powershell.exe /FI "WINDOWTITLE eq *host_agent*" >nul 2>&1
    pause
    exit /b 1
)

echo [3/4] Starting Docker container...
docker-compose up -d
if errorlevel 1 (
    echo [ERROR] Docker start failed.
    taskkill /F /IM powershell.exe /FI "WINDOWTITLE eq *host_agent*" >nul 2>&1
    pause
    exit /b 1
)

timeout /t 3 /nobreak >nul

echo [4/4] Attaching to dashboard...
echo.
echo ============================================================
echo   Dashboard is now running.
echo   Press Ctrl+C to stop and cleanup.
echo ============================================================
echo.

REM Attach to container and show dashboard
docker exec -it system-monitor-dashboard /app/dashboard.sh

REM Cleanup on exit
echo.
echo Cleaning up...
echo Stopping Docker container...
docker-compose down

echo Stopping Host Agent...
REM Kill all PowerShell processes running host_agent_windows.ps1
REM Use wmic to find processes with the script name in command line
for /f "tokens=2 delims=," %%a in ('wmic process where "name='powershell.exe' or name='pwsh.exe'" get processid^,commandline /format:csv ^| findstr /I "host_agent_windows.ps1"') do (
    if not "%%a"=="ProcessId" (
        taskkill /F /PID %%a >nul 2>&1
    )
)
REM Fallback: Try to kill by window title (if hidden window still has title)
taskkill /F /FI "WINDOWTITLE eq *host_agent*" >nul 2>&1

echo.
echo System Monitor stopped successfully.
pause

