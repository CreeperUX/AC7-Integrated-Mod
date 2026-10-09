@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-Console.ps1" -Action Start
set "AC7_RESULT=%errorlevel%"
if not "%AC7_RESULT%"=="0" pause
exit /b %AC7_RESULT%
