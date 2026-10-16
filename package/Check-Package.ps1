param([string]$PackageRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Install-Core.ps1')
$info=Test-AC7Package $PackageRoot
# Installed app (0.7.0): the shipped update key must be a public RSA key of at least 3072 bits (no private parts).
$updateKey=[IO.File]::ReadAllText((Join-Path $PackageRoot 'app\update-key.xml'))
if($updateKey -match '<(D|P|Q|DP|DQ|InverseQ)>'){Stop-AC7Problem 'PACKAGE' 'app\update-key.xml 含有私钥内容。' '不要发布这个整合包；只能放公钥。'}
$rsa=New-Object Security.Cryptography.RSACryptoServiceProvider;$rsa.PersistKeyInCsp=$false
try{$rsa.FromXmlString($updateKey);if($rsa.KeySize -lt 3072){Stop-AC7Problem 'PACKAGE' 'app\update-key.xml 不是有效的更新公钥。' '请重新解压完整的整合包。'}}finally{$rsa.Dispose()}
Write-Host ('PACKAGE CHECK passed: AC7 '+$info.version+' required files, payload hashes, settings and update key. No game files touched.')
