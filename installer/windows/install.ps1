$ErrorActionPreference = 'Stop'

function Assert-InstallPath {
  param([Parameter(Mandatory = $true)][string]$Candidate)

  $programsRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $env:LOCALAPPDATA 'Programs')
  ).TrimEnd('\') + '\'
  $candidatePath = [System.IO.Path]::GetFullPath($Candidate)
  if (-not $candidatePath.StartsWith(
      $programsRoot,
      [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw "Unsafe installation path: $candidatePath"
  }
}

$archive = Join-Path $PSScriptRoot 'payload.zip'
$versionFile = Join-Path $PSScriptRoot 'version.txt'
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
  throw 'The installer payload is missing.'
}

$version = if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
  (Get-Content -LiteralPath $versionFile -Raw).Trim()
} else {
  'Unknown'
}
$installDirectory = Join-Path `
  $env:LOCALAPPDATA `
  'Programs\App Release Center'
Assert-InstallPath -Candidate $installDirectory

$temporaryDirectory = Join-Path `
  $env:TEMP `
  ("app-release-center-install-{0}" -f [guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory -Path $temporaryDirectory -Force | Out-Null
  Expand-Archive `
    -LiteralPath $archive `
    -DestinationPath $temporaryDirectory `
    -Force

  Get-Process -Name 'app_release_center' -ErrorAction SilentlyContinue |
    Stop-Process -Force
  if (Test-Path -LiteralPath $installDirectory) {
    Remove-Item -LiteralPath $installDirectory -Recurse -Force
  }
  New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
  Get-ChildItem -LiteralPath $temporaryDirectory -Force | ForEach-Object {
    Copy-Item `
      -LiteralPath $_.FullName `
      -Destination $installDirectory `
      -Recurse `
      -Force
  }

  $executable = Join-Path $installDirectory 'app_release_center.exe'
  if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw 'The application executable was not installed.'
  }

  $shell = New-Object -ComObject WScript.Shell
  $startMenuDirectory = Join-Path `
    ([Environment]::GetFolderPath('Programs')) `
    'App Release Center'
  New-Item -ItemType Directory -Path $startMenuDirectory -Force | Out-Null

  $appShortcut = $shell.CreateShortcut(
    (Join-Path $startMenuDirectory 'App Release Center.lnk')
  )
  $appShortcut.TargetPath = $executable
  $appShortcut.WorkingDirectory = $installDirectory
  $appShortcut.IconLocation = "$executable,0"
  $appShortcut.Save()

  $desktopShortcut = $shell.CreateShortcut(
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'App Release Center.lnk')
  )
  $desktopShortcut.TargetPath = $executable
  $desktopShortcut.WorkingDirectory = $installDirectory
  $desktopShortcut.IconLocation = "$executable,0"
  $desktopShortcut.Save()

  $uninstallScript = Join-Path $installDirectory 'uninstall.ps1'
  $uninstallShortcut = $shell.CreateShortcut(
    (Join-Path $startMenuDirectory 'Uninstall App Release Center.lnk')
  )
  $uninstallShortcut.TargetPath = 'powershell.exe'
  $uninstallShortcut.Arguments = `
    "-NoProfile -ExecutionPolicy Bypass -File `"$uninstallScript`""
  $uninstallShortcut.WorkingDirectory = $installDirectory
  $uninstallShortcut.Save()

  $uninstallKey = `
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AppReleaseCenter'
  New-Item -Path $uninstallKey -Force | Out-Null
  New-ItemProperty `
    -Path $uninstallKey `
    -Name 'DisplayName' `
    -Value 'App Release Center' `
    -PropertyType String `
    -Force | Out-Null
  New-ItemProperty `
    -Path $uninstallKey `
    -Name 'DisplayVersion' `
    -Value $version `
    -PropertyType String `
    -Force | Out-Null
  New-ItemProperty `
    -Path $uninstallKey `
    -Name 'InstallLocation' `
    -Value $installDirectory `
    -PropertyType String `
    -Force | Out-Null
  New-ItemProperty `
    -Path $uninstallKey `
    -Name 'DisplayIcon' `
    -Value $executable `
    -PropertyType String `
    -Force | Out-Null
  New-ItemProperty `
    -Path $uninstallKey `
    -Name 'UninstallString' `
    -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$uninstallScript`"" `
    -PropertyType String `
    -Force | Out-Null
  New-ItemProperty `
    -Path $uninstallKey `
    -Name 'NoModify' `
    -Value 1 `
    -PropertyType DWord `
    -Force | Out-Null
  New-ItemProperty `
    -Path $uninstallKey `
    -Name 'NoRepair' `
    -Value 1 `
    -PropertyType DWord `
    -Force | Out-Null

  Start-Process -FilePath $executable -WorkingDirectory $installDirectory
} finally {
  if (Test-Path -LiteralPath $temporaryDirectory) {
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
  }
}
