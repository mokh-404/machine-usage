@echo off
REM run_windows.bat
REM One-Click Launcher for Windows
REM Starts Host Agent, Docker, and Web Dashboard

setlocal enabledelayedexpansion

title System Monitor - Windows Launcher

echo ============================================================
echo   System Monitoring Solution - Windows Launcher
echo ============================================================
echo.

REM Create metrics directory and clean old data
if not exist "metrics" mkdir metrics
del /q "metrics\*.json" 2>nul
del /q "metrics\*.csv" 2>nul

REM Check if Docker is running
docker info >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker is not running or not installed.
    echo Please start Docker Desktop and try again.
    pause
    exit /b 1
)

echo [1/4] Starting Host Agent in background...
echo Logs will be written to host_agent.log
start "HostAgent" /B cmd /c "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0host_agent_windows.ps1" -MetricsFile "%~dp0metrics\metrics.json" > "%~dp0host_agent.log" 2>&1"

echo Waiting for Host Agent to initialize...
set "RETRIES=0"
:wait_metrics
if exist "%~dp0metrics\metrics.json" goto metrics_found
timeout /t 1 /nobreak >nul
set /a RETRIES+=1
if %RETRIES% geq 10 (
    echo [WARNING] Host Agent has not created metrics file yet.
    echo Please check host_agent.log for errors.
    echo The Dashboard might show empty data until the Agent starts working.
    timeout /t 5
    goto continue_docker
)
goto wait_metrics

:metrics_found
echo Host Agent is active.

:continue_docker

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

echo [4/4] Launching Web Dashboard...
echo.
echo ============================================================
echo   System Monitor is Running
echo   Dashboard available at: http://localhost:8085
echo ============================================================
echo.
timeout /t 2 >nul
start http://localhost:8085

echo Attaching to container logs (Press Ctrl+C to stop)...
docker compose logs -f

:cleanup
echo.
echo Stopping Docker container...
docker compose stop
echo Stopping Host Agent...
Stop-Process -Name powershell -Force -ErrorAction SilentlyContinue
echo Done.
