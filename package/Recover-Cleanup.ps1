param([string]$GameRoot,[switch]$Interactive,[switch]$Confirmed,[switch]$CheckOnly)
# Uninstall with backup: rolls back an interrupted install first, then removes only files whose hash matches
# the ownership record. Changed files are backed up and kept; runtime logs are archived and kept.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Cleanup-Core.ps1')
if(!$GameRoot){
 $GameRoot=Get-AC7SavedText $PSScriptRoot 'game-path.txt'
 if(!$GameRoot -and $Interactive){$GameRoot=(Read-Host '粘贴 AC7 游戏根目录（Steam → 管理 → 浏览本地文件）').Trim().Trim('"')}
 if(!$GameRoot){Stop-AC7Problem 'SETUP_REQUIRED' '尚未设置游戏路径。' '请用 -GameRoot 指定，或先在 Start-GUI.cmd 中选择游戏位置。'}
}
$game=Resolve-AC7GameRoot $GameRoot
if($Interactive -and !$CheckOnly -and !$Confirmed){
 $preview=Invoke-AC7Cleanup -PackageRoot $PSScriptRoot -GameRoot $game -CheckOnly
 Write-Host "游戏路径：$game"
 Write-Host $preview.Message
 Write-Host '只删除内容与安装记录一致的文件，先备份；被修改的文件保留，运行日志归档后保留。'
 Write-Host '若安装过其他 UE4SS Mod 或不清楚文件来源，请取消。'
 if((Read-Host '确认这些文件属于本工具安装的 AC7 Mod，请输入 RECOVER；直接回车取消') -cne 'RECOVER'){Stop-AC7Problem 'CANCELLED' '已取消，未修改任何文件。' '确认文件归属后再运行 Recover-Cleanup.cmd。'}
 $Confirmed=$true
}
$result=Invoke-AC7Cleanup -PackageRoot $PSScriptRoot -GameRoot $game -Confirmed:$Confirmed -CheckOnly:$CheckOnly
Write-Host $result.Message
Write-Output ('CLEANUP removed='+@($result.Removed).Count+' retained='+@($result.Retained).Count+' rolledback='+$result.RolledBack)
