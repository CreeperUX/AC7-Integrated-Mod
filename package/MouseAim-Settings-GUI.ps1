. (Join-Path $PSScriptRoot 'Install-Core.ps1')
function Set-AC7SettingControlValue($Control,$Spec,[double]$Value) {
 switch($Spec.Kind){
  'bool'{$Control.IsChecked=($Value -ne 0)}
  'choice'{foreach($item in $Control.Items){if([double]$item.Tag -eq $Value){$Control.SelectedItem=$item}}}
  default{$Control.Text=Format-AC7Number $Value}
 }
}
function Get-AC7SettingControlValues($Context) {
 $values=[ordered]@{}
 foreach($spec in Get-AC7MouseSettingSpec){
  $control=$Context.Controls[$spec.Name]
  if(!$control){$values[$spec.Name]=[double]$Context.Values[$spec.Name];continue}
  switch($spec.Kind){
   'bool'{$values[$spec.Name]=if($control.IsChecked){1.0}else{0.0}}
   'choice'{if(!$control.SelectedItem){throw "请选择：$($spec.Label)。"};$values[$spec.Name]=[double]$control.SelectedItem.Tag}
   default{$values[$spec.Name]=ConvertFrom-AC7MouseText $spec.Name ([string]$control.Text)}
  }
 }
 Assert-AC7MouseSettings $values
 return $values
}
# Save to the package, then write the installed config.ini / camera-settings.lua when it is safe to do so.
function Save-AC7MouseSettingsFromDialog([string]$Root,$Values,[string]$GameRoot) {
 Save-AC7MouseSettings $Root $Values $GameRoot
 $sync=Sync-AC7GameConfig $Root $GameRoot
 if($sync.Applied){return '已保存，并写入游戏中的 config.ini，下次启动生效。原设置备份为 MouseAim-Settings.ini.bak。'}
 return '已保存到本包：'+$sync.Message
}
function New-AC7MouseSettingsDialog([string]$Root,$Owner,[ValidateSet('dark','light')][string]$Theme='dark',[string]$GameRoot='') {
 Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
 $xml=[xml](Get-Content -LiteralPath (Join-Path $PSScriptRoot 'MouseAim-Settings-GUI.xaml') -Raw -Encoding UTF8)
 $dialog=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xml));if($Owner){$dialog.Owner=$Owner}
 Set-CreeperUXTheme $dialog $Theme
 if(Get-Command Set-AC7WindowIcon -ErrorAction SilentlyContinue){Set-AC7WindowIcon $dialog}
 $area=[Windows.SystemParameters]::WorkArea;$dialog.Width=[Math]::Min($dialog.Width,$area.Width-24);$dialog.Height=[Math]::Min($dialog.Height,$area.Height-24);$dialog.MinWidth=[Math]::Min($dialog.MinWidth,$dialog.Width);$dialog.MinHeight=[Math]::Min($dialog.MinHeight,$dialog.Height)
 $values=Read-AC7MouseSettings (Get-AC7DataFile $Root 'MouseAim-Settings.ini')
 # Closures resolve commands only at global scope (see Keybindings-GUI.ps1): carry function references on the context.
 $commands=@{Collect=${function:Get-AC7SettingControlValues};Save=${function:Save-AC7MouseSettingsFromDialog};Defaults=${function:Get-AC7DefaultMouseSettings};Spec=${function:Get-AC7MouseSettingSpec};SetValue=${function:Set-AC7SettingControlValue}}
 $ctx=[pscustomobject]@{Window=$dialog;State=@{Saved=$false;Message=''};Controls=@{};Status=$dialog.FindName('SettingsStatus');Save=$dialog.FindName('SaveSettings');Root=$Root;GameRoot=$GameRoot;Values=$values;Commands=$commands}
 $groups=@{control='ControlRows';camera='CameraRows';hud='HudRows';assist='AssistRows'}
 foreach($spec in Get-AC7MouseSettingSpec){
  if(!$groups.ContainsKey($spec.Group)){continue}   # launcher-only rows (flight_recording)
  $row=[Windows.Controls.Grid]::new();$row.Margin=[Windows.Thickness]::new(0,0,0,10)
  $column=[Windows.Controls.ColumnDefinition]::new();$column.Width=[Windows.GridLength]::new(1,[Windows.GridUnitType]::Star);[void]$row.ColumnDefinitions.Add($column)
  $column=[Windows.Controls.ColumnDefinition]::new();$column.Width=[Windows.GridLength]::new(156);[void]$row.ColumnDefinitions.Add($column)
  $text=[Windows.Controls.StackPanel]::new();$text.Margin=[Windows.Thickness]::new(0,0,10,0);$text.VerticalAlignment='Center'
  $label=[Windows.Controls.TextBlock]::new();$label.Text=$spec.Label;$label.TextWrapping='Wrap';[void]$text.Children.Add($label)
  $hint=[Windows.Controls.TextBlock]::new();$hint.FontSize=11;$hint.TextWrapping='Wrap';$hint.Margin=[Windows.Thickness]::new(0,2,0,0)
  $hint.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,'CxQuiet')
  $hint.Text=if($spec.Kind -in @('number','int')){'范围 '+(Format-AC7Number $spec.Min)+'–'+(Format-AC7Number $spec.Max)+' · '+$spec.Hint}else{$spec.Hint}
  [void]$text.Children.Add($hint);[void]$row.Children.Add($text)
  switch($spec.Kind){
   'bool'{$control=[Windows.Controls.CheckBox]::new();$control.Content='开启'}
   'choice'{$control=[Windows.Controls.ComboBox]::new();foreach($choice in $spec.Choices){$item=[Windows.Controls.ComboBoxItem]::new();$item.Content=$choice.Label;$item.Tag=[double]$choice.Value;[void]$control.Items.Add($item)}}
   default{$control=[Windows.Controls.TextBox]::new()}
  }
  $control.VerticalAlignment='Center'
  [Windows.Automation.AutomationProperties]::SetName($control,$spec.Label)
  [Windows.Controls.Grid]::SetColumn($control,1);[void]$row.Children.Add($control)
  Set-AC7SettingControlValue $control $spec ([double]$values[$spec.Name])
  $ctx.Controls[$spec.Name]=$control
  [void]$dialog.FindName($groups[$spec.Group]).Children.Add($row)
 }
 $dialog.FindName('TargetInfo').Text=if($GameRoot){'保存到本包的 MouseAim-Settings.ini，并在已安装时写入游戏：'+$GameRoot+'\ue4ss\Mods\AC7MouseAim\config.ini。'}else{'未选择游戏位置：只保存到本包的 MouseAim-Settings.ini，安装或更新时写入游戏。'}
 $dialog.FindName('RestoreSettings').Add_Click({
  $defaults=& $ctx.Commands.Defaults
  foreach($spec in (& $ctx.Commands.Spec)){if($ctx.Controls[$spec.Name]){& $ctx.Commands.SetValue $ctx.Controls[$spec.Name] $spec ([double]$defaults[$spec.Name])}}
  $ctx.Status.Text='已恢复默认；点击保存应用，或取消放弃。'
 }.GetNewClosure())
 $dialog.FindName('CancelSettings').Add_Click({$ctx.Window.Close()}.GetNewClosure())
 $ctx.Save.Add_Click({
  try{
   $collected=& $ctx.Commands.Collect $ctx
   $message=& $ctx.Commands.Save $ctx.Root $collected $ctx.GameRoot
   $ctx.State.Saved=$true;$ctx.State.Message=$message;$ctx.Status.Text=$message
  }catch{$ctx.Status.Text='未保存：'+$_.Exception.Message+' '+[string]$_.Exception.Data['AC7Hint']}
 }.GetNewClosure())
 return $ctx
}
function Show-AC7MouseSettingsDialog([string]$Root,$Owner,[string]$Theme='dark',[string]$GameRoot='') {
 $context=New-AC7MouseSettingsDialog $Root $Owner $Theme $GameRoot
 [void]$context.Window.ShowDialog();return $context.State
}
