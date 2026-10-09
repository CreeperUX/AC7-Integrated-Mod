param([string]$GameRoot)
# Collect the latest runtime logs from the game folder into sessions\flight-* with a short summary.
# Read-only for the game folder; logs stay where they are.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Cleanup-Core.ps1')
if(!$GameRoot){$GameRoot=Get-AC7SavedGameRoot $PSScriptRoot}
$result=Invoke-AC7CollectLogs $PSScriptRoot $GameRoot
Write-Host ('已收集运行日志：'+$result.Folder)
Write-Host ('包含：'+($result.Copied -join '、'))
Write-Host ('UE4SS.log 中含 error／refused／failed 的行：'+$result.Errors+'。详见 summary.txt；反馈问题时请附上整个文件夹。')
