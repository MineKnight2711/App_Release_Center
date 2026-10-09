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
$providerKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\$providerId"
$classKey = "Registry::HKEY_CLASSES_ROOT\CLSID\$providerId"
Remove-Item -LiteralPath $providerKey -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $classKey -Recurse -Force -ErrorAction SilentlyContinue

$dataDirectory = Join-Path $env:ProgramData 'App Management Center\Remote Unlock'
$configFile = Join-Path $dataDirectory 'config.txt'
if (Test-Path -LiteralPath $configFile) {
  $thumbprint = (Get-Content -LiteralPath $configFile -Raw).Trim()
  if ($thumbprint) {
    Remove-Item -LiteralPath "Cert:\LocalMachine\My\$thumbprint" -Force -ErrorAction SilentlyContinue
  }
}
Remove-Item -LiteralPath $dataDirectory -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item `
  -LiteralPath (Join-Path $env:ProgramFiles 'App Management Center\Remote Unlock') `
  -Recurse `
  -Force `
  -ErrorAction SilentlyContinue

Write-Host 'AMC Remote Unlock removed. The standard Windows sign-in providers were not changed.'
