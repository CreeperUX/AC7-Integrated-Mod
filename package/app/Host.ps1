# AC7 Integrated host for the installed app (0.7.0), kept in the install root. The Start menu entry (AC7 Integrated.exe,
# or powershell.exe when the native launcher is missing), the launcher and Windows "Apps" start it. It resolves the
# current version, checks it (repairing damaged program files from the cached verified package) and runs that version.
# Console output is Chinese; failures end with an ASCII [CODE] marker, launch results with [READY] / [NOT READY] /
# [ORIGINAL]. Exit codes: 0 done, 1 failed or cancelled with problems, 3 the game was started but the mod is not ready.
param(
 [ValidateSet('Gui','Launch','Update','Repair','Rollback','Uninstall','Status','CheckUpdate')][string]$Action='Gui',
 [string]$Feed='',[switch]$Yes,[switch]$NoRegister,[switch]$NoLaunch,[switch]$RemoveData,[switch]$Offline,[switch]$WhatIf,
 [int]$ReadyTimeout=120,[string]$SaveRoot='',[string]$UninstallKey='',[string]$Shortcut='',[switch]$TestOnlySkipExeHash
)
$ErrorActionPreference='Stop'
foreach($module in @('Microsoft.PowerShell.Management','Microsoft.PowerShell.Utility')){Import-Module ([IO.Path]::Combine($PSHOME,'Modules',$module,($module+'.psd1'))) -ErrorAction Stop}
$installRoot=$PSScriptRoot
. ([IO.Path]::Combine($installRoot,'App-Core.ps1'))
if(!$UninstallKey){$UninstallKey=Get-AC7AppUninstallKey}
if(!$Shortcut){$Shortcut=Get-AC7AppShortcutPath}
$powershell=[IO.Path]::Combine($PSHOME,'powershell.exe')
function Write-AC7HostFindings($Findings){
 foreach($finding in @($Findings)){
  $mark=switch($finding.Status){'ok'{'[正常]  '} 'fixed'{'[已修复]'} 'info'{'[提示]  '} default{'[需处理]'}}
  $color=switch($finding.Status){'ok'{'Green'} 'fixed'{'Yellow'} 'info'{'Cyan'} default{'Red'}}
  Write-Host ($mark+' '+$finding.Item+'：'+$finding.Message) -ForegroundColor $color
 }
}
function Wait-AC7HostClose{if(!$Yes){[void](Read-Host '按回车关闭此窗口')}}
function Start-AC7HostLauncher{
 # A new launcher window after an update, repair or rollback (the native launcher when installed: no console window).
 $launcher=[IO.Path]::Combine($installRoot,(Get-AC7AppLauncherName))
 if([IO.File]::Exists($launcher)){Start-Process -FilePath $launcher;return}
 Start-Process -FilePath $powershell -WindowStyle Hidden -ArgumentList @('-NoProfile','-STA','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',('"'+[IO.Path]::Combine($installRoot,'Host.ps1')+'"'),'-Action','Gui')
}
function Get-AC7HostReadyPackage{
 # Before every start: app.json, version files and host files, repaired offline from the cached verified package.
 $findings=@(Invoke-AC7AppRepair -InstallRoot $installRoot -Quick -NoRegister)
 foreach($finding in @($findings | Where-Object {$_.Status -eq 'fixed'})){Write-Host ('已自动修复：'+$finding.Message) -ForegroundColor Yellow}
 $bad=@($findings | Where-Object {$_.Status -eq 'problem'})
 if($bad.Count){Stop-AC7App 'APP_DAMAGED' $bad[0].Message '请在开始菜单打开 AC7 Integrated 并使用“检查并修复”；需要时会从 GitHub 重新下载同一版本。'}
 return Get-AC7AppCurrentPackage $installRoot
}
function Invoke-AC7HostGameDeploy([switch]$Repair){
 return @(Invoke-AC7AppGameDeploy -InstallRoot $installRoot -Repair:$Repair -SaveRoot $SaveRoot -TestOnlySkipExeHash:$TestOnlySkipExeHash)
}
$titles=@{Launch='启动游戏';Update='检查更新';Repair='检查并修复';Rollback='回退版本';Uninstall='卸载'}
if($titles.ContainsKey($Action)){try{$Host.UI.RawUI.WindowTitle='AC7 Integrated · '+$titles[$Action]}catch{}}
try{
 switch($Action){
  'Gui'{
   try{$package=Get-AC7HostReadyPackage}catch{
    $message='AC7 Integrated 暂时无法打开：'+$_.Exception.Message+[Environment]::NewLine+[Environment]::NewLine+'接下来会打开“检查并修复”。'
    try{Add-Type -AssemblyName PresentationFramework;[void][Windows.MessageBox]::Show($message,'AC7 Integrated')}catch{}
    Start-Process -FilePath $powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-Action','Repair')
    exit 1
   }
   # Same process: AC7 Integrated.exe hosts this script, so the launcher window belongs to AC7 Integrated (taskbar icon).
   $global:LASTEXITCODE=0
   & ([IO.Path]::Combine($package,'Launcher-GUI.ps1'))
   exit $LASTEXITCODE
  }
  'Launch'{
   Write-Host 'AC7 Integrated · 启动游戏（仅限单人游戏；进入多人对战前请先停用 Mod）'
   $package=Get-AC7HostReadyPackage
   $current=Get-AC7AppPackageVersion $package
   $game=Get-AC7AppGameInfo $installRoot $package
   if(!$game.GameRoot){Stop-AC7App 'SETUP_REQUIRED' '尚未选择游戏位置。' '请在开始菜单打开 AC7 Integrated，自动定位游戏后点击“安装／更新”。'}
   if(!$game.Exists){Stop-AC7App 'GAME_PATH' ('保存的游戏位置无效：'+$game.GameRoot) '请在启动器中重新定位游戏。'}
   if($game.Running){Stop-AC7App 'GAME_RUNNING' '游戏已在运行。' '无需重复启动。'}
   if($game.Error){Stop-AC7App 'GAME_STATE' $game.Error '请在启动器中点击“检查”查看详情。'}
   if($game.Pending){Stop-AC7App 'GAME_PENDING' '上一次安装或更新没有完成。' '请在启动器中点击“卸载（备份并清理）”回滚未完成的操作，再重新安装。'}
   if($game.Installed -and $game.OwnedByApp){
    if(@($game.Blocked).Count){
     Write-Host ('[GAME_FILES_BLOCKED] 游戏目录中的 '+(@($game.Blocked) -join '、')+' 缺失或被改动。') -ForegroundColor Red
     Write-Host '刚安装或更新后出现这种情况，通常是安全软件拦截或隔离了 DLL。请先在 Windows 安全中心 → 保护历史中恢复误拦截的文件（不要关闭安全软件），然后运行“检查并修复”恢复这些文件。' -ForegroundColor Yellow
     $fix=$false
     if(!$Yes){$fix=(Read-Host '输入 R 立即运行检查并修复（被改动的文件先备份）；直接回车取消启动') -ieq 'R'}
     if(!$fix){Stop-AC7App 'GAME_FILES_BLOCKED' '游戏目录中的 Mod 文件不完整，已停止启动。' '运行“检查并修复”后再启动。'}
     Write-AC7HostFindings (Invoke-AC7HostGameDeploy -Repair)
     $game=Get-AC7AppGameInfo $installRoot $package
     if(@($game.Blocked).Count){Stop-AC7App 'GAME_FILES_BLOCKED' ('修复后仍缺失或被改动：'+(@($game.Blocked) -join '、')+'。') '文件很可能被安全软件再次拦截。请在保护历史中允许这些文件后重试。'}
    }
    if($game.ManifestVersion -ne $current){
     Write-Host ('游戏中的 Mod 是 '+$game.ManifestVersion+'，正在更新到 '+$current+'…')
     $findings=@(Invoke-AC7HostGameDeploy)
     Write-AC7HostFindings $findings
     $bad=@($findings | Where-Object {$_.Status -eq 'problem'})
     if($bad.Count){Stop-AC7App 'GAME_DEPLOY' $bad[0].Message '处理后再启动；也可以在启动器中点击“安装／更新”。'}
     $game=Get-AC7AppGameInfo $installRoot $package
    }
    $other=@(@($game.Changed)+@($game.Missing))
    if($other.Count){Write-Host ('提示：以下 Mod 文件与安装时不同：'+($other -join '、')+'。需要时运行“检查并修复”恢复。') -ForegroundColor Yellow}
   }elseif($game.Installed){Write-Host ('提示：游戏中的 Mod 由另一个整合包管理（'+$game.Project+'）。需要交给安装版管理时，在启动器中点击“安装／更新”。') -ForegroundColor Yellow}
   elseif(@($game.UnownedLoader).Count){Write-Host ('提示：游戏目录中有不属于本工具的加载器：'+(@($game.UnownedLoader) -join '、')+'。') -ForegroundColor Yellow}
   $since=[DateTime]::UtcNow
   $started=Start-AC7AppGame $package $game.GameRoot (Get-AC7AppSavedText ([IO.Path]::Combine($installRoot,'data')) 'steam-path.txt') -WhatIf:$WhatIf
   Write-Host $started.Message
   if(!$game.Installed -or $game.Mode -ne 'enabled'){
    Write-Host ('[ORIGINAL] '+$(if($game.Installed){'Mod 已停用，游戏以原版启动。'}else{'游戏中没有安装本 Mod，以原版启动。'})) -ForegroundColor Green
    exit 0
   }
   $banner=Get-AC7AppExpectedBanner $game.GameRoot $current
   Write-Host ('正在等待鼠标飞控就绪（最多 '+$ReadyTimeout+' 秒）…')
   $ready=Wait-AC7AppReady ([IO.Path]::Combine($game.GameRoot,'ue4ss','UE4SS.log')) $since $banner $ReadyTimeout
   if($ready.State -eq 'ready'){
    Write-Host ('[READY] 鼠标飞控已加载（AC7 '+$banner+'）。仅限单人任务；F4 切换 PEACE／WAR，F8 开关飞控。') -ForegroundColor Green
    if(!$Yes){Start-Sleep -Seconds 5}
    exit 0
   }
   Write-Host ('[NOT READY] '+$ready.Reason) -ForegroundColor Red
   Write-Host '需要反馈时，请在启动器中点击“收集日志”，附上整个文件夹。' -ForegroundColor Yellow
   Wait-AC7HostClose;exit 3
  }
  'Update'{
   Write-Host 'AC7 Integrated · 检查更新（GitHub 发布页，只下载、不上传任何数据）'
   $state=Read-AC7AppState $installRoot
   Write-Host ('当前版本：'+$state.current)
   $busy=Get-AC7AppBusyReason $installRoot;if($busy){Stop-AC7App 'APP_BUSY' $busy '退出游戏后重试。'}
   $latest=@(Get-AC7AppReleaseList $Feed)[0]
   $latestVersion='';if($latest -and [string]$latest.tag_name -match '^v(.+)$'){$latestVersion=$Matches[1]}
   if(!$latestVersion -or (Compare-AC7AppVersion $latestVersion ([string]$state.current)) -le 0){
    Write-Host ('[UP-TO-DATE] 已是最新版本（GitHub 上的最新版本：'+$(if($latestVersion){$latestVersion}else{'无'})+'）。') -ForegroundColor Green
    if(!$NoLaunch -and $Yes){Start-AC7HostLauncher}
    Wait-AC7HostClose;exit 0
   }
   $offer=Get-AC7AppUpdateOffer -InstallRoot $installRoot -Feed $Feed -Release $latest
   Write-Host ('发现新版本：'+$offer.Version+$(if($offer.Prerelease){'（Beta 测试版）'}else{''})) -ForegroundColor Cyan
   if($offer.NotesUrl){Write-Host ('更新说明：'+$offer.NotesUrl)}
   if(!$Yes -and (Read-Host '输入 Y 下载并安装；直接回车取消') -ine 'Y'){Remove-AC7AppTree $offer.Cache;Write-Host '已取消，没有任何改动。';exit 0}
   Write-Host '正在下载并校验签名和哈希…'
   $report=@(Install-AC7AppUpdate -InstallRoot $installRoot -Offer $offer -Feed $Feed -NoRegister:$NoRegister -UninstallKey $UninstallKey -Shortcut $Shortcut)
   Write-AC7HostFindings $report
   Write-Host ('[UPDATED] 已更新到 '+$offer.Version+'。设置、键位和附加 Mod 都已保留；需要时可在“检查并修复”中回退到 '+$state.current+'。') -ForegroundColor Green
   $findings=@(Invoke-AC7HostGameDeploy)
   Write-AC7HostFindings $findings
   if(@($findings | Where-Object {$_.Status -eq 'problem'}).Count){Write-Host '游戏中的 Mod 还没有更新到新版本；处理上面的问题后运行“检查并修复”，或下次启动游戏时自动更新。' -ForegroundColor Yellow}
   if(!$NoLaunch -and ($Yes -or (Read-Host '直接回车打开启动器；输入 N 关闭') -ine 'N')){Start-AC7HostLauncher}
   exit 0
  }
  'Repair'{
   Write-Host 'AC7 Integrated · 检查并修复'
   $busy=Get-AC7AppBusyReason $installRoot;if($busy){Write-Host ('提示：'+$busy+' 游戏目录中的文件这次不会修复。') -ForegroundColor Yellow}
   $findings=@(Invoke-AC7AppRepair -InstallRoot $installRoot -Feed $Feed -Offline:$Offline -NoRegister:$NoRegister -UninstallKey $UninstallKey -Shortcut $Shortcut -SaveRoot $SaveRoot -TestOnlySkipExeHash:$TestOnlySkipExeHash)
   Write-AC7HostFindings $findings
   $bad=@($findings | Where-Object {$_.Status -eq 'problem'}).Count
   Write-Host $(if($bad){'检查完成：'+$bad+' 项需要处理，见上方说明。'}else{'[REPAIRED] 检查完成，没有需要处理的问题。'})
   if($Yes){exit $(if($bad){1}else{0})}
   $state=Read-AC7AppState $installRoot;$previous=[string]$state.previous
   $prompt='直接回车打开启动器'+$(if($previous){'；输入 R 回退到上一版本 '+$previous}else{''})+'；输入 Q 关闭'
   $answer=Read-Host $prompt
   if($previous -and $answer -ieq 'R'){
    Write-AC7HostFindings @(Invoke-AC7AppRollback -InstallRoot $installRoot -NoRegister:$NoRegister -UninstallKey $UninstallKey -Shortcut $Shortcut)
    Write-AC7HostFindings (Invoke-AC7HostGameDeploy)
    Write-Host ('已回退到 '+$previous+'。') -ForegroundColor Green;$answer=Read-Host '直接回车打开启动器；输入 Q 关闭'
   }
   if($answer -ine 'Q' -and !$NoLaunch){Start-AC7HostLauncher}
   exit $(if($bad){1}else{0})
  }
  'Rollback'{
   $state=Read-AC7AppState $installRoot
   if(!$state.previous){Stop-AC7App 'NO_PREVIOUS' '没有可以回退的上一版本。'}
   if(!$Yes -and (Read-Host ('输入 Y 从 '+$state.current+' 回退到 '+$state.previous+'；直接回车取消')) -ine 'Y'){exit 0}
   Write-AC7HostFindings @(Invoke-AC7AppRollback -InstallRoot $installRoot -NoRegister:$NoRegister -UninstallKey $UninstallKey -Shortcut $Shortcut)
   Write-AC7HostFindings (Invoke-AC7HostGameDeploy)
   Write-Host ('[ROLLED BACK] 已回退到 '+$state.previous+'。') -ForegroundColor Green
   if(!$NoLaunch -and !$Yes -and (Read-Host '直接回车打开启动器；输入 N 关闭') -ine 'N'){Start-AC7HostLauncher}
   exit 0
  }
  'Uninstall'{
   Write-Host '卸载 AC7 Integrated'
   Write-Host '会先用当前版本卸载游戏目录中由本程序安装的 Mod（先备份；被改动的文件保留），再删除程序文件、开始菜单项和卸载项。'
   if(!$Yes -and (Read-Host '输入 Y 确认卸载；直接回车取消') -ine 'Y'){Write-Host '已取消。';exit 0}
   $keep=!$RemoveData
   if(!$Yes){$keep=(Read-Host 'data 文件夹保存着设置、键位、附加 Mod、存档备份和卸载备份。直接回车保留；输入 D 一并删除') -ine 'D'}
   Set-Location -LiteralPath ([IO.Path]::GetTempPath())
   foreach($line in @(Invoke-AC7AppUninstall -InstallRoot $installRoot -KeepData $keep -NoRegister:$NoRegister -UninstallKey $UninstallKey -Shortcut $Shortcut)){Write-Host $line}
   Write-Host '[UNINSTALLED] 已卸载 AC7 Integrated。' -ForegroundColor Green
   if($keep){Write-Host ('已保留玩家数据：'+[IO.Path]::Combine($installRoot,'data'))}
   Wait-AC7HostClose;exit 0
  }
  'Status'{
   ConvertTo-Json -InputObject (Get-AC7AppStatus $installRoot) -Depth 5 | Write-Output
   exit 0
  }
  'CheckUpdate'{
   $package=Get-AC7AppCurrentPackage $installRoot
   $check=Get-AC7AppUpdateCheck $package $Feed
   if($check.Update){
    $offer=Get-AC7AppUpdateOffer -InstallRoot $installRoot -Feed $Feed -Release $check.Release
    Remove-AC7AppTree $offer.Cache
    Write-Host ('[UPDATE] '+$offer.Version+' 当前 '+$check.Current+$(if($check.NotesUrl){' '+$check.NotesUrl}else{''}))
   }else{Write-Host ('[UP-TO-DATE] '+$check.Current+$(if($check.Latest){'（GitHub 最新：'+$check.Latest+'）'}else{''}))}
   exit 0
  }
 }
}catch{
 $failure=$_
 $code=[string]$failure.Exception.Data['AC7Code']
 Write-Host ('[未完成] '+$failure.Exception.Message+$(if($code){' ['+$code+']'}else{''})) -ForegroundColor Red
 $hint=[string]$failure.Exception.Data['AC7Hint'];if($hint){Write-Host $hint -ForegroundColor Yellow}
 if($Action -in @('Launch','Update','Repair','Rollback','Uninstall')){Wait-AC7HostClose}
 # The launcher closes itself before an update or rollback (-Yes: no prompts): show why and bring it back.
 if($Action -in @('Update','Rollback') -and !$NoLaunch){
  if($Yes){try{Add-Type -AssemblyName PresentationFramework;[void][Windows.MessageBox]::Show(('未完成：'+$failure.Exception.Message+$(if($code){' ['+$code+']'}else{''})+[Environment]::NewLine+[Environment]::NewLine+$hint+[Environment]::NewLine+[Environment]::NewLine+'已安装的版本保持不变。'),'AC7 Integrated')}catch{}}
  try{Start-AC7HostLauncher}catch{}
 }
 exit 1
}
