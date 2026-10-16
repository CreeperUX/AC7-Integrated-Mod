param([switch]$Keep)
# Installed app (0.7.0) end to end in tests\tmp: setup from a built zip with import from a portable package that owns a
# FAKE game install and takeover by the app, signed updates and their refusals, rollback, offline and online repair (app
# files and the fake game install), launch diagnostics on a fake UE4SS.log (Steam is never started: -WhatIf), pruning,
# uninstall with the game cleanup, registration under a temporary HKCU\Software\AC7IntegratedTest key with a shortcut in
# the fixture, the signing scripts, the launcher update check and the setup program. No network (local fake feeds only),
# no real game, Steam or save folder; the real install root, uninstall entry and Start menu are never touched.
$ErrorActionPreference='Stop'
$source=Split-Path $PSScriptRoot -Parent
$realGame='D:\SteamLibrary\steamapps\common\ACE COMBAT 7'
$fixture=Join-Path $PSScriptRoot ('tmp\app-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $fixture | Out-Null
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem,System.Security
$powershell=Join-Path $PSHOME 'powershell.exe'
. (Join-Path $source 'app\App-Core.ps1')
. (Join-Path $source 'Install-Core.ps1')   # Read-AC7MouseSettings & co. for the assertions
$rsa=New-Object Security.Cryptography.RSACryptoServiceProvider(3072);$rsa.PersistKeyInCsp=$false
$other=New-Object Security.Cryptography.RSACryptoServiceProvider(3072);$other.PersistKeyInCsp=$false
$publicXml=$rsa.ToXmlString($false)
$testKeyRoot='HKCU:\Software\AC7IntegratedTest';$key=$testKeyRoot+'\'+[guid]::NewGuid().ToString('N');$link=Join-Path $fixture 'menu\AC7 Integrated.lnk'
$launcherExe=Join-Path $source 'AC7 Integrated.exe'
foreach($candidate in '..\source\build\AC7 Integrated.exe','..\native\build\AC7 Integrated.exe'){if(!(Test-Path -LiteralPath $launcherExe)){$launcherExe=[IO.Path]::GetFullPath((Join-Path $source $candidate))}}   # workspace / repository layout
$realManifest=Join-Path $realGame 'ue4ss\AC7-MouseAim-owner.json'
$realBefore=if(Test-Path -LiteralPath $realManifest){(Get-FileHash -LiteralPath $realManifest).Hash}else{''}
$realEntry=Test-Path -LiteralPath (Get-AC7AppUninstallKey);$realLink=Test-Path -LiteralPath (Get-AC7AppShortcutPath);$realInstall=Test-Path -LiteralPath (Get-AC7AppDefaultInstallRoot)
$script:checks=0
function Pass([string]$Text){$script:checks++;Write-Host "PASS $Text"}
function Assert-True([bool]$Condition,[string]$Message){if(!$Condition){throw $Message}}
function Write-FileList([string]$Dir){
 $lines=@(foreach($file in @(Get-ChildItem -LiteralPath $Dir -Recurse -File | Sort-Object FullName)){
  if($file.FullName -eq (Join-Path $Dir 'FILES.sha256')){continue}
  (Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant()+'  '+$file.FullName.Substring($Dir.Length+1).Replace('\','/')
 })
 [IO.File]::WriteAllText((Join-Path $Dir 'FILES.sha256'),(($lines -join "`n")+"`n"),(New-Object Text.UTF8Encoding($false)))
}
function New-TestRelease([string]$Version,[scriptblock]$Change={},[string]$KeyXml=$publicXml,[switch]$AfterList){
 # A release zip like build_release.py makes: one top folder AC7-Integrated-v<version>, FILES.sha256 of every file.
 $name='AC7-Integrated-v'+$Version;$base=Join-Path $fixture ('b-'+[guid]::NewGuid().ToString('N').Substring(0,6));$dir=Join-Path $base $name
 New-Item -ItemType Directory -Path $dir -Force | Out-Null
 Get-ChildItem -LiteralPath $source -File | Where-Object {$_.Extension -in '.ps1','.xaml','.json','.ini','.cmd','.txt','.md' -and $_.Name -notin 'migrations.json','app-settings.json','app-version.json'} | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $dir}
 foreach($folder in 'payload','ui','licenses','app'){Copy-Item -LiteralPath (Join-Path $source $folder) -Destination (Join-Path $dir $folder) -Recurse}
 if(Test-Path -LiteralPath $launcherExe){Copy-Item -LiteralPath $launcherExe -Destination $dir}
 foreach($empty in 'game-path.txt','steam-path.txt'){[IO.File]::WriteAllText((Join-Path $dir $empty),'')}
 $info=Join-Path $dir 'package-info.json';[IO.File]::WriteAllText($info,([regex]::Replace([IO.File]::ReadAllText($info),'"version"\s*:\s*"[^"]*"',('"version": "'+$Version+'"'))),(New-Object Text.UTF8Encoding($false)))
 [IO.File]::WriteAllText((Join-Path $dir 'app\update-key.xml'),$KeyXml)
 if(!$AfterList){& $Change $dir}
 Write-FileList $dir
 if($AfterList){& $Change $dir}
 $zipPath=Join-Path $base ($name+'.zip')
 [IO.Compression.ZipFile]::CreateFromDirectory($dir,$zipPath,[IO.Compression.CompressionLevel]::Fastest,$true)
 return [pscustomobject]@{Zip=$zipPath;Dir=$dir}
}
function New-TestFeed([string]$ZipPath,[string]$Tag='',$Signer=$rsa,[scriptblock]$EditManifest={},[object[]]$Extra=@(),[string]$UrlPrefix='https://github.com/CreeperUX/AC7-Integrated-Mod/releases/download/'){
 # A local stand-in for the GitHub release list: releases.json plus <tag>\<asset>.
 $name=[IO.Path]::GetFileName($ZipPath);$version=([regex]::Match($name,'^AC7-Integrated-v(.+)\.zip$')).Groups[1].Value
 $tagName=if($Tag){$Tag}else{'v'+$version}
 $feed=Join-Path $fixture ('f-'+[guid]::NewGuid().ToString('N').Substring(0,6));$assetDir=Join-Path $feed $tagName
 New-Item -ItemType Directory -Path $assetDir -Force | Out-Null;Copy-Item -LiteralPath $ZipPath -Destination $assetDir
 $manifest=[ordered]@{schema=1;product='AC7-Integrated';version=$version;asset=$name;sha256=(Get-FileHash -LiteralPath $ZipPath).Hash;size=(Get-Item -LiteralPath $ZipPath).Length}
 & $EditManifest $manifest
 $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes((ConvertTo-Json -InputObject ([pscustomobject]$manifest)))
 [IO.File]::WriteAllBytes((Join-Path $assetDir 'update-manifest.json'),$bytes)
 [IO.File]::WriteAllText((Join-Path $assetDir 'update-manifest.json.sig'),[Convert]::ToBase64String($Signer.SignData($bytes,'SHA256')))
 $assets=@(foreach($file in $name,'update-manifest.json','update-manifest.json.sig'){[pscustomobject]@{name=$file;size=(Get-Item -LiteralPath (Join-Path $assetDir $file)).Length;browser_download_url=($UrlPrefix+$tagName+'/'+$file)}})
 $release=[pscustomobject]@{tag_name=$tagName;html_url=('https://example.invalid/releases/'+$tagName);draft=$false;prerelease=($version -match '-');assets=$assets}
 [IO.File]::WriteAllText((Join-Path $feed 'releases.json'),(ConvertTo-Json -Depth 6 -InputObject @(@($release)+@($Extra))))
 return $feed
}
function Invoke-TestHost([string]$Root,[string[]]$Arguments){
 $previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
 try{$output=@(& $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'Host.ps1') @Arguments 2>&1 | ForEach-Object {[string]$_});$code=$LASTEXITCODE}finally{$ErrorActionPreference=$previous}
 return [pscustomobject]@{Code=$code;Text=($output -join "`n")}
}
function Invoke-TestScript([string]$Script,[string[]]$Arguments){
 $previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
 try{$output=@(& $powershell -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1 | ForEach-Object {[string]$_});$code=$LASTEXITCODE}finally{$ErrorActionPreference=$previous}
 return [pscustomobject]@{Code=$code;Text=($output -join "`n")}
}
function Get-TestState([string]$Root){return ([IO.File]::ReadAllText((Join-Path $Root 'app.json')) | ConvertFrom-Json)}
function Get-TestGame([string]$Game){return (Get-AC7InstallState $Game)}
function Assert-GameClean([string]$Game,[string]$Project,[string]$Version){
 $state=Get-AC7InstallState $Game
 if(!$state.Installed -or $state.Pending -or @($state.Entries | Where-Object Status -ne 'ok').Count -or @($state.UnownedLoader).Count){throw ('game install not clean: '+(Format-AC7StateText $state))}
 if($Project -and !(Test-AC7AppSamePath $state.Project $Project)){throw ('game owner is '+$state.Project+', expected '+$Project)}
 if($Version -and [string]$state.Manifest.Version -ne $Version){throw ('game mod version is '+$state.Manifest.Version+', expected '+$Version)}
 return $state
}

try{
# ---- 0. version order ----
foreach($case in @(@('0.7.0','0.7.0-beta.1',1),@('0.7.0-beta.2','0.7.0-beta.10',-1),@('0.7.1-beta.1','0.7.0',1),@('0.7.0-rc.1','0.7.0-beta.9',1),@('0.10.0','0.9.9',1),@('0.7.0-beta.1','0.7.0-beta.1',0),@('1.0.0-alpha.3','0.99.99',1))){
 Assert-True ((Compare-AC7AppVersion $case[0] $case[1]) -eq $case[2]) ('version order '+$case[0]+' vs '+$case[1])
}
Assert-True ((@(Get-AC7AppSortedVersions @('0.7.0-beta.2','0.7.0','0.7.0-beta.10','0.6.1-beta.1','bad')) -join ',') -eq '0.7.0,0.7.0-beta.10,0.7.0-beta.2,0.6.1-beta.1') 'sorted versions'
Pass 'version order: numeric major.minor.patch, release after prereleases, beta.N numeric'

# ---- 1. portable package that owns a fake game install ----
$save=Join-Path $fixture 'save';New-Item -ItemType Directory -Path (Join-Path $save 'SaveGames\1') -Force | Out-Null;[IO.File]::WriteAllText((Join-Path $save 'SaveGames\1\ACE7Save.sav'),'fake save')
$game=Join-Path $fixture 'steam\steamapps\common\ACE COMBAT 7'
New-Item -ItemType Directory -Path (Join-Path $game 'ue4ss\Mods\OtherProbe\Scripts') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $game 'Ace7Game.exe'),'fake AC7 executable for tests');[IO.File]::WriteAllText((Join-Path $game 'ue4ss\Mods\OtherProbe\Scripts\main.lua'),'print("other mod")')
$otherHash=(Get-FileHash -LiteralPath (Join-Path $game 'ue4ss\Mods\OtherProbe\Scripts\main.lua')).Hash
$steamExe=Join-Path $fixture 'steam\steam.exe';[IO.File]::WriteAllText($steamExe,'fake steam')
$r1=New-TestRelease '0.7.0-beta.1';$zip1=$r1.Zip
$portable=Join-Path $fixture 'Portable AC7';Copy-Item -LiteralPath $r1.Dir -Destination $portable -Recurse;Remove-Item -LiteralPath (Join-Path $portable 'FILES.sha256')
$ini=Join-Path $portable 'MouseAim-Settings.ini'
[IO.File]::WriteAllText($ini,(([IO.File]::ReadAllText($ini) -replace '(?m)^sensitivity=[^\r\n]*','sensitivity=0.23') -replace '(?m)^control_mode=[^\r\n]*','control_mode=0'),(New-Object Text.UTF8Encoding($true)))
[IO.File]::WriteAllText((Join-Path $portable 'migrations.json'),'{"applied":["war-default-0.7.0"]}')   # a 0.6.x player who chose PEACE
[IO.File]::WriteAllText((Join-Path $portable 'steam-path.txt'),$steamExe)
New-Item -ItemType Directory -Path (Join-Path $portable 'ue4ss-mods\TestMod\Scripts') -Force | Out-Null;[IO.File]::WriteAllText((Join-Path $portable 'ue4ss-mods\TestMod\Scripts\main.lua'),'print("x")')
$result=Invoke-TestScript (Join-Path $portable 'Setup.ps1') @('-GameRoot',$game,'-Features','guidance','-Yes','-SaveRoot',$save,'-TestOnlySkipExeHash')
Assert-True ($result.Code -eq 0 -and $result.Text -match 'INSTALLED features=guidance') ('portable install into the fake game: '+$result.Text)
Assert-GameClean $game $portable '0.7.0-beta.1' | Out-Null
# A key binding file the new version cannot read (conflict): rebuilt in data with a backup, the original left alone.
[IO.File]::WriteAllText((Join-Path $portable 'Keybindings.ini'),"[bindings]`r`nfree_look=C`r`nfree_look_zoom=C`r`n")
$portableBefore=@{};foreach($file in Get-ChildItem -LiteralPath $portable -Recurse -File){$portableBefore[$file.FullName]=(Get-FileHash -LiteralPath $file.FullName).Hash}
Pass 'fixture: portable package installed the mod into a fake game folder (owner = portable package)'

