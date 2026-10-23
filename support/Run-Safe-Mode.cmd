@echo off
setlocal
set "GAME=%~dp0DuskLake.exe"
if not exist "%GAME%" (
  echo DuskLake.exe not found. Put this file next to the game executable.
  pause
  exit /b 2
)
set "LOG=%TEMP%\DuskLake-safe-%RANDOM%.log"
echo OpenGL compatibility + low settings (where supported).
echo Detailed log: %LOG%
"%GAME%" --verbose --log-file "%LOG%" --rendering-method gl_compatibility --rendering-driver opengl3 -- --safe-mode
set "EXITCODE=%ERRORLEVEL%"
echo.
echo Dusk Lake exit code: %EXITCODE%
echo Send the log file to the developer after reviewing personal paths.
pause
exit /b %EXITCODE%
