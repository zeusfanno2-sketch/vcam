@echo off
title CAMKEY server (dong cua so = tat server)
cd /d "%~dp0"

rem tat task tu dong de tranh chay 2 instance
schtasks /Change /TN "CAMKEY Server" /DISABLE >nul 2>&1

rem giai phong port 8787 neu con instance cu
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":8787" ^| findstr "LISTENING"') do (
  taskkill /F /PID %%a >nul 2>&1
)

echo.
echo   CAMKEY server: http://127.0.0.1:8787
echo   Dong cua so nay de tat server.
echo.

node server.js
echo.
echo Server da tat.
pause
