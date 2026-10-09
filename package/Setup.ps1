param([string]$GameRoot,[ValidateSet('','mouse','guidance','full','weapons')][string]$Features='',[switch]$Yes,[string]$SaveRoot,[switch]$CheckOnly,[switch]$TestOnlySkipExeHash)
# Console install/update. Interactive by default; -GameRoot/-Features/-Yes run it without prompts.
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
. (Join-Path $root 'Install-Core.ps1')
. (Join-Path $root 'Discover-Installations.ps1')
Write-Host 'AC7 安装向导：安装或更新鼠标飞控。仅限单人游戏，多人对战前请先停用 Mod。'
if(!$GameRoot){
 $saved=Get-AC7SavedText $root 'game-path.txt'
 if(!$saved){try{$found=Find-AC7Installations '' (Get-AC7SavedText $root 'steam-path.txt');if($found.GamePath){$saved=$found.GamePath}}catch{}}
 if($Yes){$GameRoot=$saved}
 else{
  while($true){
   $prompt=if($saved){"游戏路径（回车使用 $saved；输入 Q 取消）"}else{'粘贴游戏路径（包含 Ace7Game.exe 的文件夹，可带引号；输入 Q 取消）'}
   $inputPath=Read-Host $prompt
   if($inputPath.Trim() -ieq 'Q'){Stop-AC7Problem 'CANCELLED' '已取消安装。' '准备好游戏路径后可重新运行 Setup.cmd。'}
   if(!$inputPath.Trim()){$inputPath=$saved}
   try{$GameRoot=Resolve-AC7GameRoot $inputPath;break}catch{
    if($_.Exception.Data['AC7Code'] -ne 'GAME_PATH'){throw}
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Write-Host $_.Exception.Data['AC7Hint']
   }
  }
 }
}
$game=Resolve-AC7GameRoot $GameRoot
Write-Host "游戏根目录：$game"
Write-Host (Format-AC7StateText (Get-AC7InstallState $game))
if(!$Features){
 if(!$Yes){& (Join-Path $root 'Choose-Features.ps1')}
 $Features=(Read-AC7FeatureSettings (Join-Path $root 'features.ini')).Features
}
$Features=ConvertTo-AC7Features $Features   # 0.5.x 'weapons' = full
$plan=Invoke-AC7Install -PackageRoot $root -GameRoot $game -Features $Features -SaveRoot $SaveRoot -CheckOnly -TestOnlySkipExeHash:$TestOnlySkipExeHash
$action=if($plan.Adopted){'接管并更新'}elseif($plan.WasInstalled){'更新'}else{'全新安装'}
Write-Host ("计划：{0}，{1}；新增 {2}、更新 {3}、移除 {4} 个文件。" -f $action,(Get-AC7FeatureLabel $Features),$plan.New,$plan.Updated,$plan.Removed)
if($CheckOnly){Write-Host 'INSTALL CHECK passed. No files changed.';return}
if(!$Yes){
 Write-Host '开始前会备份存档与原有 Mod 文件；发现不属于本工具的加载器或被修改的文件会停止，不覆盖。'
 if((Read-Host '输入 Y 开始安装（其他任意键取消）') -notin @('Y','y')){Stop-AC7Problem 'CANCELLED' '已取消安装，未修改任何文件。' '需要时重新运行 Setup.cmd。'}
}
$summary=Invoke-AC7Install -PackageRoot $root -GameRoot $game -Features $Features -SaveRoot $SaveRoot -TestOnlySkipExeHash:$TestOnlySkipExeHash
Write-AC7TextAtomic (Join-Path $root 'game-path.txt') ($game+"`r`n")
Save-AC7FeatureSettings $root $Features
Write-Host (Format-AC7InstallSummary $summary) -ForegroundColor Green
Write-Output ('INSTALLED features='+$Features+' mode='+$summary.Mode+' new='+$summary.New+' updated='+$summary.Updated+' removed='+$summary.Removed)
