$ErrorActionPreference = 'Stop'

$installDirectory = [System.IO.Path]::GetFullPath(
  (Split-Path -Parent $MyInvocation.MyCommand.Path)
)
$expectedDirectory = [System.IO.Path]::GetFullPath(
  (Join-Path $env:LOCALAPPDATA 'Programs\App Release Center')
)
if (-not $installDirectory.Equals(
    $expectedDirectory,
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
  throw "Refusing to remove an unexpected directory: $installDirectory"
}

Get-Process -Name 'app_release_center' -ErrorAction SilentlyContinue |
  Stop-Process -Force

$startMenuDirectory = Join-Path `
  ([Environment]::GetFolderPath('Programs')) `
  'App Release Center'
$desktopShortcut = Join-Path `
  ([Environment]::GetFolderPath('Desktop')) `
  'App Release Center.lnk'
if (Test-Path -LiteralPath $startMenuDirectory) {
  Remove-Item -LiteralPath $startMenuDirectory -Recurse -Force
}
if (Test-Path -LiteralPath $desktopShortcut) {
  Remove-Item -LiteralPath $desktopShortcut -Force
}

$uninstallKey = `
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AppReleaseCenter'
if (Test-Path -LiteralPath $uninstallKey) {
  Remove-Item -LiteralPath $uninstallKey -Recurse -Force
}

Set-Location -LiteralPath $env:TEMP
Remove-Item -LiteralPath $installDirectory -Recurse -Force
