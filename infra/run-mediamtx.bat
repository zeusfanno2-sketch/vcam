@echo off
title MediaMTX
cd /d "%~dp0mediamtx"
if not exist mediamtx.exe (
  echo Thieu mediamtx.exe
  pause
  exit /b 1
)
mediamtx.exe
