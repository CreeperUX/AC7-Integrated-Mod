. ([IO.Path]::Combine($PSScriptRoot,'Install-Core.ps1'))
# Uninstall / recovery and log collection. Only files whose hash matches the ownership record are deleted;
# everything is backed up and verified first; runtime logs are archived and left in place.
function Copy-AC7RuntimeLogs([string]$GameRoot,[string]$Destination) {
 $copied=@()
 New-Item -ItemType Directory -Path $Destination -Force | Out-Null
 foreach($relative in @('ue4ss\UE4SS.log','ue4ss\Mods\AC7MouseAim\Scripts\full-health.csv','ue4ss\Mods\AC7MouseAim\Scripts\observations.csv','ue4ss\Mods\AC7MouseAim\config.ini')){
  $source=Join-Path $GameRoot $relative
  if(Test-Path -LiteralPath $source -PathType Leaf){Copy-Item -LiteralPath $source -Destination (Join-Path $Destination (Split-Path $relative -Leaf)) -Force;$copied+=$relative}
 }
 $logs=Join-Path $GameRoot 'ue4ss\Mods\AC7MouseAim\Logs'
 if(Test-Path -LiteralPath $logs -PathType Container){
  Assert-AC7NoLinks $logs -Tree
  Copy-Item -LiteralPath $logs -Destination (Join-Path $Destination 'native-logs') -Recurse -Force
  $copied+='ue4ss\Mods\AC7MouseAim\Logs'
 }
 return $copied
}
function Invoke-AC7CollectLogs([string]$PackageRoot,[string]$GameRoot) {
 $game=Resolve-AC7GameRoot $GameRoot
 $destination=Join-Path $PackageRoot ('sessions\flight-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
 $copied=@(Copy-AC7RuntimeLogs $game $destination)
 $log=Join-Path $destination 'UE4SS.log'
 if(!(@($copied | Where-Object {$_ -ne 'ue4ss\Mods\AC7MouseAim\config.ini'})).Count){
  Remove-Item -LiteralPath $destination -Recurse -Force
  Stop-AC7Problem 'NO_LOGS' '游戏目录中还没有运行日志。' '先在单人任务中飞行一次，再收集日志。'
 }
 $summary=@('AC7 runtime log collection','Game: '+$game,'Collected: '+($copied -join ', '))
 $errors=0
 if(Test-Path -LiteralPath $log){
  $lines=@(Get-Content -LiteralPath $log -Encoding UTF8)
  $errors=@($lines | Where-Object {$_ -match '(?i)\berror\b|refused|failed'}).Count
  $summary+=('UE4SS.log lines: '+$lines.Count+', error/refused/failed lines: '+$errors)
  $summary+='Last mod lines:'
  $summary+=@($lines | Where-Object {$_ -match 'AC7FullControl|AC7Weapons|AC7MouseAim'} | Select-Object -Last 20)
 }
 Set-Content -LiteralPath (Join-Path $destination 'summary.txt') -Value $summary -Encoding UTF8
 return [pscustomobject]@{Folder=$destination;Copied=$copied;Errors=$errors}
}
function Invoke-AC7Cleanup {
 param([Parameter(Mandatory=$true)][string]$PackageRoot,[Parameter(Mandatory=$true)][string]$GameRoot,[switch]$Confirmed,[switch]$CheckOnly)
 $layout=Get-AC7Layout
 $package=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\','/')
 $game=Resolve-AC7GameRoot $GameRoot
 Assert-AC7PackageLocation $package $game
 Assert-AC7NoLinks $game
 Assert-AC7GameClosed $game
 if(!$CheckOnly -and !$Confirmed){Stop-AC7Problem 'CONFIRM_REQUIRED' '卸载尚未确认。' '请先确认要卸载的是本工具安装的 AC7 Mod。'}
 $operation=Enter-AC7Operation $game
 try{
  $state=Get-AC7InstallState $game
  $result=[pscustomobject]@{GameRoot=$game;RolledBack=$false;Removed=@();Retained=@();Missing=@();Logs=@();Backup=$null;Changed=$false;Message=''}
  if($state.Pending){
   if($CheckOnly){$result.Message='有未完成的安装操作；确认清理时会先按记录回滚。';return $result}
   $retained=@(Invoke-AC7Rollback $game $state.Pending)
   if($retained.Count){Stop-AC7Problem 'ROLLBACK_INCOMPLETE' ('未完成的安装无法完全回滚：'+($retained -join '、')+'。') '这些文件与记录中的任何版本都不一致，已保留。请对照 backups 文件夹中的备份手动处理。'}
   $result.RolledBack=$true;$result.Changed=$true
   $state=Get-AC7InstallState $game
  }
  if(!$state.Installed){
   if(@($state.UnownedLoader).Count){Stop-AC7Problem 'UNOWNED_LOADER' ('没有本工具的安装记录，但游戏目录中有加载器文件：'+(@($state.UnownedLoader) -join '、')+'。') '这些文件可能来自其他 Mod，未删除任何文件。确认来源后手动处理；不要直接删除不明 DLL。'}
   $result.Message=if($result.RolledBack){'已回滚未完成的安装，游戏目录恢复为安装前的状态。'}else{'游戏中没有本工具安装的 Mod，无需清理。'}
   return $result
  }
  # Loader first: once it is gone the game starts unmodified even if a later step fails.
  $removable=@(@($state.Entries | Where-Object {$_.Status -eq 'ok' -and $_.Loader})+@($state.Entries | Where-Object {$_.Status -eq 'ok' -and !$_.Loader}))
  $retainedEntries=@($state.Entries | Where-Object Status -eq 'changed')
  $result.Missing=@($state.Entries | Where-Object Status -eq 'missing' | ForEach-Object Relative)
  if($CheckOnly){
   $result.Removed=@($removable | ForEach-Object Actual);$result.Retained=@($retainedEntries | ForEach-Object Actual)
   $result.Message='可删除 '+$removable.Count+' 个校验一致的文件；'+$retainedEntries.Count+' 个被修改的文件会备份并保留。未修改任何文件。'
   return $result
  }
  $backup=Join-Path $package ('cleanup-backups\'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
  New-Item -ItemType Directory -Path $backup -Force | Out-Null
  Assert-AC7NoLinks $backup
  $result.Backup=$backup
  foreach($entry in @($removable+$retainedEntries)){
   $source=Get-AC7Target $game $entry.Actual;$copy=Join-Path (Join-Path $backup 'files') $entry.Actual
   $expected=Get-AC7CurrentHash $source
   New-Item -ItemType Directory -Path (Split-Path $copy -Parent) -Force | Out-Null
   Copy-Item -LiteralPath $source -Destination $copy -Force
   if((Get-AC7FileHash -LiteralPath $copy).Hash -ne $expected){throw "Backup verification failed: $($entry.Actual)"}
  }
  Copy-Item -LiteralPath (Join-Path $game $layout.Manifest) -Destination (Join-Path $backup 'AC7-MouseAim-owner.json') -Force
  $result.Logs=@(Copy-AC7RuntimeLogs $game (Join-Path $backup 'logs'))
  $report=[ordered]@{Version=1;GameRoot=$game;Status='backup-verified';Removed=@();Retained=@($retainedEntries | ForEach-Object Actual);Missing=$result.Missing;Logs=$result.Logs}
  $reportPath=Join-Path $backup 'cleanup-report.json'
  Write-AC7Json $report $reportPath
  $removed=@();$late=@()
  foreach($entry in $removable){
   if(Test-AC7GameRunning $game){throw "Game started during cleanup; backup retained at $backup"}
   $target=Get-AC7Target $game $entry.Actual
   if((Get-AC7CurrentHash $target) -ne $entry.SHA256){$late+=$entry.Actual;continue}
   Remove-Item -LiteralPath $target -Force
   $removed+=$entry.Actual;$report.Removed=$removed;Write-AC7Json $report $reportPath
  }
  Remove-AC7EmptyDirectories $game (Get-AC7ParentDirectories $removed)
  Remove-Item -LiteralPath (Join-Path $game $layout.Manifest) -Force
  Remove-AC7EmptyDirectories $game @('ue4ss\Mods','ue4ss')
  $result.Removed=$removed;$result.Retained=@(@($retainedEntries | ForEach-Object Actual)+$late);$result.Changed=$true
  $report.Status='complete';$report.Retained=$result.Retained;Write-AC7Json $report $reportPath
  $text='已卸载：删除 '+$removed.Count+' 个校验一致的文件。备份与日志归档：'+$backup+'。'
  if($result.RolledBack){$text='已先回滚未完成的安装。'+$text}
  if($result.Retained.Count){$text+=' 以下文件与安装时不同，已备份但未删除：'+($result.Retained -join '、')+'；确认不再需要后可手动删除。'}
  if(@($result.Retained | Where-Object {$_ -ieq $layout.Loader}).Count){$text+=' 注意：加载器 dwmapi.dll 仍在游戏目录中，联机前必须手动处理。'}
  if($result.Missing.Count){$text+=' 记录中已缺失的文件：'+($result.Missing -join '、')+'。'}
  $text+=' 运行日志与其他 Mod 文件夹保留在游戏目录中。'
  $result.Message=$text
  return $result
 }finally{Exit-AC7Operation $operation}
}
