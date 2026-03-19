@echo off
REM Build Traka untuk APK/App Bundle (bypass Execution Policy)
cd /d "%~dp0.."
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0build_hybrid.ps1" %*
if errorlevel 1 pause
