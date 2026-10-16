$ErrorActionPreference='Stop'
# Other UE4SS mods (0.7.0): library plans from zips and folders (layout search, names, duplicates, warnings, unsafe
# paths, links), install/replace keeping the state, enable/disable, removal to a backup (ported from AC8 2.5.0
# Test-ExtraModsManager); AC7 deployment into a fake game folder (record, enabled.txt, hand-placed mods untouched,
# update, changed files kept, conflicts, remove-all); the dialog through its real buttons; the war-default migration.
# Run with the call operator / -File (script scope), temporary folders only.
$package=Split-Path $PSScriptRoot -Parent
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
. (Join-Path $package 'Install-Core.ps1')
$fixture=Join-Path $PSScriptRoot ('tmp\extramods-'+[guid]::NewGuid().ToString('N').Substring(0,8))
$data=Join-Path $fixture 'pkg';$src=Join-Path $fixture 'downloads';$game=Join-Path $fixture 'game'
New-Item -ItemType Directory -Path $data,$src,(Join-Path $game 'ue4ss\Mods') -Force | Out-Null
function Assert-True([bool]$Condition,[string]$Message){if(!$Condition){throw $Message}}
function New-TestZip([string]$Name,[hashtable]$Files){
 $zip=Join-Path $src $Name;$archive=[IO.Compression.ZipFile]::Open($zip,'Create')
 try{foreach($entry in $Files.Keys){$item=$archive.CreateEntry($entry);$writer=New-Object IO.StreamWriter($item.Open());$writer.Write([string]$Files[$entry]);$writer.Dispose()}}finally{$archive.Dispose()}
 return $zip
}
function Get-ModNames{return ((@(Get-ChildItem -LiteralPath (Join-Path $data 'ue4ss-mods') -Directory -Force | ForEach-Object Name) | Sort-Object) -join ',')}
function Join-Names([string[]]$Names){return ((@($Names) | Sort-Object) -join ',')}
$mods=Join-Path $data 'ue4ss-mods';$checks=0

# ---- 1. zip with a nested mod, the UE4SS loader, a pak and a second shared library ----
$zip=New-TestZip 'Pack.zip' @{'Pack/ue4ss/UE4SS.dll'='x';'Pack/ue4ss/Mods/ModA/Scripts/main.lua'='print(1)';'Pack/ue4ss/Mods/ModA/enabled.txt'='';'Pack/ue4ss/Mods/shared/OtherLib/lib.lua'='x';'Pack/ue4ss/Mods/shared/UEHelpers/UEHelpers.lua'='x';'Pack/Content/Paks/~mods/ModA.pak'='x'}
$plan=New-AC7ExtraModPlan $data $zip
Assert-True (@($plan.Items).Count -eq 1 -and $plan.Items[0].Name -eq 'ModA' -and $plan.Items[0].Kind -eq 'Lua' -and !$plan.Items[0].Problem -and !$plan.Items[0].Existing) 'nested mod found'
$text=$plan.Warnings -join ' | '
Assert-True (@($plan.Warnings).Count -eq 3 -and $text -match 'UE4SS\.dll' -and $text -match '\.pak' -and $text -match 'OtherLib') ('warnings: '+$text)
Assert-True (@(Get-ChildItem -LiteralPath $mods -Force).Count -eq 0) 'a plan must not change ue4ss-mods'
$results=@(Install-AC7ExtraModPlan $plan $data $false);Remove-AC7ExtraModPlan $plan
Assert-True ($results[0].Status -eq 'added' -and (Get-ModNames) -eq 'ModA' -and (Test-Path -LiteralPath (Join-Path $mods 'ModA\Scripts\main.lua'))) 'ModA installed'
Assert-True (!@(Get-ChildItem -LiteralPath $data -Recurse -Force -File | Where-Object {$_.Name -in @('UE4SS.dll','ModA.pak','lib.lua')}).Count) 'loader, pak and other shared library not installed'
$listed=@(Get-AC7ExtraMods $data);Assert-True ($listed.Count -eq 1 -and !$listed[0].Problem -and $listed[0].Kind -eq 'Lua') 'ModA will load'
$checks++

