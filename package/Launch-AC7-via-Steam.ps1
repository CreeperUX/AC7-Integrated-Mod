param([string]$GameRoot,[string]$SteamPath,[switch]$WhatIf)
# Plain Steam start (steam.exe -applaunch 502500, or steam://rungameid/502500). No launch-option wrapper.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Install-Core.ps1')
if(!$GameRoot){$GameRoot=Get-AC7SavedText $PSScriptRoot 'game-path.txt'}
if(!$SteamPath){$SteamPath=Get-AC7SavedText $PSScriptRoot 'steam-path.txt'}
$result=Start-AC7ViaSteam $PSScriptRoot $GameRoot $SteamPath -WhatIf:$WhatIf
Write-Host $result.Message