# ---- 2. setup: install, import from the portable package, take over the game install, register (test key) ----
$install=Join-Path $fixture 'AC7 Integrated'
$hostArgs=@('-Yes','-NoLaunch','-SaveRoot',$save,'-TestOnlySkipExeHash','-UninstallKey',$key,'-Shortcut',$link)
$result=Invoke-TestScript (Join-Path $source 'app\Install-App.ps1') (@('-Zip',$zip1,'-InstallRoot',$install,'-GameRoot',$game)+$hostArgs)
Assert-True ($result.Code -eq 0 -and $result.Text -match '\[INSTALLED\]' -and $result.Text -match '\[ADOPTED\]') ('setup failed: '+$result.Text)
$state=Get-TestState $install
Assert-True ($state.current -eq '0.7.0-beta.1' -and !$state.previous) 'app.json after setup'
$v1=Join-Path $install 'versions\0.7.0-beta.1';$data=Join-Path $install 'data'
foreach($pair in @(@('Host.ps1','Host.ps1'),@('App-Core.ps1','App-Core.ps1'),@('update-key.xml','trust\update-key.xml'),@('AC7.ico','AC7.ico'))){
 Assert-True ((Get-FileHash (Join-Path $v1 ('app\'+$pair[0]))).Hash -eq (Get-FileHash (Join-Path $install $pair[1])).Hash) ('host file '+$pair[1])
}
if(Test-Path -LiteralPath $launcherExe){Assert-True ((Get-FileHash (Join-Path $install 'AC7 Integrated.exe')).Hash -eq (Get-FileHash $launcherExe).Hash) 'native launcher in the install root'}
foreach($name in 'MouseAim-Settings.ini','Keybindings.ini','features.ini','game-path.txt','steam-path.txt','ue4ss-mods\TestMod\Scripts\main.lua','migrations.json','update-cache\0.7.0-beta.1\package.json','update-cache\0.7.0-beta.1\AC7-Integrated-v0.7.0-beta.1.zip'){Assert-True (Test-Path -LiteralPath (Join-Path $data $name)) ('data missing '+$name)}
Assert-True (!@(Get-AC7AppPackageProblems $v1).Count) 'installed version files'
Assert-True ((Get-Content -LiteralPath (Join-Path $v1 'app-version.json') -Raw | ConvertFrom-Json).version -eq '0.7.0-beta.1') 'app-version.json'
Assert-True ((Get-Content -LiteralPath (Join-Path $v1 'FILES.sha256') -Raw -Encoding UTF8) -match ([string][char]0x5F00+[char]0x59CB+[char]0x4F7F+[char]0x7528+'\.md')) 'file list names the Chinese files'
$values=Read-AC7MouseSettings (Join-Path $data 'MouseAim-Settings.ini')
Assert-True ($values.sensitivity -eq 0.23 -and $values.control_mode -eq 3) ('imported sensitivity kept, PEACE moved to WAR once: '+$values.sensitivity+' / '+$values.control_mode)
Assert-True ((Read-AC7FeatureSettings (Join-Path $data 'features.ini')).Features -eq 'guidance') 'imported installation scope'
$null=Read-AC7Keybindings (Join-Path $data 'Keybindings.ini')
Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $data 'repair-backups') -Recurse -Filter 'Keybindings.ini').Count -eq 1) 'unreadable imported key bindings rebuilt with a backup'
Assert-True ((Get-AC7AppSavedText $data 'game-path.txt') -eq $game -and (Get-AC7AppSavedText $data 'steam-path.txt') -eq $steamExe) 'game and Steam paths imported'
foreach($file in Get-ChildItem -LiteralPath $portable -Recurse -File){Assert-True ($portableBefore[$file.FullName] -eq (Get-FileHash -LiteralPath $file.FullName).Hash) ('portable file changed: '+$file.FullName)}
Assert-True (@(Get-ChildItem -LiteralPath $portable -Recurse -File).Count -eq $portableBefore.Count) 'portable package gained files'
$gameState=Assert-GameClean $game $install '0.7.0-beta.1'
Assert-True ($gameState.Features -eq 'guidance' -and [string]$gameState.Manifest.PreviousProject -eq $portable) 'game install taken over by the app, scope kept'
$config=[IO.File]::ReadAllText((Join-Path $game 'ue4ss\Mods\AC7MouseAim\config.ini'))
Assert-True ($config -match '(?m)^control_mode=3\r?$' -and $config -match '(?m)^sensitivity=0\.23\r?$') 'game config after takeover: WAR, imported sensitivity'
$probe=& $powershell -NoProfile -ExecutionPolicy Bypass -Command ". ([IO.Path]::Combine('$v1','PowerShell-Compat.ps1'));(Get-AC7DataRoot '$v1')+'|'+(Get-AC7ProjectRoot '$v1')"
Assert-True ($probe -eq ($data+'|'+$install)) ('layout resolution: '+$probe)
Pass 'setup: layout, host files, data import (settings, scope, paths, extra mods; unreadable keys rebuilt), WAR migration, portable untouched, game install taken over'
$props=Get-ItemProperty -LiteralPath $key
Assert-True ($props.DisplayName -eq 'AC7 Integrated' -and $props.DisplayVersion -eq '0.7.0-beta.1' -and $props.InstallLocation -eq $install -and $props.UninstallString -match [regex]::Escape((Join-Path $install 'Host.ps1')) -and $props.UninstallString -match '-Action Uninstall' -and $props.NoModify -eq 1) 'uninstall entry'
$shell=New-Object -ComObject WScript.Shell;$shortcut=$shell.CreateShortcut($link)
if(Test-Path -LiteralPath (Join-Path $install 'AC7 Integrated.exe')){
 Assert-True ($shortcut.TargetPath -eq (Join-Path $install 'AC7 Integrated.exe') -and !$shortcut.Arguments -and $shortcut.IconLocation -match 'AC7 Integrated\.exe' -and $props.DisplayIcon -eq (Join-Path $install 'AC7 Integrated.exe')) 'Start menu shortcut to the native launcher'
}else{Assert-True ($shortcut.Arguments -match [regex]::Escape('"'+(Join-Path $install 'Host.ps1')+'"') -and $shortcut.Arguments -match '-Action Gui' -and $shortcut.IconLocation -match 'AC7\.ico') 'Start menu shortcut'}
[void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
Assert-True (Test-AC7AppRegistered $install $key $link) 'registered'
$caught=$false;try{Register-AC7App $install '0.7.0-beta.1' 'HKLM:\Software\AC7IntegratedTest' (Join-Path $fixture 'x.lnk')}catch{$caught=$true};Assert-True $caught 'uninstall entry outside HKCU refused'
Pass 'registration: uninstall entry (temporary test key) and Start menu shortcut (fixture)'
$status=Invoke-TestHost $install @('-Action','Status')
$parsed=$status.Text | ConvertFrom-Json
Assert-True ($status.Code -eq 0 -and $parsed.current -eq '0.7.0-beta.1' -and $parsed.game.ownedByApp -eq $true -and $parsed.game.mode -eq 'enabled') ('host status: '+$status.Text)
Pass 'host status: versions and the game install (owned by the app, enabled)'
# The hosted exe is in use while the launcher is open: replacing it waits, then keeps the old one; never fails the caller.
if(Test-Path -LiteralPath (Join-Path $install 'AC7 Integrated.exe')){
 $newer=Join-Path $fixture 'newer-package';New-Item -ItemType Directory -Path $newer | Out-Null
 Copy-Item -LiteralPath (Join-Path $v1 'app') -Destination (Join-Path $newer 'app') -Recurse
 $exeBytes=[IO.File]::ReadAllBytes((Join-Path $v1 'AC7 Integrated.exe'));[IO.File]::WriteAllBytes((Join-Path $newer 'AC7 Integrated.exe'),($exeBytes+[byte[]](0)))
 $installed=Join-Path $install 'AC7 Integrated.exe';$before=(Get-FileHash $installed).Hash
 $lock=[IO.File]::Open($installed,'Open','Read','Read')
 try{$watch=[Diagnostics.Stopwatch]::StartNew();$changed=@(Install-AC7AppHostFiles $install $newer 1 6>$null);$watch.Stop()}finally{$lock.Dispose()}
 Assert-True ($changed -notcontains 'AC7 Integrated.exe' -and (Get-FileHash $installed).Hash -eq $before -and $watch.Elapsed.TotalSeconds -ge 0.9) 'exe in use: waited, old one kept, no error'
 Assert-True (!@(Get-ChildItem -LiteralPath $install -Filter '*.tmp' -File).Count) 'no temporary file left beside the exe'
 Assert-True (@(Install-AC7AppHostFiles $install $newer 1) -contains 'AC7 Integrated.exe' -and (Get-FileHash $installed).Hash -ne $before) 'exe replaced once free'
 $null=Install-AC7AppHostFiles $install $v1 1;Assert-True ((Get-FileHash $installed).Hash -eq $before) 'exe of the current version restored'
 Remove-Item -LiteralPath $newer -Recurse -Force
 Pass 'hosted exe in use: replacement waits, keeps the old exe without failing, replaces it once free'
}

# ---- 3. signed updates and refusals ----
$r2=New-TestRelease '0.7.0-beta.2' {param($dir)
 Add-Content -LiteralPath (Join-Path $dir 'app\Host.ps1') -Value '# 0.7.0-beta.2' -Encoding UTF8
 $settings=Join-Path $dir 'MouseAim-Settings.ps1'
 [IO.File]::WriteAllText($settings,([IO.File]::ReadAllText($settings).Replace('$rows=@(',('$rows=@('+"`r`n"+"  @('test_new_key','T','bool',0,1,0,'launcher','none','t'),"))),(New-Object Text.UTF8Encoding($true)))
}
$zip2=$r2.Zip
$draft=[pscustomobject]@{tag_name='v0.9.0';html_url='x';draft=$true;prerelease=$false;assets=@()}
$old=[pscustomobject]@{tag_name='v0.6.0-beta.1';html_url='x';draft=$false;prerelease=$true;assets=@()}
$feed2=New-TestFeed $zip2 -Extra @($draft,$old)
$dataIni=Join-Path $data 'MouseAim-Settings.ini'
[IO.File]::WriteAllText($dataIni,([IO.File]::ReadAllText($dataIni) -replace '(?m)^sensitivity=[^\r\n]*','sensitivity=0.31'),(New-Object Text.UTF8Encoding($true)))
$slip=Join-Path $fixture 'slip';New-Item -ItemType Directory -Path $slip | Out-Null;$slipZip=Join-Path $slip 'AC7-Integrated-v0.7.0-beta.2.zip'
$archive=[IO.Compression.ZipFile]::Open($slipZip,'Create');try{$entry=$archive.CreateEntry('AC7-Integrated-v0.7.0-beta.2/../../evil.txt');$writer=New-Object IO.StreamWriter($entry.Open());$writer.Write('x');$writer.Dispose()}finally{$archive.Dispose()}
$refusals=@(
 @{Name='bad signature';Feed=(New-TestFeed $zip2 -Signer $other);Code='UPDATE_SIGNATURE'},
 @{Name='hash mismatch';Feed=(New-TestFeed $zip2 -EditManifest {param($m) $m.sha256='0'*64});Code='UPDATE_HASH'},
 @{Name='manifest version differs from the tag';Feed=(New-TestFeed $zip2 -Tag 'v0.7.0-beta.9');Code='UPDATE_MANIFEST'},
 @{Name='download from another site';Feed=(New-TestFeed $zip2 -UrlPrefix 'https://example.invalid/releases/download/');Code='UPDATE_SOURCE'},
 @{Name='unlisted file';Feed=(New-TestFeed (New-TestRelease '0.7.0-beta.2' {param($dir) [IO.File]::WriteAllText((Join-Path $dir 'extra.ps1'),'x')} -AfterList).Zip);Code='PACKAGE_INVALID'},
 @{Name='package without the installed-app host';Feed=(New-TestFeed (New-TestRelease '0.7.0-beta.2' {param($dir) Remove-Item -LiteralPath (Join-Path $dir 'app') -Recurse}).Zip);Code='PACKAGE_INVALID'},
 @{Name='zip path traversal';Feed=(New-TestFeed $slipZip);Code='PACKAGE_INVALID'}
)
foreach($case in $refusals){
 $result=Invoke-TestHost $install (@('-Action','Update','-Feed',$case.Feed)+$hostArgs)
 Assert-True ($result.Code -ne 0 -and $result.Text -match $case.Code) ($case.Name+' was not refused: '+$result.Text)
 Assert-True ((Get-TestState $install).current -eq '0.7.0-beta.1' -and !(Test-Path -LiteralPath (Join-Path $install 'versions\0.7.0-beta.2'))) ($case.Name+' changed the installation')
}
Assert-True (!@(Get-ChildItem -LiteralPath $fixture -Recurse -Filter 'evil.txt').Count) 'path traversal wrote a file'
$result=Invoke-TestHost $install (@('-Action','Update','-Feed',(New-TestFeed $zip1))+$hostArgs)
Assert-True ($result.Code -eq 0 -and $result.Text -match '\[UP-TO-DATE\]' -and (Get-TestState $install).current -eq '0.7.0-beta.1') ('same version is not an update: '+$result.Text)
$olderFeed=Join-Path $fixture 'older-feed';New-Item -ItemType Directory -Path $olderFeed | Out-Null;[IO.File]::WriteAllText((Join-Path $olderFeed 'releases.json'),(ConvertTo-Json -Depth 5 -InputObject @($old,$draft)))
$result=Invoke-TestHost $install (@('-Action','Update','-Feed',$olderFeed)+$hostArgs)
Assert-True ($result.Code -eq 0 -and $result.Text -match '\[UP-TO-DATE\]' -and (Get-TestState $install).current -eq '0.7.0-beta.1') ('older version or draft is not an update: '+$result.Text)
# The game running from the saved folder blocks update, rollback and uninstall (mocked process).
$script:fakeProcesses=@([pscustomobject]@{Id=4242;Path=(Join-Path $game 'Ace7Game.exe')})
function Get-Process {param([string[]]$Name,$ErrorAction) $script:fakeProcesses}
foreach($action in @({Install-AC7AppUpdate -InstallRoot $install -Offer (Get-AC7AppUpdateOffer -InstallRoot $install -Feed $feed2) -Feed $feed2 -NoRegister},{Invoke-AC7AppRollback -InstallRoot $install -NoRegister},{Invoke-AC7AppUninstall -InstallRoot $install -NoRegister})){
 $code='';try{& $action | Out-Null}catch{$code=[string]$_.Exception.Data['AC7Code']}
 Assert-True ($code -eq 'APP_BUSY') ('running game not refused: '+$action+' -> '+$code)
}
$script:fakeProcesses=@([pscustomobject]@{Id=4243;Path='X:\Other Library\ACE COMBAT 7\Ace7Game.exe'})
Assert-True (!(Get-AC7AppBusyReason $install)) 'a game from another folder does not block'
Remove-Item Function:\Get-Process
Assert-True ((Get-TestState $install).current -eq '0.7.0-beta.1') 'busy refusals changed the installation'
Pass 'update refusals: bad signature, hash, tag/version, foreign URL, unlisted file, no host, path traversal, same/older/draft, game running'
$result=Invoke-TestHost $install (@('-Action','Update','-Feed',$feed2)+$hostArgs)
Assert-True ($result.Code -eq 0 -and $result.Text -match '\[UPDATED\]') ('update failed: '+$result.Text)
$state=Get-TestState $install
Assert-True ($state.current -eq '0.7.0-beta.2' -and $state.previous -eq '0.7.0-beta.1') 'app.json after update'
Assert-True ((Get-Content -LiteralPath (Join-Path $install 'Host.ps1') -Raw) -match '# 0\.7\.0-beta\.2') 'host updated from the new version'
Assert-True ((Read-AC7MouseSettings $dataIni).sensitivity -eq 0.31) 'player settings kept across the update'
Assert-True ((Test-Path -LiteralPath (Join-Path $data 'update-cache\0.7.0-beta.2\package.json')) -and !@(Get-ChildItem -LiteralPath (Join-Path $data 'update-cache') -Directory -Filter 'incoming-*').Count) 'update cache'
Assert-GameClean $game $install '0.7.0-beta.2' | Out-Null
Assert-True ((Get-ItemProperty -LiteralPath $key).DisplayVersion -eq '0.7.0-beta.2') 'uninstall entry version after the update'
Pass 'signed update: newest non-draft release (prereleases included), switched, settings kept, game install redeployed to 0.7.0-beta.2'
$result=Invoke-TestHost $install @('-Action','CheckUpdate','-Feed',$feed2)
Assert-True ($result.Code -eq 0 -and $result.Text -match '\[UP-TO-DATE\] 0\.7\.0-beta\.2') ('check update (current): '+$result.Text)

# ---- 4. launcher update check (portable and installed) ----
$check=Invoke-AC7LauncherUpdateCheck $portable $false $feed2
Assert-True ($check.Success -and $check.Update -eq '0.7.0-beta.2' -and !$check.Installed -and $check.Current -eq '0.7.0-beta.1') ('portable update check: '+($check | ConvertTo-Json -Compress))
Assert-True (!(Test-AC7AppUpdateCheckDue $portable)) 'check time recorded'
$settings=Get-AC7AppSettings $portable;Assert-True ($settings.auto_update_check -eq $true -and $settings.last_check_utc) 'app settings after a check'
$quiet=Invoke-AC7LauncherUpdateCheck $portable $true (Join-Path $fixture 'no-feed')
Assert-True ($quiet.Success -and !$quiet.Title -and !$quiet.Update) 'failed automatic check stays silent'
$loud=Invoke-AC7LauncherUpdateCheck $portable $false (Join-Path $fixture 'no-feed')
Assert-True (!$loud.Success -and $loud.Title) 'failed manual check is reported'
$bad=Invoke-AC7LauncherUpdateCheck $portable $false (New-TestFeed $zip2 -Signer $other)
Assert-True (!$bad.Success -and $bad.Message -match '签名') 'unsigned offer is not shown'
Set-AC7AppSettings $portable ([ordered]@{auto_update_check=$true;last_check_utc=[DateTime]::UtcNow.AddHours(-30).ToString('o')});Assert-True (Test-AC7AppUpdateCheckDue $portable) 'check due after 20 hours'
Set-AC7AppSettings $portable ([ordered]@{auto_update_check=$false;last_check_utc=''});Assert-True (!(Test-AC7AppUpdateCheckDue $portable)) 'automatic check switched off'
$installedCheck=Invoke-AC7LauncherUpdateCheck (Join-Path $install 'versions\0.7.0-beta.2') $false $feed2
Assert-True ($installedCheck.Success -and !$installedCheck.Update -and $installedCheck.Installed -and (Test-Path -LiteralPath (Join-Path $data 'app-settings.json'))) 'installed update check: up to date, settings in data'
$caught='';try{Start-AC7AppHostAction $portable 'Update' | Out-Null}catch{$caught=[string]$_.Exception.Data['AC7Code']};Assert-True ($caught -eq 'APP_PORTABLE') 'portable cannot run host actions'
Pass 'launcher update check: offer verified with the signed manifest, silent automatic failure, 20-hour schedule, switch, installed settings in data'

# ---- 5. rollback: settings the newer version wrote are made readable for the older one; game redeployed ----
Add-Content -LiteralPath $dataIni -Value 'test_new_key=1' -Encoding UTF8
$result=Invoke-TestHost $install (@('-Action','Rollback')+$hostArgs)
Assert-True ($result.Code -eq 0 -and $result.Text -match '\[ROLLED BACK\]') ('rollback failed: '+$result.Text)
$state=Get-TestState $install
Assert-True ($state.current -eq '0.7.0-beta.1' -and $state.previous -eq '0.7.0-beta.2') 'app.json after rollback'
Assert-True ((Read-AC7MouseSettings $dataIni).sensitivity -eq 0.31) 'rollback kept the readable settings'
Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $data 'repair-backups') -Recurse -Filter 'MouseAim-Settings.ini').Count -eq 1) 'rollback backed up the unreadable settings'
Assert-GameClean $game $install '0.7.0-beta.1' | Out-Null
Assert-True ((Get-ItemProperty -LiteralPath $key).DisplayVersion -eq '0.7.0-beta.1') 'uninstall entry version after the rollback'
Pass 'rollback: previous version current again, settings made readable (backup), game install back to 0.7.0-beta.1'

