. ([IO.Path]::Combine($PSScriptRoot,'PowerShell-Compat.ps1'))
# Shared helpers: user-facing problems, path resolution, process and build checks.
function Stop-AC7Problem([string]$Code,[string]$Message,[string]$Hint) {
 $errorObject=New-Object InvalidOperationException($Message)
 $errorObject.Data['AC7Code']=$Code;$errorObject.Data['AC7Hint']=$Hint
 throw $errorObject
}
function Get-AC7PackageInfo([string]$PackageRoot) {
 $path=Join-Path $PackageRoot 'package-info.json'
 if(!(Test-Path -LiteralPath $path -PathType Leaf)){Stop-AC7Problem 'PACKAGE' '整合包不完整：缺少 package-info.json。' '请重新解压完整的整合包，不要只复制部分文件。'}
 return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}
function Resolve-AC7GameRoot([string]$InputPath) {
 $value=([string]$InputPath).Trim().Trim('"')
 if(!$value){Stop-AC7Problem 'GAME_PATH' '尚未输入游戏路径。' '可粘贴游戏根目录或 Ace7Game.exe 的完整路径。'}
 try{$path=[IO.Path]::GetFullPath($value)}catch{Stop-AC7Problem 'GAME_PATH' '路径格式无效。' '请从资源管理器复制完整路径，不要输入 Steam 网页地址。'}
 if(Test-Path -LiteralPath $path -PathType Leaf){
  if([IO.Path]::GetFileName($path) -ine 'Ace7Game.exe'){Stop-AC7Problem 'GAME_PATH' '选择的文件不是 Ace7Game.exe。' '请重新选择游戏根目录或 Ace7Game.exe。'}
  $path=Split-Path $path -Parent
 }
 # Accept a subfolder of the game (for example ue4ss or Game\Binaries\Win64) and walk up to the root.
 for($level=0;$level -le 4;$level++){
  if(Test-Path -LiteralPath (Join-Path $path 'Ace7Game.exe') -PathType Leaf){return $path.TrimEnd('\','/')}
  $parent=Split-Path $path -Parent
  if(!$parent -or $parent -eq $path){break};$path=$parent
 }
 Stop-AC7Problem 'GAME_PATH' '未在所选位置找到 AC7 游戏（Ace7Game.exe）。' 'Steam → ACE COMBAT 7 → 管理 → 浏览本地文件，复制打开的文件夹路径。'
}
function Assert-AC7PackageLocation([string]$PackageRoot,[string]$GameRoot) {
 $package=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\','/')
 $game=[IO.Path]::GetFullPath($GameRoot).TrimEnd('\','/')
 if($package.Equals($game,[StringComparison]::OrdinalIgnoreCase) -or $package.StartsWith($game+'\',[StringComparison]::OrdinalIgnoreCase)){
  Stop-AC7Problem 'PACKAGE_LOCATION' '整合包放在了游戏目录内部。' "请关闭此窗口，将整个整合包文件夹移到游戏目录之外（例如 D:\Mods\AC7-Integrated），再运行 Start-GUI.cmd。当前整合包：$package"
 }
}
function Assert-AC7NoLinks([string]$Path,[switch]$Tree) {
 $item=Get-Item -LiteralPath $Path -Force
 while($item){
  if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){Stop-AC7Problem 'FILESYSTEM_LINK' "拒绝处理文件系统链接：$($item.FullName)" '游戏目录或 ue4ss 中存在符号链接／目录联接。为避免写到别处，未修改任何文件；请改用普通文件夹。'}
  if($item -is [IO.FileInfo]){$item=$item.Directory}else{$item=$item.Parent}
 }
 if($Tree -and (Test-Path -LiteralPath $Path -PathType Container)){
  # Enumerate one level at a time: never recurse through a filesystem link.
  foreach($child in Get-ChildItem -LiteralPath $Path -Force){Assert-AC7NoLinks $child.FullName -Tree}
 }
}
function Assert-AC7WriteAccess([string]$Directory) {
 $probe=Join-Path $Directory ('.ac7-write-test-'+[guid]::NewGuid().ToString('N')+'.tmp')
 try{
  $stream=[IO.File]::Open($probe,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  $stream.Dispose()
 }catch{Stop-AC7Problem 'WRITE_ACCESS' "无法写入目录：$Directory" '请检查此目录的写入权限及 Windows 安全中心／安全软件的保护历史。不要关闭安全软件；修正具体权限或误拦截后重试。'}
 finally{if(Test-Path -LiteralPath $probe){Remove-Item -LiteralPath $probe -Force}}
}
# Running check scoped to one game folder: an AC7 started from another library does not block this one.
# A process whose image path cannot be read is treated as running from this folder (conservative).
function Test-AC7GameRunning([string]$GameRoot) {
 $processes=@(Get-Process -Name Ace7Game -ErrorAction SilentlyContinue)
 if(!$processes.Count){return $false}
 if(!$GameRoot){return $true}
 $game=[IO.Path]::GetFullPath($GameRoot).TrimEnd('\','/')
 foreach($process in $processes){
  $image=$null;try{$image=[string]$process.Path}catch{$image=$null}
  if(!$image){return $true}
  try{$folder=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($image)).TrimEnd('\','/')}catch{return $true}
  if($folder.Equals($game,[StringComparison]::OrdinalIgnoreCase)){return $true}
 }
 return $false
}
function Assert-AC7GameClosed([string]$GameRoot) {
 if(Test-AC7GameRunning $GameRoot){Stop-AC7Problem 'GAME_RUNNING' '游戏正在运行。' '请正常退出 AC7 后再安装、切换、清理或保存设置。'}
}
# The test-only exe-hash bypass is accepted only for fake game folders under %TEMP% or a tests\tmp folder.
function Assert-AC7TestOnlyFolder([string]$GameRoot) {
 $game=[IO.Path]::GetFullPath($GameRoot).TrimEnd('\','/')+'\'
 $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+'\'
 if(!$game.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and $game.IndexOf('\tests\tmp\',[StringComparison]::OrdinalIgnoreCase) -lt 0){
  throw 'TestOnlySkipExeHash is restricted to fake game folders under %TEMP% or a tests\tmp folder.'
 }
}
function Assert-AC7GameBuild([string]$PackageRoot,[string]$GameRoot,[switch]$TestOnlySkipExeHash) {
 $info=Get-AC7PackageInfo $PackageRoot
 $exe=Join-Path $GameRoot 'Ace7Game.exe'
 if($TestOnlySkipExeHash){
  Assert-AC7TestOnlyFolder $GameRoot
  Write-Warning 'TEST ONLY: Ace7Game.exe hash check skipped for a fake game folder.'
  return
 }
 if((Get-AC7FileHash -LiteralPath $exe).Hash -ne ([string]$info.game_sha256).ToUpperInvariant()){
  Stop-AC7Problem 'GAME_BUILD' '游戏版本与本包适配版本不一致。' ('本包只适配 Steam Build '+$info.game_build+'。游戏更新后需等待新版整合包；不要替换游戏 EXE 绕过校验。')
 }
}
function Get-AC7SaveRoot {return (Join-Path $env:LOCALAPPDATA 'BANDAI NAMCO Entertainment\ACE COMBAT 7')}
function Get-AC7SavedText([string]$Root,[string]$Name) {
 $path=Join-Path $Root $Name
 if(Test-Path -LiteralPath $path -PathType Leaf){$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8;if($null -ne $text){return $text.Trim()}}
 return ''
}
function Get-AC7SavedGameRoot([string]$Root) {
 $saved=Get-AC7SavedText $Root 'game-path.txt'
 if(!$saved){Stop-AC7Problem 'SETUP_REQUIRED' '尚未设置游戏路径。' '请先运行 Start-GUI.cmd 或 Setup.cmd 完成安装。'}
 return (Resolve-AC7GameRoot $saved)
}
function Read-AC7Json([string]$Path) {
 try{return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)}
 catch{Stop-AC7Problem 'MANIFEST_INVALID' "无法读取记录文件：$Path" '文件可能被手动修改或损坏。未修改任何文件；请保留此文件以便核对。'}
}
# UTF-8 with BOM, written to a temporary file first and then moved over the destination.
function Write-AC7Json($Value,[string]$Path) {
 $json=$Value | ConvertTo-Json -Depth 8
 $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 try{
  [IO.File]::WriteAllText($temporary,$json,[Text.UTF8Encoding]::new($true))
  Move-Item -LiteralPath $temporary -Destination $Path -Force
 }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
}
function Write-AC7TextAtomic([string]$Path,[string]$Text,[switch]$Bom) {
 $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 try{
  [IO.File]::WriteAllText($temporary,$Text,[Text.UTF8Encoding]::new([bool]$Bom))
  if(Test-Path -LiteralPath $Path){Copy-Item -LiteralPath $Path -Destination ($Path+'.bak') -Force}
  Move-Item -LiteralPath $temporary -Destination $Path -Force
 }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
}
function Show-AC7Problem($Failure,[string]$PackageRoot,[string]$Stage='操作') {
 if($Failure.Exception.Data['AC7Shown']){return}
 $Failure.Exception.Data['AC7Shown']=$true
 $hint=[string]$Failure.Exception.Data['AC7Hint']
 $message=$Failure.Exception.Message
 if(!$hint){
  if($Failure.CategoryInfo.Category -eq 'PermissionDenied' -or $Failure.Exception -is [UnauthorizedAccessException]){
   $hint='请检查报错文件的只读属性、目录权限及安全软件保护历史。通用写入检查通过，也不能保证 DLL 不被单独拦截。'
  }elseif($message -match 'TestOnly'){
   $hint='这是仅供自动测试使用的参数，不能用于真实游戏目录。'
  }else{$hint='请保留下面的诊断文件，并按错误信息检查路径和文件。'}
 }
 Write-Host "[$Stage 未完成] $message" -ForegroundColor Red
 Write-Host $hint -ForegroundColor Yellow
 try{
  $folder=Join-Path $PackageRoot 'diagnostics';New-Item -ItemType Directory -Path $folder -Force | Out-Null
  $log=Join-Path $folder ((Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N')+'.txt')
  @("Stage: $Stage",$Failure.ToString(),$Failure.ScriptStackTrace) | Set-Content -LiteralPath $log -Encoding UTF8
  Write-Host "诊断文件：$log"
 }catch{Write-Host '诊断文件无法保存，请保留当前窗口截图。'}
}
