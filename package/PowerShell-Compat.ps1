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
