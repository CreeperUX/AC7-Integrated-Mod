$ErrorActionPreference='Stop'
# AC7 Integrated.exe (0.7.0, ported from AC8 2.5.0 native\launcher): the player tool as its own Windows application. A
# Windows-subsystem .NET program with the AC7 icon, version information and an asInvoker manifest, no build-machine
# paths; it hosts the launcher scripts in its own process (Host.ps1 -Action Gui at an install root, Launcher-GUI.ps1 in a
# package folder). Checked with --dry-run (nothing started) and --smoke (Launcher-GUI.ps1 -SmokeTest inside the exe: real
# WPF buttons, busy state and the asynchronous worker, without showing a window). Needs the launcher build first
# (source\launcher\build.cmd in the workspace, native\launcher\build.cmd in the repository).
$package=Split-Path $PSScriptRoot -Parent;$root=Split-Path $package -Parent
$exe=@((Join-Path $root 'source\build\AC7 Integrated.exe'),(Join-Path $root 'native\build\AC7 Integrated.exe')) | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
if(!$exe){throw 'Build the launcher first (launcher\build.cmd).'}
function Assert-True([bool]$Condition,[string]$Message){if(!$Condition){throw $Message}}
$bytes=[IO.File]::ReadAllBytes($exe);$pe=[BitConverter]::ToInt32($bytes,0x3c)
Assert-True ([BitConverter]::ToUInt16($bytes,$pe+24+68) -eq 2) 'must be a Windows (GUI) subsystem program, not a console program'
$text=[Text.Encoding]::ASCII.GetString($bytes)
Assert-True ($text -match 'requestedExecutionLevel\s+level="asInvoker"') 'must not ask for administrator rights'
Assert-True ($text -notmatch '(?i)[a-z]:[\\/]+users[\\/]') 'build-machine path in the program'
$version=(Get-Content -LiteralPath (Join-Path $package 'package-info.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version
$info=(Get-Item -LiteralPath $exe).VersionInfo
Assert-True ($info.ProductName -eq 'AC7 Integrated' -and $info.FileDescription -eq 'AC7 Integrated' -and $info.FileVersion -eq ($version -replace '-.*$','') -and $info.ProductVersion -eq $version -and $info.CompanyName -eq 'CreeperUX') ('version information: '+$info.FileVersion+' / '+$info.ProductVersion)
Add-Type -AssemblyName System.Drawing
$icon=[Drawing.Icon]::ExtractAssociatedIcon($exe);Assert-True ($icon.Width -ge 32) 'embedded icon';$icon.Dispose()
$fixture=Join-Path $PSScriptRoot ('tmp\launcher-'+[guid]::NewGuid().ToString('N').Substring(0,8))
foreach($case in @(
 @{Name='install root';Files=@('Host.ps1','Launcher-GUI.ps1');Code=0;Expect='host: {0}\Host.ps1 -Action Gui'},
 @{Name='package folder';Files=@('Launcher-GUI.ps1');Code=0;Expect='launcher: {0}\Launcher-GUI.ps1'},
 @{Name='nothing to start';Files=@();Code=2;Expect='error: *'}
)){
 $dir=Join-Path $fixture (($case.Name -replace ' ','-')+' 含空格');New-Item -ItemType Directory -Path $dir -Force | Out-Null
 Copy-Item -LiteralPath $exe -Destination $dir;foreach($file in $case.Files){[IO.File]::WriteAllText((Join-Path $dir $file),'')}
 $out=Join-Path $fixture (($case.Name -replace ' ','-')+'.txt')
 $process=Start-Process -FilePath (Join-Path $dir 'AC7 Integrated.exe') -ArgumentList @('--dry-run',('"'+$out+'"')) -Wait -PassThru
 $result=[IO.File]::ReadAllText($out,[Text.Encoding]::UTF8)
 Assert-True ($process.ExitCode -eq $case.Code) ($case.Name+': exit '+$process.ExitCode)
 Assert-True ($result -like ($case.Expect -f $dir)) ($case.Name+': '+$result)
}
# The launcher itself, hosted in the exe (no powershell.exe child), on a copy of the package (player data left out).
$copy=Join-Path $fixture 'package 含空格';New-Item -ItemType Directory -Path $copy | Out-Null
Get-ChildItem -LiteralPath $package -File | Where-Object {$_.Extension -in '.ps1','.xaml','.json','.ini','.cmd','.txt','.md' -and $_.Name -notin 'migrations.json','app-settings.json'} | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $copy}
foreach($dir in 'payload','ui','app','licenses'){Copy-Item -LiteralPath (Join-Path $package $dir) -Destination (Join-Path $copy $dir) -Recurse}
foreach($name in 'game-path.txt','steam-path.txt'){[IO.File]::WriteAllText((Join-Path $copy $name),'')}
Copy-Item -LiteralPath $exe -Destination $copy
$out=Join-Path $fixture 'smoke.txt'
$process=Start-Process -FilePath (Join-Path $copy 'AC7 Integrated.exe') -ArgumentList @('--smoke',('"'+$out+'"')) -Wait -PassThru
$result=[IO.File]::ReadAllText($out,[Text.Encoding]::UTF8)
Assert-True ($process.ExitCode -eq 0 -and $result -match 'exit=0' -and $result -match 'PASS real GUI button' -and $result -match 'PASS update and repair controls') ('hosted launcher smoke: '+$result)
Remove-Item -LiteralPath $fixture -Recurse -Force
Write-Host 'PASS AC7 Integrated.exe: GUI subsystem, icon, version, asInvoker, no build paths; Host.ps1 -Action Gui at an install root, Launcher-GUI.ps1 in a package folder (paths with spaces and Chinese); the launcher runs inside the exe (smoke)'