# ---- 6. repair: app files offline from the cache and online from the release; the game install ----
$damaged=Join-Path $install 'versions\0.7.0-beta.1\Install-Core.ps1';Add-Content -LiteralPath $damaged -Value '# damaged' -Encoding UTF8
Remove-Item -LiteralPath (Join-Path $install 'versions\0.7.0-beta.1\Setup.ps1')
[IO.File]::WriteAllText((Join-Path $install 'App-Core.ps1'),'# damaged')
$quick=@(Invoke-AC7AppRepair -InstallRoot $install -Quick -NoRegister)
Assert-True (!@($quick | Where-Object Status -eq 'problem').Count -and @($quick | Where-Object Status -eq 'fixed').Count -eq 2) ('quick repair: '+(($quick | ForEach-Object Message) -join ' / '))
Assert-True (!@(Get-AC7AppPackageProblems (Join-Path $install 'versions\0.7.0-beta.1')).Count) 'version files restored from the cache'
Assert-True ((Get-FileHash (Join-Path $install 'App-Core.ps1')).Hash -eq (Get-FileHash (Join-Path $install 'versions\0.7.0-beta.2\app\App-Core.ps1')).Hash) 'host files follow the newest intact version'
Remove-AC7AppTree (Join-Path $data 'update-cache\0.7.0-beta.1');Add-Content -LiteralPath $damaged -Value '# damaged' -Encoding UTF8
$quick=@(Invoke-AC7AppRepair -InstallRoot $install -Quick -NoRegister)
Assert-True (@($quick | Where-Object Status -eq 'problem').Count -eq 1) 'without a cache the quick check reports the damage'
$result=Invoke-TestHost $install @('-Action','Launch','-Yes','-WhatIf','-ReadyTimeout','1','-TestOnlySkipExeHash')
Assert-True ($result.Code -eq 1 -and $result.Text -match 'APP_DAMAGED' -and $result.Text -match 'Install-Core\.ps1') ('launch with damaged program files must stop: '+$result.Text)
$full=@(Invoke-AC7AppRepair -InstallRoot $install -Feed (New-TestFeed $zip1) -NoRegister -SaveRoot $save -TestOnlySkipExeHash)
Assert-True (@($full | Where-Object {$_.Item -eq '程序文件' -and $_.Status -eq 'fixed'}).Count -eq 1 -and !@(Get-AC7AppPackageProblems (Join-Path $install 'versions\0.7.0-beta.1')).Count) ('online repair of the same version: '+(($full | ForEach-Object Message) -join ' / '))
Assert-True ((Test-Path -LiteralPath (Join-Path $data 'update-cache\0.7.0-beta.1\package.json')) -and !@($full | Where-Object Status -eq 'problem').Count) 'online repair refreshed the cache, nothing else to fix'
[IO.File]::WriteAllText((Join-Path $install 'app.json'),'{broken')
$quick=@(Invoke-AC7AppRepair -InstallRoot $install -Quick -NoRegister)
Assert-True ((Get-TestState $install).current -eq '0.7.0-beta.2' -and @($quick | Where-Object Item -eq '版本记录').Count) 'app.json rebuilt from the installed versions'
Pass 'repair: quick offline repair from the cached zip, damage reported without cache (launch stops), online repair of the same version, app.json rebuilt'
# The game install: a changed flight-control DLL and a deleted loader (security software) stop the launch; repair restores.
$dll=Join-Path $game 'ue4ss\Mods\AC7MouseAim\Scripts\ac7_mouse_aim.dll';[IO.File]::AppendAllText($dll,'quarantined')
$damagedDll=(Get-FileHash -LiteralPath $dll).Hash
Remove-Item -LiteralPath (Join-Path $game 'dwmapi.dll')
[IO.File]::WriteAllText((Join-Path $data 'features.ini'),"features=everything`r`n")
$result=Invoke-TestHost $install @('-Action','Launch','-Yes','-WhatIf','-ReadyTimeout','1','-TestOnlySkipExeHash')
Assert-True ($result.Code -eq 1 -and $result.Text -match '\[GAME_FILES_BLOCKED\]' -and $result.Text -match 'dwmapi\.dll' -and $result.Text -match 'ac7_mouse_aim\.dll' -and $result.Text -notmatch '502500') ('launch with blocked game files must stop before Steam: '+$result.Text)
$result=Invoke-TestHost $install (@('-Action','Repair','-Offline')+$hostArgs)
Assert-True ($result.Code -eq 0 -and $result.Text -match '\[REPAIRED\]') ('repair failed: '+$result.Text)
$gameState=Assert-GameClean $game $install '0.7.0-beta.2'
Assert-True ($gameState.Features -eq 'guidance' -and $gameState.Mode -eq 'enabled') 'repair kept the installed scope and the enabled loader'
Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $data 'backups') -Recurse -Filter 'ac7_mouse_aim.dll' | Where-Object {(Get-FileHash -LiteralPath $_.FullName).Hash -eq $damagedDll}).Count -ge 1) 'changed DLL backed up before it was restored'
Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $data 'repair-backups') -Recurse -Filter 'features.ini').Count -eq 1 -and (Read-AC7FeatureSettings (Join-Path $data 'features.ini')).Features -eq 'guidance') 'unreadable features.ini rebuilt with a backup and set to the installed scope'
Pass 'game repair: blocked loader/DLL stops the launch (security software hint), repair restores them through Invoke-AC7Install -Repair (backup first), scope kept'

