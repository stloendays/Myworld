@echo off
setlocal
cd /d "%~dp0"
echo Dusk Lake diagnostics
echo 1. Default rendering
echo 2. OpenGL Compatibility rendering
echo 3. Gather existing logs only
choice /c 123 /n /m "Select 1-3: "
if errorlevel 3 goto collect
if errorlevel 2 goto opengl
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-DuskLakeCrash.ps1" -Mode default
goto end
:opengl
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-DuskLakeCrash.ps1" -Mode opengl
goto end
:collect
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-DuskLakeCrash.ps1" -NoLaunch
:end
echo.
pause