# ---- 2. mod without its own folder; replace keeps the disabled state; enable/disable; remove to a backup ----
$plan=New-AC7ExtraModPlan $data (New-TestZip 'Cool Mod v1.2.zip' @{'Scripts/main.lua'='print(2)'})
Assert-True ($plan.Items[0].Name -eq 'CoolMod') ('name from the zip: '+$plan.Items[0].Name)
$null=Install-AC7ExtraModPlan $plan $data $false;Remove-AC7ExtraModPlan $plan
Assert-True ((Set-AC7ExtraModEnabled $data 'ModA' $false) -eq '_ModA' -and (Get-ModNames) -eq (Join-Names '_ModA','CoolMod')) 'disabled with _'
$plan=New-AC7ExtraModPlan $data (New-TestZip 'ModA-2.0.zip' @{'ModA/Scripts/main.lua'='print(3)'})
Assert-True ($plan.Items[0].Existing -eq 'disabled') 'existing disabled copy detected'
$results=@(Install-AC7ExtraModPlan $plan $data $false)
Assert-True ($results[0].Status -eq 'skipped' -and (Get-Content -LiteralPath (Join-Path $mods '_ModA\Scripts\main.lua') -Raw) -eq 'print(1)') 'no replacement without consent'
$results=@(Install-AC7ExtraModPlan $plan $data $true);Remove-AC7ExtraModPlan $plan
Assert-True ($results[0].Status -eq 'replaced' -and (Get-Content -LiteralPath (Join-Path $mods '_ModA\Scripts\main.lua') -Raw) -eq 'print(3)') 'replaced and still disabled'
Assert-True ((Set-AC7ExtraModEnabled $data '_ModA' $true) -eq 'ModA') 'enabled again'
$caught=$false;try{Remove-AC7ExtraMod $data '..\pkg'}catch{$caught=$true};Assert-True $caught 'path outside ue4ss-mods refused'
$checks++

# ---- 3. folders: several mods, C++ warning, invalid and reserved names, links, the data folder, 7z, traversal ----
$folder=Join-Path $src 'unpacked'
foreach($rel in 'Mods\ModB\dlls\main.dll','Mods\ModC\Scripts\main.lua','Mods\Bad Name\Scripts\main.lua','Mods\AC7MouseAim\Scripts\main.lua'){$file=Join-Path $folder $rel;New-Item -ItemType Directory -Path (Split-Path $file) -Force | Out-Null;[IO.File]::WriteAllText($file,'x')}
$plan=New-AC7ExtraModPlan $data $folder;$byName=@{};foreach($item in $plan.Items){$byName[$item.Name]=$item}
Assert-True (@($plan.Items).Count -eq 4 -and $byName['ModB'].Kind -eq 'C++' -and !$byName['ModC'].Problem -and $byName['Bad Name'].Problem -and $byName['AC7MouseAim'].Problem -and !$plan.Staging) 'folder plan'
Assert-True (($plan.Warnings -join ' ') -match 'C\+\+') 'C++ caution'
$results=@(Install-AC7ExtraModPlan $plan $data $true)
Assert-True (@($results | Where-Object Status -eq 'added').Count -eq 2 -and @($results | Where-Object Status -eq 'invalid').Count -eq 2) 'only valid mods added'
$outside=Join-Path $fixture 'outside';New-Item -ItemType Directory -Path (Join-Path $outside 'Scripts') -Force | Out-Null;[IO.File]::WriteAllText((Join-Path $outside 'Scripts\main.lua'),'x')
$linked=Join-Path $src 'linked';New-Item -ItemType Directory -Path $linked | Out-Null;New-Item -ItemType Junction -Path (Join-Path $linked 'LinkMod') -Target $outside | Out-Null
$caught=$false;try{New-AC7ExtraModPlan $data $linked}catch{$caught=$true};Assert-True $caught 'folder with a link refused'
[IO.Directory]::Delete((Join-Path $linked 'LinkMod'),$false)
$caught=$false;try{New-AC7ExtraModPlan $data $mods}catch{$caught=$true};Assert-True $caught 'the data folder itself refused'
$archive7z=Join-Path $src 'mod.7z';[IO.File]::WriteAllText($archive7z,'x');$caught=$false;try{New-AC7ExtraModPlan $data $archive7z}catch{$caught=$true};Assert-True $caught '7z refused'
$caught=$false;try{New-AC7ExtraModPlan $data (New-TestZip 'slip.zip' @{'../evil/Scripts/main.lua'='x'})}catch{$caught=$true}
Assert-True ($caught -and !(Test-Path -LiteralPath (Join-Path $fixture 'evil'))) 'path traversal refused'
$checks++

