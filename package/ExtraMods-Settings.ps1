# Other UE4SS mods for AC7 (0.7.0, the AC8 2.5.0 extra-mod manager adapted to AC7's persistent install).
# Library in the player data folder: ue4ss-mods (enabled; a folder starting with _ is disabled), ue4ss-mods-removed
# (backups of removed or replaced mods) and ue4ss-mods-staging (temporary). Sync-AC7ExtraMods deploys the enabled
# library mods into the game's ue4ss\Mods with an enabled.txt and records every deployed file and its hash in
# ue4ss\AC7-ExtraMods.json; it removes only recorded files whose content is unchanged. Mod folders this tool did not
# deploy (placed by hand) are never touched.

function Get-AC7ExtraModNameProblem([string]$Name) {
 # Folder names usable as UE4SS mod names, not taken by this package's own components.
 if($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9_.\-]{0,63}$'){return '名称只能使用英文字母、数字和 _ . -'}
 if(@('AC7MouseAim','AC7Weapons','shared') -contains $Name){return '与本整合包自带的组件同名'}
 return $null
}
function Get-AC7ExtraMods([string]$DataRoot) {
 # Library folders with the standard UE4SS layout (Scripts\main.lua and/or dlls\main.dll). A folder starting with _ is
 # disabled; reserved or unusual names and filesystem links are skipped with a reason.
 $folder=Join-Path $DataRoot 'ue4ss-mods'
 if(!(Test-Path -LiteralPath $folder -PathType Container)){return @()}
 $link=[IO.FileAttributes]::ReparsePoint
 return @(foreach($dir in @(Get-ChildItem -LiteralPath $folder -Directory -Force | Sort-Object Name)){
  $name=$dir.Name;$problem=$null;$kind=@()
  if($name.StartsWith('_')){$problem='已停用（名称以 _ 开头）'}
  elseif(($nameProblem=Get-AC7ExtraModNameProblem $name)){$problem=$nameProblem}
  elseif(($dir.Attributes -band $link) -or @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -Force | Where-Object {$_.Attributes -band $link}).Count){$problem='包含文件系统链接'}
  else{
   if(Test-Path -LiteralPath (Join-Path $dir.FullName 'Scripts/main.lua') -PathType Leaf){$kind+='Lua'}
   if(Test-Path -LiteralPath (Join-Path $dir.FullName 'dlls/main.dll') -PathType Leaf){$kind+='C++'}
   if(!$kind.Count){$problem='不是 UE4SS Mod（缺少 Scripts\main.lua 或 dlls\main.dll）'}
  }
  [pscustomobject]@{Name=$name;Path=$dir.FullName;Kind=($kind -join '+');Problem=$problem}
 })
}
function Get-AC7ModTreeLinks([string]$Path) {
 # Filesystem links anywhere below $Path (they are never followed, copied or accepted).
 $link=[IO.FileAttributes]::ReparsePoint
 if((Get-Item -LiteralPath $Path -Force).Attributes -band $link){return @($Path)}
 return @(Get-ChildItem -LiteralPath $Path -Recurse -Force | Where-Object {$_.Attributes -band $link} | ForEach-Object {$_.FullName})
}
function Test-AC7ModSkippedFile([string]$Name) {
 # Never installed with a mod: the UE4SS loader itself (this package brings its own) and Pak assets (loaded by the game).
 return ($Name -in @('dwmapi.dll','UE4SS.dll','UE4SS-settings.ini','xinput1_3.dll')) -or ([IO.Path]::GetExtension($Name) -in @('.pak','.utoc','.ucas'))
}
function Copy-AC7ModTree([string]$Source,[string]$Destination) {
 [void][IO.Directory]::CreateDirectory($Destination)
 foreach($child in (New-Object IO.DirectoryInfo($Source)).GetFileSystemInfos()){
  if($child.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Filesystem link in the mod: $($child.FullName)"}
  if($child -isnot [IO.DirectoryInfo] -and (Test-AC7ModSkippedFile $child.Name)){continue}
  $target=[IO.Path]::Combine($Destination,$child.Name)
  if($child -is [IO.DirectoryInfo]){Copy-AC7ModTree $child.FullName $target}else{[IO.File]::Copy($child.FullName,$target,$false)}
 }
}
function Expand-AC7ModArchive([string]$Zip,[string]$Destination) {
 # Zip only (System.IO.Compression). Entries must stay inside the destination; size and count are bounded.
 Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
 $dest=[IO.Path]::GetFullPath($Destination).TrimEnd('\','/');[void][IO.Directory]::CreateDirectory($dest)
 $archive=[IO.Compression.ZipFile]::OpenRead($Zip)
 try{
  if($archive.Entries.Count -gt 50000){throw '压缩包里的文件太多（超过 50000 个）。'}
  $total=0L;foreach($entry in $archive.Entries){$total+=$entry.Length}
  if($total -gt 2GB){throw '压缩包解压后超过 2 GB，不像是 UE4SS Mod。'}
  foreach($entry in $archive.Entries){
   $name=$entry.FullName.Replace('/','\')
   if(!$name -or $name.StartsWith('\') -or $name.Contains(':') -or $name -match '(^|\\)\.\.(\\|$)'){throw '压缩包含有不安全的路径，已拒绝。'}
   $target=[IO.Path]::GetFullPath([IO.Path]::Combine($dest,$name))
   if(!$target.StartsWith($dest+'\',[StringComparison]::OrdinalIgnoreCase)){throw '压缩包含有不安全的路径，已拒绝。'}
   if($name.EndsWith('\')){[void][IO.Directory]::CreateDirectory($target);continue}
   [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
   [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$true)
  }
 }finally{$archive.Dispose()}
}
function Get-AC7ModLayoutKind([string]$Path) {
 $kind=@()
 if(Test-Path -LiteralPath (Join-Path $Path 'Scripts\main.lua') -PathType Leaf){$kind+='Lua'}
 if(Test-Path -LiteralPath (Join-Path $Path 'dlls\main.dll') -PathType Leaf){$kind+='C++'}
 return ($kind -join '+')
}
function Find-AC7ModRoots([string]$Root,[int]$Depth=0) {
 # Folders with the standard UE4SS mod layout, outermost first; a found mod is not searched further.
 $kind=Get-AC7ModLayoutKind $Root
 if($kind){return @([pscustomobject]@{Path=[IO.Path]::GetFullPath($Root);Kind=$kind})}
 if($Depth -ge 6){return @()}
 $found=@()
 foreach($dir in @(Get-ChildItem -LiteralPath $Root -Directory -Force | Sort-Object Name)){
  if($dir.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
  $found+=@(Find-AC7ModRoots $dir.FullName ($Depth+1))
 }
 return $found
}
function Get-AC7ModNameFromSource([string]$Source) {
 # A mod packed without its own folder takes its name from the zip or folder name ("Some Mod v1.2.zip" -> SomeMod).
 $name=[IO.Path]::GetFileNameWithoutExtension($Source.TrimEnd('\','/'))
 $name=($name -replace '(?i)[ _.-]*v?\d+(\.\d+)+.*$','') -replace '[^A-Za-z0-9_.\-]',''
 return $name.TrimStart('_','.','-')
}
function New-AC7ExtraModPlan([string]$DataRoot,[string]$Source) {
 # Inspect a zip or folder without changing ue4ss-mods. A zip is unpacked into ue4ss-mods-staging; always finish
 # with Remove-AC7ExtraModPlan. Items: Name, Kind, Path, Problem, Existing (enabled/disabled/$null).
 $mods=Join-Path $DataRoot 'ue4ss-mods';[void][IO.Directory]::CreateDirectory($mods)
 $source=[IO.Path]::GetFullPath($Source).TrimEnd('\','/');$staging=$null
 if(Test-Path -LiteralPath $source -PathType Leaf){
  if([IO.Path]::GetExtension($source) -ine '.zip'){throw '只支持 .zip 压缩包或文件夹。7z／rar 请先解压，再选择解压出来的文件夹。'}
  $staging=Join-Path $DataRoot ('ue4ss-mods-staging\'+[guid]::NewGuid().ToString('N'))
  try{Expand-AC7ModArchive $source $staging}catch{Remove-AC7ExtraModTree $staging;throw}
  $scan=$staging
 }elseif(Test-Path -LiteralPath $source -PathType Container){
  $inside=[IO.Path]::GetFullPath($DataRoot).TrimEnd('\')+'\'
  if(($source+'\').StartsWith($inside,[StringComparison]::OrdinalIgnoreCase)){throw '请选择数据文件夹以外的 Mod（例如下载并解压后的文件夹）。'}
  $links=@(Get-AC7ModTreeLinks $source);if($links.Count){throw ('文件夹里有文件系统链接，已拒绝：'+$links[0])}
  $scan=$source
 }else{throw "找不到：$Source"}
 $items=@();$warnings=@()
 foreach($root in @(Find-AC7ModRoots $scan)){
  $name=if($root.Path -eq [IO.Path]::GetFullPath($scan)){Get-AC7ModNameFromSource $source}else{Split-Path $root.Path -Leaf}
  $problem=Get-AC7ExtraModNameProblem $name
  if(!$problem -and @($items | Where-Object {$_.Name -eq $name}).Count){$problem='同一来源里有重名的 Mod'}
  $existing=$null
  if($name -and (Test-Path -LiteralPath (Join-Path $mods $name))){$existing='enabled'}elseif($name -and (Test-Path -LiteralPath (Join-Path $mods ('_'+$name)))){$existing='disabled'}
  $items+=[pscustomobject]@{Name=$name;Kind=$root.Kind;Path=$root.Path;Problem=$problem;Existing=$existing}
 }
 $files=@(Get-ChildItem -LiteralPath $scan -Recurse -File -Force)
 $loader=@($files | Where-Object {(Test-AC7ModSkippedFile $_.Name) -and $_.Extension -notin @('.pak','.utoc','.ucas')} | ForEach-Object Name | Select-Object -Unique)
 if($loader.Count){$warnings+=('含有 UE4SS 本体文件（'+($loader -join '、')+'），不会安装：本整合包已经自带 UE4SS。')}
 if(@($files | Where-Object {$_.Extension -in @('.pak','.utoc','.ucas')}).Count){$warnings+='含有 .pak 资源文件，不会安装：Pak 由游戏自身加载，需要时请按该 Mod 的说明手动放入游戏目录。'}
 $shared=@(Get-ChildItem -LiteralPath $scan -Recurse -Directory -Force -Filter 'shared' | ForEach-Object {Get-ChildItem -LiteralPath $_.FullName -Directory -Force} | Where-Object {$_.Name -ne 'UEHelpers'} | ForEach-Object Name | Select-Object -Unique)
 if($shared.Count){$warnings+=('含有共享库（'+($shared -join '、')+'），不会安装：本包只附带 UEHelpers，依赖其他共享库的 Mod 可能无法工作。')}
 if(@($items | Where-Object {!$_.Problem -and $_.Kind -match 'C\+\+'}).Count){$warnings+='C++ Mod 会在游戏中运行原生代码：只安装可信来源的 Mod，并确认它适用于本包的 UE4SS 版本（3.0.1 Beta 48e7edfe），否则可能无法加载或导致崩溃。'}
 return [pscustomobject]@{Source=$source;Staging=$staging;Items=$items;Warnings=$warnings}
}
function Remove-AC7ExtraModTree([string]$Path) {
 # Deletes without following filesystem links (Windows PowerShell 5.1 Remove-Item -Recurse does follow them).
 if(!$Path -or !(Test-Path -LiteralPath $Path)){return}
 $item=Get-Item -LiteralPath $Path -Force
 if($item.Attributes -band [IO.FileAttributes]::ReparsePoint -or !$item.PSIsContainer){if($item.PSIsContainer){[IO.Directory]::Delete($item.FullName,$false)}else{$item.Attributes='Normal';$item.Delete()};return}
 foreach($child in @(Get-ChildItem -LiteralPath $Path -Force)){Remove-AC7ExtraModTree $child.FullName}
 [IO.Directory]::Delete($item.FullName,$false)
}
function Remove-AC7ExtraModPlan($Plan) {if($Plan -and $Plan.Staging){Remove-AC7ExtraModTree $Plan.Staging}}
function Get-AC7ExtraModBackupFolder([string]$DataRoot) {
 $folder=Join-Path $DataRoot ('ue4ss-mods-removed\'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
 [void][IO.Directory]::CreateDirectory($folder);return $folder
}
function Install-AC7ExtraModPlan($Plan,[string]$DataRoot,[bool]$Replace=$false) {
 # Copies each valid item into ue4ss-mods. An existing mod is skipped, or with -Replace moved to ue4ss-mods-removed
 # first and replaced, keeping its enabled/disabled state. Returns Name, Status (added/replaced/skipped/invalid), Message.
 $mods=Join-Path $DataRoot 'ue4ss-mods';[void][IO.Directory]::CreateDirectory($mods)
 $work=Join-Path $DataRoot ('ue4ss-mods-staging\copy-'+[guid]::NewGuid().ToString('N'))
 $results=@();$backup=$null
 try{
  foreach($item in @($Plan.Items)){
   if($item.Problem){$results+=[pscustomobject]@{Name=$item.Name;Status='invalid';Message=$item.Problem};continue}
   if($item.Existing -and !$Replace){$results+=[pscustomobject]@{Name=$item.Name;Status='skipped';Message='已存在，未替换'};continue}
   $target=if($item.Existing -eq 'disabled'){'_'+$item.Name}else{$item.Name}
   $copy=Join-Path $work $item.Name;Copy-AC7ModTree $item.Path $copy
   if($item.Existing){
    if(!$backup){$backup=Get-AC7ExtraModBackupFolder $DataRoot}
    [IO.Directory]::Move((Join-Path $mods $target),(Join-Path $backup $target))
    try{[IO.Directory]::Move($copy,(Join-Path $mods $target))}catch{[IO.Directory]::Move((Join-Path $backup $target),(Join-Path $mods $target));throw}
   }else{[IO.Directory]::Move($copy,(Join-Path $mods $target))}
   $results+=[pscustomobject]@{Name=$item.Name;Status=$(if($item.Existing){'replaced'}else{'added'});Message=$(if($item.Existing){'已替换（旧版本移到 ue4ss-mods-removed）'}else{'已添加'})}
  }
 }finally{Remove-AC7ExtraModTree $work}
 return $results
}
function Set-AC7ExtraModEnabled([string]$DataRoot,[string]$Name,[bool]$Enabled) {
 # Enabled: the folder name without leading _; disabled: _ + name (what Get-AC7ExtraMods skips).
 $mods=Join-Path $DataRoot 'ue4ss-mods';$path=Join-Path $mods $Name
 if(!$Name -or $Name.Contains('\') -or $Name.Contains('/') -or !(Test-Path -LiteralPath $path -PathType Container)){throw "找不到附加 Mod：$Name"}
 $plain=$Name.TrimStart('_')
 if($Enabled){
  $problem=Get-AC7ExtraModNameProblem $plain;if($problem){throw ("无法启用 $Name：$problem。请先在文件夹中改名。")}
  $target=$plain
 }else{$target='_'+$plain}
 if($target -ceq $Name){return $Name}
 if(Test-Path -LiteralPath (Join-Path $mods $target)){throw "已有同名文件夹 $target，请先处理重复的 Mod。"}
 [IO.Directory]::Move($path,(Join-Path $mods $target));return $target
}
function Remove-AC7ExtraMod([string]$DataRoot,[string]$Name) {
 # Not deleted: moved to ue4ss-mods-removed\<time>\<name>, where it can be restored by moving it back.
 $mods=Join-Path $DataRoot 'ue4ss-mods';$path=Join-Path $mods $Name
 if(!$Name -or $Name.Contains('\') -or $Name.Contains('/') -or !(Test-Path -LiteralPath $path -PathType Container)){throw "找不到附加 Mod：$Name"}
 $backup=Get-AC7ExtraModBackupFolder $DataRoot
 [IO.Directory]::Move($path,(Join-Path $backup $Name));return (Join-Path $backup $Name)
}

# ---- deployment into the game folder (AC7: the mod is installed persistently) ----
function Get-AC7ExtraModRecordPath([string]$GameRoot){return (Join-Path $GameRoot 'ue4ss\AC7-ExtraMods.json')}
function Read-AC7ExtraModRecord([string]$GameRoot){
 $path=Get-AC7ExtraModRecordPath $GameRoot
 if(!(Test-Path -LiteralPath $path -PathType Leaf)){return @()}
 $record=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
 return @($record.Mods | Where-Object {$_ -and $_.Name -and !(Get-AC7ExtraModNameProblem ([string]$_.Name))})
}
function Get-AC7ExtraModFileList([string]$Folder){
 # Relative path and SHA-256 of every file a deployed copy of $Folder contains (loader files and paks skipped).
 $root=[IO.Path]::GetFullPath($Folder).TrimEnd('\')
 return @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object {!(Test-AC7ModSkippedFile $_.Name)} | Sort-Object FullName | ForEach-Object {
  [pscustomobject]@{Relative=$_.FullName.Substring($root.Length+1);SHA256=(Get-AC7FileHash -LiteralPath $_.FullName).Hash}})
}
function Get-AC7ExtraModGameState([string]$DataRoot,[string]$GameRoot){
 # Per library mod: deployed (identical copy in the game), pending (sync needed), conflict (a folder of that name in the
 # game was not placed by this tool), off (disabled or invalid). Used by the dialog and the sync.
 $recorded=@{};if($GameRoot -and (Test-Path -LiteralPath (Join-Path $GameRoot 'ue4ss'))){foreach($mod in @(Read-AC7ExtraModRecord $GameRoot)){$recorded[[string]$mod.Name]=$mod}}
 $state=@{}
 foreach($mod in @(Get-AC7ExtraMods $DataRoot)){
  if($mod.Problem){$state[$mod.Name]='off';continue}
  if(!$GameRoot){$state[$mod.Name]='pending';continue}
  $folder=Join-Path $GameRoot ('ue4ss\Mods\'+$mod.Name)
  if($recorded.ContainsKey($mod.Name)){
   $want=@(Get-AC7ExtraModFileList $mod.Path | Where-Object {$_.Relative -ine 'enabled.txt'})+@([pscustomobject]@{Relative='enabled.txt';SHA256=(Get-AC7BytesHash ([byte[]]@()))})
   $have=@($recorded[$mod.Name].Files)
   $same=($want.Count -eq $have.Count)
   if($same){foreach($file in $want){$match=@($have | Where-Object {[string]$_.Relative -ieq $file.Relative -and [string]$_.SHA256 -eq $file.SHA256});$path=Join-Path $folder $file.Relative
    if(!$match.Count -or !(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-AC7FileHash -LiteralPath $path).Hash -ne $file.SHA256){$same=$false;break}}}
   $state[$mod.Name]=if($same){'deployed'}else{'pending'}
  }elseif(Test-Path -LiteralPath $folder){$state[$mod.Name]='conflict'}
  else{$state[$mod.Name]='pending'}
 }
 return $state
}
function Sync-AC7ExtraMods([string]$PackageRoot,[string]$GameRoot,[switch]$RemoveAll){
 # Make the game's ue4ss\Mods match the enabled library mods (or, with -RemoveAll, remove everything this tool
 # deployed). Only recorded files with unchanged content are removed; changed ones are kept and reported. Needs the
 # game closed and this mod installed (UE4SS present).
 $data=Get-AC7DataRoot $PackageRoot
 $result=[pscustomobject]@{Applied=$false;Deployed=@();Removed=@();Kept=@();Conflicts=@();Message=''}
 $game=[IO.Path]::GetFullPath($GameRoot).TrimEnd('\','/')
 $ue4ss=Join-Path $game 'ue4ss'
 if(!(Test-Path -LiteralPath (Join-Path $ue4ss 'UE4SS.dll') -PathType Leaf) -and !$RemoveAll){$result.Message='游戏中尚未安装本 Mod（没有 UE4SS），附加 Mod 会在安装后部署。';return $result}
 Assert-AC7GameClosed $game
 Assert-AC7NoLinks $ue4ss
 $mods=Join-Path $ue4ss 'Mods'
 $recorded=@{};foreach($mod in @(Read-AC7ExtraModRecord $game)){$recorded[[string]$mod.Name]=$mod}
 $wanted=@{};if(!$RemoveAll){foreach($mod in @(Get-AC7ExtraMods $data | Where-Object {!$_.Problem})){$wanted[$mod.Name]=$mod}}
 $states=if($RemoveAll){@{}}else{Get-AC7ExtraModGameState $data $game}
 $keep=@()
 # 1. remove recorded copies that are no longer wanted or out of date
 foreach($name in @($recorded.Keys)){
  if($wanted.ContainsKey($name) -and $states[$name] -eq 'deployed'){$keep+=$recorded[$name];continue}
  $folder=Join-Path $mods $name;$left=@()
  foreach($file in @($recorded[$name].Files)){
   $path=Join-Path $folder ([string]$file.Relative)
   if(!(Test-Path -LiteralPath $path -PathType Leaf)){continue}
   if((Get-AC7FileHash -LiteralPath $path).Hash -eq [string]$file.SHA256){Remove-Item -LiteralPath $path -Force}else{$left+=$file;$result.Kept+=($name+'\'+$file.Relative)}
  }
  if(Test-Path -LiteralPath $folder){foreach($dir in @(Get-ChildItem -LiteralPath $folder -Recurse -Directory -Force | Sort-Object {$_.FullName.Length} -Descending)){if(!@(Get-ChildItem -LiteralPath $dir.FullName -Force).Count){[IO.Directory]::Delete($dir.FullName,$false)}}
   if(!@(Get-ChildItem -LiteralPath $folder -Force).Count){[IO.Directory]::Delete($folder,$false)}}
  if($left.Count){$keep+=[pscustomobject]@{Name=$name;Files=$left}}
  if(!$wanted.ContainsKey($name)){$result.Removed+=$name}
 }
 # 2. deploy wanted mods that are not already identical in the game
 foreach($name in @($wanted.Keys | Sort-Object)){
  if($states[$name] -eq 'deployed'){continue}
  $folder=Join-Path $mods $name
  if(!$recorded.ContainsKey($name) -and (Test-Path -LiteralPath $folder)){$result.Conflicts+=$name;continue}
  if(Test-Path -LiteralPath $folder){$result.Conflicts+=$name;continue}   # leftovers of a changed copy were kept above
  Copy-AC7ModTree $wanted[$name].Path $folder
  [IO.File]::WriteAllBytes((Join-Path $folder 'enabled.txt'),[byte[]]@())
  $keep+=[pscustomobject]@{Name=$name;Files=@(Get-AC7ExtraModFileList $folder)}
  $result.Deployed+=$name
 }
 $record=Get-AC7ExtraModRecordPath $game
 if($keep.Count){Write-AC7Json ([pscustomobject]@{Schema=1;Tool='AC7-Integrated';Mods=@($keep)}) $record}
 elseif(Test-Path -LiteralPath $record){Remove-Item -LiteralPath $record -Force}
 $result.Applied=$true
 $parts=@()
 if($result.Deployed.Count){$parts+=('已部署：'+($result.Deployed -join '、'))}
 if($result.Removed.Count){$parts+=('已从游戏移除：'+($result.Removed -join '、'))}
 if($result.Conflicts.Count){$parts+=('游戏里已有同名文件夹（不是本工具放的），未覆盖：'+($result.Conflicts -join '、'))}
 if($result.Kept.Count){$parts+=('这些文件被改动过，已保留：'+($result.Kept -join '、'))}
 $result.Message=if($parts.Count){($parts -join '；')+'。'}else{'游戏中的附加 Mod 已是最新。'}
 return $result
}
