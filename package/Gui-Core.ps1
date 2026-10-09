. (Join-Path $PSScriptRoot 'Cleanup-Core.ps1')
. (Join-Path $PSScriptRoot 'Discover-Installations.ps1')
function Get-AC7GuiSavedPath([string]$Root,[string]$Name){
 $path=Join-Path $Root $Name
 if(Test-Path -LiteralPath $path -PathType Leaf){$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8;if($null -ne $text){return $text.Trim()}}
 return ''
}
# game-path.txt, steam-path.txt and features.ini change together or not at all.
function Save-AC7GuiSettings([string]$Root,[string]$GameRoot,[string]$Steam,[ValidateSet('mouse','guidance','full','weapons')][string]$Features){
 $values=[ordered]@{
  'game-path.txt'=$GameRoot
  'steam-path.txt'=$Steam
  'features.ini'=(Get-AC7FeatureSettingsText $Features)
 }
 $original=@{};$temporary=@{}
 try {
  foreach($name in $values.Keys){
   $path=Join-Path $Root $name
   $exists=Test-Path -LiteralPath $path
   $original[$name]=[pscustomobject]@{Exists=$exists;Content=$(if($exists){[Convert]::ToBase64String([IO.File]::ReadAllBytes($path))}else{''})}
   $temporary[$name]=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
   [IO.File]::WriteAllText($temporary[$name],[string]$values[$name]+"`r`n",[Text.UTF8Encoding]::new($false))
  }
  foreach($name in $values.Keys){Move-Item -LiteralPath $temporary[$name] -Destination (Join-Path $Root $name) -Force}
 }catch{
  foreach($name in $original.Keys){
   $path=Join-Path $Root $name
   if($original[$name].Exists){[IO.File]::WriteAllBytes($path,[Convert]::FromBase64String([string]$original[$name].Content))}
   elseif(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}
  }
  throw
 }finally{foreach($path in $temporary.Values){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}}}
}
function New-AC7GuiResult([bool]$Success,[string]$Title,[string]$Message,[string]$GameRoot,[string]$ModState){
 return [pscustomobject]@{Success=$Success;Title=$Title;Message=$Message;GameRoot=$GameRoot;SteamPath=$null;ModState=$ModState;OpenFolder=$null}
}
function Invoke-AC7GuiAction {
 param([ValidateSet('Discover','Check','Install','Disable','Enable','Start','Recover','Collect')][string]$Action,[string]$Root,[string]$GamePath,[string]$SteamPath,[ValidateSet('mouse','guidance','full','weapons')][string]$Features='full',[bool]$Confirmed=$false)
 $Features=ConvertTo-AC7Features $Features
 if($Action -eq 'Discover'){
  $found=Find-AC7Installations -GamePath $GamePath -SteamPath $SteamPath
  $result=[pscustomobject]@{Success=$true;Title='自动定位完成';Message='未能唯一确定位置。请选择下方候选，或使用浏览按钮手动选择。';GameRoot=$found.GamePath;SteamPath=$found.SteamPath;GameCandidates=@($found.GameCandidates);SteamCandidates=@($found.SteamCandidates);ModState=$null;OpenFolder=$null}
  if($found.GamePath){
   try{
    $checked=Invoke-AC7GuiAction Check $Root $found.GamePath $found.SteamPath $Features
    $result.Title='环境检查完成';$result.Message=$checked.Message;$result.GameRoot=$checked.GameRoot;$result.ModState=$checked.ModState
   }catch{
    $result.Success=$false;$result.Title='定位完成，环境检查未通过'
    $result.Message=$_.Exception.Message+' '+[string]$_.Exception.Data['AC7Hint']
   }
  }
  if($found.Warnings.Count){$result.Message+=' '+($found.Warnings -join ' ')}
  return $result
 }
 $game=Resolve-AC7GameRoot $GamePath
 Assert-AC7PackageLocation $Root $game
 Assert-AC7NoLinks $game
 $steam=([string]$SteamPath).Trim().Trim('"')
 switch($Action){
  'Check'{
   $info=Test-AC7Package $Root
   $build='游戏版本校验通过（Steam Build '+$info.game_build+'）。'
   try{Assert-AC7GameBuild $Root $game}catch{$build=[string]$_.Exception.Message+' '+[string]$_.Exception.Data['AC7Hint']}
   $state=Get-AC7InstallState $game
   $message=$build+' '+(Format-AC7StateText $state)
   if(Test-AC7GameRunning $game){$message+=' 游戏正在运行，安装、切换和清理需要先退出游戏。'}
   elseif(!$state.Installed -and !@($state.UnownedLoader).Count){$message+=' 选择安装内容后点击“安装／更新”。'}
   elseif($state.Installed -and $state.Foreign){$message+=' 点击“安装／更新”可接管并更新到本包版本（先备份）。'}
   if($state.Installed -and $state.Features -and $state.Features -ne $Features){$message+=' 当前所选安装内容（'+(Get-AC7FeatureLabel $Features)+'）与已安装的不同，安装／更新时会按所选调整。'}
   return New-AC7GuiResult $true '检查完成' $message $game $state.Mode
  }
  'Install'{
   if(!$Confirmed){Stop-AC7Problem 'CONFIRM_REQUIRED' '安装尚未确认。' '请在确认窗口中点击“安装／更新”。'}
   Assert-AC7WriteAccess $Root
   $summary=Invoke-AC7Install -PackageRoot $Root -GameRoot $game -Features $Features
   Save-AC7GuiSettings $Root $game $steam $Features
   return New-AC7GuiResult $true '安装完成' (Format-AC7InstallSummary $summary) $game $summary.Mode
  }
  'Disable'{
   $mode=Set-AC7ModMode -PackageRoot $Root -GameRoot $game -Action Disable
   return New-AC7GuiResult $true $(if($mode.Changed){'Mod 已停用'}else{'无需停用'}) $mode.Message $game $mode.Mode
  }
  'Enable'{
   $mode=Set-AC7ModMode -PackageRoot $Root -GameRoot $game -Action Enable
   return New-AC7GuiResult $true $(if($mode.Changed){'Mod 已启用'}else{'无需启用'}) $mode.Message $game $mode.Mode
  }
  'Start'{
   $started=Start-AC7ViaSteam $Root $game $steam
   return New-AC7GuiResult $true '已发送启动请求' $started.Message $game $started.Mode
  }
  'Recover'{
   if(!$Confirmed){Stop-AC7Problem 'CONFIRM_REQUIRED' '卸载尚未确认。' '请先确认要卸载的是本工具安装的 Mod。'}
   $cleanup=Invoke-AC7Cleanup -PackageRoot $Root -GameRoot $game -Confirmed
   $state=Get-AC7InstallState $game
   $result=New-AC7GuiResult (!@($cleanup.Retained | Where-Object {$_ -ieq 'dwmapi.dll'}).Count) $(if($cleanup.Retained.Count){'卸载部分完成'}else{'卸载完成'}) $cleanup.Message $game $state.Mode
   return $result
  }
  'Collect'{
   $collected=Invoke-AC7CollectLogs $Root $game
   $result=New-AC7GuiResult $true '日志已收集' ('已复制 '+$collected.Copied.Count+' 项运行记录到 '+$collected.Folder+'。概要见 summary.txt；反馈问题时请附上整个文件夹。') $game $null
   $result.OpenFolder=$collected.Folder
   return $result
  }
 }
}
function Get-AC7GuiSelectedFeatures($Controls){
 if($Controls.WithWeapons.IsChecked){return 'full'}
 if($Controls.GuidanceOnly.IsChecked){return 'guidance'}
 if($Controls.MouseOnly.IsChecked){return 'mouse'}
 Stop-AC7Problem 'FEATURES_REQUIRED' '请选择安装内容。' '三种选择都包含鼠标飞控。'
}
function Set-AC7GuiSelectedFeatures($Controls,[ValidateSet('mouse','guidance','full','weapons')][string]$Features){
 $Features=ConvertTo-AC7Features $Features
 $Controls.MouseOnly.IsChecked=($Features -eq 'mouse')
 $Controls.GuidanceOnly.IsChecked=($Features -eq 'guidance')
 $Controls.WithWeapons.IsChecked=($Features -eq 'full')
}
