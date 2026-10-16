@echo off
setlocal
rem Started by the setup program after it has unpacked Install-App.ps1, App-Core.ps1 and the release zip.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-App.ps1"
exit /b %errorlevel%
