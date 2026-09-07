$ErrorActionPreference = 'Stop'

$installDirectory = [System.IO.Path]::GetFullPath(
  (Split-Path -Parent $MyInvocation.MyCommand.Path)
)
$expectedDirectory = [System.IO.Path]::GetFullPath(
  (Join-Path $env:LOCALAPPDATA 'Programs\App Management Center')
)
if (-not $installDirectory.Equals(
    $expectedDirectory,
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
  throw "Refusing to remove an unexpected directory: $installDirectory"
}

Get-Process -Name 'app_management_center' -ErrorAction SilentlyContinue |
  Stop-Process -Force

$startMenuDirectory = Join-Path `
  ([Environment]::GetFolderPath('Programs')) `
  'App Management Center'
$desktopShortcut = Join-Path `
  ([Environment]::GetFolderPath('Desktop')) `
  'App Management Center.lnk'
if (Test-Path -LiteralPath $startMenuDirectory) {
  Remove-Item -LiteralPath $startMenuDirectory -Recurse -Force
}
if (Test-Path -LiteralPath $desktopShortcut) {
  Remove-Item -LiteralPath $desktopShortcut -Force
}

$uninstallKey = `
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AppManagementCenter'
if (Test-Path -LiteralPath $uninstallKey) {
  Remove-Item -LiteralPath $uninstallKey -Recurse -Force
}

Set-Location -LiteralPath $env:TEMP
Remove-Item -LiteralPath $installDirectory -Recurse -Force
