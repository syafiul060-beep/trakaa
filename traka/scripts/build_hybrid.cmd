@echo off
REM Jalankan build hybrid dari CMD: panggil PowerShell dengan ExecutionPolicy Bypass.
REM Contoh:
REM   cd /d D:\Traka\traka
REM   scripts\build_hybrid.cmd -ApiUrl "https://trakaa-production.up.railway.app" -Target appbundle
setlocal
cd /d "%~dp0.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_hybrid.ps1" %*
exit /b %ERRORLEVEL%
