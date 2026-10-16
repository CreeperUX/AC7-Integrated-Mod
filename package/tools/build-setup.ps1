# Build AC7-Integrated-Setup-v<version>.exe with IExpress (part of Windows). The setup program unpacks the release zip
# together with its own app/Install-App.ps1, app/App-Core.ps1 and app/install.cmd into a temporary folder and runs
# install.cmd: a per-user install without administrator rights (see app\Install-App.ps1). The three scripts are taken
# from the zip, so the setup program and the package it installs always match. Not shipped to players.
param([Parameter(Mandatory=$true)][string]$Zip,[string]$OutDir='')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$zipPath=[IO.Path]::GetFullPath($Zip);$name=[IO.Path]::GetFileName($zipPath)
$match=[regex]::Match($name,'^AC7-Integrated-v(\d+\.\d+\.\d+(?:-(?:alpha|beta|rc)\.\d+)?)\.zip$')
if(!$match.Success){throw "Unexpected release zip name: $name"}
$version=$match.Groups[1].Value;$top='AC7-Integrated-v'+$version+'/'
if(!$OutDir){$OutDir=[IO.Path]::GetDirectoryName($zipPath)}
[void][IO.Directory]::CreateDirectory($OutDir)
$output=Join-Path ([IO.Path]::GetFullPath($OutDir)) ('AC7-Integrated-Setup-v'+$version+'.exe')
if(Test-Path -LiteralPath $output){throw "Output already exists: $output"}
$iexpress=Join-Path $env:SystemRoot 'System32\iexpress.exe'
if(!(Test-Path -LiteralPath $iexpress)){throw 'IExpress (iexpress.exe) is not available on this Windows installation.'}
$work=Join-Path ([IO.Path]::GetTempPath()) ('ac7-setup-'+[guid]::NewGuid().ToString('N'));$files=Join-Path $work 'files'
New-Item -ItemType Directory -Path $files | Out-Null
try{
 $archive=[IO.Compression.ZipFile]::OpenRead($zipPath)
 try{
  foreach($leaf in 'Install-App.ps1','App-Core.ps1','install.cmd'){
   $entry=@($archive.Entries | Where-Object {$_.FullName.Replace([char]92,[char]47) -ceq ($top+'app/'+$leaf)})[0]
   if(!$entry){throw "Missing in zip: app/$leaf"}
   [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,(Join-Path $files $leaf),$false)
  }
 }finally{$archive.Dispose()}
 Copy-Item -LiteralPath $zipPath -Destination (Join-Path $files $name)
 $target=Join-Path $work 'setup.exe';$sed=Join-Path $work 'setup.sed'
 $leaves=@($name,'Install-App.ps1','App-Core.ps1','install.cmd')
 $lines=@('[Version]','Class=IEXPRESS','SEDVersion=3','[Options]','PackagePurpose=InstallApp','ShowInstallProgramWindow=0','HideExtractAnimation=1',
  'UseLongFileName=1','InsideCompressed=0','CAB_FixedSize=0','CAB_ResvCodeSigning=0','RebootMode=N','InstallPrompt=%InstallPrompt%',
  'DisplayLicense=%DisplayLicense%','FinishMessage=%FinishMessage%','TargetName=%TargetName%','FriendlyName=%FriendlyName%',
  'AppLaunched=%AppLaunched%','PostInstallCmd=%PostInstallCmd%','AdminQuietInstCmd=%AdminQuietInstCmd%','UserQuietInstCmd=%UserQuietInstCmd%',
  'SourceFiles=SourceFiles','[Strings]','InstallPrompt=','DisplayLicense=','FinishMessage=',('TargetName='+$target),
  ('FriendlyName=AC7 Integrated '+$version+' Setup'),'AppLaunched=cmd.exe /c install.cmd','PostInstallCmd=<None>','AdminQuietInstCmd=','UserQuietInstCmd=')
 for($i=0;$i -lt $leaves.Count;$i++){$lines+=('FILE'+$i+'="'+$leaves[$i]+'"')}
 $lines+=@('[SourceFiles]',('SourceFiles0='+$files+'\'),'[SourceFiles0]')
 for($i=0;$i -lt $leaves.Count;$i++){$lines+=('%FILE'+$i+'%=')}
 [IO.File]::WriteAllLines($sed,$lines,[Text.Encoding]::ASCII)
 # IExpress does not accept a quoted SED path: run it in the work folder with the bare file name.
 $process=Start-Process -FilePath $iexpress -WorkingDirectory $work -ArgumentList @('/N','/Q','/M','setup.sed') -Wait -PassThru -WindowStyle Hidden
 if($process.ExitCode -ne 0 -or !(Test-Path -LiteralPath $target)){throw "IExpress did not create the setup program (exit $($process.ExitCode))."}
 Copy-Item -LiteralPath $target -Destination $output
}finally{if(Test-Path -LiteralPath $work){Remove-Item -LiteralPath $work -Recurse -Force}}
$hash=(Get-FileHash -LiteralPath $output).Hash
[IO.File]::WriteAllText($output+'.sha256',($hash.ToLowerInvariant()+'  '+[IO.Path]::GetFileName($output)+"`n"))
Write-Host ("$output ($((Get-Item -LiteralPath $output).Length) bytes, SHA256 $hash)")
