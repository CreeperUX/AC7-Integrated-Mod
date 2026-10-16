# AC7 Integrated installed app (0.7.0, port of the AC8 2.5.0 app layer): install, signed GitHub updates, repair,
# rollback, uninstall and launch diagnostics. AC7 keeps the mod installed persistently in the game folder (the package's
# Invoke-AC7Install); the app manages the program versions around it and brings the installed mod to the current version.
#  <install>\Host.ps1, App-Core.ps1, AC7.ico   host files, copied from the newest intact installed version
#  <install>\app.json                          {schema, current, previous, versions[]}
#  <install>\trust\update-key.xml              public RSA key that signs update-manifest.json
#  <install>\versions\<version>\               complete packages, marked by app-version.json
#  <install>\data\                             player data shared by all versions (settings, paths, backups, caches)
# Loaded by Host.ps1, by Install-App.ps1 (setup) and by the launcher (app\App-Core.ps1 of its own package, portable or
# installed). Self-contained: game-folder work loads the version package's own Install-Core.ps1 / Cleanup-Core.ps1 inside
# the calling function, so the package functions never leak into the caller. Function names use the AC7App prefix.

function Stop-AC7App([string]$Code,[string]$Message,[string]$Hint=''){
 $failure=New-Object InvalidOperationException($Message)
 $failure.Data['AC7Code']=$Code;$failure.Data['AC7Hint']=$Hint
 throw $failure
}
function Get-AC7AppRepository{return 'CreeperUX/AC7-Integrated-Mod'}
function Get-AC7AppDownloadPrefix{return 'https://github.com/CreeperUX/AC7-Integrated-Mod/releases/download/'}
function Get-AC7AppUninstallKey{return 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AC7Integrated'}
function Get-AC7AppShortcutPath{return [IO.Path]::Combine([Environment]::GetFolderPath('Programs'),'AC7 Integrated.lnk')}
function Get-AC7AppDefaultInstallRoot{return [IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'),'Programs','AC7 Integrated')}
function Test-AC7AppVersionName([string]$Version){return [bool]($Version -match '^\d{1,4}\.\d{1,4}\.\d{1,4}(?:-(?:alpha|beta|rc)\.\d{1,4})?$')}
function Compare-AC7AppVersion([string]$A,[string]$B){
 # -1, 0 or 1: major.minor.patch numerically; a release after any of its prereleases; alpha < beta < rc; then N numerically.
 if(!(Test-AC7AppVersionName $A) -or !(Test-AC7AppVersionName $B)){throw "Invalid version: '$A' / '$B'"}
 $x=$A.Split([char[]]'-',2);$y=$B.Split([char[]]'-',2)
 $p=$x[0].Split('.');$q=$y[0].Split('.')
 for($i=0;$i -lt 3;$i++){$c=([int]$p[$i]).CompareTo([int]$q[$i]);if($c -ne 0){return [Math]::Sign($c)}}
 if($x.Count -eq 1 -and $y.Count -eq 1){return 0}
 if($x.Count -eq 1){return 1};if($y.Count -eq 1){return -1}
 $p=$x[1].Split('.');$q=$y[1].Split('.')
 $c=[string]::CompareOrdinal($p[0],$q[0]);if($c -ne 0){return [Math]::Sign($c)}
 return [Math]::Sign(([int]$p[1]).CompareTo([int]$q[1]))
}
function Get-AC7AppSortedVersions([string[]]$Versions){
 # Valid version names, newest first.
 $list=New-Object Collections.Generic.List[string]
 foreach($v in @($Versions | Where-Object {Test-AC7AppVersionName $_})){$i=0;while($i -lt $list.Count -and (Compare-AC7AppVersion $list[$i] $v) -gt 0){$i++};$list.Insert($i,$v)}
 return @($list)
}
function Get-AC7AppHash([string]$Path){
 $sha=[Security.Cryptography.SHA256]::Create();$stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try{return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}finally{$stream.Dispose();$sha.Dispose()}
}
function Write-AC7AppFile([string]$Path,[byte[]]$Bytes){
 # Complete or not at all: write beside the target, then replace it.
 $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 [IO.File]::WriteAllBytes($temporary,$Bytes)
 try{
  if([IO.File]::Exists($Path)){[IO.File]::SetAttributes($Path,[IO.FileAttributes]::Normal);[IO.File]::Replace($temporary,$Path,[NullString]::Value)}
  else{[IO.File]::Move($temporary,$Path)}
 }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
function Write-AC7AppJson([string]$Path,$Value){Write-AC7AppFile $Path ((New-Object Text.UTF8Encoding($false)).GetBytes((ConvertTo-Json -InputObject $Value -Depth 8)))}
function Copy-AC7AppFile([string]$Source,[string]$Destination){
 # Returns $true when the destination was missing or different.
 if([IO.File]::Exists($Destination) -and (Get-AC7AppHash $Destination) -eq (Get-AC7AppHash $Source)){return $false}
 [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Destination))
 Write-AC7AppFile $Destination ([IO.File]::ReadAllBytes($Source))
 return $true
}
function Remove-AC7AppTree([string]$Path){
 # Never follows directory links (Windows PowerShell 5.1 Remove-Item -Recurse does).
 if(![IO.Directory]::Exists($Path)){if([IO.File]::Exists($Path)){[IO.File]::SetAttributes($Path,[IO.FileAttributes]::Normal);[IO.File]::Delete($Path)};return}
 $item=New-Object IO.DirectoryInfo($Path)
 if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){[IO.Directory]::Delete($Path,$false);return}
 foreach($child in $item.GetFileSystemInfos()){
  if($child -is [IO.DirectoryInfo]){Remove-AC7AppTree $child.FullName}
  else{$child.Attributes=[IO.FileAttributes]::Normal;$child.Delete()}
 }
 $item.Attributes=[IO.FileAttributes]::Directory;$item.Delete($false)
}
function Copy-AC7AppTree([string]$Source,[string]$Destination){
 # Folder copy without filesystem links; existing files are kept.
 [void][IO.Directory]::CreateDirectory($Destination)
 foreach($child in (New-Object IO.DirectoryInfo($Source)).GetFileSystemInfos()){
  if($child.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
  $target=[IO.Path]::Combine($Destination,$child.Name)
  if($child -is [IO.DirectoryInfo]){Copy-AC7AppTree $child.FullName $target}
  elseif(![IO.File]::Exists($target)){[IO.File]::Copy($child.FullName,$target,$false)}
 }
}
function Get-AC7AppSavedText([string]$DataRoot,[string]$Name){
 $path=[IO.Path]::Combine($DataRoot,$Name)
 if(![IO.File]::Exists($path)){return ''}
 try{return ([IO.File]::ReadAllText($path)).Trim().Trim([char]0xFEFF).Trim()}catch{return ''}
}
function Test-AC7AppSamePath([string]$A,[string]$B){
 if(!$A -or !$B){return $false}
 try{return [IO.Path]::GetFullPath($A).TrimEnd('\','/').Equals([IO.Path]::GetFullPath($B).TrimEnd('\','/'),[StringComparison]::OrdinalIgnoreCase)}catch{return $false}
}
function Test-AC7AppInside([string]$Path,[string]$Folder){
 if(!$Path -or !$Folder){return $false}
 try{$p=[IO.Path]::GetFullPath($Path).TrimEnd('\','/');$f=[IO.Path]::GetFullPath($Folder).TrimEnd('\','/')}catch{return $false}
 return ($p.Equals($f,[StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($f+'\',[StringComparison]::OrdinalIgnoreCase))
}
function Get-AC7AppLayout([string]$PackageRoot){
 # Installed (versions\<version>\ marked by app-version.json) or portable. Never throws; the launcher uses it.
 $package=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\','/')
 if([IO.File]::Exists([IO.Path]::Combine($package,'app-version.json'))){
  $install=[IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($package))
  return [pscustomobject]@{Installed=$true;PackageRoot=$package;InstallRoot=$install;DataRoot=[IO.Path]::Combine($install,'data')}
 }
 return [pscustomobject]@{Installed=$false;PackageRoot=$package;InstallRoot=$null;DataRoot=$package}
}
function Get-AC7AppPackageVersion([string]$PackageRoot){
 try{return [string]([IO.File]::ReadAllText([IO.Path]::Combine($PackageRoot,'package-info.json')) | ConvertFrom-Json).version}catch{return ''}
}

# ---- state ----
function Read-AC7AppState([string]$InstallRoot){
 $path=[IO.Path]::Combine($InstallRoot,'app.json')
 if(![IO.File]::Exists($path)){return $null}
 $state=$null;try{$state=[IO.File]::ReadAllText($path) | ConvertFrom-Json}catch{$state=$null}
 if(!$state -or $state.schema -ne 1 -or !(Test-AC7AppVersionName ([string]$state.current))){
  Stop-AC7App 'APP_STATE' 'app.json 已损坏。' '请在开始菜单打开 AC7 Integrated 并使用“检查并修复”，设置不会丢失。'
 }
 return $state
}
function Get-AC7AppInstalledVersions([string]$InstallRoot){
 # Version folders with their marker, newest first.
 $dir=[IO.Path]::Combine($InstallRoot,'versions')
 if(![IO.Directory]::Exists($dir)){return @()}
 $names=@(Get-ChildItem -LiteralPath $dir -Directory -Force | Where-Object {(Test-AC7AppVersionName $_.Name) -and [IO.File]::Exists([IO.Path]::Combine($_.FullName,'app-version.json'))} | ForEach-Object {$_.Name})
 return @(Get-AC7AppSortedVersions $names)
}
function Set-AC7AppCurrent([string]$InstallRoot,[string]$Version,[string]$Source){
 $state=$null;try{$state=Read-AC7AppState $InstallRoot}catch{$state=$null}
 $previous=$null;$entries=@()
 if($state){
  $previous=if([string]$state.current -ne $Version){[string]$state.current}else{[string]$state.previous}
  $entries=@($state.versions | Where-Object {$_ -and [string]$_.version -ne $Version})
 }
 if($previous -and !(Test-AC7AppVersionName $previous)){$previous=$null}
 $entries+=[pscustomobject]@{version=$Version;installedUtc=[DateTime]::UtcNow.ToString('o');source=$Source}
 Write-AC7AppJson ([IO.Path]::Combine($InstallRoot,'app.json')) ([pscustomobject]@{schema=1;current=$Version;previous=$previous;versions=@($entries)})
}
function Get-AC7AppCurrentPackage([string]$InstallRoot){
 $state=Read-AC7AppState $InstallRoot
 if(!$state){Stop-AC7App 'APP_STATE' '找不到 app.json，安装不完整。' '请重新运行安装程序；设置不会丢失。'}
 $package=[IO.Path]::Combine($InstallRoot,'versions',[string]$state.current)
 if(![IO.File]::Exists([IO.Path]::Combine($package,'app-version.json'))){Stop-AC7App 'APP_LAYOUT' ('当前版本 '+$state.current+' 的程序文件夹缺失。') '请在开始菜单打开 AC7 Integrated 并使用“检查并修复”。'}
 return $package
}
function Get-AC7AppBusyReason([string]$InstallRoot){
 # AC7 running from the saved game folder; any AC7 when no folder is saved or a process path cannot be read.
 $processes=@(Get-Process -Name Ace7Game -ErrorAction SilentlyContinue)
 if(!$processes.Count){return $null}
 $game='';if($InstallRoot){$game=Get-AC7AppSavedText ([IO.Path]::Combine($InstallRoot,'data')) 'game-path.txt'}
 foreach($process in $processes){
  $image=$null;try{$image=[string]$process.Path}catch{$image=$null}
  $folder=$null;if($image){try{$folder=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($image))}catch{$folder=$null}}
  if(!$game -or !$folder -or (Test-AC7AppSamePath $folder $game)){return '游戏正在运行（Ace7Game）。请先正常退出游戏，再安装、更新、修复、回退或卸载。'}
 }
 return $null
}

# ---- packages ----
function Read-AC7AppFileList([string]$Path){
 # FILES.sha256 is UTF-8 (it names Chinese files); fall back to the ANSI code page for lists written elsewhere.
 $bytes=[IO.File]::ReadAllBytes($Path)
 try{$text=(New-Object Text.UTF8Encoding($false,$true)).GetString($bytes)}catch{$text=[Text.Encoding]::Default.GetString($bytes)}
 return @($text.TrimStart([char]0xFEFF) -split "`r?`n" | Where-Object {$_})
}
function Get-AC7AppPackageProblems([string]$PackageRoot){
 # FILES.sha256 of the release package: missing or changed files (relative paths). Extra files are not reported.
 $root=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\','/')
 $list=[IO.Path]::Combine($root,'FILES.sha256')
 if(![IO.File]::Exists($list)){return @('FILES.sha256')}
 $problems=New-Object Collections.Generic.List[string]
 foreach($line in (Read-AC7AppFileList $list)){
  if($line -notmatch '^([0-9a-fA-F]{64})  (.+)$'){$problems.Add('FILES.sha256');break}
  $digest=$Matches[1].ToUpperInvariant();$rel=$Matches[2]
  $file=[IO.Path]::GetFullPath([IO.Path]::Combine($root,$rel.Replace('/','\')))
  if(!$file.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){$problems.Add($rel);continue}
  if(![IO.File]::Exists($file) -or (Get-AC7AppHash $file) -ne $digest){$problems.Add($rel)}
 }
 return @($problems)
}
function Expand-AC7AppZip([string]$ZipPath,[string]$Destination){
 # Extract a release zip (one top folder) and verify it completely: every file listed in FILES.sha256 with its hash,
 # nothing unlisted, no path outside the destination, the installed-app host present.
 Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
 $dest=[IO.Path]::GetFullPath($Destination).TrimEnd('\','/')
 [void][IO.Directory]::CreateDirectory($dest)
 $tops=@{};$archive=$null
 try{$archive=[IO.Compression.ZipFile]::OpenRead($ZipPath)}catch{Stop-AC7App 'PACKAGE_INVALID' ('安装包无法打开：'+$_.Exception.Message) '请重新下载安装包。'}
 try{
  foreach($entry in $archive.Entries){
   $name=$entry.FullName.Replace('/','\')
   if(!$name -or $name.StartsWith('\') -or $name.Contains(':') -or $name -match '(^|\\)\.\.(\\|$)'){Stop-AC7App 'PACKAGE_INVALID' '安装包含有不安全的路径，已拒绝。' '请从 GitHub 发布页重新下载。'}
   $target=[IO.Path]::GetFullPath([IO.Path]::Combine($dest,$name))
   if(!$target.StartsWith($dest+'\',[StringComparison]::OrdinalIgnoreCase)){Stop-AC7App 'PACKAGE_INVALID' '安装包含有不安全的路径，已拒绝。' '请从 GitHub 发布页重新下载。'}
   $tops[$name.Split('\')[0]]=$true
   if($name.EndsWith('\')){[void][IO.Directory]::CreateDirectory($target);continue}
   [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
   [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$false)
  }
 }finally{$archive.Dispose()}
 if($tops.Count -ne 1){Stop-AC7App 'PACKAGE_INVALID' '安装包结构不正确。' '请重新下载安装包。'}
 $package=[IO.Path]::Combine($dest,@($tops.Keys)[0])
 $problems=@(Get-AC7AppPackageProblems $package)
 if($problems.Count){Stop-AC7App 'PACKAGE_INVALID' ('安装包校验失败：'+$problems[0]) '请重新下载安装包。'}
 $listed=@{}
 foreach($line in (Read-AC7AppFileList ([IO.Path]::Combine($package,'FILES.sha256')))){$listed[$line.Substring(66).Replace('/','\')]=$true}
 foreach($file in [IO.Directory]::GetFiles($package,'*','AllDirectories')){
  $rel=$file.Substring($package.Length+1)
  if($rel -ne 'FILES.sha256' -and !$listed.ContainsKey($rel)){Stop-AC7App 'PACKAGE_INVALID' ('安装包含有未登记的文件：'+$rel) '请重新下载安装包。'}
 }
 $version=Get-AC7AppPackageVersion $package
 if(!(Test-AC7AppVersionName $version)){Stop-AC7App 'PACKAGE_INVALID' '安装包缺少有效的版本信息。' '请重新下载安装包。'}
 if(![IO.File]::Exists([IO.Path]::Combine($package,'app\Host.ps1'))){Stop-AC7App 'PACKAGE_INVALID' ('版本 '+$version+' 不支持安装版（需要 0.7.0 或更新）。') '请下载 0.7.0 或更新的版本。'}
 return [pscustomobject]@{Path=$package;Version=$version}
}
function Install-AC7AppVersion([string]$InstallRoot,[string]$ZipPath,[string]$ExpectedVersion=''){
 # versions\<version> from a release zip. The same version again (reinstall, repair) replaces only the files that
 # differ, in place, so files held open elsewhere in the folder do not block it.
 $versions=[IO.Path]::Combine($InstallRoot,'versions');[void][IO.Directory]::CreateDirectory($versions)
 $staging=[IO.Path]::Combine($versions,'.s-'+[guid]::NewGuid().ToString('N').Substring(0,8))
 try{
  $package=Expand-AC7AppZip $ZipPath $staging
  if($ExpectedVersion -and $package.Version -ne $ExpectedVersion){Stop-AC7App 'PACKAGE_VERSION' ('安装包版本 '+$package.Version+' 与预期的 '+$ExpectedVersion+' 不一致，已拒绝。') '请从 GitHub 发布页重新下载。'}
  Write-AC7AppJson ([IO.Path]::Combine($package.Path,'app-version.json')) ([pscustomobject]@{schema=1;version=$package.Version})
  $target=[IO.Path]::Combine($versions,$package.Version)
  if(![IO.Directory]::Exists($target)){[IO.Directory]::Move($package.Path,$target)}
  else{
   foreach($file in [IO.Directory]::GetFiles($package.Path,'*','AllDirectories')){
    $null=Copy-AC7AppFile $file ([IO.Path]::Combine($target,$file.Substring($package.Path.Length+1)))
   }
  }
  $problems=@(Get-AC7AppPackageProblems $target)
  if($problems.Count){Stop-AC7App 'PACKAGE_WRITE' ('写入后校验失败：'+$problems[0]) '文件可能被安全软件拦截。请查看 Windows 安全中心的保护历史，恢复误拦截的文件后重试（不要关闭安全软件）。'}
  return $package.Version
 }finally{if([IO.Directory]::Exists($staging)){Remove-AC7AppTree $staging}}
}
function Save-AC7AppCache([string]$InstallRoot,[string]$Version,[string]$ZipPath){
 # Keep the verified zip of an installed version for offline repair.
 $dir=[IO.Path]::Combine($InstallRoot,'data','update-cache',$Version);[void][IO.Directory]::CreateDirectory($dir)
 $name=[IO.Path]::GetFileName($ZipPath);$target=[IO.Path]::Combine($dir,$name)
 if(![string]::Equals([IO.Path]::GetFullPath($ZipPath),$target,[StringComparison]::OrdinalIgnoreCase)){$null=Copy-AC7AppFile $ZipPath $target}
 Write-AC7AppJson ([IO.Path]::Combine($dir,'package.json')) ([pscustomobject]@{version=$Version;asset=$name;sha256=(Get-AC7AppHash $target)})
}
function Get-AC7AppCache([string]$InstallRoot,[string]$Version){
 $dir=[IO.Path]::Combine($InstallRoot,'data','update-cache',$Version);$record=[IO.Path]::Combine($dir,'package.json')
 if(![IO.File]::Exists($record)){return $null}
 try{$info=[IO.File]::ReadAllText($record) | ConvertFrom-Json}catch{return $null}
 $cached=[IO.Path]::Combine($dir,[IO.Path]::GetFileName([string]$info.asset))
 if([string]$info.version -ne $Version -or ![IO.File]::Exists($cached) -or (Get-AC7AppHash $cached) -ne [string]$info.sha256){return $null}
 return $cached
}
function Get-AC7AppHostFiles{return @(@('Host.ps1','Host.ps1'),@('App-Core.ps1','App-Core.ps1'),@('update-key.xml','trust\update-key.xml'),@('AC7.ico','AC7.ico'))}
function Get-AC7AppLauncherName{return 'AC7 Integrated.exe'}   # the launcher as its own application (package root)
function Install-AC7AppHostFiles([string]$InstallRoot,[string]$PackageRoot,[int]$LauncherWaitSeconds=10){
 $app=[IO.Path]::Combine($PackageRoot,'app');$changed=@()
 foreach($pair in (Get-AC7AppHostFiles)){
  if(Copy-AC7AppFile ([IO.Path]::Combine($app,$pair[0])) ([IO.Path]::Combine($InstallRoot,$pair[1]))){$changed+=$pair[1]}
 }
 # AC7 Integrated.exe (package root): the launcher as its own application, the Start menu entry. It hosts the launcher
 # and stays in use while the launcher is open: never its own image (the self-check at start runs inside it); another
 # copy that is still running (a launcher closing for an update) gets a few seconds. Still in use: the old exe is kept
 # (it runs the new scripts) and replaced by the next update, repair or setup.
 $launcher=[IO.Path]::Combine($PackageRoot,(Get-AC7AppLauncherName))
 if([IO.File]::Exists($launcher)){
  $target=[IO.Path]::Combine($InstallRoot,(Get-AC7AppLauncherName))
  $self=$false;try{$self=Test-AC7AppSamePath ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) $target}catch{$self=$false}
  $deadline=[DateTime]::UtcNow.AddSeconds($LauncherWaitSeconds)
  while($true){
   try{if(Copy-AC7AppFile $launcher $target){$changed+=(Get-AC7AppLauncherName)};break}
   catch{
    $inner=$_.Exception;while($inner -is [Management.Automation.MethodInvocationException] -and $inner.InnerException){$inner=$inner.InnerException}
    if($inner -isnot [IO.IOException] -and $inner -isnot [UnauthorizedAccessException]){throw}
    if($self){break}
    if([DateTime]::UtcNow -ge $deadline){Write-Host ('提示：'+(Get-AC7AppLauncherName)+' 正在使用（启动器还开着），这次没有替换；关闭启动器后运行“检查并修复”即可更新。') -ForegroundColor Yellow;break}
    Start-Sleep -Milliseconds 250
   }
  }
 }
 return $changed
}
function Remove-AC7AppOldVersions([string]$InstallRoot){
 # Keep the current and the previous version (and their cached zips); remove older ones and interrupted staging.
 $state=Read-AC7AppState $InstallRoot;$keep=@(@([string]$state.current,[string]$state.previous) | Where-Object {$_})
 foreach($dir in @(Get-ChildItem -LiteralPath ([IO.Path]::Combine($InstallRoot,'versions')) -Directory -Force -ErrorAction SilentlyContinue)){
  if($keep -contains $dir.Name){continue}
  try{Remove-AC7AppTree $dir.FullName}catch{}
 }
 foreach($dir in @(Get-ChildItem -LiteralPath ([IO.Path]::Combine($InstallRoot,'data','update-cache')) -Directory -Force -ErrorAction SilentlyContinue)){
  if($keep -contains $dir.Name){continue}
  try{Remove-AC7AppTree $dir.FullName}catch{}
 }
}

# ---- player data ----
function Repair-AC7AppPlayerSettings([string]$DataRoot,[string]$PackageRoot){
 # Every settings file must be readable by this package. An unreadable one is backed up (data\repair-backups) and rebuilt
 # from the package template, keeping each saved value the package still accepts. Then the one-time migrations run.
 . ([IO.Path]::Combine($PackageRoot,'Install-Core.ps1'))
 $report=@()
 $checks=@(
  @{Name='MouseAim-Settings.ini';Label='飞控设置';Read={param($p) $null=Read-AC7MouseSettings $p}},
  @{Name='features.ini';Label='安装内容';Read={param($p) $null=Read-AC7FeatureSettings $p}},
  @{Name='Keybindings.ini';Label='键位设置';Read={param($p) $null=Read-AC7Keybindings $p}}
 )
 foreach($check in $checks){
  $path=[IO.Path]::Combine($DataRoot,$check.Name);$template=[IO.Path]::Combine($PackageRoot,$check.Name)
  if(![IO.File]::Exists($path)){[IO.File]::Copy($template,$path);$report+=[pscustomobject]@{Item=$check.Label;Status='fixed';Message=($check.Name+' 缺失，已恢复默认。')};continue}
  $reason=$null;try{& $check.Read $path}catch{$reason=$_.Exception.Message}
  if(!$reason){$report+=[pscustomobject]@{Item=$check.Label;Status='ok';Message=($check.Name+' 正常。')};continue}
  $backup=[IO.Path]::Combine($DataRoot,'repair-backups',(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
  [void][IO.Directory]::CreateDirectory($backup);[IO.File]::Copy($path,[IO.Path]::Combine($backup,$check.Name))
  $templateBytes=[IO.File]::ReadAllBytes($template);$bom=$templateBytes.Length -ge 3 -and $templateBytes[0] -eq 0xEF -and $templateBytes[1] -eq 0xBB -and $templateBytes[2] -eq 0xBF
  $text=[IO.File]::ReadAllText($template);$saved=[ordered]@{};$kept=0
  foreach($line in [IO.File]::ReadAllLines($path)){if($line -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.*?)\s*$' -and !$saved.Contains($Matches[1])){$saved[$Matches[1]]=$Matches[2]}}
  $probe=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
  try{
   foreach($key in @($saved.Keys)){
    $pattern='(?m)^'+[regex]::Escape($key)+'=[^\r\n]*'
    if(![regex]::IsMatch($text,$pattern)){continue}
    $candidate=[regex]::Replace($text,$pattern,($key+'='+$saved[$key]).Replace('$','$$'))
    if($candidate -eq $text){continue}
    [IO.File]::WriteAllText($probe,$candidate,(New-Object Text.UTF8Encoding($bom)))
    $accepted=$true;try{& $check.Read $probe}catch{$accepted=$false}
    if($accepted){$text=$candidate;$kept++}
   }
  }finally{if([IO.File]::Exists($probe)){[IO.File]::Delete($probe)}}
  Write-AC7AppFile $path ((New-Object Text.UTF8Encoding($bom)).GetBytes($text))
  $report+=[pscustomobject]@{Item=$check.Label;Status='fixed';Message=($check.Name+' 无法读取（'+$reason+'）。原文件已备份到 '+$backup+'，已恢复默认并保留 '+$kept+' 项可用设置。')}
 }
 if(Get-Command Invoke-AC7SettingsMigrations -ErrorAction SilentlyContinue){
  $ini=[IO.Path]::Combine($DataRoot,'MouseAim-Settings.ini');$before=$null
  try{$before=(Read-AC7MouseSettings $ini).control_mode}catch{$before=$null}
  $applied=@(Invoke-AC7SettingsMigrations $PackageRoot)
  $after=$null;try{$after=(Read-AC7MouseSettings $ini).control_mode}catch{$after=$null}
  if($applied -contains 'war-default-0.7.0' -and $before -eq 0 -and $after -eq 3){
   $report+=[pscustomobject]@{Item='飞控设置';Status='fixed';Message='0.7.0 起默认飞控为 WAR，已将启动时的飞控设为 WAR（游戏中按 F4 可切回 PEACE）。'}
  }
 }
 return $report
}
function Initialize-AC7AppData([string]$InstallRoot,[string]$PackageRoot,[string]$ImportFrom=''){
 # data\ for a new install (defaults or the files of a portable package) and for every new version (new defaults,
 # migrations). Existing player files are never replaced here; an imported package is only read.
 $data=[IO.Path]::Combine($InstallRoot,'data');[void][IO.Directory]::CreateDirectory($data)
 $report=@()
 foreach($name in 'MouseAim-Settings.ini','Keybindings.ini','features.ini','game-path.txt','steam-path.txt'){
  $target=[IO.Path]::Combine($data,$name);if([IO.File]::Exists($target)){continue}
  $source=[IO.Path]::Combine($PackageRoot,$name)
  if($ImportFrom){$old=[IO.Path]::Combine($ImportFrom,$name);if([IO.File]::Exists($old)){$source=$old;$report+=[pscustomobject]@{Item='导入';Status='fixed';Message=('已导入 '+$name)}}}
  if([IO.File]::Exists($source)){[IO.File]::Copy($source,$target)}else{[IO.File]::WriteAllText($target,'')}
 }
 $mods=[IO.Path]::Combine($data,'ue4ss-mods');[void][IO.Directory]::CreateDirectory($mods)
 $readme=[IO.Path]::Combine($PackageRoot,'ue4ss-mods','README.txt')
 if([IO.File]::Exists($readme)){$null=Copy-AC7AppFile $readme ([IO.Path]::Combine($mods,'README.txt'))}
 if($ImportFrom){
  $oldMods=[IO.Path]::Combine($ImportFrom,'ue4ss-mods')
  if([IO.Directory]::Exists($oldMods)){
   foreach($dir in @(Get-ChildItem -LiteralPath $oldMods -Directory -Force)){
    if($dir.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
    $target=[IO.Path]::Combine($mods,$dir.Name)
    if(![IO.Directory]::Exists($target)){Copy-AC7AppTree $dir.FullName $target;$report+=[pscustomobject]@{Item='导入';Status='fixed';Message=('已导入附加 Mod '+$dir.Name)}}
   }
  }
 }
 $report+=@(Repair-AC7AppPlayerSettings $data $PackageRoot | Where-Object {$_.Status -ne 'ok'})
 return $report
}
function Get-AC7AppGameOwner([string]$GameRoot){
 # The ownership record of the AC7 mod in a game folder (read-only), or $null.
 if(!$GameRoot){return $null}
 $path=[IO.Path]::Combine($GameRoot,'ue4ss','AC7-MouseAim-owner.json')
 if(![IO.File]::Exists($path)){return $null}
 try{$manifest=[IO.File]::ReadAllText($path) | ConvertFrom-Json}catch{return $null}
 return [pscustomobject]@{Project=[string]$manifest.Project;Version=[string]$manifest.Version;Tool=[string]$manifest.Tool;Features=[string]$manifest.Features}
}
function Test-AC7AppPortablePackage([string]$Folder){
 # A portable AC7 Integrated package folder (not a version of an installed app).
 if(!$Folder){return $false}
 try{$full=[IO.Path]::GetFullPath($Folder)}catch{return $false}
 foreach($name in 'MouseAim-Settings.ini','Install-Core.ps1','package-info.json'){if(![IO.File]::Exists([IO.Path]::Combine($full,$name))){return $false}}
 return ![IO.File]::Exists([IO.Path]::Combine($full,'app-version.json'))
}
function Find-AC7AppGame([string]$PackageRoot,[string]$GameRoot='',[string]$DataRoot=''){
 # The game folder: explicit, saved in data, or the single AC7 installation that Steam lists (read-only discovery with
 # the package's Discover-Installations.ps1). $null when none or several are found.
 if($GameRoot){return [IO.Path]::GetFullPath($GameRoot).TrimEnd('\','/')}
 if($DataRoot){
  $saved=Get-AC7AppSavedText $DataRoot 'game-path.txt'
  if($saved){try{if([IO.File]::Exists([IO.Path]::Combine($saved,'Ace7Game.exe'))){return [IO.Path]::GetFullPath($saved).TrimEnd('\','/')}}catch{}}
 }
 try{
  . ([IO.Path]::Combine($PackageRoot,'Discover-Installations.ps1'))
  $found=Find-AC7Installations -GamePath '' -SteamPath ''
  if($found.GamePath){return [string]$found.GamePath}
 }catch{}
 return $null
}
function Find-AC7AppPortablePackage([string]$InstallRoot,[string]$GameRoot){
 # The portable package that owns the mod installed in the game folder (from its ownership record), or $null.
 $owner=Get-AC7AppGameOwner $GameRoot
 if(!$owner -or !$owner.Project){return $null}
 try{$candidate=[IO.Path]::GetFullPath($owner.Project).TrimEnd('\','/')}catch{return $null}
 if($InstallRoot -and (Test-AC7AppInside $candidate $InstallRoot)){return $null}
 if(Test-AC7AppPortablePackage $candidate){return $candidate}
 return $null
}

# ---- registration (Start menu, Apps & features) ----
function Assert-AC7AppUninstallKey([string]$UninstallKey){
 if(!$UninstallKey.StartsWith('HKCU:\',[StringComparison]::OrdinalIgnoreCase)){throw "Uninstall entry must be under HKCU: $UninstallKey"}
}
function Register-AC7App([string]$InstallRoot,[string]$Version,[string]$UninstallKey=(Get-AC7AppUninstallKey),[string]$Shortcut=(Get-AC7AppShortcutPath)){
 Assert-AC7AppUninstallKey $UninstallKey
 $powershell=[IO.Path]::Combine($PSHOME,'powershell.exe');$hostScript=[IO.Path]::Combine($InstallRoot,'Host.ps1')
 $icon=[IO.Path]::Combine($InstallRoot,'AC7.ico');$launcher=[IO.Path]::Combine($InstallRoot,(Get-AC7AppLauncherName))
 if([IO.File]::Exists($launcher)){$icon=$launcher}
 [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Shortcut))
 $shell=New-Object -ComObject WScript.Shell
 try{
  $link=$shell.CreateShortcut($Shortcut)
  if([IO.File]::Exists($launcher)){$link.TargetPath=$launcher;$link.Arguments=''}
  else{$link.TargetPath=$powershell;$link.Arguments='-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$hostScript+'" -Action Gui'}
  $link.WorkingDirectory=$InstallRoot;$link.Description='AC7 Integrated 启动器（仅限单人游戏）'
  if([IO.File]::Exists($icon)){$link.IconLocation=$icon+',0'}
  $link.Save()
 }finally{[void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)}
 if(!(Test-Path -LiteralPath $UninstallKey)){New-Item -Path $UninstallKey -Force | Out-Null}
 $size=0;foreach($file in [IO.Directory]::GetFiles([IO.Path]::Combine($InstallRoot,'versions'),'*','AllDirectories')){$size+=(New-Object IO.FileInfo($file)).Length}
 $values=[ordered]@{DisplayName='AC7 Integrated';DisplayVersion=$Version;Publisher='CreeperUX';InstallLocation=$InstallRoot
  UninstallString=('"'+$powershell+'" -NoProfile -ExecutionPolicy Bypass -File "'+$hostScript+'" -Action Uninstall')
  URLInfoAbout=('https://github.com/'+(Get-AC7AppRepository));HelpLink=('https://github.com/'+(Get-AC7AppRepository)+'/issues')}
 if([IO.File]::Exists($icon)){$values['DisplayIcon']=$icon}
 foreach($name in $values.Keys){Set-ItemProperty -LiteralPath $UninstallKey -Name $name -Value $values[$name]}
 foreach($name in 'NoModify','NoRepair'){New-ItemProperty -LiteralPath $UninstallKey -Name $name -Value 1 -PropertyType DWord -Force | Out-Null}
 New-ItemProperty -LiteralPath $UninstallKey -Name 'EstimatedSize' -Value ([int][Math]::Ceiling($size/1KB)) -PropertyType DWord -Force | Out-Null
}
function Unregister-AC7App([string]$UninstallKey=(Get-AC7AppUninstallKey),[string]$Shortcut=(Get-AC7AppShortcutPath)){
 Assert-AC7AppUninstallKey $UninstallKey
 if([IO.File]::Exists($Shortcut)){[IO.File]::Delete($Shortcut)}
 if(Test-Path -LiteralPath $UninstallKey){Remove-Item -LiteralPath $UninstallKey -Recurse -Force}
}
function Test-AC7AppRegistered([string]$InstallRoot,[string]$UninstallKey=(Get-AC7AppUninstallKey),[string]$Shortcut=(Get-AC7AppShortcutPath)){
 if(![IO.File]::Exists($Shortcut) -or !(Test-Path -LiteralPath $UninstallKey)){return $false}
 $location=(Get-ItemProperty -LiteralPath $UninstallKey -ErrorAction SilentlyContinue).InstallLocation
 if(![string]::Equals([string]$location,$InstallRoot,[StringComparison]::OrdinalIgnoreCase)){return $false}
 # A powershell.exe shortcut (no native launcher at the time) is replaced once the launcher is installed.
 $launcher=[IO.Path]::Combine($InstallRoot,(Get-AC7AppLauncherName))
 if([IO.File]::Exists($launcher)){
  $shell=New-Object -ComObject WScript.Shell
  try{$target=$shell.CreateShortcut($Shortcut).TargetPath}finally{[void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)}
  if(![string]::Equals([string]$target,$launcher,[StringComparison]::OrdinalIgnoreCase)){return $false}
 }
 return $true
}

# ---- updates (GitHub releases, signed manifest) ----
function Invoke-AC7AppGitHub([string]$Path){
 [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
 $uri='https://api.github.com/repos/'+(Get-AC7AppRepository)+'/'+$Path
 try{return Invoke-RestMethod -Uri $uri -Headers @{'User-Agent'='AC7-Integrated-Updater';'Accept'='application/vnd.github+json'} -TimeoutSec 30 -UseBasicParsing}
 catch{Stop-AC7App 'UPDATE_NETWORK' ('无法连接 GitHub：'+$_.Exception.Message) '请检查网络后重试。只读取 GitHub 发布页，不上传任何数据。'}
}
function Get-AC7AppReleaseList([string]$Feed=''){
 # Published releases with a version tag, newest first. Prereleases are included (AC7 ships betas); drafts are not.
 # $Feed: a local folder with releases.json and <tag>\<asset> files (tests); everything else is checked the same way.
 if($Feed){$raw=[IO.File]::ReadAllText([IO.Path]::Combine($Feed,'releases.json')) | ConvertFrom-Json}
 else{$raw=Invoke-AC7AppGitHub 'releases?per_page=50'}
 $byVersion=@{}
 foreach($release in @($raw | ForEach-Object {$_})){   # Windows PowerShell emits a JSON array as one object
  if(!$release -or $release.draft){continue}
  if([string]$release.tag_name -match '^v(.+)$' -and (Test-AC7AppVersionName $Matches[1]) -and !$byVersion.ContainsKey($Matches[1])){$byVersion[$Matches[1]]=$release}
 }
 return @(foreach($version in (Get-AC7AppSortedVersions @($byVersion.Keys))){$byVersion[$version]})
}
function Get-AC7AppReleaseByTag([string]$Feed,[string]$Tag){
 if($Feed){
  $found=@(Get-AC7AppReleaseList $Feed | Where-Object {[string]$_.tag_name -ceq $Tag})
  if(!$found.Count){Stop-AC7App 'UPDATE_ASSET' ('GitHub 上找不到版本 '+$Tag+' 的发布。') '这个版本可能已被移除，请到 GitHub 发布页手动下载。'}
  return $found[0]
 }
 return Invoke-AC7AppGitHub ('releases/tags/'+[Uri]::EscapeDataString($Tag))
}
function Save-AC7AppReleaseAsset($Release,[string]$Name,[string]$Destination,[string]$Feed='',[long]$MaxBytes=262144){
 $asset=@($Release.assets | Where-Object {[string]$_.name -ceq $Name})
 if($asset.Count -ne 1){Stop-AC7App 'UPDATE_ASSET' ('发布中缺少 '+$Name+'。') '这个版本可能不支持自动更新，请到 GitHub 发布页手动下载安装程序。'}
 if([long]$asset[0].size -le 0 -or [long]$asset[0].size -gt $MaxBytes){Stop-AC7App 'UPDATE_ASSET' ($Name+' 大小异常，已拒绝。') '请到 GitHub 发布页手动下载。'}
 $url=[string]$asset[0].browser_download_url;$prefix=Get-AC7AppDownloadPrefix
 if(!$url.StartsWith($prefix,[StringComparison]::Ordinal)){Stop-AC7App 'UPDATE_SOURCE' '下载地址不是本项目的 GitHub 发布，已拒绝。' '请到 GitHub 发布页手动下载。'}
 if($Feed){
  $parts=$url.Substring($prefix.Length).Split('/')
  if($parts.Count -ne 2 -or $parts[1] -cne $Name -or $parts[0] -notmatch '^v[0-9A-Za-z.\-]+$'){Stop-AC7App 'UPDATE_SOURCE' '下载地址不是本项目的 GitHub 发布，已拒绝。'}
  [IO.File]::Copy([IO.Path]::Combine($Feed,$parts[0],$Name),$Destination,$true)
 }else{
  $ProgressPreference='SilentlyContinue'
  try{Invoke-WebRequest -Uri $url -OutFile $Destination -UseBasicParsing -TimeoutSec 600 -Headers @{'User-Agent'='AC7-Integrated-Updater'}}
  catch{Stop-AC7App 'UPDATE_NETWORK' ('下载 '+$Name+' 失败：'+$_.Exception.Message) '请检查网络后重试。'}
 }
 if((New-Object IO.FileInfo($Destination)).Length -ne [long]$asset[0].size){Stop-AC7App 'UPDATE_ASSET' ($Name+' 下载不完整。') '请重试。'}
}
function Test-AC7AppUpdateSignature([byte[]]$Data,[string]$Signature,[string]$KeyPath){
 # RSA-SHA256 (PKCS#1 v1.5) over the exact manifest bytes with the trusted public key of this installation.
 if(![IO.File]::Exists($KeyPath)){return $false}
 $xml=[IO.File]::ReadAllText($KeyPath)
 if($xml -match '<(D|P|Q|DP|DQ|InverseQ)>'){Stop-AC7App 'UPDATE_KEY' '更新公钥文件含有私钥内容，已拒绝。' '请重新运行安装程序。'}
 $rsa=New-Object Security.Cryptography.RSACryptoServiceProvider;$rsa.PersistKeyInCsp=$false
 try{
  try{$rsa.FromXmlString($xml)}catch{return $false}
  if($rsa.KeySize -lt 3072){return $false}
  $bytes=$null;try{$bytes=[Convert]::FromBase64String($Signature.Trim())}catch{return $false}
  return $rsa.VerifyData($Data,'SHA256',$bytes)
 }finally{$rsa.Dispose()}
}
function Get-AC7AppUpdateOffer{
 # The signed update manifest of a release (the newest one, one tag, or a release object already read), verified with
 # the trusted key: signature, product, version equal to the tag, asset name, hash and size. Does not download the zip.
 param([string]$InstallRoot='',[string]$Feed='',[string]$Tag='',$Release=$null,[string]$KeyPath='',[string]$CacheRoot='')
 if(!$Release){$Release=if($Tag){Get-AC7AppReleaseByTag $Feed $Tag}else{@(Get-AC7AppReleaseList $Feed)[0]}}
 if(!$Release){Stop-AC7App 'UPDATE_NONE' 'GitHub 上还没有可用的发布。' '请稍后再试。'}
 $tagName=[string]$Release.tag_name
 if($tagName -notmatch '^v(.+)$' -or !(Test-AC7AppVersionName $Matches[1])){Stop-AC7App 'UPDATE_MANIFEST' ('发布标签 '+$tagName+' 无法识别。')}
 $version=$Matches[1]
 if(!$KeyPath){$KeyPath=[IO.Path]::Combine($InstallRoot,'trust','update-key.xml')}
 if(!$CacheRoot){$CacheRoot=[IO.Path]::Combine($InstallRoot,'data','update-cache')}
 $cache=[IO.Path]::Combine($CacheRoot,'incoming-'+[guid]::NewGuid().ToString('N').Substring(0,12));[void][IO.Directory]::CreateDirectory($cache)
 try{
  $manifestPath=[IO.Path]::Combine($cache,'update-manifest.json');$signaturePath=$manifestPath+'.sig'
  Save-AC7AppReleaseAsset $Release 'update-manifest.json' $manifestPath $Feed
  Save-AC7AppReleaseAsset $Release 'update-manifest.json.sig' $signaturePath $Feed
  $bytes=[IO.File]::ReadAllBytes($manifestPath)
  if(!(Test-AC7AppUpdateSignature $bytes ([IO.File]::ReadAllText($signaturePath)) $KeyPath)){
   Stop-AC7App 'UPDATE_SIGNATURE' '更新清单的签名无效，已拒绝。' '请稍后重试；如果持续出现，请到 GitHub 发布页手动下载安装程序。'
  }
  $manifest=$null;try{$manifest=(New-Object Text.UTF8Encoding($false)).GetString($bytes) | ConvertFrom-Json}catch{$manifest=$null}
  $asset='AC7-Integrated-v'+$version+'.zip'
  if(!$manifest -or $manifest.schema -ne 1 -or [string]$manifest.product -ne 'AC7-Integrated' -or [string]$manifest.version -ne $version -or [string]$manifest.asset -ne $asset -or [string]$manifest.sha256 -notmatch '^[0-9A-Fa-f]{64}$' -or [long]$manifest.size -le 0){
   Stop-AC7App 'UPDATE_MANIFEST' '更新清单与发布不一致，已拒绝。' '请到 GitHub 发布页手动下载安装程序。'
  }
 }catch{Remove-AC7AppTree $cache;throw}
 return [pscustomobject]@{Version=$version;Tag=$tagName;Manifest=$manifest;Release=$Release;Cache=$cache;NotesUrl=[string]$Release.html_url;Prerelease=[bool]$Release.prerelease}
}
function Save-AC7AppUpdatePackage($Offer,[string]$Feed=''){
 $target=[IO.Path]::Combine($Offer.Cache,[string]$Offer.Manifest.asset)
 Save-AC7AppReleaseAsset $Offer.Release ([string]$Offer.Manifest.asset) $target $Feed ([Math]::Min([long]$Offer.Manifest.size,[long]536870912))
 if((New-Object IO.FileInfo($target)).Length -ne [long]$Offer.Manifest.size -or (Get-AC7AppHash $target) -ne ([string]$Offer.Manifest.sha256).ToUpperInvariant()){
  Stop-AC7App 'UPDATE_HASH' '下载的安装包与签名清单不符，已拒绝。' '请重试；网络或代理可能改动了文件。'
 }
 return $target
}
function Get-AC7AppUpdateCheck([string]$PackageRoot,[string]$Feed=''){
 # The newest published release compared with this package's version. Reads only the release list.
 $current=Get-AC7AppPackageVersion $PackageRoot
 $latest=@(Get-AC7AppReleaseList $Feed)[0]
 $version='';if($latest -and [string]$latest.tag_name -match '^v(.+)$'){$version=$Matches[1]}
 $newer=[bool]($version -and (Test-AC7AppVersionName $current) -and (Compare-AC7AppVersion $version $current) -gt 0)
 return [pscustomobject]@{Current=$current;Latest=$version;Update=$newer;Release=$latest;NotesUrl=$(if($latest){[string]$latest.html_url}else{''});Prerelease=$(if($latest){[bool]$latest.prerelease}else{$false})}
}
function Complete-AC7AppInstall{
 # After versions\<version> is in place: player data, cached zip, app.json switch, host files, registration, pruning.
 param([string]$InstallRoot,[string]$Version,[string]$Source,[string]$ZipPath,[string]$ImportFrom='',[switch]$NoRegister,[string]$UninstallKey=(Get-AC7AppUninstallKey),[string]$Shortcut=(Get-AC7AppShortcutPath))
 $package=[IO.Path]::Combine($InstallRoot,'versions',$Version)
 $report=@(Initialize-AC7AppData $InstallRoot $package $ImportFrom)
 Save-AC7AppCache $InstallRoot $Version $ZipPath
 Set-AC7AppCurrent $InstallRoot $Version $Source
 $null=Install-AC7AppHostFiles $InstallRoot $package
 if(!$NoRegister){Register-AC7App $InstallRoot $Version $UninstallKey $Shortcut}
 Remove-AC7AppOldVersions $InstallRoot
 foreach($dir in @(Get-ChildItem -LiteralPath ([IO.Path]::Combine($InstallRoot,'data','update-cache')) -Directory -Filter 'incoming-*' -ErrorAction SilentlyContinue)){try{Remove-AC7AppTree $dir.FullName}catch{}}
 return $report
}
function Install-AC7AppUpdate{
 # Downloads the offered package, checks it against the signed manifest, installs it as a new version and switches to
 # it. Any failure leaves app.json on the old version. The game folder is updated afterwards (Invoke-AC7AppGameDeploy).
 param([string]$InstallRoot,$Offer,[string]$Feed='',[switch]$NoRegister,[string]$UninstallKey=(Get-AC7AppUninstallKey),[string]$Shortcut=(Get-AC7AppShortcutPath))
 $busy=Get-AC7AppBusyReason $InstallRoot;if($busy){Stop-AC7App 'APP_BUSY' $busy '退出游戏后重试。'}
 $state=Read-AC7AppState $InstallRoot
 if((Compare-AC7AppVersion $Offer.Version ([string]$state.current)) -le 0){Stop-AC7App 'UPDATE_NOT_NEWER' ('已是最新版本 '+$state.current+'。')}
 $downloaded=Save-AC7AppUpdatePackage $Offer $Feed
 $version=Install-AC7AppVersion $InstallRoot $downloaded $Offer.Version
 return @(Complete-AC7AppInstall -InstallRoot $InstallRoot -Version $version -Source 'update' -ZipPath $downloaded -NoRegister:$NoRegister -UninstallKey $UninstallKey -Shortcut $Shortcut)
}

# ---- launcher (portable and installed) ----
function Get-AC7AppSettings([string]$PackageRoot){
 # app-settings.json in the player data folder: auto_update_check (default on), last_check_utc.
 $values=[ordered]@{auto_update_check=$true;last_check_utc=''}
 $path=[IO.Path]::Combine((Get-AC7AppLayout $PackageRoot).DataRoot,'app-settings.json')
 if([IO.File]::Exists($path)){
  try{
   $saved=[IO.File]::ReadAllText($path) | ConvertFrom-Json
   if($null -ne $saved.auto_update_check){$values.auto_update_check=[bool]$saved.auto_update_check}
   if($saved.last_check_utc){$values.last_check_utc=[string]$saved.last_check_utc}
  }catch{}
 }
 return $values
}
function Set-AC7AppSettings([string]$PackageRoot,$Values){
 $data=(Get-AC7AppLayout $PackageRoot).DataRoot;[void][IO.Directory]::CreateDirectory($data)
 Write-AC7AppJson ([IO.Path]::Combine($data,'app-settings.json')) ([pscustomobject][ordered]@{auto_update_check=[bool]$Values.auto_update_check;last_check_utc=[string]$Values.last_check_utc})
}
function Test-AC7AppUpdateCheckDue([string]$PackageRoot){
 # The automatic check runs at most once every 20 hours and can be switched off in the launcher.
 $settings=Get-AC7AppSettings $PackageRoot
 if(!$settings.auto_update_check){return $false}
 if(!$settings.last_check_utc){return $true}
 try{$last=[DateTime]::Parse($settings.last_check_utc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)}catch{return $true}
 return ([DateTime]::UtcNow-$last.ToUniversalTime()).TotalHours -ge 20
}
function Invoke-AC7LauncherUpdateCheck([string]$PackageRoot,[bool]$Quiet=$false,[string]$Feed=''){
 # "检查更新" and the daily automatic check. Reads the GitHub release list (nothing is uploaded); a newer release is
 # offered only when its signed manifest verifies. Never throws: a failed manual check returns Success=$false, a failed
 # automatic check returns an empty quiet result. Installing goes through Host.ps1 -Action Update (installed app only).
 $layout=Get-AC7AppLayout $PackageRoot
 $result=[pscustomobject]@{Success=$true;Title='';Message='';GameRoot=$null;SteamPath=$null;ModState=$null;OpenFolder=$null;Update=$null;Current='';Installed=$layout.Installed;Quiet=$Quiet;NotesUrl=''}
 try{
  try{$settings=Get-AC7AppSettings $PackageRoot;$settings.last_check_utc=[DateTime]::UtcNow.ToString('o');Set-AC7AppSettings $PackageRoot $settings}catch{}
  $check=Get-AC7AppUpdateCheck $PackageRoot $Feed
  $result.Current=$check.Current;$result.NotesUrl=$check.NotesUrl
  if($check.Update){
   $key=if($layout.Installed){[IO.Path]::Combine($layout.InstallRoot,'trust','update-key.xml')}else{[IO.Path]::Combine($PackageRoot,'app','update-key.xml')}
   $offer=Get-AC7AppUpdateOffer -Feed $Feed -Release $check.Release -KeyPath $key -CacheRoot ([IO.Path]::GetTempPath())
   Remove-AC7AppTree $offer.Cache
   $label=if($offer.Prerelease){'（Beta 测试版）'}else{''}
   $result.Update=$offer.Version;$result.Title='发现新版本 '+$offer.Version+$label
   $result.Message=if($layout.Installed){'当前 '+$check.Current+'。确认后会关闭启动器，在控制台中下载、校验签名并安装；设置、键位和附加 Mod 都会保留，游戏中已安装的 Mod 会随之更新。'}else{'当前 '+$check.Current+'（便携版）。请到 GitHub 发布页下载新版本；安装版可以在启动器中一键更新。'}
   return $result
  }
  $result.Title='已是最新版本';$result.Message='当前 '+$check.Current+' 是 GitHub 上的最新版本。'
  return $result
 }catch{
  if($Quiet){$result.Title='';$result.Message='';return $result}
  $result.Success=$false;$result.Title='检查更新失败';$result.Message=$_.Exception.Message+' '+[string]$_.Exception.Data['AC7Hint']
  return $result
 }
}
function Start-AC7AppHostAction([string]$PackageRoot,[ValidateSet('Update','Repair','Rollback','Launch','Uninstall')][string]$Action){
 # Installed app only: runs Host.ps1 -Action <Action> in a visible console and returns the process. The launcher closes
 # itself for Update / Repair / Rollback (the host reopens it); for Launch it may stay open.
 $layout=Get-AC7AppLayout $PackageRoot
 if(!$layout.Installed){Stop-AC7App 'APP_PORTABLE' '便携版不能在启动器中更新或修复。' '请到 GitHub 发布页下载新版本；用安装程序安装后可以一键更新和修复。'}
 $hostScript=[IO.Path]::Combine($layout.InstallRoot,'Host.ps1')
 if(![IO.File]::Exists($hostScript)){Stop-AC7App 'APP_LAYOUT' '安装版的宿主文件缺失。' '请重新运行安装程序；设置不会丢失。'}
 return Start-Process -FilePath ([IO.Path]::Combine($PSHOME,'powershell.exe')) -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$hostScript+'"'),'-Action',$Action) -PassThru
}

# ---- game folder (through the version package's own install functions) ----
function Get-AC7AppGameInfo([string]$InstallRoot,[string]$PackageRoot,[string]$GameRoot=''){
 # Read-only: the saved (or given) game folder and the state of the mod installed there. OwnedByApp: the ownership
 # record names this installation. Blocked: owned DLLs / loader that are missing or changed (security software).
 . ([IO.Path]::Combine($PackageRoot,'Install-Core.ps1'))
 $result=[pscustomobject]@{GameRoot=$null;Exists=$false;Running=$false;Installed=$false;OwnedByApp=$false;Project=$null;ManifestVersion=$null;Features=$null;Mode='none';Pending=$false;PendingOwned=$false;Blocked=@();Changed=@();Missing=@();UnownedLoader=@();Error=$null;Text=''}
 $game=$GameRoot;if(!$game){$game=Get-AC7AppSavedText ([IO.Path]::Combine($InstallRoot,'data')) 'game-path.txt'}
 if(!$game){return $result}
 $result.GameRoot=$game
 try{$game=Resolve-AC7GameRoot $game}catch{$result.Error=$_.Exception.Message;return $result}
 $result.GameRoot=$game;$result.Exists=$true
 $result.Running=Test-AC7GameRunning $game
 try{$state=Get-AC7InstallState $game}catch{$result.Error=$_.Exception.Message+' '+[string]$_.Exception.Data['AC7Hint'];return $result}
 $result.Installed=[bool]$state.Installed;$result.Mode=[string]$state.Mode;$result.Features=$state.Features;$result.Project=$state.Project
 if($state.Manifest){$result.ManifestVersion=[string]$state.Manifest.Version}
 $result.OwnedByApp=[bool]($state.Installed -and (Test-AC7AppSamePath $state.Project $InstallRoot))
 if($state.Pending){$result.Pending=$true;$result.PendingOwned=(Test-AC7AppInside ([string]$state.Pending.PackageRoot) $InstallRoot)}
 $result.Blocked=@($state.Entries | Where-Object {$_.Status -ne 'ok' -and ($_.Loader -or $_.Relative -like '*.dll')} | ForEach-Object {if($_.Status -eq 'missing'){$_.Relative}else{$_.Actual}})
 $result.Changed=@($state.Changed);$result.Missing=@($state.Missing);$result.UnownedLoader=@($state.UnownedLoader)
 $result.Text=Format-AC7StateText $state
 return $result
}
function Invoke-AC7AppGameDeploy{
 # Brings the mod that this app installed in the game folder to the current version through the package's own
 # Invoke-AC7Install (save backup, journal, every file verified): after an update or rollback, before a launch, and with
 # -Repair for "检查并修复" (changed or deleted owned files are restored; changed ones are backed up first). -Adopt also
 # takes over an install made by another package (setup). A running game and a mod of another package are left alone.
 # Returns findings: Item, Status (ok / fixed / info / problem), Message.
 # Scope: -Repair restores the scope that is installed; otherwise data\features.ini (the launcher's selection) applies.
 # -SyncFeatures (repair, after features.ini had to be rebuilt) writes the installed scope back into features.ini.
 param([string]$InstallRoot,[switch]$Repair,[switch]$Adopt,[switch]$SyncFeatures,[string]$GameRoot='',[string]$SaveRoot='',[switch]$TestOnlySkipExeHash)
 $findings=New-Object Collections.ArrayList   # (List[object] of PSObjects cannot be unrolled by @() in Windows PowerShell 5.1)
 $item='游戏中的 Mod'
 $package=Get-AC7AppCurrentPackage $InstallRoot
 . ([IO.Path]::Combine($package,'Install-Core.ps1'))
 $data=[IO.Path]::Combine($InstallRoot,'data')
 $game=$GameRoot;if(!$game){$game=Get-AC7AppSavedText $data 'game-path.txt'}
 if(!$game){[void]$findings.Add([pscustomobject]@{Item=$item;Status='info';Message='尚未选择游戏位置。在启动器中自动定位或浏览选择游戏后，点击“安装／更新”。'});return @($findings)}
 try{$game=Resolve-AC7GameRoot $game}catch{[void]$findings.Add([pscustomobject]@{Item=$item;Status='problem';Message=('保存的游戏位置无效：'+$_.Exception.Message+' 请在启动器中重新定位游戏。')});return @($findings)}
 if(Test-AC7GameRunning $game){[void]$findings.Add([pscustomobject]@{Item=$item;Status='problem';Message='游戏正在运行，游戏目录中的 Mod 文件没有检查也没有更新。退出游戏后运行“检查并修复”。'});return @($findings)}
 try{$state=Get-AC7InstallState $game}catch{[void]$findings.Add([pscustomobject]@{Item=$item;Status='problem';Message=($_.Exception.Message+' '+[string]$_.Exception.Data['AC7Hint'])});return @($findings)}
 $current=Get-AC7AppPackageVersion $package
 if($state.Pending){[void]$findings.Add([pscustomobject]@{Item=$item;Status='problem';Message='上一次安装或更新没有完成。请在启动器中点击“卸载（备份并清理）”回滚未完成的操作，再重新安装。'});return @($findings)}
 if(!$state.Installed){
  if(@($state.UnownedLoader).Count){[void]$findings.Add([pscustomobject]@{Item=$item;Status='problem';Message=('游戏目录中有不属于本工具的加载器文件：'+(@($state.UnownedLoader) -join '、')+'。可能来自其他 Mod，未改动。')})}
  else{[void]$findings.Add([pscustomobject]@{Item=$item;Status='info';Message='游戏中没有安装本 Mod（原版）。需要时在启动器中选择安装内容后点击“安装／更新”。'})}
  return @($findings)
 }
 $owned=Test-AC7AppSamePath $state.Project $InstallRoot
 if(!$owned -and !$Adopt){[void]$findings.Add([pscustomobject]@{Item=$item;Status='info';Message=('游戏中的 Mod 由另一个整合包管理（'+$state.Project+'），未改动。需要交给安装版管理时，在启动器中点击“安装／更新”。')});return @($findings)}
 if($owned -and $SyncFeatures -and $state.Features){
  try{Save-AC7FeatureSettings $package $state.Features;[void]$findings.Add([pscustomobject]@{Item='安装内容';Status='fixed';Message=('features.ini 已按游戏中的安装恢复为：'+(Get-AC7FeatureLabel $state.Features)+'。')})}catch{}
 }
 $bad=@($state.Entries | Where-Object Status -ne 'ok')
 if($owned -and !$bad.Count -and [string]$state.Manifest.Version -eq $current -and !@($state.UnownedLoader).Count){
  [void]$findings.Add([pscustomobject]@{Item=$item;Status='ok';Message=('游戏目录中的 Mod 文件完整（AC7 '+$current+'，'+(Get-AC7FeatureLabel $state.Features)+'）。')})
  return @($findings)
 }
 $features=$null
 if($Repair){$features=$state.Features}
 else{try{$features=(Read-AC7FeatureSettings ([IO.Path]::Combine($data,'features.ini'))).Features}catch{$features=$null}}
 if(!$features){$features=$state.Features}
 $controlBefore=$null;if($Adopt){try{$controlBefore=(Read-AC7MouseSettings ([IO.Path]::Combine($data,'MouseAim-Settings.ini'))).control_mode}catch{}}
 try{
  $summary=Invoke-AC7Install -PackageRoot $package -GameRoot $game -Features $features -SaveRoot $SaveRoot -Repair:([bool]($Repair -and $bad.Count)) -TestOnlySkipExeHash:$TestOnlySkipExeHash
 }catch{
  [void]$findings.Add([pscustomobject]@{Item=$item;Status='problem';Message=('游戏中的 Mod 未能更新：'+$_.Exception.Message+' '+[string]$_.Exception.Data['AC7Hint'])})
  return @($findings)
 }
 $text=Format-AC7InstallSummary $summary
 if(@($summary.Repaired).Count){$text='已恢复缺失或被改动的文件：'+(@($summary.Repaired) -join '、')+'（被改动的文件已先备份）。'+$text}
 [void]$findings.Add([pscustomobject]@{Item=$item;Status='fixed';Message=$text})
 if($Adopt -and $controlBefore -eq 3){
  # Taking over imports the values of the installed config.ini, which predate the war-default-0.7.0 migration that
  # setup has just applied: keep WAR as the startup flight control (F4 still switches to PEACE).
  try{
   $values=Read-AC7MouseSettings ([IO.Path]::Combine($data,'MouseAim-Settings.ini'))
   if($values.control_mode -eq 0){$values.control_mode=3;Save-AC7MouseSettings $package $values;$null=Sync-AC7GameConfig $package $game}
  }catch{[void]$findings.Add([pscustomobject]@{Item='飞控设置';Status='problem';Message=('启动时的飞控未能设为 WAR：'+$_.Exception.Message)})}
 }
 return @($findings)
}
function Start-AC7AppGame([string]$PackageRoot,[string]$GameRoot,[string]$SteamPath,[switch]$WhatIf){
 . ([IO.Path]::Combine($PackageRoot,'Install-Core.ps1'))
 return Start-AC7ViaSteam $PackageRoot $GameRoot $SteamPath -WhatIf:$WhatIf
}

# ---- launch diagnostics (the game's ue4ss\UE4SS.log) ----
function Get-AC7AppExpectedBanner([string]$GameRoot,[string]$Fallback){
 # The version the installed flight-control script prints when it has loaded ("[AC7FullControl] AC7 <version> ...").
 $file=[IO.Path]::Combine($GameRoot,'ue4ss','Mods','AC7MouseAim','Scripts','full.lua')
 if([IO.File]::Exists($file)){
  try{$match=[regex]::Match([IO.File]::ReadAllText($file),"log\('AC7 ([^\s']+)");if($match.Success){return $match.Groups[1].Value}}catch{}
 }
 return $Fallback
}
function Read-AC7AppSharedText([string]$Path){
 # The game keeps UE4SS.log open for writing.
 $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
 try{$reader=New-Object IO.StreamReader($stream,(New-Object Text.UTF8Encoding($false)),$true);return $reader.ReadToEnd()}finally{$stream.Dispose()}
}
function Get-AC7AppReadiness([string]$LogPath,[DateTime]$SinceUtc,[string]$Version){
 # One look at UE4SS.log: State ready / failed / waiting / nolog (no log written since $SinceUtc), Reason in Chinese.
 if(![IO.File]::Exists($LogPath) -or [IO.File]::GetLastWriteTimeUtc($LogPath) -lt $SinceUtc){return [pscustomobject]@{State='nolog';Reason='游戏目录中还没有新的 ue4ss\UE4SS.log。';Line=''}}
 $text=$null;try{$text=Read-AC7AppSharedText $LogPath}catch{return [pscustomobject]@{State='waiting';Reason='UE4SS.log 暂时无法读取。';Line=''}}
 $lines=@($text -split "`r?`n")
 if(@($lines | Where-Object {$_ -match ('\[AC7FullControl\] AC7 '+[regex]::Escape($Version)+'(\s|$)')}).Count){return [pscustomobject]@{State='ready';Reason='';Line=''}}
 $short={param($s) $t=([string]$s).Trim();if($t.Length -gt 220){$t=$t.Substring(0,220)+'…'};$t}
 $refused=@($lines | Where-Object {$_ -match '(?i)refused' -and $_ -match 'AC7'})   # other mods' lines are not ours to judge
 if($refused.Count){$line=& $short $refused[0];return [pscustomobject]@{State='failed';Reason=('飞控核心拒绝启动（UE4SS 运行库或游戏版本校验未通过）：'+$line);Line=$line}}
 $failed=@($lines | Where-Object {$_ -match '\[AC7FullControl\] ERROR'})
 if($failed.Count){$line=& $short $failed[0];return [pscustomobject]@{State='failed';Reason=('飞控模块报错：'+$line);Line=$line}}
 $scriptErrors=@($lines | Where-Object {$_ -match 'AC7MouseAim' -and $_ -match '(?i)\berror\b'})
 if($scriptErrors.Count){$line=& $short $scriptErrors[0];return [pscustomobject]@{State='failed';Reason=('鼠标飞控脚本加载出错：'+$line);Line=$line}}
 $other=@($lines | Where-Object {$_ -match '\[AC7FullControl\] AC7 (\S+)'})
 if($other.Count){$found=[regex]::Match($other[0],'\[AC7FullControl\] AC7 (\S+)').Groups[1].Value;return [pscustomobject]@{State='failed';Reason=('游戏加载的飞控是 AC7 '+$found+'，与安装的 '+$Version+' 不同。请运行“检查并修复”。');Line=(& $short $other[0])}}
 if(!@($lines | Where-Object {$_ -match 'AC7MouseAim|\[AC7FullControl\]'}).Count){return [pscustomobject]@{State='waiting';Reason='UE4SS 已启动，但鼠标飞控模块（AC7MouseAim）还没有加载。请检查 ue4ss\Mods\mods.txt 和其他附加 Mod。';Line=''}}
 return [pscustomobject]@{State='waiting';Reason='鼠标飞控模块已开始加载，但还没有就绪。';Line=''}
}
function Wait-AC7AppReady([string]$LogPath,[DateTime]$SinceUtc,[string]$Version,[int]$TimeoutSeconds=120,[int]$PollMilliseconds=1000){
 # Polls UE4SS.log until the mod is ready or has failed, or the time is up. Returns the last readiness with a final reason.
 $deadline=[DateTime]::UtcNow.AddSeconds([Math]::Max(0,$TimeoutSeconds))
 while($true){
  $state=Get-AC7AppReadiness $LogPath $SinceUtc $Version
  if($state.State -eq 'ready' -or $state.State -eq 'failed'){return $state}
  if([DateTime]::UtcNow -ge $deadline){break}
  Start-Sleep -Milliseconds $PollMilliseconds
 }
 if($state.State -eq 'nolog'){$state.Reason='UE4SS 没有启动：'+$TimeoutSeconds+' 秒内游戏目录中没有新的 ue4ss\UE4SS.log。可能是游戏没有启动或仍在更新、Mod 已停用，或加载器 dwmapi.dll 被安全软件拦截（请查看 Windows 安全中心的保护历史，不要关闭安全软件）。'}
 else{$state.Reason=$TimeoutSeconds.ToString()+' 秒内没有就绪：'+$state.Reason}
 return $state
}

# ---- repair, rollback, uninstall, status ----
function Invoke-AC7AppRepair{
 # Findings: Item, Status (ok / fixed / info / problem), Message. -Quick (before every start): app.json, version files and
 # host files only, repaired from the cached verified zip. The full check adds a download of the same version when
 # needed, the player settings, the mod in the game folder (Invoke-AC7Install -Repair) and the registration.
 param([string]$InstallRoot,[string]$Feed='',[switch]$Offline,[switch]$Quick,[switch]$NoRegister,[string]$UninstallKey=(Get-AC7AppUninstallKey),[string]$Shortcut=(Get-AC7AppShortcutPath),[string]$SaveRoot='',[switch]$TestOnlySkipExeHash)
 $findings=New-Object Collections.ArrayList
 $state=$null;try{$state=Read-AC7AppState $InstallRoot}catch{$state=$null}
 $installed=@(Get-AC7AppInstalledVersions $InstallRoot)
 if(!$state -or $installed -notcontains [string]$state.current){
  if(!$installed.Count){[void]$findings.Add([pscustomobject]@{Item='版本';Status='problem';Message='没有找到已安装的版本，请重新运行安装程序（设置不会丢失）。'});return @($findings)}
  $previous=if($installed.Count -gt 1){$installed[1]}else{$null}
  Write-AC7AppJson ([IO.Path]::Combine($InstallRoot,'app.json')) ([pscustomobject]@{schema=1;current=$installed[0];previous=$previous;versions=@()})
  [void]$findings.Add([pscustomobject]@{Item='版本记录';Status='fixed';Message=('app.json 缺失或损坏，已按已安装的版本重建，当前版本 '+$installed[0]+'。')})
  $state=Read-AC7AppState $InstallRoot
 }
 $current=[string]$state.current;$package=[IO.Path]::Combine($InstallRoot,'versions',$current)
 $problems=@(Get-AC7AppPackageProblems $package)
 if($problems.Count){
  $restored=$false;$why=''
  $cached=Get-AC7AppCache $InstallRoot $current
  if($cached){try{$null=Install-AC7AppVersion $InstallRoot $cached $current;$restored=$true}catch{$why=$_.Exception.Message}}
  if(!$restored -and !$Offline -and !$Quick){
   try{
    $offer=Get-AC7AppUpdateOffer -InstallRoot $InstallRoot -Feed $Feed -Tag ('v'+$current)
    if($offer.Version -ne $current){Stop-AC7App 'UPDATE_MANIFEST' '发布版本与当前版本不一致。'}
    $downloaded=Save-AC7AppUpdatePackage $offer $Feed
    $null=Install-AC7AppVersion $InstallRoot $downloaded $current;Save-AC7AppCache $InstallRoot $current $downloaded;$restored=$true
    try{Remove-AC7AppTree $offer.Cache}catch{}
   }catch{$why=$_.Exception.Message}
  }
  $sample=$problems[0]+$(if($problems.Count -gt 1){' 等 '+$problems.Count+' 个文件'}else{''})
  if($restored){[void]$findings.Add([pscustomobject]@{Item='程序文件';Status='fixed';Message=('版本 '+$current+' 的 '+$sample+' 缺失或被改动，已从校验过的安装包恢复。')})}
  else{[void]$findings.Add([pscustomobject]@{Item='程序文件';Status='problem';Message=('版本 '+$current+' 的 '+$sample+' 缺失或被改动，无法自动恢复'+$(if($why){'：'+$why}else{'（需要联网下载同一版本）'})+'。')})}
 }else{[void]$findings.Add([pscustomobject]@{Item='程序文件';Status='ok';Message=('版本 '+$current+' 的程序文件完整。')})}
 # Host files follow the newest installed version that is intact.
 $hostSource=$null
 foreach($version in $installed){$candidate=[IO.Path]::Combine($InstallRoot,'versions',$version);if(!@(Get-AC7AppPackageProblems $candidate).Count){$hostSource=$candidate;break}}
 if($hostSource){
  $changed=@(Install-AC7AppHostFiles $InstallRoot $hostSource)
  if($changed.Count){[void]$findings.Add([pscustomobject]@{Item='启动入口';Status='fixed';Message=('已恢复 '+($changed -join '、')+'。')})}
 }
 if($Quick){return @($findings)}
 $data=[IO.Path]::Combine($InstallRoot,'data');[void][IO.Directory]::CreateDirectory($data)
 if(!@($findings | Where-Object {$_.Item -eq '程序文件' -and $_.Status -eq 'problem'}).Count){
  $settings=@(Repair-AC7AppPlayerSettings $data $package)
  foreach($finding in $settings){[void]$findings.Add($finding)}
  $rebuilt=[bool]@($settings | Where-Object {$_.Item -eq '安装内容' -and $_.Status -eq 'fixed'}).Count
  foreach($finding in @(Invoke-AC7AppGameDeploy -InstallRoot $InstallRoot -Repair -SyncFeatures:$rebuilt -SaveRoot $SaveRoot -TestOnlySkipExeHash:$TestOnlySkipExeHash)){[void]$findings.Add($finding)}
 }
 if(!$NoRegister -and !(Test-AC7AppRegistered $InstallRoot $UninstallKey $Shortcut)){
  Register-AC7App $InstallRoot $current $UninstallKey $Shortcut
  [void]$findings.Add([pscustomobject]@{Item='开始菜单与卸载项';Status='fixed';Message='已恢复开始菜单快捷方式和 Windows“应用”中的卸载项。'})
 }
 try{Remove-AC7AppOldVersions $InstallRoot}catch{}
 return @($findings)
}
function Invoke-AC7AppRollback{
 # Switch back to the previous version (its files restored from the cache first when damaged). Settings written by the
 # newer version are made readable for the older one (backup first). The game folder is redeployed by the caller.
 param([string]$InstallRoot,[switch]$NoRegister,[string]$UninstallKey=(Get-AC7AppUninstallKey),[string]$Shortcut=(Get-AC7AppShortcutPath))
 $busy=Get-AC7AppBusyReason $InstallRoot;if($busy){Stop-AC7App 'APP_BUSY' $busy '退出游戏后重试。'}
 $state=Read-AC7AppState $InstallRoot
 $previous=[string]$state.previous
 if(!$previous -or ![IO.File]::Exists([IO.Path]::Combine($InstallRoot,'versions',$previous,'app-version.json'))){Stop-AC7App 'NO_PREVIOUS' '没有可以回退的上一版本。'}
 $package=[IO.Path]::Combine($InstallRoot,'versions',$previous)
 if(@(Get-AC7AppPackageProblems $package).Count){
  $cached=Get-AC7AppCache $InstallRoot $previous
  if(!$cached){Stop-AC7App 'PREVIOUS_DAMAGED' ('上一版本 '+$previous+' 的文件不完整，无法回退。') '请运行“检查并修复”。'}
  $null=Install-AC7AppVersion $InstallRoot $cached $previous
 }
 $report=@(Repair-AC7AppPlayerSettings ([IO.Path]::Combine($InstallRoot,'data')) $package | Where-Object {$_.Status -ne 'ok'})
 Write-AC7AppJson ([IO.Path]::Combine($InstallRoot,'app.json')) ([pscustomobject]@{schema=1;current=$previous;previous=[string]$state.current;versions=@($state.versions)})
 if(!$NoRegister -and (Test-AC7AppRegistered $InstallRoot $UninstallKey $Shortcut)){Set-ItemProperty -LiteralPath $UninstallKey -Name DisplayVersion -Value $previous}
 return $report
}
function Invoke-AC7AppUninstall{
 # The mod this app installed in the game folder is removed first with the package's own cleanup (verified backup in
 # data\cleanup-backups; changed files are kept). Then only the app's own entries are removed; data is kept by default;
 # the install folder itself only when empty. Returns report lines.
 param([string]$InstallRoot,[bool]$KeepData=$true,[switch]$NoRegister,[string]$UninstallKey=(Get-AC7AppUninstallKey),[string]$Shortcut=(Get-AC7AppShortcutPath))
 if(![IO.File]::Exists([IO.Path]::Combine($InstallRoot,'app.json')) -or ![IO.Directory]::Exists([IO.Path]::Combine($InstallRoot,'versions'))){Stop-AC7App 'APP_LAYOUT' ('这里不是 AC7 Integrated 的安装目录：'+$InstallRoot)}
 $busy=Get-AC7AppBusyReason $InstallRoot;if($busy){Stop-AC7App 'APP_BUSY' $busy '退出游戏后重试。'}
 $data=[IO.Path]::Combine($InstallRoot,'data');$report=@()
 $package=$null;try{$package=Get-AC7AppCurrentPackage $InstallRoot;if(@(Get-AC7AppPackageProblems $package).Count){$package=$null}}catch{$package=$null}
 $game=Get-AC7AppSavedText $data 'game-path.txt'
 if($game -and [IO.Directory]::Exists($game)){
  $owner=Get-AC7AppGameOwner $game
  $pending=[IO.File]::Exists([IO.Path]::Combine($game,'ue4ss','AC7-MouseAim-pending.json'))
  $ours=($owner -and (Test-AC7AppSamePath $owner.Project $InstallRoot))
  if(!$ours -and $pending){try{$journal=[IO.File]::ReadAllText([IO.Path]::Combine($game,'ue4ss','AC7-MouseAim-pending.json')) | ConvertFrom-Json;$ours=Test-AC7AppInside ([string]$journal.PackageRoot) $InstallRoot}catch{}}
  if($ours){
   if(!$package){Stop-AC7App 'CLEANUP_REQUIRED' '游戏目录中有本程序安装的 Mod，但当前版本的程序文件不完整，无法清理。' '请先运行“检查并修复”，再卸载。'}
   . ([IO.Path]::Combine($package,'Cleanup-Core.ps1'))
   $cleanup=Invoke-AC7Cleanup -PackageRoot $package -GameRoot $game -Confirmed
   $report+=('游戏目录：'+$cleanup.Message)
  }elseif($owner){$report+=('游戏中的 Mod 由另一个整合包管理（'+$owner.Project+'），未改动。')}
 }
 if(!$NoRegister){Unregister-AC7App $UninstallKey $Shortcut}
 foreach($name in 'versions','trust'){Remove-AC7AppTree ([IO.Path]::Combine($InstallRoot,$name))}
 foreach($pair in (Get-AC7AppHostFiles)){if($pair[1] -notlike 'trust\*'){Remove-AC7AppTree ([IO.Path]::Combine($InstallRoot,$pair[1]))}}
 foreach($name in (Get-AC7AppLauncherName),'app.json'){Remove-AC7AppTree ([IO.Path]::Combine($InstallRoot,$name))}
 if(!$KeepData){Remove-AC7AppTree $data}
 if([IO.Directory]::Exists($InstallRoot) -and !@([IO.Directory]::GetFileSystemEntries($InstallRoot)).Count){[IO.Directory]::Delete($InstallRoot,$false)}
 return $report
}
function Get-AC7AppStatus([string]$InstallRoot){
 $state=Read-AC7AppState $InstallRoot
 $game=$null
 try{$game=Get-AC7AppGameInfo $InstallRoot (Get-AC7AppCurrentPackage $InstallRoot)}catch{$game=$null}
 return [pscustomobject]@{installRoot=$InstallRoot;dataRoot=[IO.Path]::Combine($InstallRoot,'data');current=[string]$state.current;previous=[string]$state.previous;installed=@(Get-AC7AppInstalledVersions $InstallRoot)
  game=$(if($game){[pscustomobject]@{path=$game.GameRoot;installed=$game.Installed;ownedByApp=$game.OwnedByApp;version=$game.ManifestVersion;features=$game.Features;mode=$game.Mode;pending=$game.Pending;error=$game.Error}}else{$null})}
}
