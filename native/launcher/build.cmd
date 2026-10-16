@echo off
rem Builds ..\build\AC7 Integrated.exe with the .NET Framework 4 C# compiler included in Windows (no Visual Studio
rem needed). It references the Windows PowerShell 5.1 engine (System.Management.Automation) of this machine.
cd /d "%~dp0"
if not exist ..\build mkdir ..\build
python -X utf8 assembly-info.py ..\build\LauncherVersion.cs
if errorlevel 1 exit /b 1
set "AC7_SMA="
for /f "usebackq delims=" %%I in (`%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command "[PSObject].Assembly.Location"`) do set "AC7_SMA=%%I"
if not defined AC7_SMA exit /b 1
"%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:winexe /platform:anycpu /optimize+ /debug- /codepage:65001 /win32icon:..\..\package\app\AC7.ico /win32manifest:AC7-Launcher.manifest /reference:"%AC7_SMA%" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /out:"..\build\AC7 Integrated.exe" AC7-Launcher.cs ..\build\LauncherVersion.cs
exit /b %errorlevel%
