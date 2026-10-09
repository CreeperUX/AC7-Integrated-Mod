$ErrorActionPreference='Stop'
# Steam library discovery for AC7 (app 502500, Ace7Game.exe in the game root). Fixtures only; read-only.
$package=Split-Path $PSScriptRoot -Parent
. (Join-Path $package 'Discover-Installations.ps1')
$root=Join-Path $PSScriptRoot ('tmp\discovery-'+[guid]::NewGuid().ToString('N').Substring(0,8))
$steam=Join-Path $root 'Steam';$exe=Join-Path $steam 'steam.exe'
New-Item -ItemType Directory -Path (Join-Path $steam 'steamapps') -Force | Out-Null
Set-Content -LiteralPath $exe -Value 'fixture'
$script:testSteams=@($exe)
function Get-AC7SteamCandidates {param($Preferred) return $script:testSteams}
function New-LibraryGame([string]$Library,[string]$InstallDir='ACE COMBAT 7'){
 $game=Join-Path $Library ('steamapps/common/'+$InstallDir)
 New-Item -ItemType Directory -Path $game -Force | Out-Null
 Set-Content -LiteralPath (Join-Path $game 'Ace7Game.exe') -Value 'fixture'
 Set-Content -LiteralPath (Join-Path $Library 'steamapps/appmanifest_502500.acf') -Value ('"AppState" { "appid" "502500" "installdir" "'+$InstallDir+'" }') -Encoding UTF8
 return [IO.Path]::GetFullPath($game)
}
$count=0
function Pass($Text){$script:count++;Write-Host "PASS $Text"}
$game=New-LibraryGame $steam
$result=Find-AC7Installations '' ''
if($result.GamePath -ne $game -or $result.SteamPath -ne $exe){throw 'Default library detection failed'}
Pass 'Steam default library'
$external=Join-Path $root '另一个盘符 游戏库'
$externalGame=New-LibraryGame $external 'ACE COMBAT 7 custom'
$libraryFile=Join-Path $steam 'steamapps/libraryfolders.vdf'
$escaped=$external.Replace('\','\\')
Set-Content -LiteralPath $libraryFile -Value ('// comment'+"`n"+'"libraryfolders" { "0" { "path" "'+$steam.Replace('\','\\')+'" } "1" { "path" "'+$escaped+'" "apps" { "502500" "1" } } }') -Encoding UTF8
$result=Find-AC7Installations '' ''
if($result.GamePath -or $result.GameCandidates.Count -ne 2 -or $result.GameCandidates -notcontains $externalGame){throw 'Multiple libraries were silently selected or missed'}
Pass 'modern multi-library format, escaped Chinese paths, comments and ambiguity'
$result=Find-AC7Installations $externalGame $exe
if($result.GamePath -ne $externalGame){throw 'Manual selection overwritten'}
$result=Find-AC7Installations (Join-Path $root 'stale') $exe
if($result.GamePath -ne (Join-Path $root 'stale')){throw 'Stale manual path overwritten'}
Pass 'saved/manual paths retained even when invalid'
Set-Content -LiteralPath $libraryFile -Value ('"LibraryFolders" { "1" "'+$escaped+'" }') -Encoding UTF8
$result=Find-AC7Installations '' ''
if($result.GameCandidates -notcontains $externalGame){throw 'Legacy library format failed'}
Pass 'legacy Steam library format'
Set-Content -LiteralPath $libraryFile -Value '"libraryfolders" {' -Encoding UTF8
$result=Find-AC7Installations '' ''
if($result.GamePath -ne $game -or !$result.Warnings.Count){throw 'Malformed library file blocked partial discovery'}
Pass 'malformed metadata gives a warning without losing the default library'
Set-Content -LiteralPath (Join-Path $steam 'steamapps/appmanifest_502500.acf') -Value '"AppState" { "appid" "502500" "installdir" "..\\..\\outside" }'
$result=Find-AC7Installations '' ''
if($result.GameCandidates.Count){throw 'Escaping manifest path accepted'}
Pass 'manifest path escape rejected'
Set-Content -LiteralPath (Join-Path $steam 'steamapps/appmanifest_502500.acf') -Value '"AppState" { "appid" "2288340" "installdir" "ACE COMBAT 7" }'
$result=Find-AC7Installations '' ''
if($result.GameCandidates.Count){throw 'Manifest of another app accepted'}
Pass 'manifest with a different app id ignored'
$script:testSteams=@()
$result=Find-AC7Installations '' ''
if($result.GamePath -or $result.SteamPath -or $result.GameCandidates.Count){throw 'No-installation fallback failed'}
Pass 'no installation leaves manual inputs available'
$steam2=Join-Path $root 'Steam2';New-Item -ItemType Directory -Path $steam2 | Out-Null
$exe2=Join-Path $steam2 'steam.exe';Set-Content -LiteralPath $exe2 -Value 'fixture'
$script:testSteams=@($exe,$exe2)
$result=Find-AC7Installations '' ''
if($result.SteamPath -or $result.SteamCandidates.Count -ne 2){throw 'Multiple Steam clients silently selected'}
Pass 'multiple Steam clients require a choice'
$readonlyBefore=@(Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {$_.FullName+'|'+(Get-FileHash -LiteralPath $_.FullName).Hash}) -join "`n"
$null=Find-AC7Installations '' ''
$readonlyAfter=@(Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {$_.FullName+'|'+(Get-FileHash -LiteralPath $_.FullName).Hash}) -join "`n"
if($readonlyBefore -ne $readonlyAfter){throw 'Discovery modified files'}
Pass 'discovery leaves manifests and games byte-identical'
Remove-Item -LiteralPath $root -Recurse -Force
Write-Host "PASS $count discovery scenarios. No live registry or game changed."
exit 0
