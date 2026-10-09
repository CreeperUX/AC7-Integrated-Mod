$ErrorActionPreference='Stop'
# Keybindings: package file round trip, numeric [keybindings] staging in config.ini, guards, and the real WPF dialog
# (including the $ctx.Commands fix: the dialog must work when its functions live in a child scope).
$package=Split-Path $PSScriptRoot -Parent
. (Join-Path $package 'Keybindings-GUI.ps1')
. (Join-Path $package 'CreeperUX-Theme.ps1')
$fixture=Join-Path $PSScriptRoot ('tmp\keybindings-'+[guid]::NewGuid().ToString('N').Substring(0,8));New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$fakeGame=Join-Path $fixture 'game';New-Item -ItemType Directory -Path $fakeGame | Out-Null;Set-Content -LiteralPath (Join-Path $fakeGame 'Ace7Game.exe') -Value 'fake' -Encoding ASCII
$script:fakeProcesses=@()
function Get-Process {param([string[]]$Name,$ErrorAction) $script:fakeProcesses}
Copy-Item -LiteralPath (Join-Path $package 'Keybindings.ini') -Destination $fixture
$values=Read-AC7Keybindings (Join-Path $fixture 'Keybindings.ini');if($values.free_look -ne 'C' -or $values.pitch_up -ne 'S' -or $values.free_look_zoom -ne 'MouseRight'){throw 'Default binding mismatch'}
$values.free_look='V';$values.free_look_zoom='MouseX1';$values.pitch_up='I';$values.pitch_down='K';$values.roll_left='J';$values.roll_right='L';$values.yaw_left='U';$values.yaw_right='O'
Save-AC7Keybindings $fixture $values
$saved=Read-AC7Keybindings (Join-Path $fixture 'Keybindings.ini');if($saved.free_look -ne 'V' -or $saved.yaw_right -ne 'O'){throw 'Saved values not retained'}
if(!(Test-Path -LiteralPath (Join-Path $fixture 'Keybindings.ini.bak'))){throw 'Missing backup'}
$config=[IO.File]::ReadAllText((Join-Path $package 'payload\ue4ss\Mods\AC7MouseAim\config.ini'))
$settings=Read-AC7MouseSettings (Join-Path $package 'MouseAim-Settings.ini')
$runtime=Update-AC7ConfigText (Update-AC7ConfigText $config $settings $saved) $settings $saved
if(([regex]::Matches($runtime,'(?m)^\[keybindings\]')).Count -ne 1 -or $runtime -notmatch '(?m)^free_look=86\r$' -or $runtime -notmatch '(?m)^free_look_zoom=5\r$' -or $runtime -notmatch '(?m)^pitch_up=73\r$'){throw 'Runtime staging not numeric or duplicated'}
if((Get-AC7IniValues $runtime 'control').free_look_zoom -ne '1.75'){throw '[control] free_look_zoom (zoom factor) was overwritten by the key code'}
$import=Import-AC7KeybindingsFromText $runtime (Get-AC7DefaultBindings)
if($import.Values.free_look -ne 'V' -or $import.Values.free_look_zoom -ne 'MouseX1' -or @($import.Changed).Count -ne 8){throw 'Virtual-key import round trip failed'}
$before=[IO.File]::ReadAllBytes((Join-Path $fixture 'Keybindings.ini'))
$values.roll_left='I';$caught=$false;try{Save-AC7Keybindings $fixture $values}catch{$caught=$true};if(!$caught){throw 'Conflict accepted'};$values.roll_left='J'
$values.free_look='F5';$caught=$false;try{Save-AC7Keybindings $fixture $values}catch{$caught=$true};if(!$caught){throw 'Reserved key accepted'};$values.free_look='V'
$script:fakeProcesses=@([pscustomobject]@{Id=1;Path=(Join-Path $fakeGame 'Ace7Game.exe')})
$caught=$false;try{Save-AC7Keybindings $fixture $values $fakeGame}catch{$caught=([string]$_.Exception.Data['AC7Code'] -eq 'GAME_RUNNING')};if(!$caught){throw 'Running-game save accepted'}
Save-AC7Keybindings $fixture $values;$script:fakeProcesses=@()
$before=[IO.File]::ReadAllBytes((Join-Path $fixture 'Keybindings.ini'))
$values.roll_left='I';try{Save-AC7Keybindings $fixture $values}catch{};$values.roll_left='J'
if([Convert]::ToBase64String($before) -ne [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $fixture 'Keybindings.ini')))){throw 'Rejected save changed configuration'}
Set-Content -LiteralPath (Join-Path $fixture 'bad.ini') -Value "[bindings]`r`nfree_look=V`r`nfree_look=J" -Encoding ASCII
$caught=$false;try{Read-AC7Keybindings (Join-Path $fixture 'bad.ini')}catch{$caught=$true};if(!$caught){throw 'Duplicate key entry accepted'}
Write-Host 'PASS defaults/custom save, backup, numeric [keybindings] staging, VK import, duplicate/reserved/conflict guards and game-running rejection'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$click=[Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)
$ctx=New-AC7KeybindingsDialog $fixture $null 'dark' ''
if($ctx.Buttons.Count -ne 8){throw 'GUI missing actions'}
$ctx.Buttons.free_look.RaiseEvent($click);if($ctx.State.Capture -ne 'free_look'){throw 'Capture not armed'}
Set-AC7CapturedBinding $ctx 66;if($ctx.State.Values.free_look -ne 'B'){throw 'Key capture not retained'}
$ctx.Save.RaiseEvent($click);if(!$ctx.State.Saved -or (Read-AC7Keybindings (Join-Path $fixture 'Keybindings.ini')).free_look -ne 'B'){throw ('GUI save failed: '+$ctx.Status.Text)}
if($ctx.Status.Text -notmatch '本包'){throw 'Package-only save not reported'}
$ctx.Buttons.roll_left.RaiseEvent($click);Set-AC7CapturedBinding $ctx 66;if($ctx.Save.IsEnabled){throw 'GUI conflict did not block save'}
$ctx.Window.FindName('RestoreBindings').RaiseEvent($click);if($ctx.State.Values.free_look -ne 'C' -or !$ctx.Save.IsEnabled){throw 'GUI restore-default failed'}
$ctx.Save.RaiseEvent($click);if((Read-AC7Keybindings (Join-Path $fixture 'Keybindings.ini')).free_look -ne 'C'){throw 'GUI defaults not saved'}
# Scope isolation (the 2.4.1 fix): in a fresh process the dialog functions exist only inside a child scope, yet the
# event closures (mouse capture, settings and keybinding saves) must still reach them through $ctx.Commands.
$probe=Join-Path $fixture 'scope-probe.ps1'
$probeText=@'
param($Package,$Fixture)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
& {
 . (Join-Path $Package 'Keybindings-GUI.ps1');. (Join-Path $Package 'MouseAim-Settings-GUI.ps1');. (Join-Path $Package 'CreeperUX-Theme.ps1')
 $click=[Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)
 $inner=New-AC7KeybindingsDialog $Fixture $null 'light' ''
 $inner.Buttons.yaw_left.RaiseEvent($click)
 $mouse=[Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0,[Windows.Input.MouseButton]::Middle);$mouse.RoutedEvent=[Windows.Input.Mouse]::PreviewMouseDownEvent
 $inner.Window.RaiseEvent($mouse)
 $inner.Save.RaiseEvent($click)
 $settings=New-AC7MouseSettingsDialog $Fixture $null 'light' ''
 $settings.Controls.sensitivity.Text='0.33';$settings.Save.RaiseEvent($click)
 'RESULT keys='+$inner.State.Saved+' '+$inner.State.Values.yaw_left+' settings='+$settings.State.Saved
}
'@
[IO.File]::WriteAllText($probe,$probeText,[Text.UTF8Encoding]::new($true))
Copy-Item -LiteralPath (Join-Path $package 'MouseAim-Settings.ini') -Destination $fixture
$previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
$isolated=(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -STA -ExecutionPolicy Bypass -File $probe -Package $package -Fixture $fixture 2>&1 | ForEach-Object {"$_"}) -join "`n"
$ErrorActionPreference=$previous
if($isolated -notmatch 'RESULT keys=True MouseMiddle settings=True' -or (Read-AC7Keybindings (Join-Path $fixture 'Keybindings.ini')).yaw_left -ne 'MouseMiddle' -or (Read-AC7MouseSettings (Join-Path $fixture 'MouseAim-Settings.ini')).sensitivity -ne 0.33){throw ('Dialogs failed with functions only in a child scope: '+$isolated)}
foreach($theme in @('dark','light')){
 $ctx=New-AC7KeybindingsDialog $fixture $null $theme ''
 foreach($size in @(@(860,760),@(680,560))){
  $ctx.Window.Content.Measure([Windows.Size]::new($size[0],$size[1]));$ctx.Window.Content.Arrange([Windows.Rect]::new(0,0,$size[0],$size[1]));$ctx.Window.Content.UpdateLayout()
  if($ctx.Buttons.free_look.ActualWidth -le 0 -or $ctx.Save.ActualWidth -le 0){throw 'GUI layout did not measure'}
 }
}
Remove-Item Function:\Get-Process
Remove-Item -LiteralPath $fixture -Recurse -Force
Write-Host 'PASS real WPF capture (button + mouse event), save/restore, conflict state, child-scope closures, dark/light layout'
exit 0
