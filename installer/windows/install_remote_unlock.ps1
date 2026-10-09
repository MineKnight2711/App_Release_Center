param([switch]$Elevated)

$ErrorActionPreference = 'Stop'

function Test-Administrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
  $arguments = @(
    '-NoProfile'
    '-ExecutionPolicy', 'Bypass'
    '-File', ('"{0}"' -f $PSCommandPath)
    '-Elevated'
  )
  $process = Start-Process `
    powershell.exe `
    -Verb RunAs `
    -ArgumentList $arguments `
    -Wait `
    -PassThru
  exit $process.ExitCode
}

$providerId = '{7C74A62C-784B-4D6A-B84E-57EE71A46F39}'
$sourceDll = Join-Path $PSScriptRoot 'amc_remote_unlock_provider.dll'
if (-not (Test-Path -LiteralPath $sourceDll -PathType Leaf)) {
  throw 'Remote unlock provider DLL is missing.'
}

$installDirectory = Join-Path $env:ProgramFiles 'App Management Center\Remote Unlock'
$dataDirectory = Join-Path $env:ProgramData 'App Management Center\Remote Unlock'
New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null

$providerDll = Join-Path $installDirectory 'amc_remote_unlock_provider.dll'
Copy-Item -LiteralPath $sourceDll -Destination $providerDll -Force

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$acl = [Security.AccessControl.DirectorySecurity]::new()
$acl.SetAccessRuleProtection($true, $false)
$inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
$propagate = [Security.AccessControl.PropagationFlags]::None
$full = [Security.AccessControl.FileSystemRights]::FullControl
$modify = [Security.AccessControl.FileSystemRights]::Modify
foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
  $rule = [Security.AccessControl.FileSystemAccessRule]::new(
    [Security.Principal.SecurityIdentifier]::new($sid),
    $full,
    $inherit,
    $propagate,
    [Security.AccessControl.AccessControlType]::Allow
  )
  $acl.AddAccessRule($rule)
}
$userRule = [Security.AccessControl.FileSystemAccessRule]::new(
  $identity.User,
  $modify,
  $inherit,
  $propagate,
  [Security.AccessControl.AccessControlType]::Allow
)
$acl.AddAccessRule($userRule)
Set-Acl -LiteralPath $dataDirectory -AclObject $acl

$configFile = Join-Path $dataDirectory 'config.txt'
$thumbprint = if (Test-Path -LiteralPath $configFile) {
  (Get-Content -LiteralPath $configFile -Raw).Trim()
} else {
  ''
}
$certificate = if ($thumbprint) {
  Get-Item -LiteralPath "Cert:\LocalMachine\My\$thumbprint" -ErrorAction SilentlyContinue
} else {
  $null
}
if (-not $certificate) {
  $certificate = New-SelfSignedCertificate `
    -Type Custom `
    -Subject 'CN=AMC Remote Unlock' `
    -KeyAlgorithm RSA `
    -KeyLength 3072 `
    -Provider 'Microsoft Software Key Storage Provider' `
    -HashAlgorithm SHA256 `
    -KeyExportPolicy NonExportable `
    -KeyUsage KeyEncipherment `
    -CertStoreLocation 'Cert:\LocalMachine\My' `
    -NotAfter (Get-Date).AddYears(10)
  $thumbprint = $certificate.Thumbprint
}

$rsa = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($certificate)
$parameters = $rsa.ExportParameters($false)
function ConvertTo-Base64Url([byte[]]$Bytes) {
  return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}
$publicKey = [ordered]@{
  version = 1
  keyId = $thumbprint
  modulus = ConvertTo-Base64Url $parameters.Modulus
  exponent = ConvertTo-Base64Url $parameters.Exponent
}
[IO.File]::WriteAllText($configFile, $thumbprint, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText(
  (Join-Path $dataDirectory 'public-key.json'),
  ($publicKey | ConvertTo-Json -Compress),
  [Text.UTF8Encoding]::new($false)
)

$providerKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\$providerId"
$classKey = "Registry::HKEY_CLASSES_ROOT\CLSID\$providerId"
$serverKey = Join-Path $classKey 'InprocServer32'
New-Item -Path $providerKey -Force | Out-Null
Set-Item -Path $providerKey -Value 'AMC Remote Unlock'
New-Item -Path $serverKey -Force | Out-Null
Set-Item -Path $serverKey -Value $providerDll
New-ItemProperty -Path $serverKey -Name ThreadingModel -Value Apartment -PropertyType String -Force | Out-Null

Write-Host 'AMC Remote Unlock installed. Lock Windows once to load the provider.'
