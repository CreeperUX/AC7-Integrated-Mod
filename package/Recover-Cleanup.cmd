@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-Console.ps1" -Action Recover
set "AC7_RESULT=%errorlevel%"
pause
exit /b %AC7_RESULT%
