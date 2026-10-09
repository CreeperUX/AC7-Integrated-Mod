param([string]$WorkRoot,[switch]$Keep)
# Install -> update -> disable -> enable -> uninstall against a TEMPORARY FAKE game folder, plus adoption of a
# Codex-style install, refusals that must leave everything byte-identical, fault injection and journal rollback.
# Runs on a copy of the package so the package's own settings files are never changed.
# Never touches the real AC7 install or the real save folder (both are only read, at most).
$ErrorActionPreference='Stop'
$source=Split-Path $PSScriptRoot -Parent
$realGame='D:\SteamLibrary\steamapps\common\ACE COMBAT 7'
if(!$WorkRoot){$WorkRoot=Join-Path $PSScriptRoot ('tmp\lifecycle-'+[guid]::NewGuid().ToString('N').Substring(0,8))}
$work=[IO.Path]::GetFullPath($WorkRoot)
if($work.StartsWith($realGame,[StringComparison]::OrdinalIgnoreCase) -or ($work.IndexOf('\tests\tmp\',[StringComparison]::OrdinalIgnoreCase) -lt 0 -and !$work.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase))){throw "Unsafe work root: $work"}
New-Item -ItemType Directory -Path $work -Force | Out-Null
$script:count=0
function Pass([string]$Text){$script:count++;Write-Host "PASS $Text"}
function Get-Snapshot([string]$Path){
 if(!(Test-Path -LiteralPath $Path)){return ''}
 $root=[IO.Path]::GetFullPath($Path).TrimEnd('\')
 return (@(Get-ChildItem -LiteralPath $root -Recurse -Force | Sort-Object FullName | ForEach-Object {
  $relative=$_.FullName.Substring($root.Length+1)
  if($_.PSIsContainer){'D|'+$relative}else{'F|'+$relative+'|'+(Get-FileHash -LiteralPath $_.FullName).Hash}
 }) -join "`n")
}
$realManifest=Join-Path $realGame 'ue4ss\AC7-MouseAim-owner.json'
$realBefore=if(Test-Path -LiteralPath $realManifest){(Get-FileHash -LiteralPath $realManifest).Hash}else{''}

# Package copy (scripts, payload, fonts); tests, docs and runtime folders are excluded.
$pkg=Join-Path $work 'pkg'
New-Item -ItemType Directory -Path $pkg | Out-Null
Get-ChildItem -LiteralPath $source -File | Where-Object {$_.Extension -in '.ps1','.xaml','.json','.ini','.cmd','.txt','.md'} | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $pkg}
foreach($dir in 'payload','ui'){Copy-Item -LiteralPath (Join-Path $source $dir) -Destination (Join-Path $pkg $dir) -Recurse}
# Paths remembered by the user's launcher must not leak into the copy (tests expect no saved game/Steam path).
foreach($name in 'game-path.txt','steam-path.txt'){[IO.File]::WriteAllText((Join-Path $pkg $name),'',[Text.UTF8Encoding]::new($false))}
. (Join-Path $pkg 'Gui-Core.ps1')
$layout=Get-AC7Layout

# Fake game folder: a fake Ace7Game.exe plus an unrelated UE4SS mod folder that must never be touched.
$game=Join-Path $work 'fake-steam\steamapps\common\ACE COMBAT 7'
New-Item -ItemType Directory -Path (Join-Path $game 'ue4ss\Mods\OtherProbe\Scripts') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $game 'Ace7Game.exe') -Value 'fake AC7 executable for tests' -Encoding ASCII
Set-Content -LiteralPath (Join-Path $game 'ue4ss\Mods\OtherProbe\Scripts\main.lua') -Value 'print("other mod")' -Encoding ASCII
$save=Join-Path $work 'fake-localappdata\ACE COMBAT 7'
New-Item -ItemType Directory -Path (Join-Path $save 'SaveGames\1') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $save 'SaveGames\1\ACE7Save.sav') -Value 'fake save' -Encoding ASCII
$ps=Join-Path $PSHOME 'powershell.exe'
function Invoke-Tool([string]$Script,[string[]]$Arguments,[int]$Expect=0){
 $previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
 try{$output=@(& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkg $Script) @Arguments 2>&1 | ForEach-Object {"$_"});$code=$LASTEXITCODE}
 finally{$ErrorActionPreference=$previous}
 $text=$output -join "`n"
 if($code -ne $Expect){throw "$Script exited $code (expected $Expect):`n$text"}
 return $text
}
function Assert-Clean([string]$Root,[int]$Files){
 $state=Get-AC7InstallState $Root
 if(!$state.Installed -or $state.Pending -or @($state.Entries | Where-Object Status -ne 'ok').Count -or @($state.UnownedLoader).Count){throw 'Install state not clean: '+(Format-AC7StateText $state)}
 if($Files -and @($state.Entries).Count -ne $Files){throw "Expected $Files owned files, found $(@($state.Entries).Count)"}
 return $state
}
$otherBefore=(Get-FileHash -LiteralPath (Join-Path $game 'ue4ss\Mods\OtherProbe\Scripts\main.lua')).Hash

