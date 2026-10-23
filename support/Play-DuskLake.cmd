@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-DuskLake.ps1"
if errorlevel 1 (
    echo.
    echo Startup failed. Review the DuskLake-Diagnostics ZIP on your Desktop.
    pause
    exit /b 1
)
exit /b 0
