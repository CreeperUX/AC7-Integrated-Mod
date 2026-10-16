# Write update-manifest.json and update-manifest.json.sig for an AC7 release zip; both are uploaded as release assets
# next to the zip. The manifest names the zip, its SHA-256 and size; the signature is RSA-SHA256 (PKCS#1 v1.5, base64)
# over the exact manifest bytes. The signature is checked against the public key inside the zip (app/update-key.xml), so
# a package can never be published with a key that does not match. Not shipped to players.
param([Parameter(Mandatory=$true)][string]$Zip,[Parameter(Mandatory=$true)][string]$PrivateKeyPath,[string]$OutDir='')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Security,System.IO.Compression,System.IO.Compression.FileSystem
$zipPath=[IO.Path]::GetFullPath($Zip);$name=[IO.Path]::GetFileName($zipPath)
$match=[regex]::Match($name,'^AC7-Integrated-v(\d+\.\d+\.\d+(?:-(?:alpha|beta|rc)\.\d+)?)\.zip$')
if(!$match.Success){throw "Unexpected release zip name: $name"}
$version=$match.Groups[1].Value;$top='AC7-Integrated-v'+$version+'/'
function Read-ZipText($Archive,[string]$Path){
 # Entry names may use / (the release builder) or \ (older .NET zip tools).
 $entry=@($Archive.Entries | Where-Object {$_.FullName.Replace([char]92,[char]47) -ceq $Path})[0];if(!$entry){throw "Missing in zip: $Path"}
 $reader=New-Object IO.StreamReader($entry.Open());try{return $reader.ReadToEnd()}finally{$reader.Dispose()}
}
$archive=[IO.Compression.ZipFile]::OpenRead($zipPath)
try{
 if([string]((Read-ZipText $archive ($top+'package-info.json')) | ConvertFrom-Json).version -ne $version){throw 'package-info.json version differs from the zip name.'}
 $null=Read-ZipText $archive ($top+'app/Host.ps1')
 $null=Read-ZipText $archive ($top+'FILES.sha256')
 $publicKey=Read-ZipText $archive ($top+'app/update-key.xml')
}finally{$archive.Dispose()}
if($publicKey -match '<(D|P|Q|DP|DQ|InverseQ)>'){throw 'The packaged update key contains private key material.'}
$sha=[Security.Cryptography.SHA256]::Create();$stream=[IO.File]::OpenRead($zipPath)
try{$digest=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}finally{$stream.Dispose();$sha.Dispose()}
$manifest=[pscustomobject][ordered]@{schema=1;product='AC7-Integrated';version=$version;asset=$name;sha256=$digest;size=(New-Object IO.FileInfo($zipPath)).Length}
$bytes=(New-Object Text.UTF8Encoding($false)).GetBytes((ConvertTo-Json -InputObject $manifest))
$plain=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes([IO.Path]::GetFullPath($PrivateKeyPath)),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
$signer=New-Object Security.Cryptography.RSACryptoServiceProvider;$signer.PersistKeyInCsp=$false
try{$signer.FromXmlString([Text.Encoding]::UTF8.GetString($plain));$signature=$signer.SignData($bytes,'SHA256')}finally{[Array]::Clear($plain,0,$plain.Length);$signer.Dispose()}
$verifier=New-Object Security.Cryptography.RSACryptoServiceProvider;$verifier.PersistKeyInCsp=$false
try{$verifier.FromXmlString($publicKey);if($verifier.KeySize -lt 3072 -or !$verifier.VerifyData($bytes,'SHA256',$signature)){throw 'The public key inside the zip does not match the signing key.'}}finally{$verifier.Dispose()}
if(!$OutDir){$OutDir=[IO.Path]::GetDirectoryName($zipPath)}
[void][IO.Directory]::CreateDirectory($OutDir)
[IO.File]::WriteAllBytes((Join-Path $OutDir 'update-manifest.json'),$bytes)
[IO.File]::WriteAllText((Join-Path $OutDir 'update-manifest.json.sig'),[Convert]::ToBase64String($signature),(New-Object Text.UTF8Encoding($false)))
Write-Host ("Signed update manifest for $name ($version, SHA256 $digest) in $OutDir")