# ---- 4. deployment into a fake game folder ----
$gmods=Join-Path $game 'ue4ss\Mods'
$none=Sync-AC7ExtraMods $data $game
Assert-True (!$none.Applied -and $none.Message -match 'UE4SS') 'no UE4SS in the game: nothing deployed'
[IO.File]::WriteAllText((Join-Path $game 'ue4ss\UE4SS.dll'),'fake')
New-Item -ItemType Directory -Path (Join-Path $gmods 'HandMod\Scripts') -Force | Out-Null;[IO.File]::WriteAllText((Join-Path $gmods 'HandMod\Scripts\main.lua'),'hand')
$null=Set-AC7ExtraModEnabled $data 'ModB' $false     # library: ModA, _ModB, CoolMod, ModC
$sync=Sync-AC7ExtraMods $data $game
Assert-True ($sync.Applied -and (Join-Names $sync.Deployed) -eq (Join-Names 'CoolMod','ModA','ModC') -and !@($sync.Conflicts).Count) ('deployed: '+$sync.Message)
Assert-True ((Test-Path -LiteralPath (Join-Path $gmods 'ModA\Scripts\main.lua')) -and (Test-Path -LiteralPath (Join-Path $gmods 'ModA\enabled.txt')) -and !(Test-Path -LiteralPath (Join-Path $gmods 'ModB')) -and !(Test-Path -LiteralPath (Join-Path $gmods '_ModB'))) 'enabled mods deployed with enabled.txt, disabled not'
Assert-True ((Get-Content -LiteralPath (Join-Path $gmods 'HandMod\Scripts\main.lua') -Raw) -eq 'hand') 'hand-placed mod untouched'
$state=Get-AC7ExtraModGameState $data $game
Assert-True ($state['ModA'] -eq 'deployed' -and $state['_ModB'] -eq 'off') 'game state'
$again=Sync-AC7ExtraMods $data $game;Assert-True (!@($again.Deployed).Count -and !@($again.Removed).Count -and $again.Message -match '最新') 'idempotent'
$null=Set-AC7ExtraModEnabled $data 'CoolMod' $false;$sync=Sync-AC7ExtraMods $data $game
Assert-True (@($sync.Removed) -contains 'CoolMod' -and !(Test-Path -LiteralPath (Join-Path $gmods 'CoolMod'))) 'disabled mod removed from the game'
[IO.File]::WriteAllText((Join-Path $mods 'ModA\Scripts\main.lua'),'print(4)')
Assert-True ((Get-AC7ExtraModGameState $data $game)['ModA'] -eq 'pending') 'library change detected'
$sync=Sync-AC7ExtraMods $data $game
Assert-True ((Get-Content -LiteralPath (Join-Path $gmods 'ModA\Scripts\main.lua') -Raw) -eq 'print(4)' -and @($sync.Deployed) -contains 'ModA') 'updated copy deployed'
[IO.File]::WriteAllText((Join-Path $gmods 'ModC\Scripts\main.lua'),'edited in game')
$null=Set-AC7ExtraModEnabled $data 'ModC' $false;$sync=Sync-AC7ExtraMods $data $game
Assert-True (@($sync.Kept).Count -eq 1 -and (Get-Content -LiteralPath (Join-Path $gmods 'ModC\Scripts\main.lua') -Raw) -eq 'edited in game' -and !(Test-Path -LiteralPath (Join-Path $gmods 'ModC\enabled.txt'))) 'changed file kept, unchanged ones removed'
$plan=New-AC7ExtraModPlan $data (New-TestZip 'HandMod.zip' @{'HandMod/Scripts/main.lua'='mine'});$null=Install-AC7ExtraModPlan $plan $data $true;Remove-AC7ExtraModPlan $plan
$sync=Sync-AC7ExtraMods $data $game
Assert-True (@($sync.Conflicts) -contains 'HandMod' -and (Get-Content -LiteralPath (Join-Path $gmods 'HandMod\Scripts\main.lua') -Raw) -eq 'hand' -and (Get-AC7ExtraModGameState $data $game)['HandMod'] -eq 'conflict') 'unrecorded folder of the same name not overwritten'
$sync=Sync-AC7ExtraMods $data $game -RemoveAll
Assert-True (!(Test-Path -LiteralPath (Join-Path $gmods 'ModA')) -and (Test-Path -LiteralPath (Join-Path $gmods 'HandMod\Scripts\main.lua')) -and (Test-Path -LiteralPath (Join-Path $gmods 'ModC\Scripts\main.lua'))) 'remove-all: deployed copies removed, changed and hand-placed files kept'
Assert-True (Test-Path -LiteralPath (Join-Path $mods 'ModA')) 'library kept on remove-all'
$checks++

