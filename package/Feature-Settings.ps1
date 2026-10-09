# Installation scope. Every choice installs AC7MouseAim; guidance/full add AC7Weapons with that missile tier (AC8
# missile_mode): guidance = proportional-navigation lead only, full = all AC8 rules. "weapons" (0.4/0.5.x) means full.
function ConvertTo-AC7Features([string]$Features) {
 $value=([string]$Features).Trim().ToLowerInvariant()
 if($value -eq 'weapons'){return 'full'}
 if($value -notin @('mouse','guidance','full')){throw "Unknown installation scope: $Features"}
 return $value
}
function Read-AC7FeatureSettings([string]$Path) {
 $features='full';$seen=$false
 if(Test-Path -LiteralPath $Path){
  foreach($line in Get-Content -LiteralPath $Path -Encoding UTF8){
   $clean=$line.Trim();if(!$clean -or $clean.StartsWith(';') -or $clean.StartsWith('#')){continue}
   if($seen){throw 'features.ini：只能有一行 features=mouse、features=guidance 或 features=full。'}
   if($clean -match '^features\s*=\s*(mouse|guidance|full|weapons)$'){$features=ConvertTo-AC7Features $Matches[1]}
   else{throw "features.ini 中有无效设置：$clean"}
   $seen=$true
  }
 }
 return [pscustomobject]@{Features=$features;Weapons=($features -ne 'mouse')}
}
function Get-AC7FeatureSettingsText([string]$Features) {
 return '; Installation scope: mouse = AC7MouseAim only (stock missiles); guidance = + AC7Weapons, guidance lead only;'+"`r`n"+'; full = + AC7Weapons, all AC8 missile rules. Applied by the next install/update (Start-GUI.cmd or Setup.cmd).'+"`r`n"+'features='+(ConvertTo-AC7Features $Features)+"`r`n"
}
function Save-AC7FeatureSettings([string]$Root,[ValidateSet('mouse','guidance','full','weapons')][string]$Features) {
 Write-AC7TextAtomic (Join-Path $Root 'features.ini') (Get-AC7FeatureSettingsText $Features)
}
# AC7Weapons/Scripts/settings.lua for a tier (LF, like the payload file; full is byte-identical to the payload).
function Get-AC7WeaponsSettingsText([string]$Features) {
 $mode=ConvertTo-AC7Features $Features;if($mode -eq 'mouse'){throw 'AC7Weapons is not installed for the mouse-only scope'}
 return "-- Written by the AC7 installer from features.ini: guidance = proportional-navigation lead only; full = all AC8 rules.`nreturn {missile_mode='$mode'}`n"
}
function Get-AC7FeatureLabel([string]$Features) {
 switch($Features){'mouse'{return '仅鼠标飞控'} 'guidance'{return '鼠标飞控 + 导弹仅制导'} 'full'{return '鼠标飞控 + 导弹完整强化'} 'weapons'{return '鼠标飞控 + 导弹完整强化'} default{return '未知'}}
}
function Get-AC7FeatureDescription([string]$Features) {
 switch($Features){
  'mouse'{return '只安装鼠标飞控（AC7MouseAim），所有导弹保持原版。'}
  'guidance'{return '另启用 AC7Weapons 的“仅制导”档：只把 30 种玩家导弹的比例引导前置量调到 AC8 规则；速度、射程、伤害、近炸与外观保持原版。仅单人任务生效，离开任务时恢复原值。'}
  'full'{return '另启用 AC7Weapons 的“完整强化”档：按 AC8 规则调整玩家导弹的制导前置、速度与转向、锁定范围、近炸、爆炸范围与射程，外观保持原版。仅单人任务生效，离开任务时恢复原值。'}
  'weapons'{return (Get-AC7FeatureDescription 'full')}
 }
}
