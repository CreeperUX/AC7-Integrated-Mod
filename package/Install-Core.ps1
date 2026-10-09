. ([IO.Path]::Combine($PSScriptRoot,'Install-Common.ps1'))
. ([IO.Path]::Combine($PSScriptRoot,'Feature-Settings.ps1'))
. ([IO.Path]::Combine($PSScriptRoot,'MouseAim-Settings.ps1'))
. ([IO.Path]::Combine($PSScriptRoot,'Keybinding-Settings.ps1'))
# Persistent AC7 install with an ownership manifest (ue4ss\AC7-MouseAim-owner.json, compatible superset of the
# Codex Deploy.ps1 format). Safety model: never overwrite or delete a file whose hash is not recorded as ours;
# validate everything before the first write; back up and journal before changing the game folder.
function Get-AC7Layout {
 return [pscustomobject]@{
  Manifest='ue4ss\AC7-MouseAim-owner.json'
  Pending='ue4ss\AC7-MouseAim-pending.json'
  Loader='dwmapi.dll'
  DisabledLoader='ue4ss\dwmapi.dll.disabled'
  Runtime='ue4ss\UE4SS.dll'
  ModsList='ue4ss\Mods\mods.txt'
  Config='ue4ss\Mods\AC7MouseAim\config.ini'
  CameraSettings='ue4ss\Mods\AC7MouseAim\Scripts\camera-settings.lua'
  WeaponsPrefix='ue4ss\Mods\AC7Weapons\'
  WeaponsSettings='ue4ss\Mods\AC7Weapons\Scripts\settings.lua'
  Tool='AC7-Integrated'
 }
}
function ConvertTo-AC7Relative([string]$Relative) {
 $value=([string]$Relative).Trim().Replace('/','\')
 if(!$value -or [IO.Path]::IsPathRooted($value) -or $value.Contains(':') -or $value.StartsWith('\')){throw "Unsafe manifest path: $Relative"}
 foreach($segment in $value.Split('\')){if(!$segment -or $segment -eq '.' -or $segment -eq '..'){throw "Unsafe manifest path: $Relative"}}
 if($value -ine 'dwmapi.dll' -and !$value.StartsWith('ue4ss\',[StringComparison]::OrdinalIgnoreCase)){throw "Manifest path outside the loader area: $Relative"}
 return $value
}
function Get-AC7Target([string]$GameRoot,[string]$Relative) {
 $game=[IO.Path]::GetFullPath($GameRoot).TrimEnd('\','/')
 $target=[IO.Path]::GetFullPath((Join-Path $game (ConvertTo-AC7Relative $Relative)))
 if(!$target.StartsWith($game+'\',[StringComparison]::OrdinalIgnoreCase)){throw "Manifest path escaped the game folder: $Relative"}
 return $target
}
function Get-AC7CurrentHash([string]$Path) {
 if(Test-Path -LiteralPath $Path -PathType Leaf){return (Get-AC7FileHash -LiteralPath $Path).Hash}
 if(Test-Path -LiteralPath $Path){return '<directory>'}
 return $null
}
# Read-only snapshot of the loader area. Hashes every recorded file; never writes.
function Get-AC7InstallState([string]$GameRoot) {
 $layout=Get-AC7Layout
 $game=[IO.Path]::GetFullPath($GameRoot).TrimEnd('\','/')
 $ue4ss=Join-Path $game 'ue4ss'
 if(Test-Path -LiteralPath $ue4ss){Assert-AC7NoLinks $ue4ss -Tree}
 foreach($relative in $layout.Loader,$layout.DisabledLoader){$path=Join-Path $game $relative;if(Test-Path -LiteralPath $path){Assert-AC7NoLinks $path}}
 $state=[pscustomobject]@{GameRoot=$game;Manifest=$null;Pending=$null;Installed=$false;Foreign=$false;Project=$null;Version=$null;Features=$null;Mode='none';Entries=@();Changed=@();Missing=@();UnownedLoader=@();OtherMods=@();OtherLoaders=@()}
 $pendingPath=Join-Path $game $layout.Pending
 if(Test-Path -LiteralPath $pendingPath -PathType Leaf){$state.Pending=Read-AC7Json $pendingPath}
 $manifestPath=Join-Path $game $layout.Manifest
 $loaderPath=Join-Path $game $layout.Loader;$disabledPath=Join-Path $game $layout.DisabledLoader
 if(Test-Path -LiteralPath $manifestPath -PathType Leaf){
  $manifest=Read-AC7Json $manifestPath
  $state.Manifest=$manifest;$state.Installed=$true
  $entries=@()
  try{
   $files=@($manifest.Files)
   if(!$files.Count){throw 'the record lists no files'}
   $seen=@{};$loaders=0
   foreach($file in $files){
    $relative=ConvertTo-AC7Relative ([string]$file.Relative)
    $sha=([string]$file.SHA256).ToUpperInvariant()
    if($sha -notmatch '^[0-9A-F]{64}$'){throw "invalid hash for $relative"}
    $isLoader=($relative -ieq $layout.Loader -or $relative -ieq $layout.DisabledLoader)
    $key=if($isLoader){'<loader>'}else{$relative.ToUpperInvariant()}
    if($seen.ContainsKey($key)){throw "duplicate entry $relative"};$seen[$key]=$true
    if($isLoader){$loaders++}
    $entries+=[pscustomobject]@{Relative=$relative;SHA256=$sha;Actual=$relative;Status='missing';Loader=$isLoader}
   }
   if($loaders -ne 1){throw 'the record must list exactly one dwmapi.dll loader'}
  }catch{
   if($_.Exception.Data['AC7Code']){throw}
   Stop-AC7Problem 'MANIFEST_INVALID' ('安装记录无法识别：'+$_.Exception.Message) '未修改任何文件。请保留 ue4ss\AC7-MouseAim-owner.json 以便核对；不要直接删除不明 DLL。'
  }
  $state.Mode='missing'
  foreach($entry in $entries){
   if($entry.Loader){
    # The loader may sit at dwmapi.dll (enabled) or ue4ss\dwmapi.dll.disabled (disabled); the actual location wins.
    $rootHash=Get-AC7CurrentHash $loaderPath;$offHash=Get-AC7CurrentHash $disabledPath
    if($rootHash -eq $entry.SHA256){$entry.Actual=$layout.Loader;$entry.Status='ok';$state.Mode='enabled';if($offHash){$state.UnownedLoader+=$layout.DisabledLoader}}
    elseif($offHash -eq $entry.SHA256){$entry.Actual=$layout.DisabledLoader;$entry.Status='ok';$state.Mode='disabled';if($rootHash){$state.UnownedLoader+=$layout.Loader}}
    elseif($rootHash){$entry.Actual=$layout.Loader;$entry.Status='changed';$state.Mode='enabled'}
    elseif($offHash){$entry.Actual=$layout.DisabledLoader;$entry.Status='changed';$state.Mode='disabled'}
   }else{
    $current=Get-AC7CurrentHash (Get-AC7Target $game $entry.Relative)
    if($current -eq $entry.SHA256){$entry.Status='ok'}elseif($current){$entry.Status='changed'}
   }
  }
  $state.Entries=$entries
  $state.Changed=@($entries | Where-Object Status -eq 'changed' | ForEach-Object Actual)
  $state.Missing=@($entries | Where-Object Status -eq 'missing' | ForEach-Object Relative)
  $state.Project=[string]$manifest.Project
  $state.Foreign=([string]$manifest.Tool -ne $layout.Tool)
  $state.Version=if($manifest.Version){'AC7 '+[string]$manifest.Version}elseif($manifest.ClaudeStage -and $manifest.ClaudeStage.Version){[string]$manifest.ClaudeStage.Version}else{'Codex AC7 0.4.x'}
  $state.Features=if([string]$manifest.Features -in @('mouse','guidance','full','weapons')){ConvertTo-AC7Features ([string]$manifest.Features)}elseif(@($entries | Where-Object {$_.Relative.StartsWith($layout.WeaponsPrefix,[StringComparison]::OrdinalIgnoreCase)}).Count){'full'}else{'mouse'}
  if(!@($entries | Where-Object {$_.Relative -ieq $layout.Runtime}).Count -and (Test-Path -LiteralPath (Join-Path $game $layout.Runtime))){$state.UnownedLoader+=$layout.Runtime}
 }else{
  foreach($relative in $layout.Loader,$layout.DisabledLoader,$layout.Runtime){if(Test-Path -LiteralPath (Join-Path $game $relative)){$state.UnownedLoader+=$relative}}
 }
 $mods=Join-Path $game 'ue4ss\Mods'
 if(Test-Path -LiteralPath $mods -PathType Container){$state.OtherMods=@(Get-ChildItem -LiteralPath $mods -Directory -Force | Where-Object {$_.Name -notin @('AC7MouseAim','AC7Weapons')} | ForEach-Object Name)}
 $state.OtherLoaders=@('dinput8.dll','xinput1_3.dll','xinput1_4.dll','version.dll','winmm.dll' | Where-Object {Test-Path -LiteralPath (Join-Path $game $_)})
 return $state
}
function Assert-AC7StateUsable($State,[switch]$LoaderOnly) {
 if($State.Pending){Stop-AC7Problem 'PENDING' '上一次安装或更新没有完成。' '请点击“卸载（备份并清理）”或运行 Recover-Cleanup.cmd：会先回滚未完成的操作，只处理能校验的文件。'}
 if(@($State.UnownedLoader).Count){Stop-AC7Problem 'UNOWNED_LOADER' ('游戏目录中有不属于本工具的加载器文件：'+(@($State.UnownedLoader) -join '、')+'。') '可能来自其他 Mod 或手动复制。为避免覆盖，未修改任何文件。请先卸载那个 Mod 或手动移走这些文件再重试；不要直接删除不明 DLL。'}
 $changed=@($State.Entries | Where-Object Status -eq 'changed');$missing=@($State.Entries | Where-Object Status -eq 'missing')
 if($LoaderOnly){$changed=@($changed | Where-Object Loader);$missing=@($missing | Where-Object Loader)}
 if($changed.Count){Stop-AC7Problem 'MODIFIED' ('以下已安装文件被修改过：'+(($changed | ForEach-Object Actual) -join '、')+'。') '为避免覆盖你的修改，未修改任何文件。若是手动改了 config.ini，请记下数值后在“飞控设置”中填写，再把文件恢复原样或移走（可先备份）。也可用“卸载（备份并清理）”：备份后只删除校验一致的文件，被修改的文件保留。'}
 if($missing.Count){Stop-AC7Problem 'MISSING' ('以下已安装文件缺失：'+(($missing | ForEach-Object Relative) -join '、')+'。') '可能被手动删除或移动（例如为联机手动移走了 dwmapi.dll）。请先用“卸载（备份并清理）”整理，再重新安装；联机前请使用“停用 Mod”。'}
}
function Format-AC7StateText($State) {
 $parts=@()
 if(!$State.Installed){
  if(@($State.UnownedLoader).Count){$parts+=('检测到不属于本工具的加载器：'+(@($State.UnownedLoader) -join '、')+'。')}else{$parts+='尚未安装本 Mod（原版状态）。'}
 }else{
  $source=if($State.Foreign){'由其他工具部署（'+$State.Version+'）'}else{$State.Version}
  $mode=switch($State.Mode){'enabled'{'Mod 已启用（仅限单人）'} 'disabled'{'Mod 已停用（原版启动，可联机）'} default{'加载器缺失'}}
  $parts+=('已安装：'+$source+'，'+(Get-AC7FeatureLabel $State.Features)+'；'+$mode+'。')
  if(@($State.UnownedLoader).Count){$parts+=('另有不属于本工具的加载器：'+(@($State.UnownedLoader) -join '、')+'。')}
  if(@($State.Changed).Count){$parts+=('已被修改：'+(@($State.Changed) -join '、')+'。')}
  if(@($State.Missing).Count){$parts+=('缺失：'+(@($State.Missing) -join '、')+'。')}
 }
 if($State.Pending){$parts+='有未完成的安装操作，需要先“卸载（备份并清理）”回滚。'}
 if(@($State.OtherMods).Count){$parts+=('ue4ss\Mods 中另有其他文件夹（本工具不管理）：'+(@($State.OtherMods) -join '、')+'。')}
 if(@($State.OtherLoaders).Count){$parts+=('游戏目录中另有可能的其他 Mod 加载器：'+(@($State.OtherLoaders) -join '、')+'，联机前请一并确认。')}
 return ($parts -join ' ')
}
function Get-AC7MissingDirectories([string]$GameRoot,[string]$Directory) {
 $game=[IO.Path]::GetFullPath($GameRoot).TrimEnd('\','/');$missing=@()
 $current=[IO.Path]::GetFullPath($Directory).TrimEnd('\','/')
 while($current.StartsWith($game+'\',[StringComparison]::OrdinalIgnoreCase)){
  if(Test-Path -LiteralPath $current){break}
  $missing=@($current.Substring($game.Length+1))+$missing
  $current=Split-Path $current -Parent
 }
 return $missing
}
function Get-AC7ParentDirectories([string[]]$Relatives) {
 $directories=@{}
 foreach($relative in @($Relatives | Where-Object {$_})){$directory=Split-Path $relative -Parent;while($directory){$directories[$directory]=$true;$directory=Split-Path $directory -Parent}}
 return @($directories.Keys)
}
# Removes only directories that are empty, deepest first, and never the game root itself.
function Remove-AC7EmptyDirectories([string]$GameRoot,[string[]]$Directories) {
 $game=[IO.Path]::GetFullPath($GameRoot).TrimEnd('\','/')
 foreach($relative in @($Directories | Where-Object {$_} | Sort-Object {$_.Length} -Descending)){
  $path=[IO.Path]::GetFullPath((Join-Path $game $relative))
  if(!$path.StartsWith($game+'\',[StringComparison]::OrdinalIgnoreCase)){continue}
  if((Test-Path -LiteralPath $path -PathType Container) -and !@(Get-ChildItem -LiteralPath $path -Force).Count){Remove-Item -LiteralPath $path -Force}
 }
}
# Write to a temporary sibling, verify, then replace; the target is never left half-written.
function Copy-AC7PlanFile($Entry,[string]$Target,[string]$Suffix) {
 $temporary=$Target+$Suffix
 if($null -ne $Entry.Bytes){[IO.File]::WriteAllBytes($temporary,[byte[]]$Entry.Bytes)}else{[IO.File]::Copy([string]$Entry.Source,$temporary,$true)}
 [IO.File]::SetAttributes($temporary,[IO.FileAttributes]::Normal)
 if((Get-AC7FileHash -LiteralPath $temporary).Hash -ne $Entry.SHA256){Remove-Item -LiteralPath $temporary -Force;throw "Copy verification failed: $Target"}
 if(Test-Path -LiteralPath $Target){[IO.File]::Delete($Target)}
 [IO.File]::Move($temporary,$Target)
 if((Get-AC7FileHash -LiteralPath $Target).Hash -ne $Entry.SHA256){throw "Write verification failed: $Target"}
}
function ConvertTo-AC7OrderedManifest($Manifest) {
 $result=[ordered]@{}
 foreach($property in $Manifest.PSObject.Properties){$result[$property.Name]=$property.Value}
 $result['Files']=@(@($Manifest.Files) | ForEach-Object {[ordered]@{Relative=[string]$_.Relative;SHA256=([string]$_.SHA256).ToUpperInvariant()}})
 return $result
}
function Test-AC7Package([string]$PackageRoot) {
 foreach($name in @('PowerShell-Compat.ps1','Install-Common.ps1','Install-Core.ps1','Cleanup-Core.ps1','Feature-Settings.ps1','features.ini','MouseAim-Settings.ps1','MouseAim-Settings.ini','MouseAim-Settings-GUI.ps1','MouseAim-Settings-GUI.xaml','Keybinding-Settings.ps1','Keybindings.ini','Keybindings.schema.json','Keybindings-GUI.ps1','Keybindings-GUI.xaml','Discover-Installations.ps1','Gui-Core.ps1','Gui-Worker.ps1','Launcher-GUI.ps1','Launcher-GUI.xaml','CreeperUX-Theme.ps1','ui/creeperux/tokens.json','ui/creeperux/fonts/chakra-petch-600-latin.ttf','ui/creeperux/fonts/share-tech-mono-400-latin.ttf','Start-GUI.cmd','Setup.ps1','Setup.cmd','Run-Console.ps1','Mod-Mode.ps1','Enable-Mod.cmd','Disable-Mod.cmd','Recover-Cleanup.ps1','Recover-Cleanup.cmd','package-info.json','payload-manifest.json')){
  if(!(Test-Path -LiteralPath (Join-Path $PackageRoot $name) -PathType Leaf)){Stop-AC7Problem 'PACKAGE' "整合包不完整：缺少 $name。" '请重新解压完整的整合包。'}
 }
 $info=Get-AC7PackageInfo $PackageRoot
 $payload=[IO.Path]::GetFullPath((Join-Path $PackageRoot 'payload')).TrimEnd('\','/')
 # Windows PowerShell emits a JSON array as one object; enumerate it explicitly.
 $parsed=Get-Content -LiteralPath (Join-Path $PackageRoot 'payload-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 $manifest=@($parsed | ForEach-Object {$_})
 $actual=@(Get-ChildItem -LiteralPath $payload -File -Recurse -Force)
 if($actual.Count -ne $manifest.Count){Stop-AC7Problem 'PACKAGE' '安装文件数量与清单不一致。' '请重新解压完整的整合包；不要向 payload 文件夹添加或删除文件。'}
 $seen=@{}
 foreach($item in $manifest){
  $file=[IO.Path]::GetFullPath((Join-Path $payload ([string]$item.Path)))
  if(!$file.StartsWith($payload+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Payload path escaped package.'}
  if($seen.ContainsKey($file)){throw 'Duplicate payload manifest path.'};$seen[$file]=$true
  if(!(Test-Path -LiteralPath $file -PathType Leaf) -or (Get-AC7FileHash -LiteralPath $file).Hash -ne ([string]$item.SHA256).ToUpperInvariant()){Stop-AC7Problem 'PACKAGE' "安装文件校验失败：$($item.Path)" '整合包文件不完整或被修改。请重新下载并解压。'}
 }
 $dll=Join-Path $payload 'ue4ss\Mods\AC7MouseAim\Scripts\ac7_mouse_aim.dll'
 if($info.native_sha256 -and (Get-AC7FileHash -LiteralPath $dll).Hash -ne ([string]$info.native_sha256).ToUpperInvariant()){Stop-AC7Problem 'PACKAGE' '飞控 DLL 与 package-info.json 记录不一致。' '请重新下载并解压整合包。'}
 $null=Read-AC7MouseSettings (Join-Path $PackageRoot 'MouseAim-Settings.ini')
 $null=Read-AC7FeatureSettings (Join-Path $PackageRoot 'features.ini')
 $null=Read-AC7Keybindings (Join-Path $PackageRoot 'Keybindings.ini')
 return $info
}
# Desired file set: payload files (AC7Weapons only when selected) with mods.txt, config.ini, camera-settings.lua
# and the AC7Weapons tier (settings.lua) generated from the package settings.
function New-AC7InstallPlan([string]$PackageRoot,[ValidateSet('mouse','guidance','full','weapons')][string]$Features,[string]$LoaderRelative) {
 $layout=Get-AC7Layout;$Features=ConvertTo-AC7Features $Features
 $payload=[IO.Path]::GetFullPath((Join-Path $PackageRoot 'payload')).TrimEnd('\','/')
 $settings=Read-AC7MouseSettings (Join-Path $PackageRoot 'MouseAim-Settings.ini')
 $bindings=Read-AC7Keybindings (Join-Path $PackageRoot 'Keybindings.ini')
 $utf8=[Text.UTF8Encoding]::new($false);$plan=@()
 foreach($file in @(Get-ChildItem -LiteralPath $payload -File -Recurse -Force | Sort-Object FullName)){
  $relative=ConvertTo-AC7Relative $file.FullName.Substring($payload.Length+1)
  if($Features -eq 'mouse' -and $relative.StartsWith($layout.WeaponsPrefix,[StringComparison]::OrdinalIgnoreCase)){continue}
  $bytes=$null;$source=$file.FullName
  if($relative -ieq $layout.Loader){$relative=$LoaderRelative}
  elseif($relative -ieq $layout.ModsList){
   $lines=@(([IO.File]::ReadAllText($source)) -split "`r?`n" | Where-Object {$_.Trim() -and ($Features -ne 'mouse' -or $_ -notmatch '^\s*AC7Weapons\s*:')})
   $bytes=[Text.Encoding]::ASCII.GetBytes(($lines -join "`r`n")+"`r`n")
  }elseif($relative -ieq $layout.Config){$bytes=$utf8.GetBytes((Update-AC7ConfigText ([IO.File]::ReadAllText($source)) $settings $bindings))}
  elseif($relative -ieq $layout.CameraSettings){$bytes=$utf8.GetBytes((Update-AC7CameraSettingsText ([IO.File]::ReadAllText($source)) $settings))}
  elseif($relative -ieq $layout.WeaponsSettings){$bytes=[Text.Encoding]::ASCII.GetBytes((Get-AC7WeaponsSettingsText $Features))}
  $sha=if($null -ne $bytes){Get-AC7BytesHash $bytes}else{(Get-AC7FileHash -LiteralPath $source).Hash}
  $plan+=[pscustomobject]@{Relative=$relative;Source=$(if($null -ne $bytes){$null}else{$source});Bytes=$bytes;SHA256=$sha;Loader=($relative -ieq $LoaderRelative)}
 }
 # Write the loader last: an interrupted fresh install never leaves an active loader without its runtime.
 return @(@($plan | Where-Object {!$_.Loader})+@($plan | Where-Object Loader))
}
function Backup-AC7SaveData([string]$SaveRoot,[string]$Destination) {
 if(!$SaveRoot -or !(Test-Path -LiteralPath $SaveRoot -PathType Container)){return 0}
 $source=[IO.Path]::GetFullPath($SaveRoot).TrimEnd('\','/')
 Copy-Item -LiteralPath $source -Destination $Destination -Recurse -Force
 $files=@(Get-ChildItem -LiteralPath $source -File -Recurse -Force)
 foreach($file in $files){
  $copy=Join-Path $Destination $file.FullName.Substring($source.Length+1)
  if(!(Test-Path -LiteralPath $copy -PathType Leaf) -or (Get-AC7FileHash -LiteralPath $copy).Hash -ne (Get-AC7FileHash -LiteralPath $file.FullName).Hash){throw "Save backup verification failed: $($file.Name)"}
 }
 return $files.Count
}
function Restore-AC7BackupFile([string]$GameRoot,[string]$Backup,[string]$Relative,[string]$Hash) {
 if(!$Backup){return $false}
 $source=Join-Path (Join-Path $Backup 'previous') $Relative
 if(!(Test-Path -LiteralPath $source -PathType Leaf) -or (Get-AC7FileHash -LiteralPath $source).Hash -ne $Hash){return $false}
 $target=Get-AC7Target $GameRoot $Relative
 New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
 Copy-AC7PlanFile ([pscustomobject]@{Source=$source;Bytes=$null;SHA256=$Hash}) $target '.ac7restore'
 return $true
}
# Undo an install transaction from its journal. Every file must match a hash the journal knows
# (before or after); anything else is retained and reported, never overwritten or deleted.
function Invoke-AC7Rollback([string]$GameRoot,$Journal) {
 $layout=Get-AC7Layout;$game=[IO.Path]::GetFullPath($GameRoot).TrimEnd('\','/');$retained=@()
 $backup=[string]$Journal.Backup;$suffix=[string]$Journal.TmpSuffix
 $targets=@($Journal.Targets);[array]::Reverse($targets)
 foreach($item in $targets){
  $target=Get-AC7Target $game ([string]$item.Relative)
  if($suffix -and (Test-Path -LiteralPath ($target+$suffix) -PathType Leaf)){Remove-Item -LiteralPath ($target+$suffix) -Force}
  $current=Get-AC7CurrentHash $target
  if($item.Before){
   if($current -eq $item.Before){continue}
   if(($null -eq $current -or $current -eq $item.After) -and (Restore-AC7BackupFile $game $backup ([string]$item.Relative) ([string]$item.Before))){continue}
   $retained+=[string]$item.Relative
  }elseif($null -ne $current){
   if($current -eq $item.After){Remove-Item -LiteralPath $target -Force}else{$retained+=[string]$item.Relative}
  }
 }
 foreach($item in @($Journal.Obsolete)){
  $current=Get-AC7CurrentHash (Get-AC7Target $game ([string]$item.Relative))
  if($current -eq $item.Before){continue}
  if($null -eq $current -and (Restore-AC7BackupFile $game $backup ([string]$item.Relative) ([string]$item.Before))){continue}
  $retained+=[string]$item.Relative
 }
 $manifestPath=Join-Path $game $layout.Manifest
 if($Journal.HadManifest){
  $previous=Join-Path $backup 'previous\AC7-MouseAim-owner.json'
  if($backup -and (Test-Path -LiteralPath $previous -PathType Leaf)){Copy-Item -LiteralPath $previous -Destination $manifestPath -Force}else{$retained+=$layout.Manifest}
 }elseif(Test-Path -LiteralPath $manifestPath){Remove-Item -LiteralPath $manifestPath -Force}
 if(!$retained.Count){
  $pending=Join-Path $game $layout.Pending
  if(Test-Path -LiteralPath $pending){Remove-Item -LiteralPath $pending -Force}
  Remove-AC7EmptyDirectories $game (@($Journal.CreatedDirs)+@(Get-AC7ParentDirectories @($targets | ForEach-Object {[string]$_.Relative})))
 }
 return $retained
}
# Settings migration when adopting an install made by another package: the installed values become this
# package's MouseAim-Settings.ini / Keybindings.ini (previous files kept as .bak).
function Import-AC7InstalledSettings([string]$PackageRoot,[string]$GameRoot,$State) {
 $layout=Get-AC7Layout
 if(!@($State.Entries | Where-Object {$_.Relative -ieq $layout.Config -and $_.Status -eq 'ok'}).Count){return @()}
 $configText=[IO.File]::ReadAllText((Get-AC7Target $GameRoot $layout.Config))
 $cameraText=''
 if(@($State.Entries | Where-Object {$_.Relative -ieq $layout.CameraSettings -and $_.Status -eq 'ok'}).Count){$cameraText=[IO.File]::ReadAllText((Get-AC7Target $GameRoot $layout.CameraSettings))}
 $mouse=Import-AC7MouseSettingsFromText $configText $cameraText (Read-AC7MouseSettings (Join-Path $PackageRoot 'MouseAim-Settings.ini'))
 # 0.6.0 strokes are 1.4x the 0.5.3/0.5.4 ones at hud_line_width=1: rescale an imported multiplier so it looks the same.
 if([string]$State.Version -match '^0\.5\.[34]$' -and $null -ne $mouse.Values['hud_line_width']){
  $mouse.Values['hud_line_width']=[Math]::Round([Math]::Min([double]2,[Math]::Max([double]0.5,[double]$mouse.Values['hud_line_width']/1.4)),2)
  if($mouse.Values['hud_line_width'] -eq 1){$mouse.Changed=@(@($mouse.Changed) | Where-Object {$_ -ne 'hud_line_width'})}
 }
 # 0.5.1 defaulted to the reticle inside the game HUD (hud_renderer 3); from 0.5.2 the default is the GPU overlay at
 # native resolution (1), so an imported 3 from 0.5.1 means "default" and moves to 1. 0.4.x/0.5.0 values (0/1) are kept.
 if([string]$State.Version -match '0\.5\.1' -and $mouse.Values['hud_renderer'] -eq 3){$mouse.Values['hud_renderer']=1;$mouse.Changed=@(@($mouse.Changed) | Where-Object {$_ -ne 'hud_renderer'})}
 $keys=Import-AC7KeybindingsFromText $configText (Read-AC7Keybindings (Join-Path $PackageRoot 'Keybindings.ini'))
 if(@($mouse.Changed).Count){Save-AC7MouseSettings $PackageRoot $mouse.Values}
 if(@($keys.Changed).Count){Save-AC7Keybindings $PackageRoot $keys.Values}
 return @(@($mouse.Changed)+@($keys.Changed))
}
function Invoke-AC7Install {
 param([Parameter(Mandatory=$true)][string]$PackageRoot,[Parameter(Mandatory=$true)][string]$GameRoot,[ValidateSet('mouse','guidance','full','weapons')][string]$Features='full',[string]$SaveRoot,[switch]$CheckOnly,
  [switch]$TestOnlySkipExeHash,[int]$TestOnlyFaultAfter=-1,[switch]$TestOnlySkipRollback)
 $layout=Get-AC7Layout;$Features=ConvertTo-AC7Features $Features
 $package=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\','/')
 if(!$SaveRoot){$SaveRoot=Get-AC7SaveRoot}
 $game=Resolve-AC7GameRoot $GameRoot
 Assert-AC7PackageLocation $package $game
 Assert-AC7NoLinks $game
 Assert-AC7GameClosed $game
 Assert-AC7GameBuild $package $game -TestOnlySkipExeHash:$TestOnlySkipExeHash
 $info=Test-AC7Package $package
 $operation=Enter-AC7Operation $game
 try{
  $state=Get-AC7InstallState $game
  Assert-AC7StateUsable $state
  $loaderRelative=if($state.Mode -eq 'disabled'){$layout.DisabledLoader}else{$layout.Loader}
  $sameProject=$false
  if($state.Installed -and $state.Project){try{$sameProject=[IO.Path]::GetFullPath($state.Project).TrimEnd('\','/').Equals($package,[StringComparison]::OrdinalIgnoreCase)}catch{$sameProject=$false}}
  $imported=@()
  if($state.Installed -and !$sameProject -and !$CheckOnly){$imported=@(Import-AC7InstalledSettings $package $game $state)}
  $plan=@(New-AC7InstallPlan $package $Features $loaderRelative)
  $old=@{};foreach($entry in $state.Entries){$old[$entry.Actual]=$entry}
  $planned=@{};foreach($item in $plan){$planned[$item.Relative]=$item}
  $conflicts=@();$targets=@()
  foreach($item in $plan){
   $target=Get-AC7Target $game $item.Relative;$before=$null
   if($old.ContainsKey($item.Relative)){$before=$old[$item.Relative].SHA256}
   elseif(Test-Path -LiteralPath $target){
    # An unrecorded file is adopted only when it is already byte-identical to the new file.
    if((Get-AC7CurrentHash $target) -eq $item.SHA256){$before=$item.SHA256}else{$conflicts+=$item.Relative}
   }
   $targets+=[pscustomobject]@{Relative=$item.Relative;After=$item.SHA256;Before=$before}
  }
  if($conflicts.Count){Stop-AC7Problem 'UNOWNED_FILE' ('以下位置已有不属于本工具的文件，安装会覆盖它们：'+($conflicts -join '、')+'。') '为避免覆盖，未修改任何文件。请先确认来源，移走或备份这些文件后重试。'}
  $obsolete=@($state.Entries | Where-Object {!$planned.ContainsKey($_.Actual)} | ForEach-Object {[pscustomobject]@{Relative=$_.Actual;Before=$_.SHA256}})
  $changes=@($targets | Where-Object {$_.Before -ne $_.After})
  $summary=[pscustomobject]@{GameRoot=$game;Version=[string]$info.version;Features=$Features;Mode=$(if($state.Mode -eq 'disabled'){'disabled'}else{'enabled'});Adopted=($state.Installed -and !$sameProject);WasInstalled=[bool]$state.Installed;PreviousVersion=$state.Version;
   Files=$plan.Count;New=@($changes | Where-Object {!$_.Before}).Count;Updated=@($changes | Where-Object {$_.Before}).Count;Removed=$obsolete.Count;Imported=$imported;Backup=$null;SaveFiles=0;OtherMods=@($state.OtherMods);OtherLoaders=@($state.OtherLoaders)}
  if($CheckOnly){return $summary}
  Assert-AC7WriteAccess $game
  $stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
  $backup=Join-Path $package ('backups\install-'+$stamp)
  New-Item -ItemType Directory -Path $backup -Force | Out-Null
  Assert-AC7NoLinks $backup
  $summary.Backup=$backup
  $summary.SaveFiles=Backup-AC7SaveData $SaveRoot (Join-Path $backup 'savedata')
  # Previous owned files and the ownership record, verified before any game file changes.
  $previous=Join-Path $backup 'previous'
  foreach($entry in @($state.Entries)){
   $copy=Join-Path $previous $entry.Actual
   New-Item -ItemType Directory -Path (Split-Path $copy -Parent) -Force | Out-Null
   Copy-Item -LiteralPath (Get-AC7Target $game $entry.Actual) -Destination $copy -Force
   if((Get-AC7FileHash -LiteralPath $copy).Hash -ne $entry.SHA256){throw "Backup verification failed: $($entry.Actual)"}
  }
  if($state.Installed){New-Item -ItemType Directory -Path $previous -Force | Out-Null;Copy-Item -LiteralPath (Join-Path $game $layout.Manifest) -Destination (Join-Path $previous 'AC7-MouseAim-owner.json') -Force}
  $created=@(Get-AC7MissingDirectories $game (Join-Path $game 'ue4ss'))
  foreach($item in $plan){$created+=@(Get-AC7MissingDirectories $game (Split-Path (Get-AC7Target $game $item.Relative) -Parent))}
  $id=[guid]::NewGuid().ToString('N')
  $journal=[pscustomobject]@{Version=1;Operation='install';Id=$id;UTC=[DateTime]::UtcNow.ToString('o');GameRoot=$game;PackageRoot=$package;Backup=$backup;HadManifest=[bool]$state.Installed;
   TmpSuffix=('.ac7tmp-'+$id.Substring(0,8));Targets=@($targets);Obsolete=@($obsolete);CreatedDirs=@($created | Select-Object -Unique)}
  New-Item -ItemType Directory -Path (Join-Path $game 'ue4ss') -Force | Out-Null
  Assert-AC7WriteAccess (Join-Path $game 'ue4ss')
  Write-AC7Json $journal (Join-Path $backup 'journal.json')
  Write-AC7Json $journal (Join-Path $game $layout.Pending)
  # Test-only fault injection: fail before mutation step N (file write, obsolete removal or manifest write).
  $step=0
  try{
   foreach($item in $plan){
    $record=$targets | Where-Object {$_.Relative -eq $item.Relative} | Select-Object -First 1
    if($record.Before -eq $record.After){continue}
    if($TestOnlyFaultAfter -ge 0 -and $step -ge $TestOnlyFaultAfter){throw 'TestOnly injected fault during install.'}
    $target=Get-AC7Target $game $item.Relative
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Copy-AC7PlanFile $item $target $journal.TmpSuffix
    $step++
   }
   foreach($item in $obsolete){
    if($TestOnlyFaultAfter -ge 0 -and $step -ge $TestOnlyFaultAfter){throw 'TestOnly injected fault during install.'}
    $target=Get-AC7Target $game $item.Relative
    if((Get-AC7CurrentHash $target) -ne $item.Before){throw "Obsolete file changed during install: $($item.Relative)"}
    Remove-Item -LiteralPath $target -Force
    $step++
   }
   Remove-AC7EmptyDirectories $game (Get-AC7ParentDirectories @($obsolete | ForEach-Object Relative))
   if($TestOnlyFaultAfter -ge 0 -and $step -ge $TestOnlyFaultAfter){throw 'TestOnly injected fault during install.'}
   $manifest=[ordered]@{Tool=$layout.Tool;Version=[string]$info.version;Project=$package;GameRoot=$game;Features=$Features;ModState=$summary.Mode;
    Files=@($plan | ForEach-Object {[ordered]@{Relative=$_.Relative;SHA256=$_.SHA256}});UTC=[DateTime]::UtcNow.ToString('o');Backup=$backup;TransactionId=$id}
   if($state.Installed -and !$sameProject){$manifest['PreviousProject']=$state.Project;$manifest['PreviousVersion']=$state.Version}
   Write-AC7Json $manifest (Join-Path $game $layout.Manifest)
   $verify=Get-AC7InstallState $game
   if(@($verify.Entries | Where-Object Status -ne 'ok').Count -or @($verify.Entries).Count -ne $plan.Count -or @($verify.UnownedLoader).Count){throw 'Post-install verification failed.'}
   Remove-Item -LiteralPath (Join-Path $game $layout.Pending) -Force
  }catch{
   $failure=$_
   if($TestOnlySkipRollback){throw}
   $retained=@(Invoke-AC7Rollback $game $journal)
   if($retained.Count){Stop-AC7Problem 'ROLLBACK_INCOMPLETE' ('安装失败，自动回滚未完全完成：'+($retained -join '、')+'。') ('原因：'+$failure.Exception.Message+' 备份：'+$backup+'。请运行“卸载（备份并清理）”继续处理。')}
   Stop-AC7Problem 'INSTALL_ROLLED_BACK' ('安装未完成，已自动恢复到安装前的状态。原因：'+$failure.Exception.Message) ('备份：'+$backup+'。请按原因检查目录权限或安全软件后重试。')
  }
  return $summary
 }finally{Exit-AC7Operation $operation}
}
function Format-AC7InstallSummary($Summary) {
 $what=Get-AC7FeatureLabel $Summary.Features
 if($Summary.Adopted){$text='已接管原有安装（'+$Summary.PreviousVersion+'）并更新到 AC7 '+$Summary.Version+'：'+$what+'。'}
 elseif($Summary.WasInstalled){$text='已更新 AC7 '+$Summary.Version+'：'+$what+'。'}
 else{$text='已安装 AC7 '+$Summary.Version+'：'+$what+'。'}
 $text+=' 新增 '+$Summary.New+' 个、更新 '+$Summary.Updated+' 个、移除 '+$Summary.Removed+' 个文件，全部逐个校验。'
 if(@($Summary.Imported).Count){$text+=' 已从原安装导入设置：'+(@($Summary.Imported) -join '、')+'。'}
 if($Summary.Backup){$text+=' 存档（'+$Summary.SaveFiles+' 个文件）与原文件备份：'+$Summary.Backup+'。'}
 if($Summary.Mode -eq 'disabled'){$text+=' Mod 仍处于停用状态（原版启动）；需要单人 Mod 时点击“启用 Mod”。'}
 else{$text+=' 仅限单人；进入多人对战前请先退出游戏并“停用 Mod”。'}
 return $text
}
# Multiplayer switch: move the owned loader between dwmapi.dll and ue4ss\dwmapi.dll.disabled (reversible).
function Set-AC7ModMode {
 param([Parameter(Mandatory=$true)][string]$PackageRoot,[Parameter(Mandatory=$true)][string]$GameRoot,[ValidateSet('Enable','Disable','Status')][string]$Action='Status',[switch]$TestOnlySkipExeHash)
 $layout=Get-AC7Layout
 $game=Resolve-AC7GameRoot $GameRoot
 Assert-AC7NoLinks $game
 if($Action -eq 'Status'){$state=Get-AC7InstallState $game;return [pscustomobject]@{Changed=$false;Mode=$state.Mode;Message=(Format-AC7StateText $state)}}
 Assert-AC7GameClosed $game
 if($Action -eq 'Enable'){Assert-AC7GameBuild $PackageRoot $game -TestOnlySkipExeHash:$TestOnlySkipExeHash}
 $operation=Enter-AC7Operation $game
 try{
  $state=Get-AC7InstallState $game
  $wantDisabled=($Action -eq 'Disable')
  if(!$state.Installed){
   if(@($state.UnownedLoader).Count){Assert-AC7StateUsable $state}
   if($wantDisabled){return [pscustomobject]@{Changed=$false;Mode='none';Message='游戏中没有本 Mod 的加载器，已是原版启动状态。'}}
   Stop-AC7Problem 'NOT_INSTALLED' '游戏中还没有安装本 Mod。' '请先点击“安装／更新”。'
  }
  if($wantDisabled -and $state.Mode -eq 'missing' -and !$state.Pending -and !@($state.UnownedLoader).Count){
   return [pscustomobject]@{Changed=$false;Mode='missing';Message='加载器 dwmapi.dll 不在游戏目录中，游戏会以原版启动。建议用“卸载（备份并清理）”整理安装记录。'}
  }
  if($wantDisabled){Assert-AC7StateUsable $state -LoaderOnly}else{Assert-AC7StateUsable $state}
  if($wantDisabled -and $state.Mode -eq 'disabled'){return [pscustomobject]@{Changed=$false;Mode='disabled';Message='Mod 已处于停用状态，游戏会以原版启动。'}}
  if(!$wantDisabled -and $state.Mode -eq 'enabled'){return [pscustomobject]@{Changed=$false;Mode='enabled';Message='Mod 已处于启用状态（仅限单人）。'}}
  $loader=@($state.Entries | Where-Object Loader)[0]
  $from=Get-AC7Target $game $loader.Actual
  $toRelative=if($wantDisabled){$layout.DisabledLoader}else{$layout.Loader}
  $to=Get-AC7Target $game $toRelative
  if(Test-Path -LiteralPath $to){Stop-AC7Problem 'UNOWNED_LOADER' "目标位置已有文件：$toRelative" '未修改任何文件。请确认这个文件的来源后手动处理。'}
  $manifestPath=Join-Path $game $layout.Manifest;$manifestBytes=[IO.File]::ReadAllBytes($manifestPath)
  [IO.File]::Move($from,$to)
  try{
   if((Get-AC7FileHash -LiteralPath $to).Hash -ne $loader.SHA256){throw 'Loader verification failed after move.'}
   $manifest=ConvertTo-AC7OrderedManifest $state.Manifest
   foreach($file in $manifest['Files']){if(([string]$file.Relative) -ieq $loader.Relative){$file.Relative=$toRelative}}
   $manifest['ModState']=if($wantDisabled){'disabled'}else{'enabled'}
   $manifest['ModeUTC']=[DateTime]::UtcNow.ToString('o')
   Write-AC7Json $manifest $manifestPath
  }catch{
   if((Test-Path -LiteralPath $to) -and !(Test-Path -LiteralPath $from)){[IO.File]::Move($to,$from)}
   [IO.File]::WriteAllBytes($manifestPath,$manifestBytes)
   throw
  }
  if($wantDisabled -and (Test-Path -LiteralPath (Join-Path $game $layout.Loader))){throw 'Loader still present after disabling.'}
  if($wantDisabled){
   return [pscustomobject]@{Changed=$true;Mode='disabled';Message='已停用 Mod：加载器 dwmapi.dll 已移到 ue4ss\dwmapi.dll.disabled，游戏将以原版启动，可以进入多人对战。需要时点击“启用 Mod”恢复。此检查只覆盖本 Mod；联机前请确认其他 Mod 也已停用。'}
  }
  return [pscustomobject]@{Changed=$true;Mode='enabled';Message='已启用 Mod（单人模式）。仅限单人任务；进入多人对战前请先退出游戏并停用 Mod。'}
 }finally{Exit-AC7Operation $operation}
}
# Writes the package settings into an installed, unmodified config.ini / camera-settings.lua and updates
# their recorded hashes. Never touches a file that differs from the ownership record.
function Sync-AC7GameConfig([string]$PackageRoot,[string]$GameRoot) {
 $result=[pscustomobject]@{Applied=$false;Message=''}
 if(!$GameRoot){$result.Message='尚未选择游戏位置，已保存到本包；安装时写入游戏。';return $result}
 try{$game=Resolve-AC7GameRoot $GameRoot}catch{$result.Message='游戏位置无效，已保存到本包；安装时写入游戏。';return $result}
 Assert-AC7GameClosed $game
 $layout=Get-AC7Layout
 $operation=Enter-AC7Operation $game
 try{
  $state=Get-AC7InstallState $game
  if(!$state.Installed){$result.Message='游戏中尚未安装本 Mod，已保存到本包；安装时写入。';return $result}
  if($state.Pending -or @($state.UnownedLoader).Count){$result.Message='游戏目录需要先检查（未完成的操作或未知加载器），已只保存到本包。';return $result}
  $entries=@{}
  foreach($relative in $layout.Config,$layout.CameraSettings){
   $entry=@($state.Entries | Where-Object {$_.Relative -ieq $relative})
   if($entry.Count -ne 1 -or $entry[0].Status -ne 'ok'){$result.Message="游戏中的 $relative 已被修改或缺失，未覆盖；已保存到本包。";return $result}
   $entries[$relative]=$entry[0]
  }
  $settings=Read-AC7MouseSettings (Join-Path $PackageRoot 'MouseAim-Settings.ini')
  $bindings=Read-AC7Keybindings (Join-Path $PackageRoot 'Keybindings.ini')
  $utf8=[Text.UTF8Encoding]::new($false);$writes=@()
  foreach($relative in $layout.Config,$layout.CameraSettings){
   $path=Get-AC7Target $game $relative;$text=[IO.File]::ReadAllText($path)
   $new=if($relative -ieq $layout.Config){Update-AC7ConfigText $text $settings $bindings}else{Update-AC7CameraSettingsText $text $settings}
   $bytes=$utf8.GetBytes($new);$sha=Get-AC7BytesHash $bytes
   if($sha -ne $entries[$relative].SHA256){$writes+=[pscustomobject]@{Relative=$relative;Path=$path;Old=[IO.File]::ReadAllBytes($path);Bytes=$bytes;SHA256=$sha;Source=$null}}
  }
  if(!$writes.Count){$result.Applied=$true;$result.Message='游戏中的配置已是这些设置。';return $result}
  $manifestPath=Join-Path $game $layout.Manifest;$manifestBytes=[IO.File]::ReadAllBytes($manifestPath);$done=@()
  try{
   foreach($write in $writes){Copy-AC7PlanFile $write $write.Path ('.ac7tmp-'+[guid]::NewGuid().ToString('N').Substring(0,8));$done+=$write}
   $manifest=ConvertTo-AC7OrderedManifest $state.Manifest
   foreach($file in $manifest['Files']){foreach($write in $writes){if(([string]$file.Relative) -ieq $write.Relative){$file.SHA256=$write.SHA256}}}
   $manifest['SettingsUTC']=[DateTime]::UtcNow.ToString('o')
   Write-AC7Json $manifest $manifestPath
  }catch{
   foreach($write in $done){[IO.File]::WriteAllBytes($write.Path,[byte[]]$write.Old)}
   [IO.File]::WriteAllBytes($manifestPath,$manifestBytes)
   throw
  }
  $result.Applied=$true;$result.Message='已写入游戏中的 config.ini，下次启动生效。'
  return $result
 }finally{Exit-AC7Operation $operation}
}
# Plain Steam start: no launch-option wrapper. Prefers steam.exe -applaunch, else the steam:// URL.
function Start-AC7ViaSteam([string]$PackageRoot,[string]$GameRoot,[string]$SteamPath,[switch]$WhatIf) {
 $info=Get-AC7PackageInfo $PackageRoot;$appId=[string]$info.steam_app_id;$mode='unknown'
 if($GameRoot){
  $game=Resolve-AC7GameRoot $GameRoot
  Assert-AC7GameClosed $game
  $mode=(Get-AC7InstallState $game).Mode
 }elseif(Test-AC7GameRunning ''){Stop-AC7Problem 'GAME_RUNNING' '游戏已在运行。' '无需重复启动。'}
 $steam=([string]$SteamPath).Trim().Trim('"')
 if($steam -and (Test-Path -LiteralPath $steam -PathType Leaf) -and [IO.Path]::GetFileName($steam) -ieq 'steam.exe'){
  $how='steam.exe -applaunch '+$appId
  if(!$WhatIf){Start-Process -FilePath $steam -ArgumentList '-applaunch',$appId}
 }else{
  $how='steam://rungameid/'+$appId
  if(!$WhatIf){Start-Process -FilePath ('steam://rungameid/'+$appId)}
 }
 $text=switch($mode){
  'enabled'{'将以单人 Mod 模式启动。请勿进入多人对战；联机前先退出游戏并停用 Mod。'}
  'disabled'{'Mod 已停用，将以原版启动，可以联机。'}
  'none'{'未安装本 Mod，将以原版启动。'}
  default{'请以 Steam 和游戏窗口为准。'}
 }
 return [pscustomobject]@{Method=$how;Mode=$mode;Message=('已通过 Steam 发送启动请求（'+$how+'）。'+$text)}
}
