# Resolve built-in modules from the running host, even with an empty inherited
# PSModulePath or disabled module auto-loading (including GUI runspaces).
foreach($ac7Module in @('Microsoft.PowerShell.Management','Microsoft.PowerShell.Utility')){
 $ac7ModulePath=[IO.Path]::Combine($PSHOME,'Modules',$ac7Module,($ac7Module+'.psd1'))
 Import-Module -Name $ac7ModulePath -ErrorAction Stop
}
# One install/update/cleanup at a time per game folder (GUI, console and tests alike).
function Enter-AC7Operation([string]$GameRoot){
 $canonical=[IO.Path]::GetFullPath($GameRoot).TrimEnd('\','/').ToUpperInvariant()
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$key=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical))).Replace('-','')}finally{$sha.Dispose()}
 $mutex=New-Object Threading.Mutex($false,('Local\AC7IntegratedSession-'+$key))
 $owned=$false
 try{
  try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
  if(!$owned){
   $failure=New-Object InvalidOperationException('另一个 AC7 安装、切换或清理操作正在进行。')
   $failure.Data['AC7Code']='SESSION_BUSY';$failure.Data['AC7Hint']='请等待其他窗口中的操作完成后再试。'
   throw $failure
  }
  return $mutex
 }catch{$mutex.Dispose();throw}
}
function Exit-AC7Operation($Mutex){if($Mutex){try{$Mutex.ReleaseMutex()}finally{$Mutex.Dispose()}}}
# Idempotent when imported through several helper files.
if(!(Test-Path Function:\Get-AC7FileHash)){
 function Get-AC7FileHash {
  param([Parameter(Mandatory=$true)][string]$LiteralPath,[ValidateSet('SHA256')][string]$Algorithm='SHA256')
  $path=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LiteralPath)
  $stream=$null;$sha=$null
  try{
   $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
   $sha=[Security.Cryptography.SHA256]::Create()
   $digest=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')
   return [pscustomobject]@{Algorithm='SHA256';Hash=$digest;Path=$path}
  }finally{if($sha){$sha.Dispose()};if($stream){$stream.Dispose()}}
 }
}
function Get-AC7BytesHash([byte[]]$Bytes){
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','')}finally{$sha.Dispose()}
}
# Installed app (0.7.0, as AC8 2.5.0): <install>\versions\<version>\ is a complete package marked by app-version.json;
# player data (settings, key bindings, scope, paths, backups, diagnostics, sessions) is shared in <install>\data.
# Without the marker the package is portable and keeps its data in its own folder (behaviour of 0.6.x).
function Get-AC7AppInfo([string]$PackageRoot){
 $package=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\','/')
 $marker=[IO.Path]::Combine($package,'app-version.json')
 if(![IO.File]::Exists($marker)){return $null}
 $versions=[IO.Path]::GetDirectoryName($package);$install=$null;$version=$null
 if($versions){$install=[IO.Path]::GetDirectoryName($versions)}
 try{$version=[string]([IO.File]::ReadAllText($marker) | ConvertFrom-Json).version}catch{$version=$null}
 $data=if($install){[IO.Path]::Combine($install,'data')}else{$null}
 if(!$install -or !$version -or [IO.Path]::GetFileName($versions) -ne 'versions' -or [IO.Path]::GetFileName($package) -ne $version -or ![IO.Directory]::Exists($data)){
  $failure=New-Object InvalidOperationException("安装版目录结构不完整：$package")
  $failure.Data['AC7Code']='APP_LAYOUT';$failure.Data['AC7Hint']='请在开始菜单打开 AC7 Integrated，使用“检查并修复”；仍不能解决时重新运行安装程序（设置不会丢失）。'
  throw $failure
 }
 return [pscustomobject]@{Version=$version;PackageRoot=$package;InstallRoot=$install;DataRoot=$data}
}
# Folder for player data. Idempotent: the data folder itself (no marker) maps to itself.
function Get-AC7DataRoot([string]$PackageRoot){
 $app=Get-AC7AppInfo $PackageRoot
 if($app){return $app.DataRoot}
 return [IO.Path]::GetFullPath($PackageRoot).TrimEnd('\','/')
}
function Get-AC7DataFile([string]$PackageRoot,[string]$Name){return [IO.Path]::Combine((Get-AC7DataRoot $PackageRoot),$Name)}
# Owner identity recorded in the game folder: the install root for the app (stable across versions), else the package.
function Get-AC7ProjectRoot([string]$PackageRoot){
 $app=Get-AC7AppInfo $PackageRoot
 if($app){return $app.InstallRoot}
 return [IO.Path]::GetFullPath($PackageRoot).TrimEnd('\','/')
}