# --- Guards -----------------------------------------------------------------------------------------------
$caught=$false;try{Assert-AC7TestOnlyFolder $realGame}catch{$caught=$true};if(!$caught){throw 'Test-only bypass accepted the real Steam library'}
Pass 'test-only exe-hash bypass is refused for the real Steam library path'
$before=Get-Snapshot $game
$text=Invoke-Tool 'Setup.ps1' @('-GameRoot',$game,'-Features','weapons','-Yes','-SaveRoot',$save) 1
if($text -notmatch '游戏版本与本包适配版本不一致' -or (Get-Snapshot $game) -ne $before){throw "Fake exe was not refused by the build check: $text"}
Pass 'fake Ace7Game.exe is refused without the explicit test-only parameter; nothing written'

$payloadEntries=Get-Content -LiteralPath (Join-Path $pkg 'payload-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json;$payloadCount=$payloadEntries.Count;$mouseCount=@($payloadEntries | Where-Object {$_.Path -notlike "*AC7Weapons*"}).Count   # PS 5.1: @(...|ConvertFrom-Json) would count the array as one item
$weaponsCount=$payloadCount-$mouseCount
# --- 1. Fresh install (mouse aim + AC7Weapons, full tier via the 0.5.x alias "weapons") ----------------------
$text=Invoke-Tool 'Setup.ps1' @('-GameRoot',$game,'-Features','weapons','-Yes','-SaveRoot',$save,'-TestOnlySkipExeHash')
if($text -notmatch "INSTALLED features=full mode=enabled new=$payloadCount updated=0 removed=0"){throw "Unexpected install summary:`n$text"}
$state=Assert-Clean $game $payloadCount
if($state.Foreign -or $state.Mode -ne 'enabled' -or $state.Features -ne 'full' -or [string]$state.Manifest.Features -ne 'full'){throw 'Manifest fields wrong after install'}
$weaponsSettings=Join-Path $game $layout.WeaponsSettings
if((Get-FileHash -LiteralPath $weaponsSettings).Hash -ne (Get-FileHash -LiteralPath (Join-Path $pkg ('payload\'+$layout.WeaponsSettings))).Hash){throw 'Full tier settings.lua differs from the payload file'}
$config=[IO.File]::ReadAllText((Join-Path $game $layout.Config))
if($config -notmatch '(?m)^\[keybindings\]\r$' -or $config -notmatch '(?m)^hud_boresight=1\r$' -or $config -notmatch '(?m)^free_look=67\r$'){throw 'Generated config.ini lacks keybindings/hud_boresight'}
if(([IO.File]::ReadAllText((Join-Path $game $layout.ModsList))) -ne "AC7MouseAim : 1`r`nAC7Weapons : 1`r`n"){throw 'mods.txt wrong for weapons'}
$backup=@(Get-ChildItem -LiteralPath (Join-Path $pkg 'backups') -Directory)[0].FullName
if((Get-FileHash -LiteralPath (Join-Path $backup 'savedata\SaveGames\1\ACE7Save.sav')).Hash -ne (Get-FileHash -LiteralPath (Join-Path $save 'SaveGames\1\ACE7Save.sav')).Hash){throw 'Save folder not backed up'}
if(Test-Path -LiteralPath (Join-Path $game $layout.Pending)){throw 'Pending journal left after install'}
Pass "fresh install: $payloadCount files hash-verified, manifest written, config.ini extended, mods.txt, save folder backed up"

# --- 2. Disable for multiplayer ----------------------------------------------------------------------------
$text=Invoke-Tool 'Mod-Mode.ps1' @('-Action','Disable','-GameRoot',$game)
if($text -notmatch 'MODE disabled' -or (Test-Path -LiteralPath (Join-Path $game 'dwmapi.dll'))){throw "Disable failed:`n$text"}
if((Get-FileHash -LiteralPath (Join-Path $game $layout.DisabledLoader)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $pkg 'payload\dwmapi.dll')).Hash){throw 'Disabled loader hash wrong'}
$state=Assert-Clean $game $payloadCount;if($state.Mode -ne 'disabled' -or [string]$state.Manifest.ModState -ne 'disabled'){throw 'Manifest not disabled'}
$text=Invoke-Tool 'Mod-Mode.ps1' @('-Action','Disable','-GameRoot',$game);if($text -notmatch 'MODE disabled'){throw 'Repeated disable failed'}
Pass 'disable: loader moved to ue4ss\dwmapi.dll.disabled, verified, manifest updated; repeat is a no-op'

# --- 3. Update while disabled: switch to mouse-only and new settings ----------------------------------------
$settings=Read-AC7MouseSettings (Join-Path $pkg 'MouseAim-Settings.ini');$settings.sensitivity=0.2;$settings.control_mode=0
Save-AC7MouseSettings $pkg $settings
$bindings=Read-AC7Keybindings (Join-Path $pkg 'Keybindings.ini');$bindings.free_look='V';Save-AC7Keybindings $pkg $bindings
$text=Invoke-Tool 'Setup.ps1' @('-GameRoot',$game,'-Features','mouse','-Yes','-SaveRoot',$save,'-TestOnlySkipExeHash')
if($text -notmatch "INSTALLED features=mouse mode=disabled new=0 updated=\d+ removed=$weaponsCount"){throw "Unexpected update summary:`n$text"}
$state=Assert-Clean $game $mouseCount
if(Test-Path -LiteralPath (Join-Path $game 'ue4ss\Mods\AC7Weapons')){throw 'AC7Weapons folder not removed'}
if(Test-Path -LiteralPath (Join-Path $game 'dwmapi.dll')){throw 'Update re-enabled the loader'}
$config=[IO.File]::ReadAllText((Join-Path $game $layout.Config))
if($config -notmatch '(?m)^sensitivity=0\.2\r$' -or $config -notmatch '(?m)^control_mode=0\r$' -or $config -notmatch '(?m)^free_look=86\r$' -or ([regex]::Matches($config,'(?m)^free_look_zoom=')).Count -ne 2){throw 'Settings not applied to config.ini'}
if(([IO.File]::ReadAllText((Join-Path $game $layout.ModsList))) -ne "AC7MouseAim : 1`r`n"){throw 'mods.txt wrong for mouse-only'}
Pass "update while disabled: AC7Weapons removed ($weaponsCount), settings/keys written, loader stays disabled"

# --- 4. Enable for single-player ----------------------------------------------------------------------------
$before=Get-Snapshot $game
$text=Invoke-Tool 'Mod-Mode.ps1' @('-Action','Enable','-GameRoot',$game) 1
if($text -notmatch '游戏版本与本包适配版本不一致' -or (Get-Snapshot $game) -ne $before){throw 'Enable without the test parameter was not refused by the build check'}
$text=Invoke-Tool 'Mod-Mode.ps1' @('-Action','Enable','-GameRoot',$game,'-TestOnlySkipExeHash')
if($text -notmatch 'MODE enabled' -or !(Test-Path -LiteralPath (Join-Path $game 'dwmapi.dll')) -or (Test-Path -LiteralPath (Join-Path $game $layout.DisabledLoader))){throw "Enable failed:`n$text"}
$state=Assert-Clean $game $mouseCount;if($state.Mode -ne 'enabled'){throw 'Mode not enabled'}
Pass 'enable: build check enforced; loader restored to dwmapi.dll and verified'
# Steam start (-WhatIf: nothing is launched): URL fallback without steam.exe, -applaunch with it; mode is reported.
# (Windows PowerShell drops empty native arguments: omit -SteamPath; the copy's steam-path.txt is empty.)
$text=Invoke-Tool 'Launch-AC7-via-Steam.ps1' @('-GameRoot',$game,'-WhatIf')
if($text -notmatch 'steam://rungameid/502500' -or $text -notmatch '单人 Mod 模式'){throw "Steam start (URL) unexpected:`n$text"}
$fakeSteam=Join-Path $work 'fake-steam\steam.exe';Set-Content -LiteralPath $fakeSteam -Value 'fake steam' -Encoding ASCII
$text=Invoke-Tool 'Launch-AC7-via-Steam.ps1' @('-GameRoot',$game,'-SteamPath',$fakeSteam,'-WhatIf')
if($text -notmatch 'steam.exe -applaunch 502500'){throw "Steam start (exe) unexpected:`n$text"}
Pass 'Steam start: steam.exe -applaunch 502500 or steam://rungameid/502500, current mode reported (WhatIf, nothing launched)'

# --- 5. Update back to full, then an idempotent re-run; guidance tier and back -----------------------------
$text=Invoke-Tool 'Setup.ps1' @('-GameRoot',$game,'-Features','full','-Yes','-SaveRoot',$save,'-TestOnlySkipExeHash')
if($text -notmatch "INSTALLED features=full mode=enabled new=$weaponsCount updated=1 removed=0"){throw "Unexpected re-add summary:`n$text"}
$text=Invoke-Tool 'Setup.ps1' @('-GameRoot',$game,'-Features','full','-Yes','-SaveRoot',$save,'-TestOnlySkipExeHash')
if($text -notmatch 'new=0 updated=0 removed=0'){throw "Re-run was not idempotent:`n$text"}
Assert-Clean $game $payloadCount | Out-Null
Pass "update: AC7Weapons re-added ($weaponsCount new, mods.txt updated); identical re-run changes nothing"
$text=Invoke-Tool 'Setup.ps1' @('-GameRoot',$game,'-Features','guidance','-Yes','-SaveRoot',$save,'-TestOnlySkipExeHash')
if($text -notmatch 'INSTALLED features=guidance mode=enabled new=0 updated=1 removed=0'){throw "Unexpected guidance summary:`n$text"}
$state=Assert-Clean $game $payloadCount
if($state.Features -ne 'guidance' -or [IO.File]::ReadAllText($weaponsSettings) -notmatch "return \{missile_mode='guidance'\}" -or ([IO.File]::ReadAllText((Join-Path $game $layout.ModsList))) -ne "AC7MouseAim : 1`r`nAC7Weapons : 1`r`n"){throw 'Guidance tier not installed'}
$text=Invoke-Tool 'Setup.ps1' @('-GameRoot',$game,'-Features','full','-Yes','-SaveRoot',$save,'-TestOnlySkipExeHash')
if($text -notmatch 'INSTALLED features=full mode=enabled new=0 updated=1 removed=0' -or (Assert-Clean $game $payloadCount).Features -ne 'full'){throw "Back to full failed:`n$text"}
if((Get-FileHash -LiteralPath $weaponsSettings).Hash -ne (Get-FileHash -LiteralPath (Join-Path $pkg ('payload\'+$layout.WeaponsSettings))).Hash){throw 'Full tier settings.lua not restored'}
Pass 'missile tiers: full -> guidance rewrites only AC7Weapons settings.lua (missile_mode=guidance); back to full restores the payload file'

# --- 6. Settings sync into the installed config.ini ------------------------------------------------------
$settings=Read-AC7MouseSettings (Join-Path $pkg 'MouseAim-Settings.ini');$settings.hud_opacity=0.5;$settings.follow_rate=12
Save-AC7MouseSettings $pkg $settings $game
$sync=Sync-AC7GameConfig $pkg $game
if(!$sync.Applied -or [IO.File]::ReadAllText((Join-Path $game $layout.Config)) -notmatch '(?m)^hud_opacity=0\.5\r$' -or [IO.File]::ReadAllText((Join-Path $game $layout.CameraSettings)) -notmatch 'follow_rate=12'){throw "Sync failed: $($sync.Message)"}
Assert-Clean $game $payloadCount | Out-Null
$sync=Sync-AC7GameConfig $pkg $game;if(!$sync.Applied -or $sync.Message -notmatch '已是'){throw 'Repeated sync not a no-op'}
Pass 'settings sync: config.ini and camera-settings.lua rewritten in place, manifest hashes updated'

# --- 7. Refusals leave everything byte-identical -------------------------------------------------------
$configPath=Join-Path $game $layout.Config;$original=[IO.File]::ReadAllBytes($configPath)
[IO.File]::AppendAllText($configPath,"; edited by hand`r`n")
$before=Get-Snapshot $game
$text=Invoke-Tool 'Setup.ps1' @('-GameRoot',$game,'-Features','weapons','-Yes','-SaveRoot',$save,'-TestOnlySkipExeHash') 1
if($text -notmatch '被修改过' -or (Get-Snapshot $game) -ne $before){throw "Modified owned file not refused:`n$text"}
$sync=Sync-AC7GameConfig $pkg $game;if($sync.Applied -or (Get-Snapshot $game) -ne $before){throw 'Sync overwrote a modified config.ini'}
Pass 'modified owned config.ini: install/update and settings sync refuse, nothing changed'
$text=Invoke-Tool 'Mod-Mode.ps1' @('-Action','Disable','-GameRoot',$game);if($text -notmatch 'MODE disabled'){throw 'Disable blocked by an unrelated modified file'}
$before=Get-Snapshot $game
$text=Invoke-Tool 'Mod-Mode.ps1' @('-Action','Enable','-GameRoot',$game,'-TestOnlySkipExeHash') 1
if($text -notmatch '被修改过' -or (Get-Snapshot $game) -ne $before){throw 'Enable with a modified file not refused'}
[IO.File]::WriteAllBytes($configPath,$original)
$text=Invoke-Tool 'Mod-Mode.ps1' @('-Action','Enable','-GameRoot',$game,'-TestOnlySkipExeHash');if($text -notmatch 'MODE enabled'){throw 'Enable after restoring config failed'}
Pass 'disable still works with only config.ini modified (multiplayer safety); enable refuses until restored'
Set-Content -LiteralPath (Join-Path $game $layout.DisabledLoader) -Value 'someone else' -Encoding ASCII
$before=Get-Snapshot $game
$text=Invoke-Tool 'Mod-Mode.ps1' @('-Action','Disable','-GameRoot',$game) 1
if($text -notmatch '不属于本工具的加载器' -or (Get-Snapshot $game) -ne $before){throw "Unowned disabled-loader file not refused:`n$text"}
Remove-Item -LiteralPath (Join-Path $game $layout.DisabledLoader)
Pass 'unknown file at ue4ss\dwmapi.dll.disabled: switch refused, nothing changed'
# Game running from this folder (mocked process): every mutating action refuses; another folder does not block.
$script:fakeProcesses=@([pscustomobject]@{Id=4242;Path=(Join-Path $game 'Ace7Game.exe')})
function Get-Process {param([string[]]$Name,$ErrorAction) $script:fakeProcesses}
$before=Get-Snapshot $game
foreach($action in @({Invoke-AC7Install -PackageRoot $pkg -GameRoot $game -Features weapons -SaveRoot $save -TestOnlySkipExeHash},{Set-AC7ModMode -PackageRoot $pkg -GameRoot $game -Action Disable},{Invoke-AC7Cleanup -PackageRoot $pkg -GameRoot $game -Confirmed},{Sync-AC7GameConfig $pkg $game},{Start-AC7ViaSteam $pkg $game '' -WhatIf})){
 $code='';try{& $action | Out-Null}catch{$code=[string]$_.Exception.Data['AC7Code']}
 if($code -ne 'GAME_RUNNING'){throw "Running game not refused: $action"}
}
if((Get-Snapshot $game) -ne $before){throw 'Running-game refusal changed files'}
$script:fakeProcesses=@([pscustomobject]@{Id=4243;Path='X:\Other Library\ACE COMBAT 7\Ace7Game.exe'})
if(Test-AC7GameRunning $game){throw 'A game running from another folder blocked this one'}
$script:fakeProcesses=@([pscustomobject]@{Id=4244;Path=$null})
if(!(Test-AC7GameRunning $game)){throw 'Unreadable process path must count as running'}
Remove-Item Function:\Get-Process
Pass 'running game (same folder) refuses install/switch/uninstall/sync; other folder ignored; unreadable path is conservative'

# --- 8. Uninstall ----------------------------------------------------------------------------------------
New-Item -ItemType Directory -Path (Join-Path $game 'ue4ss\Mods\AC7MouseAim\Logs') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $game 'ue4ss\Mods\AC7MouseAim\Logs\MouseAim-test.log') -Value 'native log' -Encoding ASCII
Set-Content -LiteralPath (Join-Path $game 'ue4ss\UE4SS.log') -Value '[AC7FullControl] test line' -Encoding ASCII
Set-Content -LiteralPath (Join-Path $game 'ue4ss\Mods\AC7MouseAim\Scripts\full-health.csv') -Value 'time_s' -Encoding ASCII
$before=Get-Snapshot $game
$text=Invoke-Tool 'Analyze-Latest.ps1' @('-GameRoot',$game)
$session=@(Get-ChildItem -LiteralPath (Join-Path $pkg 'sessions') -Directory)[0].FullName
foreach($name in 'UE4SS.log','full-health.csv','config.ini','summary.txt','native-logs\MouseAim-test.log'){if(!(Test-Path -LiteralPath (Join-Path $session $name))){throw "Log collection lacks $name"}}
if((Get-Snapshot $game) -ne $before){throw 'Log collection changed the game folder'}
Pass 'log collection: UE4SS.log, native Logs, CSV and config copied to sessions\flight-* with summary; game folder unchanged'
$text=Invoke-Tool 'Recover-Cleanup.ps1' @('-GameRoot',$game) 1
if($text -notmatch '卸载尚未确认' -or (Get-Snapshot $game) -ne $before){throw 'Unconfirmed uninstall not refused'}
$text=Invoke-Tool 'Recover-Cleanup.ps1' @('-GameRoot',$game,'-CheckOnly')
if($text -notmatch "CLEANUP removed=$payloadCount retained=0" -or (Get-Snapshot $game) -ne $before){throw "Cleanup check changed files:`n$text"}
$text=Invoke-Tool 'Recover-Cleanup.ps1' @('-GameRoot',$game,'-Confirmed')
if($text -notmatch "CLEANUP removed=$payloadCount retained=0"){throw "Uninstall failed:`n$text"}
$left=@(Get-ChildItem -LiteralPath $game -Recurse -File -Force | ForEach-Object {$_.FullName.Substring($game.Length+1)} | Sort-Object)
$expected=@('Ace7Game.exe','ue4ss\Mods\AC7MouseAim\Logs\MouseAim-test.log','ue4ss\Mods\AC7MouseAim\Scripts\full-health.csv','ue4ss\Mods\OtherProbe\Scripts\main.lua','ue4ss\UE4SS.log' | Sort-Object)
if(($left -join '|') -ne ($expected -join '|')){throw ('Unexpected files after uninstall: '+($left -join ', '))}
if((Get-FileHash -LiteralPath (Join-Path $game 'ue4ss\Mods\OtherProbe\Scripts\main.lua')).Hash -ne $otherBefore){throw 'Other mod touched'}
$archive=@(Get-ChildItem -LiteralPath (Join-Path $pkg 'cleanup-backups') -Directory)[0].FullName
foreach($relative in 'logs\native-logs\MouseAim-test.log','logs\UE4SS.log','logs\full-health.csv','files\dwmapi.dll','AC7-MouseAim-owner.json','cleanup-report.json'){if(!(Test-Path -LiteralPath (Join-Path $archive $relative))){throw "Archive lacks $relative"}}
if(!(Get-AC7InstallState $game).Installed -and @((Get-AC7InstallState $game).UnownedLoader).Count -eq 0){}else{throw 'Game still reports an install'}
Pass "uninstall: confirmation required; $payloadCount owned files removed after verified backup; logs archived and kept; other mod untouched"
$text=Invoke-Tool 'Recover-Cleanup.ps1' @('-GameRoot',$game,'-Confirmed');if($text -notmatch 'removed=0'){throw 'Second uninstall not a no-op'}
Pass 'uninstall again: nothing to do'

# --- 9. Adopt a Codex-style install (other project, no Tool field), with settings import -----------------
$game2=Join-Path $work 'fake-steam-2\steamapps\common\ACE COMBAT 7'
New-Item -ItemType Directory -Path $game2 -Force | Out-Null
Set-Content -LiteralPath (Join-Path $game2 'Ace7Game.exe') -Value 'fake AC7 executable for tests' -Encoding ASCII
$payload=Join-Path $pkg 'payload'
$codexConfig=[IO.File]::ReadAllText((Join-Path $payload $layout.Config))
$codexConfig=$codexConfig -replace "\r\n\r\n; Reference gun cross[^\r\n]*\r\nhud_boresight=1",''
$codexConfig=$codexConfig -replace "\r\n; Reticle stroke width[^\r\n]*\r\nhud_line_width=1",''
$codexConfig=$codexConfig.Substring(0,$codexConfig.IndexOf("`r`n; Additional optical"))
$codexConfig=$codexConfig.Replace("; 1 = reticle (ring, gun cross, HMD rings, ticks), panel and notices on the GPU overlay at native resolution (default);`r`n; 3 = reticle inside the game HUD layer (1920x1080, HUD glow) + GPU panel/notices; 0 = legacy small windows.`r`n; Backend selected at startup.`r`nhud_renderer=1","; GPU compositor=1, legacy small windows=0. Backend selected at startup.`r`nhud_renderer=1")
# The 0.5.0 config.ini is a pure extension: removing the added lines gives back the deployed Codex/0.5.0-stage file.
if((Get-AC7BytesHash ([Text.Encoding]::ASCII.GetBytes($codexConfig))) -ne 'B6B51DF85DA5D1852D5D3A85ADFF71C173CF12A96276550E68240B4A813AE412'){throw 'Payload config.ini is not a pure extension of the deployed file'}
$codexConfig=$codexConfig.Replace('sensitivity=0.10','sensitivity=0.15').Replace('control_mode=3','control_mode=0')
$files=@()
foreach($file in Get-ChildItem -LiteralPath $payload -File -Recurse){
 $relative=$file.FullName.Substring($payload.Length+1)
 if($relative -like '*\ui-fonts\*'){continue}
 $target=Join-Path $game2 $relative;New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
 if($relative -ieq $layout.Config){[IO.File]::WriteAllText($target,$codexConfig,[Text.UTF8Encoding]::new($false))}else{Copy-Item -LiteralPath $file.FullName -Destination $target}
 $files+=[ordered]@{SHA256=(Get-FileHash -LiteralPath $target).Hash;Relative=$relative}
}
$codex=[ordered]@{GameRoot=$game2;Files=$files;UTC='2026-10-05T00:32:19Z';Backup='C:\Codex\AC7-Mouse-Aim\sessions\deploy-20261005';Project='C:\Codex\AC7-Mouse-Aim';ClaudeStage=[ordered]@{Version='AC7-0.5.0-candidate';UTC='20261008T060602Z';Backup='C:\Claude\backup'}}
[IO.File]::WriteAllText((Join-Path $game2 $layout.Manifest),($codex | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($true))
$state=Get-AC7InstallState $game2
if(!$state.Installed -or !$state.Foreign -or $state.Version -ne 'AC7-0.5.0-candidate' -or $state.Features -ne 'full' -or $state.Mode -ne 'enabled'){throw 'Codex manifest not recognised'}
# A changed file in the Codex install must block adoption.
$spec=Join-Path $game2 'ue4ss\Mods\AC7Weapons\Scripts\spec.lua';$specBytes=[IO.File]::ReadAllBytes($spec)
[IO.File]::AppendAllText($spec,'-- local edit')
$before=Get-Snapshot $game2
$text=Invoke-Tool 'Setup.ps1' @('-GameRoot',$game2,'-Features','weapons','-Yes','-SaveRoot',$save,'-TestOnlySkipExeHash') 1
if($text -notmatch '被修改过' -or (Get-Snapshot $game2) -ne $before){throw 'Changed Codex file did not block adoption'}
[IO.File]::WriteAllBytes($spec,$specBytes)
Pass 'Codex-style manifest recognised; a modified file in it blocks adoption without changes'
$text=Invoke-Tool 'Setup.ps1' @('-GameRoot',$game2,'-Features','weapons','-Yes','-SaveRoot',$save,'-TestOnlySkipExeHash')
if($text -notmatch 'INSTALLED features=full mode=enabled new=4 updated=\d+ removed=0'){throw "Adoption summary unexpected:`n$text"}
$state=Assert-Clean $game2 $payloadCount
if($state.Foreign -or [string]$state.Manifest.PreviousProject -ne 'C:\Codex\AC7-Mouse-Aim'){throw 'Adopted manifest lacks previous project'}
if([IO.File]::ReadAllText((Join-Path $game2 $layout.Config)) -notmatch "(?m)^hud_renderer=1\r?$"){throw 'Adoption changed hud_renderer 1 (0.5.0 value, the 0.5.2 default)'}
# Keys present in the installed files win (sensitivity, control_mode, hud_opacity, follow_rate); keys the old
# config never had (free_look_zoom, hud_boresight, [keybindings]) keep this package's values.
$imported=Read-AC7MouseSettings (Join-Path $pkg 'MouseAim-Settings.ini')
if($imported.sensitivity -ne 0.15 -or $imported.control_mode -ne 0 -or $imported.hud_opacity -ne 0.65 -or $imported.follow_rate -ne 8 -or $imported.free_look_zoom -ne 1.75){throw 'Settings were not imported from the adopted install'}
if((Read-AC7Keybindings (Join-Path $pkg 'Keybindings.ini')).free_look -ne 'V'){throw 'Package keybindings lost during import'}
$config=[IO.File]::ReadAllText((Join-Path $game2 $layout.Config))
if($config -notmatch '(?m)^sensitivity=0\.15\r$' -or $config -notmatch '(?m)^\[keybindings\]\r$'){throw 'Adopted config.ini not regenerated'}
Pass 'adoption: Codex install taken over (ui-fonts added), user values imported (sensitivity 0.15, PEACE), manifest rewritten'
# 0.5.1 defaulted to hud_renderer=3 (reticle in the game HUD); importing it from a 0.5.1 install gives the 0.5.2 default 1.
$cfgPath=Join-Path $game2 $layout.Config;$cfgBytes=[IO.File]::ReadAllBytes($cfgPath)
[IO.File]::WriteAllText($cfgPath,([IO.File]::ReadAllText($cfgPath) -replace '(?m)^hud_renderer=1(\r?)$','hud_renderer=3$1'),[Text.UTF8Encoding]::new($false))
$fake=[pscustomobject]@{Version='0.5.1';Entries=@([pscustomobject]@{Relative=$layout.Config;Status='ok'})}
$changed=@(Import-AC7InstalledSettings $pkg $game2 $fake)
if($changed -contains 'hud_renderer' -or (Read-AC7MouseSettings (Join-Path $pkg 'MouseAim-Settings.ini')).hud_renderer -ne 1){throw '0.5.1 hud_renderer 3 was not migrated to 1'}
$fake.Version='AC7-0.5.0-candidate';$changed=@(Import-AC7InstalledSettings $pkg $game2 $fake)
if($changed -notcontains 'hud_renderer' -or (Read-AC7MouseSettings (Join-Path $pkg 'MouseAim-Settings.ini')).hud_renderer -ne 3){throw 'An explicit hud_renderer 3 from another version was not kept'}
# 0.5.3/0.5.4 line width 1.4 (tuned) is 1.0 at the 0.6.0 stroke width
[IO.File]::WriteAllText($cfgPath,([IO.File]::ReadAllText($cfgPath) -replace '(?m)^hud_renderer=\d(\r?)$','hud_renderer=1$1' -replace '(?m)^hud_line_width=[^\r\n]*','hud_line_width=1.4'),[Text.UTF8Encoding]::new($false))
$fake.Version='0.5.4';$changed=@(Import-AC7InstalledSettings $pkg $game2 $fake)
if($changed -contains 'hud_line_width' -or (Read-AC7MouseSettings (Join-Path $pkg 'MouseAim-Settings.ini')).hud_line_width -ne 1){throw '0.5.4 hud_line_width 1.4 was not rescaled to 1'}
[IO.File]::WriteAllText($cfgPath,([IO.File]::ReadAllText($cfgPath) -replace '(?m)^hud_line_width=[^\r\n]*','hud_line_width=2'),[Text.UTF8Encoding]::new($false))
$null=@(Import-AC7InstalledSettings $pkg $game2 $fake)
if((Read-AC7MouseSettings (Join-Path $pkg 'MouseAim-Settings.ini')).hud_line_width -ne 1.43){throw '0.5.4 hud_line_width 2 was not rescaled to 1.43'}
[IO.File]::WriteAllBytes($cfgPath,$cfgBytes);$settings=Read-AC7MouseSettings (Join-Path $pkg 'MouseAim-Settings.ini');$settings.hud_renderer=1;$settings.hud_line_width=1;Save-AC7MouseSettings $pkg $settings
Pass 'renderer migration: 0.5.1 hud_renderer 3 -> 1 (GPU overlay default); an explicit 3 from other versions is kept'

# --- 10. Fault injection: automatic rollback restores the exact previous state ------------------------------
$before=Get-Snapshot $game2
$code='';try{Invoke-AC7Install -PackageRoot $pkg -GameRoot $game2 -Features mouse -SaveRoot $save -TestOnlySkipExeHash -TestOnlyFaultAfter 1 | Out-Null}catch{$code=[string]$_.Exception.Data['AC7Code']}
if($code -ne 'INSTALL_ROLLED_BACK' -or (Get-Snapshot $game2) -ne $before){throw "Fault was not rolled back ($code)"}
Pass 'fault after the first write: automatic rollback, game folder byte-identical'
# Interrupted run (no rollback) leaves a journal: install refuses, journal rollback restores the state.
$settings=Read-AC7MouseSettings (Join-Path $pkg 'MouseAim-Settings.ini');$settings.hud_fps=144;Save-AC7MouseSettings $pkg $settings
try{Invoke-AC7Install -PackageRoot $pkg -GameRoot $game2 -Features mouse -SaveRoot $save -TestOnlySkipExeHash -TestOnlyFaultAfter 1 -TestOnlySkipRollback | Out-Null}catch{}
if(!(Test-Path -LiteralPath (Join-Path $game2 $layout.Pending)) -or (Get-Snapshot $game2) -eq $before){throw 'Interrupted install did not leave a journal'}
$text=Invoke-Tool 'Setup.ps1' @('-GameRoot',$game2,'-Features','weapons','-Yes','-SaveRoot',$save,'-TestOnlySkipExeHash') 1
if($text -notmatch '没有完成'){throw 'Install did not refuse a pending journal'}
$retained=@(Invoke-AC7Rollback $game2 (Read-AC7Json (Join-Path $game2 $layout.Pending)))
if($retained.Count -or (Get-Snapshot $game2) -ne $before){throw 'Journal rollback did not restore the previous state'}
Pass 'interrupted install: journal blocks further installs; rollback restores the exact previous state'
try{Invoke-AC7Install -PackageRoot $pkg -GameRoot $game2 -Features mouse -SaveRoot $save -TestOnlySkipExeHash -TestOnlyFaultAfter 2 -TestOnlySkipRollback | Out-Null}catch{}
$text=Invoke-Tool 'Recover-Cleanup.ps1' @('-GameRoot',$game2,'-Confirmed')
if($text -notmatch "CLEANUP removed=$payloadCount retained=0 rolledback=True" -or (Test-Path -LiteralPath (Join-Path $game2 'ue4ss'))){throw "Recover after interruption failed:`n$text"}
Pass 'recover after an interrupted install: rolled back, then uninstalled completely'

# --- 11. Unowned loader without a manifest blocks install and uninstall ---------------------------------------
Copy-Item -LiteralPath (Join-Path $pkg 'payload\dwmapi.dll') -Destination (Join-Path $game2 'dwmapi.dll')
$before=Get-Snapshot $game2
$text=Invoke-Tool 'Setup.ps1' @('-GameRoot',$game2,'-Features','weapons','-Yes','-SaveRoot',$save,'-TestOnlySkipExeHash') 1
if($text -notmatch '不属于本工具的加载器' -or (Get-Snapshot $game2) -ne $before){throw 'Unowned loader did not block install'}
$text=Invoke-Tool 'Recover-Cleanup.ps1' @('-GameRoot',$game2,'-Confirmed') 1
if($text -notmatch '加载器文件' -or (Get-Snapshot $game2) -ne $before){throw 'Unowned loader was removed by cleanup'}
Pass 'unowned dwmapi.dll without a manifest: install and uninstall both refuse, file kept'
# GUI worker path on the fake folder: check reports state and the build mismatch without changing anything.
$check=Invoke-AC7GuiAction -Action Check -Root $pkg -GamePath $game -SteamPath '' -Features weapons
if($check.Title -ne '检查完成' -or $check.Message -notmatch '游戏版本与本包适配版本不一致' -or $check.ModState -ne 'none'){throw "GUI check unexpected: $($check.Message)"}
Pass 'GUI check action reports build mismatch and install state (read-only)'

$realAfter=if(Test-Path -LiteralPath $realManifest){(Get-FileHash -LiteralPath $realManifest).Hash}else{''}
if($realAfter -ne $realBefore){throw 'Real AC7 manifest changed during the test!'}
Pass 'real AC7 install manifest unchanged (read-only check)'
if(!$Keep){Remove-Item -LiteralPath $work -Recurse -Force}
Write-Host "PASS $script:count lifecycle scenarios on a fake game folder."
exit 0
