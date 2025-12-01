@echo off
title OS Project - Hybrid Monitor

echo [1/3] Creating shared folder...
if not exist "reports" mkdir reports

echo [2/3] Starting Docker Container...
docker-compose up -d --build

echo [3/3] Starting Host Agent...
echo.
echo ========================================================
echo  Docker is running in background.
echo  This window is now the HOST AGENT.
echo  Do NOT close this window, or real data will stop.
echo ========================================================
echo.

powershell -ExecutionPolicy Bypass -File .\host_agent.ps1

:: When user closes the window or stops script, stop docker
echo Stopping Docker...
docker-compose down
pause