$ErrorActionPreference='Stop'
# Launcher fits without scrolling: key controls stay inside the fitted root in both themes, several window sizes,
# with candidate lists shown and a long status message.
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$package=Split-Path $PSScriptRoot -Parent
. (Join-Path $package 'CreeperUX-Theme.ps1')
$xml=[xml](Get-Content -LiteralPath (Join-Path $package 'Launcher-GUI.xaml') -Raw -Encoding UTF8)
$manager=New-Object Xml.XmlNamespaceManager($xml.NameTable)
$manager.AddNamespace('w','http://schemas.microsoft.com/winfx/2006/xaml/presentation')
if($xml.SelectNodes('//w:ScrollViewer[@Grid.Row="1"]',$manager).Count){throw 'Main-page scrolling returned'}
$cases=0
foreach($theme in 'dark','light'){
 foreach($size in @(@(1040,800),@(880,660),@(760,500),@(1280,800))){
  foreach($expanded in $false,$true){
   $window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xml))
   Set-CreeperUXTheme $window $theme
   $root=$window.FindName('PreviewRoot')
   if($root -isnot [Windows.Controls.Viewbox]){throw 'Expected fitted, non-scrolling root'}
   if($expanded){
    foreach($name in 'GameCandidates','SteamCandidates'){$window.FindName($name).Visibility='Visible'}
    $window.FindName('StatusMessage').Text=('环境检查未通过。请选择另一个目录后重试。'*8)
    $window.FindName('ModeDescription').Text=('另启用 AC7Weapons 的“完整强化”档：按 AC8 规则调整玩家导弹参数。'*3)
   }
   $root.Measure([Windows.Size]::new($size[0],$size[1]))
   $root.Arrange([Windows.Rect]::new(0,0,$size[0],$size[1]));$root.UpdateLayout()
   foreach($name in 'Install','Start','DisableMod','EnableMod','Settings','Keybindings','CollectLogs','Recover','OpenLogs','StatusMessage','ThemeToggle','ModeBadge'){
    $control=$window.FindName($name)
    $rect=$control.TransformToAncestor($root).TransformBounds([Windows.Rect]::new(0,0,$control.ActualWidth,$control.ActualHeight))
    if($rect.Width -le 0 -or $rect.Height -le 0 -or $rect.X -lt -1 -or $rect.Y -lt -1 -or $rect.Right -gt $root.ActualWidth+1 -or $rect.Bottom -gt $root.ActualHeight+1){throw "Clipped control: $theme $size $expanded $name"}
   }
   $cases++
  }
 }
}
Write-Host "PASS $cases no-scroll layouts: both themes, window sizes, multiple candidates and long status messages."
exit 0
