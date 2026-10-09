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

function Assert-PayloadArchive {
  param([Parameter(Mandatory = $true)][string]$ArchivePath)

  $requiredEntries = @(
    'app_management_center.exe',
    'amc_remote_unlock_provider.dll',
    'flutter_windows.dll',
    'install_remote_unlock.ps1',
    'uninstall_remote_unlock.ps1',
    'data/app.so',
    'data/icudtl.dat',
    'data/flutter_assets/AssetManifest.bin',
    'data/flutter_assets/FontManifest.json',
    'data/flutter_assets/NativeAssetsManifest.json'
  )

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
  try {
    $entries = @{}
    foreach ($entry in $zip.Entries) {
      $entries[$entry.FullName.Replace('\', '/')] = $true
    }

    $missing = @()
    foreach ($entry in $requiredEntries) {
      if (-not $entries.ContainsKey($entry)) {
        $missing += $entry
      }
    }

    if ($missing.Count -gt 0) {
      throw (
        'Installer payload is missing Flutter runtime files: {0}' -f
        ($missing -join ', ')
      )
    }
  } finally {
    $zip.Dispose()
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
  'app_management_center.exe'
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
$sedPath = Join-Path $buildDirectory 'app_management_center.sed'
$targetPath = Join-Path `
  $buildDirectory `
  "AppManagementCenter_Setup_v$safeVersion.exe"

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
  -LiteralPath (Join-Path $PSScriptRoot 'install_remote_unlock.ps1') `
  -Destination (Join-Path $payloadDirectory 'install_remote_unlock.ps1') `
  -Force
Copy-Item `
  -LiteralPath (Join-Path $PSScriptRoot 'uninstall_remote_unlock.ps1') `
  -Destination (Join-Path $payloadDirectory 'uninstall_remote_unlock.ps1') `
  -Force
Copy-Item `
  -LiteralPath (Join-Path $PSScriptRoot 'install.ps1') `
  -Destination (Join-Path $stageDirectory 'install.ps1') `
  -Force
Set-Content `
  -LiteralPath (Join-Path $stageDirectory 'version.txt') `
  -Value $Version `
  -Encoding Ascii

if (Test-Path -LiteralPath $payloadArchive -PathType Leaf) {
  Remove-Item -LiteralPath $payloadArchive -Force
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
  $payloadDirectory,
  $payloadArchive,
  [System.IO.Compression.CompressionLevel]::Optimal,
  $false
)
Assert-PayloadArchive -ArchivePath $payloadArchive

if (Test-Path -LiteralPath $targetPath) {
  Remove-Item -LiteralPath $targetPath -Force
}

$sourceDirectory = $stageDirectory.TrimEnd('\') + '\'
# No FinishMessage: IExpress shows it whatever install.ps1 returns, which
# announced success over a failed install. install.ps1 reports a failure
# itself, and a successful install opens the app.
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
InstallPrompt=Install App Management Center $Version for the current user?
DisplayLicense=
FinishMessage=
TargetName=$targetPath
FriendlyName=App Management Center Setup
AppLaunched=powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1
PostInstallCmd=<None>
AdminQuietInstCmd=powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1
UserQuietInstCmd=powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1
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
