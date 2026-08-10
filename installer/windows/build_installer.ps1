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

function Read-EnvFileValues {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string[]]$Keys
  )

  $values = @{}
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $values
  }

  Get-Content -LiteralPath $Path | ForEach-Object {
    $match = [regex]::Match(
      $_,
      '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$'
    )
    if ($match.Success) {
      $key = $match.Groups[1].Value
      if (($Keys -contains $key) -and -not $values.ContainsKey($key)) {
        $values[$key] = $match.Groups[2].Value.Trim()
      }
    }
  }

  return $values
}

function Get-FirebaseConfigLines {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)

  $keys = @(
    'FIREBASE_API_KEY',
    'FIREBASE_APP_ID',
    'FIREBASE_MESSAGING_SENDER_ID',
    'FIREBASE_PROJECT_ID',
    'FIREBASE_AUTH_DOMAIN',
    'FIREBASE_STORAGE_BUCKET'
  )
  $requiredKeys = @(
    'FIREBASE_API_KEY',
    'FIREBASE_APP_ID',
    'FIREBASE_MESSAGING_SENDER_ID',
    'FIREBASE_PROJECT_ID'
  )
  $sourceValues = Read-EnvFileValues `
    -Path (Join-Path $ProjectRoot '.env') `
    -Keys $keys
  $lines = @()
  $missingRequired = @()

  foreach ($key in $keys) {
    $value = $null
    if ($sourceValues.ContainsKey($key)) {
      $value = $sourceValues[$key]
    } else {
      $value = [Environment]::GetEnvironmentVariable($key, 'Process')
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
      if ($requiredKeys -contains $key) {
        $missingRequired += $key
      }
      continue
    }

    $lines += "$key=$value"
  }

  if (($lines.Count -gt 0) -and ($missingRequired.Count -gt 0)) {
    Write-Warning (
      'Firebase release config is incomplete. Missing: {0}' -f
      ($missingRequired -join ', ')
    )
  }

  return $lines
}

function Assert-PayloadArchive {
  param([Parameter(Mandatory = $true)][string]$ArchivePath)

  $requiredEntries = @(
    'app_release_center.exe',
    'flutter_windows.dll',
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

$releaseFirebaseConfig = Join-Path $releaseDirectory 'firebase.env'
$firebaseConfigLines = @(Get-FirebaseConfigLines -ProjectRoot $projectRoot)
if ($firebaseConfigLines.Count -gt 0) {
  Set-Content `
    -LiteralPath $releaseFirebaseConfig `
    -Value $firebaseConfigLines `
    -Encoding Ascii
  Write-Host "Firebase release config written: $releaseFirebaseConfig"
} elseif (Test-Path -LiteralPath $releaseFirebaseConfig -PathType Leaf) {
  Remove-Item -LiteralPath $releaseFirebaseConfig -Force
}

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
