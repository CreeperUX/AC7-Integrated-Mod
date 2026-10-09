function Get-AC7KeybindingSpec {
 return Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Keybindings.schema.json') -Raw -Encoding UTF8 | ConvertFrom-Json
}
function Get-AC7DefaultBindings {
 $values=[ordered]@{};foreach($action in (Get-AC7KeybindingSpec).actions){$values[$action.name]=[string]$action.default};return $values
}
function Convert-AC7KeyToken([string]$Token) {
 $found=@((Get-AC7KeybindingSpec).keys.PSObject.Properties | Where-Object Name -ieq $Token.Trim())
 if($found.Count -ne 1){throw "不支持的按键：$Token。F1–F10 为已有功能保留；不接受组合键。"}
 return [string]$found[0].Name
}
function Convert-AC7VirtualKeyToToken([int]$VirtualKey) {
 $found=@((Get-AC7KeybindingSpec).keys.PSObject.Properties | Where-Object {[int]$_.Value.vk -eq $VirtualKey})
 if($found.Count -ne 1){throw "不支持的虚拟键码：$VirtualKey"}
 return [string]$found[0].Name
}
function Assert-AC7Keybindings($Values) {
 $spec=Get-AC7KeybindingSpec;$seen=@{};$known=@($spec.actions | ForEach-Object name)
 foreach($key in @($Values.Keys)){if($key -notin $known){throw "未知键位功能：$key"}}
 foreach($action in $spec.actions){
  if(!$Values.Contains($action.name)){throw "缺少键位功能：$($action.name)"}
  $token=Convert-AC7KeyToken ([string]$Values[$action.name]);$vk=[int]$spec.keys.PSObject.Properties[$token].Value.vk
  if($vk -ne 0 -and $seen.ContainsKey($vk)){throw "按键冲突：$token 同时用于[$($seen[$vk])]和[$($action.label)]。请更换其中一项。"}
  if($vk -ne 0){$seen[$vk]=[string]$action.label}
 }
}
function Read-AC7Keybindings([string]$Path) {
 $values=Get-AC7DefaultBindings;$seen=@{};$section=$false
 if(Test-Path -LiteralPath $Path){foreach($line in (Get-Content -LiteralPath $Path -Encoding UTF8)){
  $text=$line.Trim();if(!$text -or $text.StartsWith(';') -or $text.StartsWith('#')){continue}
  if($text -ieq '[bindings]'){if($section){throw '重复的 bindings 分区。'};$section=$true;continue}
  if(!$section -or $text -notmatch '^([a-z_]+)\s*=\s*([A-Za-z0-9]+)$'){throw "无效键位配置：$text"}
  $key=$Matches[1];$token=$Matches[2]
  if(!$values.Contains($key)){throw "未知键位功能：$key"};if($seen.ContainsKey($key)){throw "重复键位功能：$key"}
  $seen[$key]=$true;$values[$key]=Convert-AC7KeyToken $token
 }}
 Assert-AC7Keybindings $values;return $values
}
# Saving is refused only while the selected game folder is running; a package-only save is harmless.
function Save-AC7Keybindings([string]$Root,$Values,[string]$GameRoot) {
 if($GameRoot){Assert-AC7GameClosed $GameRoot}
 Assert-AC7Keybindings $Values
 $path=Join-Path $Root 'Keybindings.ini';$temporary=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 $lines=@('; Saved by Start-GUI.cmd > Keybindings. Written into the installed config.ini [keybindings].','; Manual axes must match the game bindings. Throttle/brake stay stock.','[bindings]')
 foreach($action in (Get-AC7KeybindingSpec).actions){$lines+=($action.name+'='+(Convert-AC7KeyToken ([string]$Values[$action.name])))}
 try {
  [IO.File]::WriteAllText($temporary,($lines -join "`r`n")+"`r`n",[Text.Encoding]::ASCII)
  if(Test-Path -LiteralPath $path){Copy-Item -LiteralPath $path -Destination ($path+'.bak') -Force}
  Move-Item -LiteralPath $temporary -Destination $path -Force
 }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
}
# Token names -> the numeric [keybindings] table read by the native DLL (GetPrivateProfileInt).
function ConvertTo-AC7KeybindingCodes($Values) {
 Assert-AC7Keybindings $Values;$spec=Get-AC7KeybindingSpec;$codes=[ordered]@{}
 foreach($action in $spec.actions){$token=Convert-AC7KeyToken ([string]$Values[$action.name]);$codes[[string]$action.name]=[string][int]$spec.keys.PSObject.Properties[$token].Value.vk}
 return $codes
}
function Import-AC7KeybindingsFromText([string]$ConfigText,$Base) {
 $values=[ordered]@{};foreach($key in $Base.Keys){$values[$key]=$Base[$key]}
 $ini=Get-AC7IniValues $ConfigText 'keybindings';if(!$ini.Count){return [pscustomobject]@{Values=$values;Changed=@()}}
 $candidate=[ordered]@{};foreach($key in $values.Keys){$candidate[$key]=$values[$key]}
 try{
  foreach($key in @($candidate.Keys)){if($ini.ContainsKey($key)){$candidate[$key]=Convert-AC7VirtualKeyToToken ([int]$ini[$key])}}
  Assert-AC7Keybindings $candidate
 }catch{return [pscustomobject]@{Values=$values;Changed=@()}}
 $changed=@($candidate.Keys | Where-Object {$candidate[$_] -ne $values[$_]})
 return [pscustomobject]@{Values=$candidate;Changed=$changed}
}
