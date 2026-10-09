param([string]$PackageRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Install-Core.ps1')
$info=Test-AC7Package $PackageRoot
Write-Host ('PACKAGE CHECK passed: AC7 '+$info.version+' required files, payload hashes and settings. No game files touched.')
