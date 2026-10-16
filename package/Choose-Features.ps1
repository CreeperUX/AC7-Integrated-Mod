$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Install-Common.ps1')
. (Join-Path $PSScriptRoot 'Feature-Settings.ps1')
$file=Get-AC7DataFile $PSScriptRoot 'features.ini';$previous=Read-AC7FeatureSettings $file
$default=switch($previous.Features){'mouse'{'1'} 'guidance'{'2'} default{'3'}}
Write-Host '1. 仅鼠标飞控 / Mouse aim only'
Write-Host ('   '+(Get-AC7FeatureDescription 'mouse'))
Write-Host '2. 鼠标飞控 + 导弹仅制导 / Mouse aim + missile guidance lead only'
Write-Host ('   '+(Get-AC7FeatureDescription 'guidance'))
Write-Host '3. 鼠标飞控 + 导弹完整强化 / Mouse aim + full AC8 missile rules'
Write-Host ('   '+(Get-AC7FeatureDescription 'full'))
while($true){
 $choice=Read-Host "输入 1、2 或 3（回车保留 $default；Q 取消）"
 if(!$choice){$choice=$default}
 if($choice -in @('1','2','3')){break}
 if($choice -ieq 'Q'){Stop-AC7Problem 'CANCELLED' '已取消选择，设置未更改。' '需要时重新运行 Choose-Features.cmd。'}
 Write-Host '请输入 1、2 或 3，设置尚未更改。' -ForegroundColor Yellow
}
$value=switch($choice){'1'{'mouse'} '2'{'guidance'} default{'full'}}
Save-AC7FeatureSettings $PSScriptRoot $value
Write-Host ('已保存：'+(Get-AC7FeatureLabel $value)+'。下次“安装／更新”时生效。')
