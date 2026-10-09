$ErrorActionPreference='Stop'
# Mouse-aim settings: validation and migration, section-aware config.ini editing (CRLF, comments, minimal diffs),
# camera-settings.lua, settings import, and the WPF settings dialog layout in both themes.
$package=Split-Path $PSScriptRoot -Parent
. (Join-Path $package 'MouseAim-Settings-GUI.ps1')
. (Join-Path $package 'CreeperUX-Theme.ps1')
$fixture=Join-Path $PSScriptRoot ('tmp\settings-'+[guid]::NewGuid().ToString('N').Substring(0,8));New-Item -ItemType Directory -Path $fixture -Force | Out-Null
function Expect-Failure([string]$Text,[string]$Name){
 Set-Content -LiteralPath (Join-Path $fixture 'case.ini') -Value $Text -Encoding UTF8
 $caught=$false;try{Read-AC7MouseSettings (Join-Path $fixture 'case.ini') | Out-Null}catch{$caught=$true}
 if(!$caught){throw "Accepted invalid settings: $Name"}
}
$defaults=Read-AC7MouseSettings (Join-Path $package 'MouseAim-Settings.ini')
$specDefaults=Get-AC7DefaultMouseSettings
foreach($key in $specDefaults.Keys){if($defaults[$key] -ne $specDefaults[$key]){throw "Shipped MouseAim-Settings.ini differs from spec default: $key"}}
$payload=[IO.File]::ReadAllText((Join-Path $package 'payload\ue4ss\Mods\AC7MouseAim\config.ini'))
$camera=[IO.File]::ReadAllText((Join-Path $package 'payload\ue4ss\Mods\AC7MouseAim\Scripts\camera-settings.lua'))
$control=Get-AC7IniValues $payload 'control'
foreach($spec in Get-AC7MouseSettingSpec){
 if($spec.Target -eq 'config' -and !(Test-AC7SameValue $control[$spec.Name] (Format-AC7Number $spec.Default))){throw "Payload config.ini default differs: $($spec.Name)"}
}
Write-Host 'PASS shipped defaults equal the spec and the payload config.ini (no change on adoption)'
Set-Content -LiteralPath (Join-Path $fixture 'legacy.ini') -Value "control_mode=2`r`nhud_renderer=2`r`nsensitivity=0,25" -Encoding UTF8
$legacy=Read-AC7MouseSettings (Join-Path $fixture 'legacy.ini')
if($legacy.control_mode -ne 3 -or $legacy.hud_renderer -ne 3 -or $legacy.sensitivity -ne 0.25){throw 'Legacy migration failed'}
Set-Content -LiteralPath (Join-Path $fixture 'legacy.ini') -Value 'control_mode=1' -Encoding UTF8
if((Read-AC7MouseSettings (Join-Path $fixture 'legacy.ini')).control_mode -ne 0){throw 'control_mode 1 -> PEACE failed'}
Expect-Failure 'sensitivity=2' 'out of range';Expect-Failure 'hud_boresight=2' 'bool 2';Expect-Failure 'hud_boresight=0.5' 'bool 0.5'
Expect-Failure 'hud_fps=120.5' 'fractional int';Expect-Failure 'camera_mode=2' 'bad choice';Expect-Failure 'unknown_key=1' 'unknown key'
Expect-Failure "sensitivity=0.1`r`nsensitivity=0.2" 'duplicate';Expect-Failure 'sensitivity=abc' 'not a number';Expect-Failure 'control_mode=7' 'control_mode range'
Write-Host 'PASS migrations (control_mode 1/2, AC8 hud_renderer 2 -> 3, decimal comma) and 9 invalid-value rejections'
$bindings=Read-AC7Keybindings (Join-Path $package 'Keybindings.ini')
$generated=Update-AC7ConfigText $payload $defaults $bindings
if($generated -ne $payload){throw 'Defaults rewrote an unchanged payload config.ini'}
$changed=[ordered]@{};foreach($key in $defaults.Keys){$changed[$key]=$defaults[$key]};$changed.sensitivity=0.3;$changed.hud_boresight=0;$changed.free_look_zoom=2.5
$generated=Update-AC7ConfigText $payload $changed $bindings
$diff=@(Compare-Object ($payload -split "`r`n") ($generated -split "`r`n") | Where-Object SideIndicator -eq '=>' | ForEach-Object InputObject)
if(($diff -join '|') -ne 'sensitivity=0.3|hud_boresight=0|free_look_zoom=2.5'){throw ('Unexpected config diff: '+($diff -join '|'))}
if(([regex]::Matches($generated,"(?<!`r)`n")).Count){throw 'LF-only line written'}
if((Get-AC7IniValues $generated 'keybindings').free_look_zoom -ne '2'){throw '[keybindings] free_look_zoom changed by the zoom factor'}
Write-Host 'PASS config.ini edit is minimal (3 changed lines), CRLF kept, same key name in two sections kept apart'
# A Codex-era config without hud_boresight, free_look_zoom and [keybindings] gets them in the right sections.
$old=$payload -replace "\r\n\r\n; Reference gun cross[^\r\n]*\r\nhud_boresight=1",''
$old=$old.Substring(0,$old.IndexOf("`r`n; Additional optical"))
$upgraded=Update-AC7ConfigText $old $defaults $bindings
$controlValues=Get-AC7IniValues $upgraded 'control';$keyValues=Get-AC7IniValues $upgraded 'keybindings'
if($controlValues.hud_boresight -ne '1' -or $controlValues.free_look_zoom -ne '1.75' -or $keyValues.free_look -ne '67' -or $keyValues.free_look_zoom -ne '2' -or @($keyValues.Keys).Count -ne 8){throw 'Old config not upgraded correctly'}
if($upgraded.IndexOf('hud_boresight=') -gt $upgraded.IndexOf('[keybindings]')){throw 'hud_boresight inserted outside [control]'}
if(!$upgraded.EndsWith("`r`n")){throw 'Upgraded config lacks final newline'}
Write-Host 'PASS old config.ini gains hud_boresight/free_look_zoom in [control] and a numeric [keybindings] section'
$cameraOut=Update-AC7CameraSettingsText $camera $defaults
if($cameraOut -ne $camera){throw 'Unchanged camera settings rewritten'}
$changed.follow_rate=11.5;$changed.level_rate=0
$cameraOut=Update-AC7CameraSettingsText $camera $changed
if($cameraOut -notmatch 'follow_rate=11\.5' -or $cameraOut -notmatch 'level_rate=0\b' -or $cameraOut -notmatch '^-- F10 reloads'){throw 'camera-settings.lua not updated in place'}
$import=Import-AC7MouseSettingsFromText ($payload.Replace('sensitivity=0.10','sensitivity=0.4').Replace('hud_opacity=0.65','hud_opacity=9')) $cameraOut (Get-AC7DefaultMouseSettings)
if($import.Values.sensitivity -ne 0.4 -or $import.Values.hud_opacity -ne 0.65 -or $import.Values.follow_rate -ne 11.5 -or $import.Values.level_rate -ne 0){throw 'Import did not keep valid values / skip invalid ones'}
Write-Host 'PASS camera-settings.lua edited in place with comments; import keeps valid installed values and skips out-of-range ones'
Copy-Item -LiteralPath (Join-Path $package 'MouseAim-Settings.ini') -Destination $fixture
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
foreach($theme in @('dark','light')){
 $ctx=New-AC7MouseSettingsDialog $fixture $null $theme ''
 foreach($size in @(@(940,860),@(700,560))){
  $ctx.Window.Content.Measure([Windows.Size]::new($size[0],$size[1]));$ctx.Window.Content.Arrange([Windows.Rect]::new(0,0,$size[0],$size[1]));$ctx.Window.Content.UpdateLayout()
  foreach($name in 'sensitivity','arrival_braking','level_rate','hud_boresight','hud_line_width'){if($ctx.Controls[$name].ActualWidth -le 0){throw "Settings control not laid out: $name"}}
  $root=$ctx.Window.Content
  $save=$ctx.Save;$rect=$save.TransformToAncestor($root).TransformBounds([Windows.Rect]::new(0,0,$save.ActualWidth,$save.ActualHeight))
  if($rect.Right -gt $root.ActualWidth+1 -or $rect.Bottom -gt $root.ActualHeight+1){throw "Save button clipped at $size ($theme)"}
 }
}
Remove-Item -LiteralPath $fixture -Recurse -Force
Write-Host 'PASS settings dialog lays out all 20 controls without clipping in dark/light at two window sizes'
exit 0
