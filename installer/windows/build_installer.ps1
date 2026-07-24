param(
  [string]$Version = ''
)

$ErrorActionPreference = 'Stop'

function Assert-ChildPath {
  param(
    [Parameter(Mandatory = $true)][string]$Candidate,
    [Parameter(Mandatory = $true)][string]$Parent
  )

  $candidatePath = [System.IO.Path]::GetFullPath($Candidate)
  $parentPath = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
  if (-not $candidatePath.StartsWith(
      $parentPath,
      [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw "Unsafe installer build path: $candidatePath"
  }
}

$projectRoot = [System.IO.Path]::GetFullPath(
  (Join-Path $PSScriptRoot '..\..')
)
$releaseDirectory = Join-Path `
  $projectRoot `
  'build\windows\x64\runner\Release'
$releaseExecutable = Join-Path `
  $releaseDirectory `
  'app_release_center.exe'
if (-not (Test-Path -LiteralPath $releaseExecutable -PathType Leaf)) {
  throw 'Windows release build is missing. Run flutter build windows --release first.'
}

if ([string]::IsNullOrWhiteSpace($Version)) {
  $pubspec = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Raw
  $versionMatch = [regex]::Match(
    $pubspec,
    '(?m)^\s*version:\s*([^\s]+)\s*$'
  )
  if (-not $versionMatch.Success) {
    throw 'Could not read the application version from pubspec.yaml.'
  }
  $Version = $versionMatch.Groups[1].Value.Split('+')[0]
}

$safeVersion = $Version -replace '[^0-9A-Za-z._-]', '_'
$buildDirectory = Join-Path $projectRoot 'build\installer'
$stageDirectory = Join-Path $buildDirectory 'stage'
$payloadDirectory = Join-Path $buildDirectory 'payload'
$payloadArchive = Join-Path $stageDirectory 'payload.zip'
$sedPath = Join-Path $buildDirectory 'app_release_center.sed'
$targetPath = Join-Path `
  $buildDirectory `
  "AppReleaseCenter_Setup_v$safeVersion.exe"

Assert-ChildPath -Candidate $stageDirectory -Parent $buildDirectory
Assert-ChildPath -Candidate $payloadDirectory -Parent $buildDirectory
if (Test-Path -LiteralPath $stageDirectory) {
  Remove-Item -LiteralPath $stageDirectory -Recurse -Force
}
if (Test-Path -LiteralPath $payloadDirectory) {
  Remove-Item -LiteralPath $payloadDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $payloadDirectory -Force | Out-Null

Get-ChildItem -LiteralPath $releaseDirectory -Force | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination $payloadDirectory -Recurse -Force
}
Copy-Item `
  -LiteralPath (Join-Path $PSScriptRoot 'uninstall.ps1') `
  -Destination (Join-Path $payloadDirectory 'uninstall.ps1') `
  -Force
Copy-Item `
  -LiteralPath (Join-Path $PSScriptRoot 'install.ps1') `
  -Destination (Join-Path $stageDirectory 'install.ps1') `
  -Force
Set-Content `
  -LiteralPath (Join-Path $stageDirectory 'version.txt') `
  -Value $Version `
  -Encoding Ascii

Compress-Archive `
  -Path (Join-Path $payloadDirectory '*') `
  -DestinationPath $payloadArchive `
  -CompressionLevel Optimal `
  -Force

if (Test-Path -LiteralPath $targetPath) {
  Remove-Item -LiteralPath $targetPath -Force
}

$sourceDirectory = $stageDirectory.TrimEnd('\') + '\'
$sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3

[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=0
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles

[SourceFiles]
SourceFiles0=$sourceDirectory

[SourceFiles0]
%FILE0%=
%FILE1%=
%FILE2%=

[Strings]
InstallPrompt=Install App Release Center $Version for the current user?
DisplayLicense=
FinishMessage=App Release Center $Version was installed successfully.
TargetName=$targetPath
FriendlyName=App Release Center Setup
AppLaunched=powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
FILE0="payload.zip"
FILE1="install.ps1"
FILE2="version.txt"
"@
Set-Content -LiteralPath $sedPath -Value $sed -Encoding Ascii

$iexpress = Join-Path $env:SystemRoot 'System32\iexpress.exe'
if (-not (Test-Path -LiteralPath $iexpress -PathType Leaf)) {
  throw 'Windows IExpress was not found.'
}

$process = Start-Process `
  -FilePath $iexpress `
  -ArgumentList @('/N', '/Q', $sedPath) `
  -Wait `
  -PassThru `
  -WindowStyle Hidden
if ($process.ExitCode -ne 0) {
  throw "IExpress failed with exit code $($process.ExitCode)."
}
if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
  throw 'IExpress completed without creating the installer executable.'
}

$installer = Get-Item -LiteralPath $targetPath
Write-Host "Installer created: $($installer.FullName)"
Write-Host "Installer size: $([math]::Round($installer.Length / 1MB, 2)) MB"
