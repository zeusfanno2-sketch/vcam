@echo off
title CAMKEY tunnel
cd /d "%~dp0"
:loop
echo [%date% %time%] starting cloudflared...>> tunnel.log
cloudflared.exe tunnel --url http://127.0.0.1:8787 --no-autoupdate >> tunnel.log 2>&1
echo [%date% %time%] cloudflared exited, restart in 5s>> tunnel.log
timeout /t 5 /nobreak >nul
goto loop
