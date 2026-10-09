param([string]$PackageRoot=(Split-Path $PSScriptRoot -Parent))
# Developer tool: regenerate payload-manifest.json after the payload changes (for example a new DLL build),
# and keep package-info.json native_sha256 in sync by hand. Check-Package.ps1 verifies both.
$ErrorActionPreference='Stop'
. (Join-Path $PackageRoot 'PowerShell-Compat.ps1')
$payload=[IO.Path]::GetFullPath((Join-Path $PackageRoot 'payload')).TrimEnd('\','/')
$lines=@()
foreach($file in @(Get-ChildItem -LiteralPath $payload -File -Recurse -Force | Sort-Object FullName)){
 $relative=$file.FullName.Substring($payload.Length+1).Replace('\','\\')
 $lines+=('  {"Path": "'+$relative+'", "SHA256": "'+(Get-AC7FileHash -LiteralPath $file.FullName).Hash+'"}')
}
$text="[`r`n"+($lines -join ",`r`n")+"`r`n]`r`n"
[IO.File]::WriteAllText((Join-Path $PackageRoot 'payload-manifest.json'),$text,[Text.UTF8Encoding]::new($false))
Write-Host ('payload-manifest.json: '+$lines.Count+' files')
