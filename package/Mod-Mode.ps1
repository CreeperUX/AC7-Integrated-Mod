param([ValidateSet('Disable','Enable','Status')][string]$Action='Status',[string]$GameRoot,[switch]$TestOnlySkipExeHash)
# Single-player / multiplayer switch. Disable moves the owned loader dwmapi.dll to ue4ss\dwmapi.dll.disabled
# (hash-verified, reversible); Enable moves it back after checking the game build.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Install-Core.ps1')
if(!$GameRoot){$GameRoot=Get-AC7SavedGameRoot $PSScriptRoot}
$result=Set-AC7ModMode -PackageRoot $PSScriptRoot -GameRoot $GameRoot -Action $Action -TestOnlySkipExeHash:$TestOnlySkipExeHash
$color=if($result.Mode -eq 'enabled'){'Yellow'}else{'Green'}
Write-Host $result.Message -ForegroundColor $color
Write-Output ('MODE '+$result.Mode)
