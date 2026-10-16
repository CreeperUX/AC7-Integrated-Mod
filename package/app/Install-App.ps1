# AC7 Integrated setup (0.7.0): installs the release zip next to this script as a per-user app in
# %LOCALAPPDATA%\Programs\AC7 Integrated. No administrator rights. Running it again repairs or updates the installation
# and keeps the player data. When the game has the mod installed by a portable package, that package's settings, key
# bindings, scope, paths and extra mods are imported (the package itself is only read) and the installed mod can be
# taken over by the app (the package's own Invoke-AC7Install: save backup, journal, every file verified).
param(
 [string]$Zip='',[string]$InstallRoot='',[string]$ImportFrom='',[switch]$NoImport,[string]$GameRoot='',[switch]$NoAdopt,
 [switch]$Yes,[switch]$NoRegister,[switch]$NoLaunch,[string]$SaveRoot='',[string]$UninstallKey='',[string]$Shortcut='',[switch]$TestOnlySkipExeHash
)
$ErrorActionPreference='Stop'
foreach($module in @('Microsoft.PowerShell.Management','Microsoft.PowerShell.Utility')){Import-Module ([IO.Path]::Combine($PSHOME,'Modules',$module,($module+'.psd1'))) -ErrorAction Stop}
. ([IO.Path]::Combine($PSScriptRoot,'App-Core.ps1'))
try{$Host.UI.RawUI.WindowTitle='AC7 Integrated · 安装'}catch{}
try{
 Write-Host 'AC7 Integrated 安装程序 · 仅限单人游戏（进入多人对战前请先停用 Mod）'
 if(!$InstallRoot){$InstallRoot=Get-AC7AppDefaultInstallRoot}
 $InstallRoot=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\','/')
 if(!$UninstallKey){$UninstallKey=Get-AC7AppUninstallKey}
 if(!$Shortcut){$Shortcut=Get-AC7AppShortcutPath}
 if(!$Zip){
  $found=@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'AC7-Integrated-v*.zip' -File)
  if($found.Count -ne 1){Stop-AC7App 'SETUP_PACKAGE' '找不到要安装的安装包（AC7-Integrated-v….zip）。' '请重新下载安装程序。'}
  $Zip=$found[0].FullName
 }
 $packageZip=[IO.Path]::GetFullPath($Zip)
 Write-Host ('安装位置：'+$InstallRoot)
 $busy=Get-AC7AppBusyReason $InstallRoot;if($busy){Stop-AC7App 'APP_BUSY' $busy '退出游戏后重新运行安装程序。'}
 $existing=$null;try{$existing=Read-AC7AppState $InstallRoot}catch{$existing=$null}
 $setupVersion=([regex]::Match([IO.Path]::GetFileName($packageZip),'^AC7-Integrated-v(.+)\.zip$')).Groups[1].Value
 if($existing -and (Test-AC7AppVersionName $setupVersion) -and (Compare-AC7AppVersion $setupVersion ([string]$existing.current)) -lt 0){
  Write-Host ('已安装更新的版本 '+$existing.current+'，此安装程序是 '+$setupVersion+'。') -ForegroundColor Yellow
  if($Yes -or (Read-Host ('输入 Y 改为使用 '+$setupVersion+'；直接回车取消')) -ine 'Y'){Stop-AC7App 'SETUP_OLDER' '已取消，没有任何改动。'}
 }
 Write-Host '正在校验并写入程序文件…'
 $version=Install-AC7AppVersion $InstallRoot $packageZip
 $package=[IO.Path]::Combine($InstallRoot,'versions',$version)
 $data=[IO.Path]::Combine($InstallRoot,'data')
 $firstInstall=![IO.Directory]::Exists($data)
 # The game folder: explicit, saved by an earlier install, or the single one Steam lists (read-only discovery).
 $game=$null
 if($GameRoot -or !$firstInstall -or !$NoImport -or !$NoAdopt){$game=Find-AC7AppGame $package $GameRoot $(if($firstInstall){''}else{$data})}
 if($game){Write-Host ('游戏位置：'+$game)}
 $import=''
 if($firstInstall -and !$NoImport){
  if($ImportFrom){
   $import=[IO.Path]::GetFullPath($ImportFrom).TrimEnd('\','/')
   if(!(Test-AC7AppPortablePackage $import)){Stop-AC7App 'IMPORT_SOURCE' ('这里不是 AC7 Integrated 便携版：'+$import) '请选择便携版整合包的文件夹（包含 MouseAim-Settings.ini）。'}
  }elseif($game){$import=Find-AC7AppPortablePackage $InstallRoot $game}
  if($import){
   Write-Host ('找到正在使用的便携版：'+$import)
   if(!$Yes -and !$ImportFrom -and (Read-Host '直接回车导入它的设置、键位、安装内容、路径和附加 Mod（原文件不改动）；输入 N 不导入') -ieq 'N'){$import=''}
  }
 }
 $report=@(Complete-AC7AppInstall -InstallRoot $InstallRoot -Version $version -Source 'setup' -ZipPath $packageZip -ImportFrom $import -NoRegister:$NoRegister -UninstallKey $UninstallKey -Shortcut $Shortcut)
 foreach($item in $report){Write-Host ('  '+$item.Message) -ForegroundColor $(if($item.Status -eq 'problem'){'Red'}else{'Gray'})}
 if($game -and !(Get-AC7AppSavedText $data 'game-path.txt')){[IO.File]::WriteAllText([IO.Path]::Combine($data,'game-path.txt'),$game+"`r`n",(New-Object Text.UTF8Encoding($false)))}
 Write-Host ''
 Write-Host ('[INSTALLED] 已安装 AC7 Integrated '+$version+'。默认飞控为 WAR，游戏中按 F4 可切换到 PEACE。') -ForegroundColor Green
 # The mod in the game folder: take over an install made by a portable package, so that updates and repairs reach it.
 $owner=$null;if($game){$owner=Get-AC7AppGameOwner $game}
 if($game -and $owner -and !(Test-AC7AppSamePath $owner.Project $InstallRoot)){
  $adopt=$false
  if($NoAdopt){}
  elseif(!$Yes){$adopt=(Read-Host ('游戏中的 Mod 由 '+$owner.Project+' 安装。直接回车交给安装版管理（先备份存档和原文件，逐个校验）；输入 N 暂不接管')) -ine 'N'}
  elseif($GameRoot){$adopt=$true}
  if($adopt){
   Write-Host '正在接管游戏中的 Mod…'
   $findings=@(Invoke-AC7AppGameDeploy -InstallRoot $InstallRoot -Adopt -GameRoot $game -SaveRoot $SaveRoot -TestOnlySkipExeHash:$TestOnlySkipExeHash)
   foreach($finding in $findings){Write-Host ('  '+$finding.Message) -ForegroundColor $(if($finding.Status -eq 'problem'){'Red'}else{'Gray'})}
   if(@($findings | Where-Object {$_.Status -eq 'problem'}).Count){Write-Host '游戏中的 Mod 暂未接管；处理上面的问题后，在启动器中点击“安装／更新”即可接管。' -ForegroundColor Yellow}
   else{Write-Host '[ADOPTED] 游戏中的 Mod 已由安装版管理。' -ForegroundColor Green}
  }else{Write-Host ('游戏中的 Mod 仍由 '+$owner.Project+' 管理。需要时在启动器中点击“安装／更新”交给安装版。') -ForegroundColor Yellow}
 }elseif($game -and !$owner){Write-Host '游戏中还没有安装本 Mod：打开启动器，选择安装内容后点击“安装／更新”。'}
 Write-Host '以后从开始菜单的“AC7 Integrated”打开启动器；检查更新、检查并修复也在启动器里，卸载在 Windows 设置 → 应用。'
 if($import){Write-Host ('便携版仍在原处：'+$import+'。确认安装版正常后可以自行删除（其中 backups 保存着旧的存档备份）。')}
 if(!$NoLaunch -and ($Yes -or (Read-Host '直接回车打开启动器；输入 N 结束') -ine 'N')){
  $launcher=[IO.Path]::Combine($InstallRoot,(Get-AC7AppLauncherName))
  if([IO.File]::Exists($launcher)){Start-Process -FilePath $launcher}
  else{Start-Process -FilePath ([IO.Path]::Combine($PSHOME,'powershell.exe')) -WindowStyle Hidden -ArgumentList @('-NoProfile','-STA','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',('"'+[IO.Path]::Combine($InstallRoot,'Host.ps1')+'"'),'-Action','Gui')}
 }
 exit 0
}catch{
 $code=[string]$_.Exception.Data['AC7Code']
 Write-Host ('[安装未完成] '+$_.Exception.Message+$(if($code){' ['+$code+']'}else{''})) -ForegroundColor Red
 $hint=[string]$_.Exception.Data['AC7Hint'];if($hint){Write-Host $hint -ForegroundColor Yellow}
 Write-Host '已安装的版本和玩家数据保持不变。'
 if(!$Yes){[void](Read-Host '按回车关闭')}
 exit 1
}
