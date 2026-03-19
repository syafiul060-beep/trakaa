@echo off
REM Jalankan run_hybrid.ps1 via PowerShell (bypass Execution Policy)
cd /d "%~dp0.."
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0run_hybrid.ps1" %*
if errorlevel 1 pause
