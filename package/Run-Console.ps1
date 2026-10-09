param([ValidateSet('Setup','Start','Enable','Disable','Status','Recover','Features','Analyze','Check')][string]$Action)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Install-Common.ps1')
try {
 switch($Action){
  'Setup' {& (Join-Path $PSScriptRoot 'Setup.ps1')}
  'Start' {& (Join-Path $PSScriptRoot 'Launch-AC7-via-Steam.ps1')}
  'Enable' {& (Join-Path $PSScriptRoot 'Mod-Mode.ps1') -Action Enable}
  'Disable' {& (Join-Path $PSScriptRoot 'Mod-Mode.ps1') -Action Disable}
  'Status' {& (Join-Path $PSScriptRoot 'Mod-Mode.ps1') -Action Status}
  'Recover' {& (Join-Path $PSScriptRoot 'Recover-Cleanup.ps1') -Interactive}
  'Features' {& (Join-Path $PSScriptRoot 'Choose-Features.ps1')}
  'Analyze' {& (Join-Path $PSScriptRoot 'Analyze-Latest.ps1')}
  'Check' {& (Join-Path $PSScriptRoot 'Check-Package.ps1')}
 }
 exit 0
}catch{
 $stage=switch($Action){'Setup'{'安装'} 'Start'{'启动'} 'Enable'{'启用 Mod'} 'Disable'{'停用 Mod'} 'Status'{'查看状态'} 'Recover'{'卸载'} 'Features'{'选择安装内容'} 'Analyze'{'收集日志'} default{'检查'}}
 Show-AC7Problem $_ $PSScriptRoot $stage;exit 1
}