# ---- 5. the dialog through its real buttons and commands (syncs into the game) ----
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
. (Join-Path $package 'CreeperUX-Theme.ps1')
. (Join-Path $package 'ExtraMods-GUI.ps1')
Remove-Item -LiteralPath (Join-Path $gmods 'ModC') -Recurse -Force;$null=Remove-AC7ExtraMod $data 'HandMod'
foreach($theme in 'dark','light'){
 $ctx=New-AC7ExtraModsDialog $data $game $null $theme
 Assert-True ($ctx.Rows.Children.Count -eq 4 -and $ctx.Empty.Visibility -eq 'Collapsed') ('one row per mod: '+$ctx.Rows.Children.Count)
 $ctx.Window.Content.Measure([Windows.Size]::new(860,720));$ctx.Window.Content.Arrange([Windows.Rect]::new(0,0,860,720));$ctx.Window.Content.UpdateLayout()
}
$global:AC7ModTestConfirm=@()
$ctx.Commands.Confirm={param($Owner,$Message,$Title,$Action) $global:AC7ModTestConfirm+=,@($Title,$Message);return $true}
$row=@($ctx.Rows.Children | Where-Object {$_.Children[1].Tag -eq '_ModB'})[0]
$row.Children[1].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
Assert-True ((Test-Path -LiteralPath (Join-Path $mods 'ModB')) -and (Test-Path -LiteralPath (Join-Path $gmods 'ModB\dlls\main.dll')) -and $ctx.Changed -and $ctx.Status.Text -match '已部署') ('enable button syncs: '+$ctx.Status.Text)
$row=@($ctx.Rows.Children | Where-Object {$_.Children[2].Tag -eq 'ModB'})[0]
$row.Children[2].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
Assert-True (!(Test-Path -LiteralPath (Join-Path $mods 'ModB')) -and !(Test-Path -LiteralPath (Join-Path $gmods 'ModB')) -and $global:AC7ModTestConfirm[-1][0] -eq '删除附加 Mod') 'remove button with confirmation, removed from the game'
& $ctx.Commands.Add $ctx (New-TestZip 'ModE.zip' @{'ModE/Scripts/main.lua'='x';'ModE/ue4ss/dwmapi.dll'='x'})
Assert-True ((Test-Path -LiteralPath (Join-Path $gmods 'ModE\Scripts\main.lua')) -and !(Test-Path -LiteralPath (Join-Path $gmods 'ModE\ue4ss\dwmapi.dll')) -and $global:AC7ModTestConfirm[-1][1] -match 'dwmapi\.dll') ('add from a zip: '+$ctx.Status.Text)
$ctx.Commands.Confirm={param($Owner,$Message,$Title,$Action) return $false}
& $ctx.Commands.Add $ctx (New-TestZip 'ModF.zip' @{'ModF/Scripts/main.lua'='x'})
Assert-True (!(Test-Path -LiteralPath (Join-Path $mods 'ModF'))) 'cancelled add changes nothing'
$ctx=New-AC7ExtraModsDialog $data '' $null 'dark';& $ctx.Commands.Sync $ctx 'x';Assert-True ($ctx.Status.Text -match '尚未选择游戏位置') 'no game path: library only'
Remove-Variable -Name AC7ModTestConfirm -Scope Global
$checks++

# ---- 6. war-default migration (once; a later PEACE choice is kept) ----
$settings=Get-AC7DefaultMouseSettings;$settings.control_mode=0;Save-AC7MouseSettings $data $settings
$applied=@(Invoke-AC7SettingsMigrations $data)
Assert-True ($applied -contains 'war-default-0.7.0' -and (Read-AC7MouseSettings (Join-Path $data 'MouseAim-Settings.ini')).control_mode -eq 3 -and (Test-Path -LiteralPath (Join-Path $data 'migrations.json'))) 'saved PEACE moved to WAR once'
$settings.control_mode=0;Save-AC7MouseSettings $data $settings
Assert-True (!@(Invoke-AC7SettingsMigrations $data).Count -and (Read-AC7MouseSettings (Join-Path $data 'MouseAim-Settings.ini')).control_mode -eq 0) 'a later PEACE choice is kept'
# Values taken over from a 0.7.0+ install already went through the migration: recorded only; older ones move to WAR.
Remove-Item -LiteralPath (Join-Path $data 'migrations.json') -Force
Assert-True ((@(Invoke-AC7SettingsMigrations $data '0.7.0-beta.1') -contains 'war-default-0.7.0') -and (Read-AC7MouseSettings (Join-Path $data 'MouseAim-Settings.ini')).control_mode -eq 0) 'PEACE from a 0.7.0 install kept'
Remove-Item -LiteralPath (Join-Path $data 'migrations.json') -Force
Assert-True ((@(Invoke-AC7SettingsMigrations $data 'AC7-0.6.1-beta.1') -contains 'war-default-0.7.0') -and (Read-AC7MouseSettings (Join-Path $data 'MouseAim-Settings.ini')).control_mode -eq 3) 'PEACE from a 0.6.1 install moved to WAR'
$checks++

Remove-AC7ExtraModTree $fixture
Write-Host "PASS extra mods + migration: $checks groups (zip/folder plans, notices, replace keeping state, enable/disable, backups, unsafe paths and links refused, game deployment with record and enabled.txt, hand-placed mods untouched, update, changed files kept, conflicts, remove-all, dialog buttons syncing, war-default once)"
