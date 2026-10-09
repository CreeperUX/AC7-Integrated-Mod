# Mouse-aim settings: one spec drives validation, MouseAim-Settings.ini, the installed config.ini
# ([control] section) and camera-settings.lua (follow_rate/level_rate). Ranges match the AC7 native reader.
function Get-AC7MouseSettingSpec {
 $rows=@(
  @('sensitivity','鼠标灵敏度','number',0.01,1,0.10,'control','config','游戏内 Ctrl+PageUp／PageDown 可临时调整'),
  @('control_mode','启动时的飞控','choice',0,3,3,'control','config','F4 在飞行中切换'),
  @('manual_ws_pitch','W／S 俯仰手动接管','bool',0,1,1,'control','config','按住俯仰键时让出自动控制'),
  @('free_look_zoom','自由观察放大倍率','number',1,3,1.75,'control','config','按住观察键 + 放大键时，1 = 不加倍'),
  @('mouse_reference_fov','鼠标参考视场角（度）','number',30,150,62,'control','config','放大时保持屏幕上的鼠标位移'),
  @('camera_mode','启动时的机位','choice',0,1,1,'camera','config','F3 在飞行中切换'),
  @('camera_distance_m','拉远机位距离（米）','number',10,100,36,'camera','config','机体后方'),
  @('camera_height_m','拉远机位高度（米）','number',0,20,6,'camera','config','机体上方'),
  @('follow_rate','镜头方向跟随速度','number',2,20,8,'camera','camera','越大越快'),
  @('level_rate','镜头回平速度','number',0,10,3,'camera','camera','0 = 不自动回平'),
  @('hud_renderer','HUD 绘制方式','choice',0,3,1,'hud','config','默认用 GPU 在原生分辨率独立绘制准星、面板与提示'),
  @('hud_fps','HUD 刷新目标（Hz）','int',60,240,120,'hud','config','不是游戏帧率保证'),
  @('hud_opacity','HUD 不透明度','number',0.15,1,0.65,'hud','config','越小越透明'),
  @('hud_line_width','准星线宽（倍数）','number',0.5,2,1,'hud','config','1 = 默认细线；游戏中改 config.ini 后按 F10 即时生效'),
  @('hud_connector','方向连接线','bool',0,1,1,'hud','config','机头与鼠标目标之间的连线'),
  @('hud_link_always','连接线常显','bool',0,1,0,'hud','config','关闭时只在偏差较大时显示'),
  @('hud_boresight','机头参考准星','bool',0,1,1,'hud','config','Alt+F7 在本次运行中临时切换'),
  @('model_assist','模型制动辅助','bool',0,1,1,'assist','config','接近目标时的有界制动'),
  @('model_assist_strength','辅助强度','number',0,0.35,0.20,'assist','config','越大越早开始制动'),
  @('arrival_braking','到达制动','number',1,1.35,1.15,'assist','config','1 = 旧版制动')
 )
 $choices=@{
  control_mode=@([pscustomobject]@{Value=0;Label='PEACE · 经典飞控'},[pscustomobject]@{Value=3;Label='WAR · 精确飞行引擎'})
  camera_mode=@([pscustomobject]@{Value=0;Label='原生机位'},[pscustomobject]@{Value=1;Label='拉远跟随机位'})
  hud_renderer=@([pscustomobject]@{Value=1;Label='GPU 独立绘制（默认，原生分辨率）'},[pscustomobject]@{Value=3;Label='准星画进游戏 HUD + GPU 面板'},[pscustomobject]@{Value=0;Label='旧版小窗口'})
 }
 foreach($row in $rows){
  [pscustomobject]@{Name=$row[0];Label=$row[1];Kind=$row[2];Min=[double]$row[3];Max=[double]$row[4];Default=[double]$row[5];Group=$row[6];Target=$row[7];Hint=$row[8];Choices=$choices[$row[0]]}
 }
}
function Get-AC7DefaultMouseSettings {
 $values=[ordered]@{};foreach($spec in Get-AC7MouseSettingSpec){$values[$spec.Name]=$spec.Default};return $values
}
function Format-AC7Number([double]$Value) {
 return $Value.ToString('0.######',[Globalization.CultureInfo]::InvariantCulture)
}
# Legacy and AC8 values: control_mode 1 -> PEACE, 2/4/5 -> WAR; AC8 canvas-only renderer 2 -> hybrid 3.
function ConvertTo-AC7MouseValue([string]$Name,[double]$Value) {
 if($Name -eq 'control_mode'){if($Value -eq 1){return 0};if($Value -in @(2,4,5)){return 3}}
 if($Name -eq 'hud_renderer' -and $Value -eq 2){return 3}
 return $Value
}
function Assert-AC7MouseSettings($Values) {
 $specs=@(Get-AC7MouseSettingSpec);$known=@($specs | ForEach-Object Name)
 foreach($key in @($Values.Keys)){if($key -notin $known){throw "未知的飞控设置：$key"}}
 foreach($spec in $specs){
  if(!$Values.Contains($spec.Name)){throw "缺少飞控设置：$($spec.Label)（$($spec.Name)）"}
  $value=[double]$Values[$spec.Name]
  if([double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt $spec.Min -or $value -gt $spec.Max){
   throw ("$($spec.Label) 超出范围："+(Format-AC7Number $value)+"，允许 "+(Format-AC7Number $spec.Min)+"–"+(Format-AC7Number $spec.Max)+'。')
  }
  if($spec.Kind -eq 'bool' -and $value -ne 0 -and $value -ne 1){throw "$($spec.Label) 只能是 0 或 1。"}
  if($spec.Kind -eq 'int' -and $value -ne [math]::Floor($value)){throw "$($spec.Label) 必须是整数。"}
  if($spec.Kind -eq 'choice' -and $value -notin @($spec.Choices | ForEach-Object Value)){throw "$($spec.Label) 的取值无效：$(Format-AC7Number $value)。"}
 }
}
function ConvertFrom-AC7MouseText([string]$Name,[string]$Text) {
 $clean=$Text.Trim().Replace(',','.')
 $parsed=0.0
 if($clean -notmatch '^-?[0-9]+(?:\.[0-9]+)?$' -or ![double]::TryParse($clean,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$parsed)){
  $label=@(Get-AC7MouseSettingSpec | Where-Object Name -eq $Name)[0].Label
  throw "$label 需要填写数字：$Text"
 }
 return (ConvertTo-AC7MouseValue $Name $parsed)
}
function Read-AC7MouseSettings([string]$Path) {
 $values=Get-AC7DefaultMouseSettings;$seen=@{}
 if(Test-Path -LiteralPath $Path){
  foreach($line in (Get-Content -LiteralPath $Path -Encoding UTF8)){
   $clean=$line.Trim();if(!$clean -or $clean.StartsWith(';') -or $clean.StartsWith('#')){continue}
   if($clean -notmatch '^([a-z_]+)\s*=\s*([^;]*?)\s*$'){throw "MouseAim-Settings.ini 中有无效行：$clean"}
   $key=$Matches[1];$raw=$Matches[2]
   if(!$values.Contains($key)){throw "MouseAim-Settings.ini 中有未知设置：$key"}
   if($seen.ContainsKey($key)){throw "MouseAim-Settings.ini 中重复设置：$key"};$seen[$key]=$true
   $values[$key]=ConvertFrom-AC7MouseText $key $raw
  }
 }
 Assert-AC7MouseSettings $values
 return $values
}
function Save-AC7MouseSettings([string]$Root,$Values,[string]$GameRoot) {
 if($GameRoot){Assert-AC7GameClosed $GameRoot}
 Assert-AC7MouseSettings $Values
 $lines=@('; AC7 mouse-aim settings. Saved by Start-GUI.cmd > 飞控设置; written into the installed config.ini.','; Edit while the game is closed. control_mode: 0=PEACE, 3=WAR. hud_renderer: 1=GPU overlay at native resolution, 3=reticle in the game HUD + GPU panel, 0=legacy windows.')
 foreach($spec in Get-AC7MouseSettingSpec){$lines+=($spec.Name+'='+(Format-AC7Number ([double]$Values[$spec.Name])))}
 Write-AC7TextAtomic (Join-Path $Root 'MouseAim-Settings.ini') (($lines -join "`r`n")+"`r`n") -Bom
}
function Test-AC7SameValue([string]$Old,[string]$New) {
 $a=0.0;$b=0.0;$style=[Globalization.NumberStyles]::Float;$culture=[Globalization.CultureInfo]::InvariantCulture
 if([double]::TryParse($Old.Trim(),$style,$culture,[ref]$a) -and [double]::TryParse($New.Trim(),$style,$culture,[ref]$b)){return [math]::Abs($a-$b) -le 1e-9}
 return $Old.Trim() -eq $New.Trim()
}
# Section-aware INI edit. Keeps comments, order, untouched keys and the file's newline style; an
# existing value is rewritten only when it differs numerically (0.10 stays 0.10 for a value of 0.1).
function Set-AC7IniValues([string]$Text,[string]$Section,$Values) {
 $newline=if($Text.Contains("`r`n") -or !$Text.Contains("`n")){"`r`n"}else{"`n"}
 $lines=New-Object 'Collections.Generic.List[string]'
 foreach($line in ($Text -split "`r?`n")){$lines.Add($line)}
 $start=-1
 for($i=0;$i -lt $lines.Count;$i++){if($lines[$i].Trim() -ieq "[$Section]"){$start=$i;break}}
 if($start -lt 0){
  if($lines.Count -and $lines[$lines.Count-1] -eq ''){$lines.RemoveAt($lines.Count-1)}
  if($lines.Count -and $lines[$lines.Count-1].Trim() -ne ''){$lines.Add('')}
  $lines.Add("[$Section]")
  foreach($key in $Values.Keys){$lines.Add($key+'='+$Values[$key])}
  $lines.Add('')
  return ($lines -join $newline)
 }
 foreach($key in $Values.Keys){
  $end=$lines.Count
  for($i=$start+1;$i -lt $lines.Count;$i++){if($lines[$i].TrimStart().StartsWith('[')){$end=$i;break}}
  $found=-1;$last=$start
  for($i=$start+1;$i -lt $end;$i++){
   $trimmed=$lines[$i].Trim()
   if($trimmed -ne '' -and !$trimmed.StartsWith(';')){$last=$i}
   if($trimmed -match ('^'+[regex]::Escape($key)+'\s*=\s*(.*)$')){$found=$i;break}
  }
  if($found -ge 0){
   if(!(Test-AC7SameValue $Matches[1] ([string]$Values[$key]))){$lines[$found]=$key+'='+$Values[$key]}
  }else{
   # Insert after the last setting of the section, before trailing blank/comment lines.
   for($i=$start+1;$i -lt $end;$i++){$trimmed=$lines[$i].Trim();if($trimmed -ne '' -and !$trimmed.StartsWith(';')){$last=$i}}
   $lines.Insert($last+1,$key+'='+$Values[$key])
  }
 }
 return ($lines -join $newline)
}
function Get-AC7IniValues([string]$Text,[string]$Section) {
 $values=@{};$inside=$false
 foreach($line in ($Text -split "`r?`n")){
  $trimmed=$line.Trim()
  if($trimmed.StartsWith('[')){$inside=($trimmed -ieq "[$Section]");continue}
  if($inside -and $trimmed -match '^([A-Za-z_]+)\s*=\s*([^;]*?)\s*$' -and !$values.ContainsKey($Matches[1])){$values[$Matches[1]]=$Matches[2]}
 }
 return $values
}
function Update-AC7ConfigText([string]$Text,$Settings,$Bindings) {
 $control=[ordered]@{}
 foreach($spec in Get-AC7MouseSettingSpec){if($spec.Target -eq 'config'){$control[$spec.Name]=Format-AC7Number ([double]$Settings[$spec.Name])}}
 $updated=Set-AC7IniValues $Text 'control' $control
 if($Bindings){$updated=Set-AC7IniValues $updated 'keybindings' (ConvertTo-AC7KeybindingCodes $Bindings)}
 return $updated
}
function Update-AC7CameraSettingsText([string]$Text,$Settings) {
 $updated=$Text
 foreach($name in 'follow_rate','level_rate'){
  $match=[regex]::Match($updated,'\b'+$name+'\s*=\s*([0-9]+(?:\.[0-9]+)?)')
  if(!$match.Success){throw "camera-settings.lua 缺少 $name，无法写入镜头设置。"}
  $value=Format-AC7Number ([double]$Settings[$name])
  if(!(Test-AC7SameValue $match.Groups[1].Value $value)){$updated=$updated.Substring(0,$match.Index)+"$name=$value"+$updated.Substring($match.Index+$match.Length)}
 }
 return $updated
}
# Reads user-facing values back from an installed config.ini / camera-settings.lua (used when adopting an install
# made by another package). Values that are missing or out of range keep the package's current value.
function Import-AC7MouseSettingsFromText([string]$ConfigText,[string]$CameraText,$Base) {
 $values=[ordered]@{};foreach($key in $Base.Keys){$values[$key]=$Base[$key]}
 $ini=Get-AC7IniValues $ConfigText 'control';$imported=@()
 foreach($spec in Get-AC7MouseSettingSpec){
  $raw=$null
  if($spec.Target -eq 'config'){if($ini.ContainsKey($spec.Name)){$raw=$ini[$spec.Name]}}
  elseif($CameraText){$match=[regex]::Match($CameraText,'\b'+$spec.Name+'\s*=\s*([0-9]+(?:\.[0-9]+)?)');if($match.Success){$raw=$match.Groups[1].Value}}
  if($null -eq $raw){continue}
  try{
   $candidate=[ordered]@{};foreach($key in $values.Keys){$candidate[$key]=$values[$key]}
   $candidate[$spec.Name]=ConvertFrom-AC7MouseText $spec.Name $raw
   Assert-AC7MouseSettings $candidate
   if($values[$spec.Name] -ne $candidate[$spec.Name]){$imported+=$spec.Name}
   $values=$candidate
  }catch{}
 }
 return [pscustomobject]@{Values=$values;Changed=$imported}
}
