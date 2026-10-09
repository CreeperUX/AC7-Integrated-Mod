param([string]$Action,[string]$Root,[string]$GamePath,[string]$SteamPath,[ValidateSet('mouse','guidance','full','weapons')][string]$Features='full',[bool]$Confirmed=$false)
$ErrorActionPreference='Stop'
try{
 . (Join-Path $PSScriptRoot 'Gui-Core.ps1')
 Invoke-AC7GuiAction -Action $Action -Root $Root -GamePath $GamePath -SteamPath $SteamPath -Features $Features -Confirmed $Confirmed}
catch{
 $failure=$_
 if(Get-Command Show-AC7Problem -ErrorAction SilentlyContinue){Show-AC7Problem $failure $Root $Action}
 $hint=[string]$failure.Exception.Data['AC7Hint']
 if(!$hint){$hint='请查看诊断记录，核对文件归属、目录权限或其他 Mod。'}
 [pscustomobject]@{Success=$false;Title='操作未完成';Message=($failure.Exception.Message+"`n"+$hint);GameRoot=$null;SteamPath=$null;ModState=$null;OpenFolder=$null}
}
