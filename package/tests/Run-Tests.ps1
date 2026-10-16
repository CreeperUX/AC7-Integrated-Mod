# Runs every AC7 tool test with Windows PowerShell 5.1. Fake folders only; the real game is never written.
$ErrorActionPreference='Stop'
$package=Split-Path $PSScriptRoot -Parent
$ps=Join-Path $PSHOME 'powershell.exe'
$runs=@(
 @{Name='Check-Package';Args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $package 'Check-Package.ps1'))},
 @{Name='Launcher-GUI -SmokeTest';Args=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $package 'Launcher-GUI.ps1'),'-SmokeTest','-NoDialog')},
 @{Name='Test-Lifecycle';Args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Test-Lifecycle.ps1'))},
 @{Name='Test-Keybindings';Args=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Test-Keybindings.ps1'))},
 @{Name='Test-Settings';Args=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Test-Settings.ps1'))},
 @{Name='Test-Discovery';Args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Test-Discovery.ps1'))},
 @{Name='Test-GuiLayout';Args=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Test-GuiLayout.ps1'))},
 @{Name='Test-App';Args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Test-App.ps1'))},
 @{Name='Test-ExtraMods';Args=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Test-ExtraMods.ps1'))}
)
# The native launcher test needs AC7 Integrated.exe built first (launcher\build.cmd); skipped with a note otherwise.
$root=Split-Path $package -Parent
if(@((Join-Path $root 'source\build\AC7 Integrated.exe'),(Join-Path $root 'native\build\AC7 Integrated.exe')) | Where-Object {Test-Path -LiteralPath $_}){$runs+=@{Name='Test-Launcher';Args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Test-Launcher.ps1'))}}
else{Write-Host 'NOTE Test-Launcher skipped: build AC7 Integrated.exe first (launcher\build.cmd).' -ForegroundColor Yellow}
$failed=0
foreach($run in $runs){
 $ErrorActionPreference='Continue'
 $output=@(& $ps @($run.Args) 2>&1 | ForEach-Object {"$_"});$code=$LASTEXITCODE
 $ErrorActionPreference='Stop'
 $output | ForEach-Object {Write-Host "  $_"}
 if($code -eq 0){Write-Host "PASS $($run.Name)" -ForegroundColor Green}else{$failed++;Write-Host "FAIL $($run.Name) (exit $code)" -ForegroundColor Red}
}
if($failed){Write-Host "$failed test run(s) failed." -ForegroundColor Red;exit 1}
Write-Host "All $($runs.Count) test runs passed." -ForegroundColor Green
exit 0