# ---- 7. launch diagnostics on the fake UE4SS.log (Steam is never started: -WhatIf) ----
$log=Join-Path $game 'ue4ss\UE4SS.log'
$banner=Get-AC7AppExpectedBanner $game 'none'
Assert-True ($banner -ne 'none' -and $banner -match '^\d+\.\d+\.\d+') ('banner version from the installed full.lua: '+$banner)
$launchArgs=@('-Action','Launch','-Yes','-WhatIf','-ReadyTimeout','2','-TestOnlySkipExeHash')
[IO.File]::WriteAllText($log,"[2026-10-15] Starting mods`r`n[Lua] [AC7FullControl] AC7 $banner (test) ready`r`n");[IO.File]::SetLastWriteTimeUtc($log,[DateTime]::UtcNow.AddHours(1))
$result=Invoke-TestHost $install $launchArgs
Assert-True ($result.Code -eq 0 -and $result.Text -match '\[READY\]' -and $result.Text -match 'steam\.exe -applaunch 502500') ('ready launch: '+$result.Text)
[IO.File]::SetLastWriteTimeUtc($log,[DateTime]::UtcNow.AddHours(-1))
$result=Invoke-TestHost $install $launchArgs
Assert-True ($result.Code -eq 3 -and $result.Text -match '\[NOT READY\]' -and $result.Text -match 'UE4SS') ('no new UE4SS.log: '+$result.Text)
[IO.File]::WriteAllText($log,"[Lua] [AC7MouseAim] error: main.lua:15: AC7 full core refused: verify native log, runtime and game build`r`n");[IO.File]::SetLastWriteTimeUtc($log,[DateTime]::UtcNow.AddHours(1))
$result=Invoke-TestHost $install $launchArgs
Assert-True ($result.Code -eq 3 -and $result.Text -match '\[NOT READY\]' -and $result.Text -match 'refused') ('refused core: '+$result.Text)
$since=[DateTime]::UtcNow.AddMinutes(-1)
[IO.File]::WriteAllText($log,"[Lua] [AC7FullControl] ERROR attempt to index nil`r`n");Assert-True ((Get-AC7AppReadiness $log $since $banner).State -eq 'failed') 'ERROR line is not ready'
[IO.File]::WriteAllText($log,"[Lua] [AC7FullControl] AC7 0.0.1-beta.1 (old)`r`n");$r=Get-AC7AppReadiness $log $since $banner;Assert-True ($r.State -eq 'failed' -and $r.Reason -match '0\.0\.1-beta\.1') 'another flight-control version is not ready'
[IO.File]::WriteAllText($log,"Starting mods`r`n");$r=Get-AC7AppReadiness $log $since $banner;Assert-True ($r.State -eq 'waiting' -and $r.Reason -match 'AC7MouseAim') 'mouse-aim module not loaded yet'
[IO.File]::WriteAllText($log,"[Lua] [OtherMod] request refused by server`r`n[Lua] [AC7MouseAim] loading`r`n");Assert-True ((Get-AC7AppReadiness $log $since $banner).State -eq 'waiting') 'another mod''s refused line is not ours'
[IO.File]::WriteAllText($log,"[Lua] Error: Mods\AC7MouseAim\Scripts\full.lua:20: attempt to call a nil value`r`n");$r=Get-AC7AppReadiness $log $since $banner;Assert-True ($r.State -eq 'failed' -and $r.Reason -match 'full\.lua:20') 'mouse-aim script error is not ready'
[IO.File]::WriteAllText($log,"[Lua] [AC7FullControl] AC7 $banner x`r`n")
$stream=[IO.File]::Open($log,'Open','ReadWrite','ReadWrite');try{Assert-True ((Get-AC7AppReadiness $log $since $banner).State -eq 'ready') 'log held open by the game'}finally{$stream.Dispose()}
Assert-True ((Wait-AC7AppReady (Join-Path $game 'ue4ss\none.log') $since $banner 0 10).Reason -match 'UE4SS') 'wait without any log'
# Disabled mod: original launch, nothing to wait for.
$current=(Get-TestState $install).current
$result=Invoke-TestScript (Join-Path $install ('versions\'+$current+'\Mod-Mode.ps1')) @('-Action','Disable','-GameRoot',$game)
Assert-True ($result.Code -eq 0 -and $result.Text -match 'MODE disabled') ('disable: '+$result.Text)
$result=Invoke-TestHost $install $launchArgs
Assert-True ($result.Code -eq 0 -and $result.Text -match '\[ORIGINAL\]') ('launch with the mod disabled: '+$result.Text)
$result=Invoke-TestScript (Join-Path $install ('versions\'+$current+'\Mod-Mode.ps1')) @('-Action','Enable','-GameRoot',$game,'-TestOnlySkipExeHash')
Assert-True ($result.Code -eq 0 -and $result.Text -match 'MODE enabled') ('enable: '+$result.Text)
# Version switched without a redeploy (e.g. the game was running): the launch brings the game install up to date first.
$null=Invoke-AC7AppRollback -InstallRoot $install -NoRegister
[IO.File]::WriteAllText($log,"[Lua] [AC7FullControl] AC7 $banner (test)`r`n");[IO.File]::SetLastWriteTimeUtc($log,[DateTime]::UtcNow.AddHours(1))
$result=Invoke-TestHost $install $launchArgs
Assert-True ($result.Code -eq 0 -and $result.Text -match '\[READY\]') ('launch after a version switch: '+$result.Text)
Assert-GameClean $game $install (Get-TestState $install).current | Out-Null
Pass 'launch diagnostics: [READY] on the banner, [NOT READY] without a new UE4SS.log / refused core / errors / other version, [ORIGINAL] when disabled, redeploy before launch'

# ---- 8. pruning: a third version removes the oldest ----
$state=Get-TestState $install
$r3=New-TestRelease '0.7.0-beta.3'
$result=Invoke-TestHost $install (@('-Action','Update','-Feed',(New-TestFeed $r3.Zip))+$hostArgs)
Assert-True ($result.Code -eq 0) ('second update: '+$result.Text)
$names=@(Get-ChildItem -LiteralPath (Join-Path $install 'versions') -Directory -Force | ForEach-Object Name | Sort-Object)
$expected=(@('0.7.0-beta.3',[string]$state.current) | Sort-Object) -join ','
Assert-True (($names -join ',') -eq $expected) ('pruned versions: '+($names -join ','))
$gone=if($state.current -eq '0.7.0-beta.1'){'0.7.0-beta.2'}else{'0.7.0-beta.1'}
Assert-True (!(Test-Path -LiteralPath (Join-Path $data ('update-cache\'+$gone)))) 'pruned cache'
Assert-GameClean $game $install '0.7.0-beta.3' | Out-Null
Pass 'pruning: current and previous versions kept, the older one and its cache removed'

# ---- 9. uninstall: the game install is cleaned first (backup), data kept, registration removed ----
$result=Invoke-TestHost $install @('-Action','Uninstall','-Yes','-UninstallKey',$key,'-Shortcut',$link)
Assert-True ($result.Code -eq 0 -and $result.Text -match '\[UNINSTALLED\]') ('uninstall failed: '+$result.Text)
Assert-True ((@(Get-ChildItem -LiteralPath $install -Force | ForEach-Object Name) -join ',') -eq 'data' -and (Test-Path -LiteralPath $dataIni)) 'uninstall keeps only data'
Assert-True (!(Test-Path -LiteralPath $key) -and !(Test-Path -LiteralPath $link)) 'uninstall entry and shortcut removed'
$after=Get-AC7InstallState $game
Assert-True (!$after.Installed -and !@($after.UnownedLoader).Count -and !(Test-Path -LiteralPath (Join-Path $game 'dwmapi.dll')) -and !(Test-Path -LiteralPath (Join-Path $game 'ue4ss\AC7-MouseAim-owner.json'))) 'game folder cleaned'
Assert-True ((Get-FileHash -LiteralPath (Join-Path $game 'ue4ss\Mods\OtherProbe\Scripts\main.lua')).Hash -eq $otherHash) 'unrelated mod untouched'
Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $data 'cleanup-backups') -Recurse -Filter 'dwmapi.dll').Count -ge 1) 'cleanup backup kept in data'
$install2=Join-Path $fixture 'Second\AC7 Integrated'
$result=Invoke-TestScript (Join-Path $source 'app\Install-App.ps1') @('-Zip',$zip1,'-InstallRoot',$install2,'-NoImport','-NoAdopt','-Yes','-NoRegister','-NoLaunch')
Assert-True ($result.Code -eq 0 -and !(Get-AC7AppSavedText (Join-Path $install2 'data') 'game-path.txt')) ('setup without import: '+$result.Text)
$result=Invoke-TestHost $install2 @('-Action','Uninstall','-Yes','-NoRegister','-RemoveData')
Assert-True ($result.Code -eq 0 -and !(Test-Path -LiteralPath $install2)) ('uninstall with data removal: '+$result.Text)
$caught='';try{Invoke-AC7AppUninstall -InstallRoot $fixture -NoRegister | Out-Null}catch{$caught=[string]$_.Exception.Data['AC7Code']}
Assert-True ($caught -eq 'APP_LAYOUT' -and (Test-Path -LiteralPath $portable)) 'uninstall refuses a folder that is not an installation'
Pass 'uninstall: game install removed by Invoke-AC7Cleanup (backup in data), program files and registration removed, data kept or removed on request'

# ---- 10. release signing scripts (a throwaway key in %TEMP%, never the release key) ----
$keyDir=Join-Path ([IO.Path]::GetTempPath()) ('ac7-signing-test-'+[guid]::NewGuid().ToString('N'));$private=Join-Path $keyDir 'key.dpapi';$public=Join-Path $fixture 'release-key.xml'
try{
 foreach($inside in @((Join-Path $source 'tools\inside.dpapi'),(Join-Path $fixture 'inside.dpapi'))){
  $caught=$false;try{& (Join-Path $source 'tools\new-update-key.ps1') -PrivateKeyPath $inside -PublicKeyPath $public}catch{$caught=$true}
  Assert-True ($caught -and !(Test-Path -LiteralPath $inside)) ('private key inside the package/workspace must be refused: '+$inside)
 }
 & (Join-Path $source 'tools\new-update-key.ps1') -PrivateKeyPath $private -PublicKeyPath $public 6>$null | Out-Null
 Assert-True ((Get-Content -LiteralPath $public -Raw) -notmatch '<D>' -and (Get-Content -LiteralPath $public -Raw) -match '<Modulus>') 'public key only'
 $caught=$false;try{& (Join-Path $source 'tools\new-update-key.ps1') -PrivateKeyPath $private -PublicKeyPath $public}catch{$caught=$true};Assert-True $caught 'existing private key must not be replaced'
 $signedZip=(New-TestRelease '0.8.0' {} ([IO.File]::ReadAllText($public))).Zip
 $out=Join-Path $fixture 'signed';& (Join-Path $source 'tools\sign-release.ps1') -Zip $signedZip -PrivateKeyPath $private -OutDir $out 6>$null | Out-Null
 $bytes=[IO.File]::ReadAllBytes((Join-Path $out 'update-manifest.json'))
 Assert-True (Test-AC7AppUpdateSignature $bytes ([IO.File]::ReadAllText((Join-Path $out 'update-manifest.json.sig'))) $public) 'signed manifest verifies'
 $manifest=[Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
 Assert-True ($manifest.product -eq 'AC7-Integrated' -and $manifest.version -eq '0.8.0' -and $manifest.asset -eq 'AC7-Integrated-v0.8.0.zip' -and $manifest.sha256 -eq (Get-FileHash $signedZip).Hash -and $manifest.size -eq (Get-Item $signedZip).Length) 'manifest content'
 $bytes[10]=$bytes[10] -bxor 1;Assert-True (!(Test-AC7AppUpdateSignature $bytes ([IO.File]::ReadAllText((Join-Path $out 'update-manifest.json.sig'))) $public)) 'changed manifest must fail'
 $caught=$false;try{& (Join-Path $source 'tools\sign-release.ps1') -Zip $zip1 -PrivateKeyPath $private -OutDir (Join-Path $fixture 'signed2')}catch{$caught=$true}
 Assert-True $caught 'a package with another public key must not be signed'
}finally{if(Test-Path -LiteralPath $keyDir){Remove-Item -LiteralPath $keyDir -Recurse -Force}}
Pass 'signing scripts: key outside the workspace only, never replaced; manifest signed and checked against the key inside the zip'

# ---- 11. setup program (IExpress, part of Windows): build and unpack only, never run the installer here ----
if(Test-Path -LiteralPath (Join-Path $env:SystemRoot 'System32\iexpress.exe')){
 $setupOut=Join-Path $fixture 'setup';New-Item -ItemType Directory -Path $setupOut | Out-Null
 & (Join-Path $source 'tools\build-setup.ps1') -Zip $zip1 -OutDir $setupOut 6>$null | Out-Null
 $exe=Join-Path $setupOut 'AC7-Integrated-Setup-v0.7.0-beta.1.exe';$unpacked=Join-Path $fixture 'setup-unpacked'
 $text=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($exe))
 Assert-True ($text -match 'requestedExecutionLevel\s+level="asInvoker"') 'setup program must not ask for administrator rights'
 $process=Start-Process -FilePath $exe -ArgumentList @('/Q','/C',('"/T:'+$unpacked+'"')) -Wait -PassThru
 Assert-True ($process.ExitCode -eq 0) 'setup program unpack'
 foreach($pair in @(@('AC7-Integrated-v0.7.0-beta.1.zip',$zip1),@('Install-App.ps1',(Join-Path $source 'app\Install-App.ps1')),@('App-Core.ps1',(Join-Path $source 'app\App-Core.ps1')),@('install.cmd',(Join-Path $source 'app\install.cmd')))){
  Assert-True ((Get-FileHash (Join-Path $unpacked $pair[0])).Hash -eq (Get-FileHash $pair[1]).Hash) ('setup program content '+$pair[0])
 }
 Assert-True (Test-Path -LiteralPath ($exe+'.sha256')) 'setup program checksum'
 Pass 'setup program: IExpress package, asInvoker, unpacks the zip with Install-App.ps1, App-Core.ps1 and install.cmd'
}else{Write-Host 'SKIP setup program: IExpress is not available here.'}

# ---- the real system was not touched ----
$realAfter=if(Test-Path -LiteralPath $realManifest){(Get-FileHash -LiteralPath $realManifest).Hash}else{''}
Assert-True ($realAfter -eq $realBefore) 'Real AC7 manifest changed during the test!'
Assert-True ((Test-Path -LiteralPath (Get-AC7AppUninstallKey)) -eq $realEntry -and (Test-Path -LiteralPath (Get-AC7AppShortcutPath)) -eq $realLink -and (Test-Path -LiteralPath (Get-AC7AppDefaultInstallRoot)) -eq $realInstall) 'real uninstall entry, shortcut or install root changed!'
Pass 'real game install, uninstall entry, Start menu shortcut and install root unchanged'
}finally{
 $rsa.Dispose();$other.Dispose()
 if(Test-Path -LiteralPath $testKeyRoot){Remove-Item -LiteralPath $testKeyRoot -Recurse -Force}
 if(!$Keep -and (Test-Path -LiteralPath $fixture)){try{Remove-AC7AppTree $fixture}catch{Write-Host ('Fixture not fully removed: '+$_.Exception.Message)}}
}
Write-Host "PASS installed app: $script:checks groups (version order, setup with import and takeover, registration, status, signed updates with refusals, launcher update check, rollback, app and game repair, launch diagnostics, pruning, uninstall, signing scripts, setup program)"
exit 0
