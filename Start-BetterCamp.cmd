@echo off
setlocal DisableDelayedExpansion
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0bettercamp.ps1" %*
set "result=%ERRORLEVEL%"
if not "%result%"=="0" echo BetterCamp stopped. Read the error above.
pause
exit /b %result%
