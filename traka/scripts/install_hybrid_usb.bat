@echo off
REM Build APK hybrid + adb install ke HP (USB). Lihat install_hybrid_usb.ps1.
cd /d "%~dp0.."
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0install_hybrid_usb.ps1" %*
if errorlevel 1 pause
