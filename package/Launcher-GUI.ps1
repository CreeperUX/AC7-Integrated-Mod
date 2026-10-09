param([switch]$RenderPreview,[string]$PreviewPath,[ValidateSet('launcher','settings','keybindings')][string]$PreviewPage='launcher',[switch]$SmokeTest,[ValidateSet('dark','light')][string]$Theme='dark',[switch]$NoDialog)
$ErrorActionPreference='Stop'
try {
. ([IO.Path]::Combine($PSScriptRoot,'PowerShell-Compat.ps1'))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms
. (Join-Path $PSScriptRoot 'Gui-Core.ps1')
. (Join-Path $PSScriptRoot 'CreeperUX-Theme.ps1')
. (Join-Path $PSScriptRoot 'Keybindings-GUI.ps1')
. (Join-Path $PSScriptRoot 'MouseAim-Settings-GUI.ps1')
$reader=New-Object System.Xml.XmlNodeReader ([xml](Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Launcher-GUI.xaml') -Raw -Encoding UTF8))
$window=[Windows.Markup.XamlReader]::Load($reader)
# Fit the initial window to the available desktop; the content scales down instead of scrolling.
$workArea=[Windows.SystemParameters]::WorkArea
$window.MinWidth=[Math]::Min($window.MinWidth,[Math]::Max(480,$workArea.Width-24))
$window.MinHeight=[Math]::Min($window.MinHeight,[Math]::Max(360,$workArea.Height-24))
$window.Width=[Math]::Min($window.Width,[Math]::Max($window.MinWidth,$workArea.Width-24))
$window.Height=[Math]::Min($window.Height,[Math]::Max($window.MinHeight,$workArea.Height-24))
$script:themeMode=$Theme
Set-CreeperUXTheme $window $script:themeMode
$script:controls=@{}
foreach($name in 'GamePath','SteamPath','BrowseGame','BrowseSteam','MouseOnly','GuidanceOnly','WithWeapons','Check','Install','Start','Recover','OpenLogs','CollectLogs','Settings','Keybindings','StatusTitle','StatusMessage','StatusCard','BusyBar','PreviewRoot','ThemeToggle','StatusMark','ModeDescription','Detect','GameCandidates','SteamCandidates','PackageVersion','DisableMod','EnableMod','ModeBadgeText'){$script:controls[$name]=$window.FindName($name)}
$script:worker=$null;$script:async=$null
$infoPath=Join-Path $PSScriptRoot 'package-info.json'
if(Test-Path -LiteralPath $infoPath){
 $info=Get-Content -LiteralPath $infoPath -Raw -Encoding UTF8 | ConvertFrom-Json
 if($info.version){$label=switch($info.status){'prerelease'{'预发布'} 'release'{'正式版'} 'beta'{'Beta 测试版'} default{'候选'}};$script:controls.PackageVersion.Text='AC7 '+[string]$info.version+' · '+$label}
}

function Set-AC7GuiStatus([string]$Title,[string]$Message,[bool]$Success=$true){
 $script:controls.StatusTitle.Text=$Title
 $script:controls.StatusMessage.Text=$Message
 $key=if($Success){'CxInfo'}else{'CxBad'}
 $script:controls.StatusMark.SetResourceReference([Windows.Controls.Border]::BackgroundProperty,$key)
}
function Set-AC7ModeBadge([string]$Mode){
 $text=switch($Mode){'enabled'{'Mod 已启用 · 仅单人'} 'disabled'{'Mod 已停用 · 可联机'} 'none'{'未安装 · 原版'} 'missing'{'加载器缺失'} default{'尚未检查'}}
 $key=switch($Mode){'enabled'{'CxWarn'} 'disabled'{'CxGood'} 'missing'{'CxBad'} default{'CxMuted'}}
 $script:controls.ModeBadgeText.Text=$text
 $script:controls.ModeBadgeText.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,$key)
}
function Set-AC7GuiBusy([bool]$Busy){
 foreach($name in 'GamePath','SteamPath','BrowseGame','BrowseSteam','MouseOnly','GuidanceOnly','WithWeapons','Check','Detect','Install','Start','Recover','GameCandidates','SteamCandidates','DisableMod','EnableMod','Settings','Keybindings','CollectLogs'){$script:controls[$name].IsEnabled=!$Busy}
 $script:controls.BusyBar.IsIndeterminate=[Windows.SystemParameters]::ClientAreaAnimation
 $script:controls.BusyBar.Value=50
 $script:controls.BusyBar.Visibility=if($Busy){'Visible'}else{'Collapsed'}
}
function Get-AC7GuiGameRoot {
 try{return (Resolve-AC7GameRoot $script:controls.GamePath.Text)}catch{return ''}
}
function Start-AC7GuiWork([string]$Action,[bool]$Confirm=$false){
 if($script:worker){return}
 Set-AC7GuiBusy $true
 Set-AC7GuiStatus '正在处理…' '请稍候，完成后会在这里显示结果。'
 try {
  $script:worker=[PowerShell]::Create()
  [void]$script:worker.AddCommand((Join-Path $PSScriptRoot 'Gui-Worker.ps1')).AddParameter('Action',$Action).AddParameter('Root',$PSScriptRoot).AddParameter('GamePath',$script:controls.GamePath.Text).AddParameter('SteamPath',$script:controls.SteamPath.Text).AddParameter('Features',(Get-AC7GuiSelectedFeatures $script:controls)).AddParameter('Confirmed',$Confirm)
  $script:async=$script:worker.BeginInvoke()
  $timer.Start()
 }catch{
  if($script:worker){$script:worker.Dispose()};$script:worker=$null
  Set-AC7GuiBusy $false;Set-AC7GuiStatus '操作未完成' $_.Exception.Message $false
 }
}
$timer=New-Object Windows.Threading.DispatcherTimer
$timer.Interval=[TimeSpan]::FromMilliseconds(150)
$timer.Add_Tick({
 if(!$script:async -or !$script:async.IsCompleted){return}
 $timer.Stop()
 try{
  $results=@($script:worker.EndInvoke($script:async))
  if(!$results.Count){throw '后台操作没有返回结果，请检查诊断记录。'}
  $result=$results[-1]
  Set-AC7GuiStatus $result.Title $result.Message ([bool]$result.Success)
  if($result.GameRoot){$script:controls.GamePath.Text=$result.GameRoot}
  if($result.SteamPath){$script:controls.SteamPath.Text=$result.SteamPath}
  if($result.ModState){Set-AC7ModeBadge $result.ModState}
  if($result.PSObject.Properties['GameCandidates']){
   foreach($name in 'GameCandidates','SteamCandidates'){
    $items=@($result.$name)
    $script:controls[$name].ItemsSource=$items
    $script:controls[$name].SelectedIndex=-1
    $script:controls[$name].Visibility=if($items.Count -gt 1){'Visible'}else{'Collapsed'}
   }
  }
  if($result.OpenFolder -and !$SmokeTest){Start-Process -FilePath 'explorer.exe' -ArgumentList ('"'+$result.OpenFolder+'"') -WindowStyle Normal}
 }catch{Set-AC7GuiStatus '操作未完成' $_.Exception.Message $false}
 finally{
  $script:worker.Dispose();$script:worker=$null;$script:async=$null;Set-AC7GuiBusy $false
  if($SmokeTest -and $script:smokeFrame){$script:smokeFrame.Continue=$false}
 }
})
function Update-AC7GuiModeDescription {
 $script:controls.ModeDescription.Text=Get-AC7FeatureDescription (Get-AC7GuiSelectedFeatures $script:controls)
}
foreach($name in 'MouseOnly','GuidanceOnly','WithWeapons'){$script:controls[$name].Add_Checked({Update-AC7GuiModeDescription})}
$script:controls.ThemeToggle.Content=if($Theme -eq 'dark'){'切换浅色'}else{'切换深色'}
$script:controls.ThemeToggle.Add_Click({
 $script:themeMode=if($script:themeMode -eq 'dark'){'light'}else{'dark'}
 Set-CreeperUXTheme $window $script:themeMode
 $script:controls.ThemeToggle.Content=if($script:themeMode -eq 'dark'){'切换浅色'}else{'切换深色'}
})
$script:controls.BrowseGame.Add_Click({
 $dialog=New-Object System.Windows.Forms.FolderBrowserDialog
 $dialog.Description='选择 AC7 游戏文件夹（包含 Ace7Game.exe）';$dialog.ShowNewFolderButton=$false
 try{if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){$script:controls.GamePath.Text=$dialog.SelectedPath}}finally{$dialog.Dispose()}
})
$script:controls.BrowseSteam.Add_Click({
 $dialog=New-Object Microsoft.Win32.OpenFileDialog
 $dialog.Title='选择 Steam 安装目录中的 steam.exe';$dialog.Filter='Steam 程序 (steam.exe)|steam.exe';$dialog.CheckFileExists=$true
 if($dialog.ShowDialog($window)){$script:controls.SteamPath.Text=$dialog.FileName}
})
$script:controls.Check.Add_Click({Start-AC7GuiWork 'Check'})
$script:controls.Detect.Add_Click({Start-AC7GuiWork 'Discover'})
$script:controls.GameCandidates.Add_SelectionChanged({
 if(!$script:worker -and $script:controls.GameCandidates.SelectedItem){
  $script:controls.GamePath.Text=[string]$script:controls.GameCandidates.SelectedItem
  Start-AC7GuiWork 'Discover'
 }
})
$script:controls.SteamCandidates.Add_SelectionChanged({
 if(!$script:worker -and $script:controls.SteamCandidates.SelectedItem){
  $script:controls.SteamPath.Text=[string]$script:controls.SteamCandidates.SelectedItem
  Start-AC7GuiWork 'Discover'
 }
})
$script:controls.Install.Add_Click({
 $features=Get-AC7GuiSelectedFeatures $script:controls
 # Single-quoted segments: Chinese curly quotes would end a double-quoted PowerShell string.
 $nl=[Environment]::NewLine
 $message='将安装或更新到：'+$nl+$script:controls.GamePath.Text+$nl+$nl+'内容：'+(Get-AC7FeatureLabel $features)+$nl+$nl+'会先备份存档与原有 Mod 文件，再逐个写入并校验；发现不属于本工具的加载器或被修改的文件时会停止，不覆盖。'+$nl+$nl+'仅限单人游戏。多人对战前请先“停用 Mod”。'
 if(Show-CreeperUXConfirmation $window $message -Title '确认安装' -Heading '安装／更新' -ConfirmText '安装／更新'){Start-AC7GuiWork 'Install' $true}
})
$script:controls.DisableMod.Add_Click({Start-AC7GuiWork 'Disable'})
$script:controls.EnableMod.Add_Click({Start-AC7GuiWork 'Enable'})
$script:controls.Start.Add_Click({Start-AC7GuiWork 'Start'})
$script:controls.CollectLogs.Add_Click({Start-AC7GuiWork 'Collect'})
$script:controls.Settings.Add_Click({
 try{
  $state=Show-AC7MouseSettingsDialog $PSScriptRoot $window $script:themeMode (Get-AC7GuiGameRoot)
  if($state.Saved){Set-AC7GuiStatus '飞控设置已保存' $state.Message}
 }catch{Set-AC7GuiStatus '飞控设置未打开' ($_.Exception.Message+' '+[string]$_.Exception.Data['AC7Hint']) $false}
})
$script:controls.Keybindings.Add_Click({
 try{
  $state=Show-AC7KeybindingsDialog $PSScriptRoot $window $script:themeMode (Get-AC7GuiGameRoot)
  if($state.Saved){Set-AC7GuiStatus '键位已保存' ($state.Message+' 请同步核对游戏内的操纵绑定。')}
 }catch{Set-AC7GuiStatus '键位设置未打开' ($_.Exception.Message+' '+[string]$_.Exception.Data['AC7Hint']) $false}
})
$script:controls.Recover.Add_Click({
 $message="将卸载当前游戏路径中由本工具安装的 Mod：先备份并校验，再只删除内容与安装记录一致的文件；被修改过的文件会备份并保留。运行日志会归档，不会删除。`n`n若安装过其他 UE4SS Mod 或不清楚文件来源，请取消。`n`n游戏路径："+$script:controls.GamePath.Text
 if(Show-CreeperUXConfirmation $window $message -Title '确认卸载' -Heading '卸载（备份并清理）' -ConfirmText '确认归属并卸载'){Start-AC7GuiWork 'Recover' $true}
})
$script:controls.OpenLogs.Add_Click({
 try{
  $folder=Join-Path $PSScriptRoot 'diagnostics'
  if(!(Test-Path -LiteralPath $folder)){Set-AC7GuiStatus '暂无诊断文件' '发生错误后，详细诊断会自动保存在这里。运行日志请用“收集日志”。';return}
  Start-Process -FilePath 'explorer.exe' -ArgumentList ('"'+$folder+'"') -WindowStyle Normal
 }catch{Set-AC7GuiStatus '无法打开文件夹' $_.Exception.Message $false}
})
$window.Add_Closing({param($sender,$event)
 if($script:worker){$event.Cancel=$true;Set-AC7GuiStatus '请等待当前操作完成' '安装、切换或清理仍在进行，完成后即可关闭窗口。'}
})
function Save-AC7PreviewImage($Element,[int]$Width,[int]$Height,[string]$Path){
 $Element.Measure([Windows.Size]::new($Width,$Height));$Element.Arrange([Windows.Rect]::new(0,0,$Width,$Height));$Element.UpdateLayout()
 $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap $Width,$Height,96,96,([Windows.Media.PixelFormats]::Pbgra32)
 $background=New-Object Windows.Media.DrawingVisual
 $drawing=$background.RenderOpen()
 $drawing.DrawRectangle($window.Resources['CxBg'],$null,[Windows.Rect]::new(0,0,$Width,$Height));$drawing.Close()
 $bitmap.Render($background)
 $bitmap.Render($Element)
 $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
 $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
 $stream=[IO.File]::Create([IO.Path]::GetFullPath($Path));try{$encoder.Save($stream)}finally{$stream.Dispose()}
}
if($SmokeTest){
 # The three mutually-exclusive installation scopes, with their descriptions; the 0.5.x value "weapons" maps to full.
 foreach($features in 'mouse','guidance','full','weapons'){
  Set-AC7GuiSelectedFeatures $script:controls $features
  if((Get-AC7GuiSelectedFeatures $script:controls) -ne (ConvertTo-AC7Features $features)){throw 'GUI feature mapping failed'}
  $checked=@('MouseOnly','GuidanceOnly','WithWeapons' | Where-Object {$script:controls[$_].IsChecked})
  if($checked.Count -ne 1 -or !$script:controls.ModeDescription.Text){throw 'GUI feature selection is not exclusive or lacks description'}
 }
 Set-AC7GuiSelectedFeatures $script:controls (Read-AC7FeatureSettings (Join-Path $PSScriptRoot 'features.ini')).Features
 foreach($mode in 'enabled','disabled','none','missing',''){Set-AC7ModeBadge $mode;if(!$script:controls.ModeBadgeText.Text){throw 'Mode badge empty'}}
 # Token adapter and actual theme button.
 $before=$script:themeMode
 $script:controls.ThemeToggle.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
 if($script:themeMode -eq $before){throw 'Theme toggle did not change mode'}
 if(![Windows.SystemParameters]::HighContrast){
  $expected=if($script:themeMode -eq 'light'){'#FFEFEBE5'}else{'#FF0D1114'}
  if($window.Resources['CxBg'].Color.ToString() -ne $expected){throw 'Theme background differs from kit token'}
 }
 $script:controls.ThemeToggle.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
 foreach($key in 'CxDisplay','CxMono'){
  $typeface=[Windows.Media.Typeface]::new($window.Resources[$key],[Windows.FontStyles]::Normal,[Windows.FontWeights]::Normal,[Windows.FontStretches]::Normal)
  $glyph=$null
  if(!$typeface.TryGetGlyphTypeface([ref]$glyph) -or $glyph.FontUri.LocalPath -notmatch 'ui[/\\]creeperux[/\\]fonts'){throw "Bundled font did not load: $key"}
 }
 Write-Output 'PASS feature radios, mode badge, theme tokens and bundled fonts.'
 # Dialogs run against a temporary copy of the settings files, never the package's own.
 $fixture=Join-Path ([IO.Path]::GetTempPath()) ('ac7-gui-smoke-'+[guid]::NewGuid().ToString('N'))
 New-Item -ItemType Directory -Path $fixture | Out-Null
 try{
  foreach($name in 'MouseAim-Settings.ini','Keybindings.ini'){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $fixture}
  $click=[Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)
  $settings=New-AC7MouseSettingsDialog $fixture $null $script:themeMode ''
  if($settings.Controls.Count -ne @(Get-AC7MouseSettingSpec).Count){throw 'Settings dialog is missing controls'}
  $before=[IO.File]::ReadAllBytes((Join-Path $fixture 'MouseAim-Settings.ini'))
  $settings.Controls.sensitivity.Text='abc';$settings.Save.RaiseEvent($click)
  if($settings.State.Saved -or $settings.Status.Text -notmatch '未保存'){throw 'Invalid sensitivity accepted'}
  $settings.Controls.hud_opacity.Text='2';$settings.Controls.sensitivity.Text='0.25';$settings.Save.RaiseEvent($click)
  if($settings.State.Saved -or $settings.Status.Text -notmatch 'HUD'){throw 'Out-of-range opacity accepted'}
  if([Convert]::ToBase64String($before) -ne [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $fixture 'MouseAim-Settings.ini')))){throw 'Rejected settings changed the file'}
  $settings.Controls.hud_opacity.Text='0.8'
  $settings.Controls.control_mode.SelectedIndex=0;$settings.Controls.hud_boresight.IsChecked=$false
  $settings.Save.RaiseEvent($click)
  $saved=Read-AC7MouseSettings (Join-Path $fixture 'MouseAim-Settings.ini')
  if(!$settings.State.Saved -or $saved.sensitivity -ne 0.25 -or $saved.control_mode -ne 0 -or $saved.hud_boresight -ne 0 -or $saved.hud_opacity -ne 0.8){throw ('Settings save failed: '+$settings.Status.Text)}
  $settings.Window.FindName('RestoreSettings').RaiseEvent($click)
  if($settings.Controls.sensitivity.Text -ne '0.1' -or $settings.Controls.control_mode.SelectedItem.Tag -ne 3 -or !$settings.Controls.hud_boresight.IsChecked){throw 'Settings restore-default failed'}
  Write-Output 'PASS settings dialog: invalid/out-of-range rejection without writing, save/readback, restore defaults.'
  $keys=New-AC7KeybindingsDialog $fixture $null $script:themeMode ''
  if($keys.Buttons.Count -ne 8){throw 'Keybindings dialog is missing actions'}
  $keys.Buttons.free_look.RaiseEvent($click);if($keys.State.Capture -ne 'free_look'){throw 'Capture not armed'}
  Set-AC7CapturedBinding $keys 66;if($keys.State.Values.free_look -ne 'B'){throw 'Key capture not retained'}
  $keys.Save.RaiseEvent($click)
  if(!$keys.State.Saved -or (Read-AC7Keybindings (Join-Path $fixture 'Keybindings.ini')).free_look -ne 'B'){throw ('Keybindings save failed: '+$keys.Status.Text)}
  $keys.Buttons.roll_left.RaiseEvent($click);Set-AC7CapturedBinding $keys 66;if($keys.Save.IsEnabled){throw 'Key conflict did not block save'}
  Write-Output 'PASS keybindings dialog: capture, save/readback through $ctx.Commands, conflict blocks save.'
 }finally{Remove-Item -LiteralPath $fixture -Recurse -Force}
 # Real button, dispatcher timer and asynchronous worker without showing a window.
 $script:controls.GamePath.Text=Join-Path $PSScriptRoot '__missing_game_for_ui_test__'
 $script:smokeFrame=New-Object Windows.Threading.DispatcherFrame
 $timeout=New-Object Windows.Threading.DispatcherTimer
 $timeout.Interval=[TimeSpan]::FromSeconds(20)
 $timeout.Add_Tick({$script:smokeFrame.Continue=$false})
 $timeout.Start()
 $script:controls.Check.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
 if(!$script:worker -or $script:controls.Check.IsEnabled){throw 'GUI did not enter busy state'}
 [Windows.Threading.Dispatcher]::PushFrame($script:smokeFrame)
 $timeout.Stop();$timer.Stop()
 if($script:worker){$script:worker.Stop();$script:worker.Dispose();throw 'GUI worker timeout'}
 if(!$script:controls.Check.IsEnabled -or $script:controls.StatusTitle.Text -ne '操作未完成'){throw 'GUI did not render error and restore controls'}
 Write-Output 'PASS real GUI button, busy state, async dispatcher result and error presentation.'
 exit 0
}
if($RenderPreview){
 if(!$PreviewPath){throw 'RenderPreview requires PreviewPath'}
 if($PreviewPage -eq 'launcher'){
  $script:controls.GamePath.Text='D:\SteamLibrary\steamapps\common\ACE COMBAT 7'
  $script:controls.SteamPath.Text='C:\Program Files (x86)\Steam\steam.exe'
  Set-AC7GuiSelectedFeatures $script:controls 'full'
  Update-AC7GuiModeDescription
  Set-AC7ModeBadge 'enabled'
  Set-AC7GuiStatus '界面预览 · 尚未执行检查' '示例路径仅用于展示。选择实际游戏位置后，可检查环境、安装或切换单人／多人。'
  $content=$script:controls.PreviewRoot
  $content.Width=940;$content.Height=740
  Save-AC7PreviewImage $content 1000 800 $PreviewPath
 }else{
  # Read-only: the dialogs load the package settings but nothing is saved.
  $context=if($PreviewPage -eq 'settings'){New-AC7MouseSettingsDialog $PSScriptRoot $null $script:themeMode 'D:\SteamLibrary\steamapps\common\ACE COMBAT 7'}else{New-AC7KeybindingsDialog $PSScriptRoot $null $script:themeMode ''}
  Set-CreeperUXTheme $window $script:themeMode
  Save-AC7PreviewImage $context.Window.Content ([int]$context.Window.Width) ([int]$context.Window.Height) $PreviewPath
 }
 Write-Output ('GUI preview rendered ('+$PreviewPage+'); no game or configuration changes.')
 exit 0
}
try{
 $script:controls.GamePath.Text=Get-AC7GuiSavedPath $PSScriptRoot 'game-path.txt'
 $script:controls.SteamPath.Text=Get-AC7GuiSavedPath $PSScriptRoot 'steam-path.txt'
 Set-AC7GuiSelectedFeatures $script:controls (Read-AC7FeatureSettings (Join-Path $PSScriptRoot 'features.ini')).Features
 Update-AC7GuiModeDescription
}catch{Set-AC7GuiStatus '读取设置未完成' $_.Exception.Message $false}
# Prevent two GUI instances from writing the same package settings simultaneously.
$sha=[Security.Cryptography.SHA256]::Create()
try{$key=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($PSScriptRoot.ToLowerInvariant()))).Replace('-','')}finally{$sha.Dispose()}
$created=$false;$mutex=New-Object Threading.Mutex($true,('Local\AC7Gui-'+$key),[ref]$created)
if(!$created){[void][Windows.MessageBox]::Show('此整合包的玩家工具已经打开。','AC7');$mutex.Dispose();exit 0}
$script:autoDiscoveryStarted=$false
$window.Add_ContentRendered({if(!$script:autoDiscoveryStarted){$script:autoDiscoveryStarted=$true;Start-AC7GuiWork 'Discover'}})
try{[void]$window.ShowDialog()}finally{$timer.Stop();$mutex.ReleaseMutex();$mutex.Dispose()}

}catch{
 $failure=$_;$diagnostic=''
 try{
  $dir=[IO.Path]::Combine($PSScriptRoot,'diagnostics');[void][IO.Directory]::CreateDirectory($dir)
  $diagnostic=[IO.Path]::Combine($dir,('gui-startup-'+[guid]::NewGuid().ToString('N')+'.txt'))
  [IO.File]::WriteAllText($diagnostic,($failure.ToString()+[Environment]::NewLine+$failure.ScriptStackTrace),[Text.UTF8Encoding]::new($true))
 }catch{}
 $message='玩家工具未能启动：'+$failure.Exception.Message
 if($diagnostic){$message+=[Environment]::NewLine+'诊断文件：'+$diagnostic}
 [Console]::Error.WriteLine($message)
 if(!$NoDialog){
  try{
   [void][Reflection.Assembly]::Load('PresentationFramework, Version=4.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35')
   [void][Windows.MessageBox]::Show($message,'AC7 启动失败')
  }catch{}
 }
 exit 1
}
