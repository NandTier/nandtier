@echo off
rem NandTier setup for Windows: double-click this file, or run it in cmd /
rem PowerShell with options, e.g.  setup\setup.bat -Offline
rem Everything goes into the tools folder of the repository, no admin rights.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
set RC=%ERRORLEVEL%
echo.
if "%~1"=="" pause
exit /b %RC%
