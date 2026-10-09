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
  'Programs\App Management Center'
Assert-InstallPath -Candidate $installDirectory

$logFile = Join-Path $env:TEMP 'AppManagementCenter-install.log'
function Write-InstallLog {
  param([Parameter(Mandatory = $true)][string]$Message)
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
  Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

# IExpress runs this script without a window: a failure has to say so
# itself, or the user is left with an empty install and no reason.
function Show-InstallError {
  param([Parameter(Mandatory = $true)][string]$Message)
  try {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
      "$Message`n`nChi tiết: $logFile",
      'App Management Center Setup',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
  } catch {
  }
}

$temporaryDirectory = Join-Path `
  $env:TEMP `
  ("app-release-center-install-{0}" -f [guid]::NewGuid().ToString('N'))
$backupDirectory = Join-Path `
  $env:TEMP `
  ("app-release-center-previous-{0}" -f [guid]::NewGuid().ToString('N'))
$movedToBackup = @()
$exitCode = 0
$copiedNames = @()
$filesReplaced = $false
try {
  Write-InstallLog "Installing $version into $installDirectory"
  New-Item -ItemType Directory -Path $temporaryDirectory -Force | Out-Null
  Expand-Archive `
    -LiteralPath $archive `
    -DestinationPath $temporaryDirectory `
    -Force
  if (-not (Test-Path -LiteralPath (Join-Path $temporaryDirectory 'app_management_center.exe') -PathType Leaf)) {
    throw 'The installer payload has no application executable.'
  }

  $running = @(Get-Process -Name 'app_management_center' -ErrorAction SilentlyContinue)
  if ($running.Count -gt 0) {
    Write-InstallLog "Stopping $($running.Count) running instance(s)"
    $running | Stop-Process -Force
    $running | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue
  }

  # The folder itself is never deleted: a process started by the app (adb,
  # a terminal) can keep it as its working directory, and deleting the files
  # then failing on the folder used to leave an empty install behind. The old
  # files move aside instead, and come back if anything below fails.
  New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
  $previous = @(Get-ChildItem -LiteralPath $installDirectory -Force)
  if ($previous.Count -gt 0) {
    New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
    foreach ($item in $previous) {
      Move-Item -LiteralPath $item.FullName -Destination $backupDirectory -Force
      $movedToBackup += $item.Name
    }
    Write-InstallLog "Moved $($movedToBackup.Count) previous item(s) aside"
  }

  foreach ($item in @(Get-ChildItem -LiteralPath $temporaryDirectory -Force)) {
    Copy-Item `
      -LiteralPath $item.FullName `
      -Destination $installDirectory `
      -Recurse `
      -Force
    $copiedNames += $item.Name
  }

  $executable = Join-Path $installDirectory 'app_management_center.exe'
  if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw 'The application executable was not installed.'
  }
  $filesReplaced = $true
  Write-InstallLog "Copied $($copiedNames.Count) item(s)"

  $shell = New-Object -ComObject WScript.Shell
  $startMenuDirectory = Join-Path `
    ([Environment]::GetFolderPath('Programs')) `
    'App Management Center'
  New-Item -ItemType Directory -Path $startMenuDirectory -Force | Out-Null

  $appShortcut = $shell.CreateShortcut(
    (Join-Path $startMenuDirectory 'App Management Center.lnk')
  )
  $appShortcut.TargetPath = $executable
  $appShortcut.WorkingDirectory = $installDirectory
  $appShortcut.IconLocation = "$executable,0"
  $appShortcut.Save()

  $desktopShortcut = $shell.CreateShortcut(
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'App Management Center.lnk')
  )
  $desktopShortcut.TargetPath = $executable
  $desktopShortcut.WorkingDirectory = $installDirectory
  $desktopShortcut.IconLocation = "$executable,0"
  $desktopShortcut.Save()

  # The remote agent only runs while the app runs, so without a Startup entry
  # the machine goes quiet after every reboot. Options > Điều khiển toggles it.
  $startupShortcut = $shell.CreateShortcut(
    (Join-Path ([Environment]::GetFolderPath('Startup')) 'App Management Center.lnk')
  )
  $startupShortcut.TargetPath = $executable
  $startupShortcut.WorkingDirectory = $installDirectory
  $startupShortcut.IconLocation = "$executable,0"
  $startupShortcut.Save()

  $uninstallScript = Join-Path $installDirectory 'uninstall.ps1'
  $uninstallShortcut = $shell.CreateShortcut(
    (Join-Path $startMenuDirectory 'Uninstall App Management Center.lnk')
  )
  $uninstallShortcut.TargetPath = 'powershell.exe'
  $uninstallShortcut.Arguments = `
    "-NoProfile -ExecutionPolicy Bypass -File `"$uninstallScript`""
  $uninstallShortcut.WorkingDirectory = $installDirectory
  $uninstallShortcut.Save()

  $uninstallKey = `
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AppManagementCenter'
  New-Item -Path $uninstallKey -Force | Out-Null
  New-ItemProperty `
    -Path $uninstallKey `
    -Name 'DisplayName' `
    -Value 'App Management Center' `
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

  Write-InstallLog 'Installed'
  Start-Process -FilePath $executable -WorkingDirectory $installDirectory
} catch {
  $failure = $_.Exception.Message
  Write-InstallLog "FAILED: $failure"
  $restored = $false
  if (-not $filesReplaced) {
    # Put the previous version back so the app keeps working.
    try {
      foreach ($name in $copiedNames) {
        $copied = Join-Path $installDirectory $name
        if (Test-Path -LiteralPath $copied) {
          Remove-Item -LiteralPath $copied -Recurse -Force
        }
      }
      foreach ($name in $movedToBackup) {
        Move-Item `
          -LiteralPath (Join-Path $backupDirectory $name) `
          -Destination $installDirectory `
          -Force
      }
      $restored = $movedToBackup.Count -gt 0
      if ($restored) { Write-InstallLog 'Restored the previous version' }
    } catch {
      Write-InstallLog "Restore FAILED: $($_.Exception.Message); previous files are in $backupDirectory"
    }
  }
  $message = "Cài đặt không thành công: $failure"
  if ($restored) {
    $message += "`n`nBản cũ đã được giữ nguyên."
  } elseif (-not $filesReplaced -and $movedToBackup.Count -gt 0) {
    $message += "`n`nBản cũ nằm ở: $backupDirectory"
  }
  Show-InstallError $message
  $exitCode = 1
} finally {
  if (Test-Path -LiteralPath $temporaryDirectory) {
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
  }
  if ($filesReplaced -and (Test-Path -LiteralPath $backupDirectory)) {
    Remove-Item -LiteralPath $backupDirectory -Recurse -Force -ErrorAction SilentlyContinue
  }
}
exit $exitCode
