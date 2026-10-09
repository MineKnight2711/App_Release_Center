# Prepares this machine to be woken by the phone, and to stay asleep until it
# is.
#
# The setting that matters is "Wake on Pattern Match". Left on, the network
# card wakes the machine for ordinary traffic, and a home network broadcasts
# constantly — so the machine wakes seconds after every sleep. That looks like
# "sleep is broken" and makes any Wake-on-LAN test meaningless, because the
# magic packet arrives at a machine that is already awake.
#
# Run it and approve the UAC prompt; it elevates itself. Add -ReadOnly to see
# what is set without changing anything, which needs no elevation.

[CmdletBinding()]
param(
  # Report what is set without changing anything.
  [switch] $ReadOnly,

  # Stop scheduled tasks from waking the machine. A printer health check or an
  # update scan asking to wake a laptop is almost never what anyone wants, and
  # it produces a wake with no device to blame it on.
  [switch] $FixWakeTasks,

  # Leave only the network card able to wake the machine. This is the decisive
  # test when the machine still will not stay asleep: if it sleeps through
  # with everything else disarmed, the culprit was one of those devices.
  #
  # The trade-off is real — with this on, pressing a key or moving the mouse
  # no longer wakes the machine and you need the power button.
  [switch] $IsolateWake,

  # Stop the wireless radio entering low-power states. A Wi-Fi card can only
  # act on a magic packet if it is still powered and still associated with the
  # access point while the machine sleeps, and "Power Saving = Auto" lets the
  # driver decide otherwise.
  #
  # Costs battery, and resets the adapter briefly when applied.
  [switch] $MaxWifiPower,

  # Let the app's wake probe receive packets.
  #
  # Waking from sleep never touches Windows Firewall — the network card acts
  # on the magic packet while the OS is down. But the probe that reports
  # whether a packet can reach this machine runs inside Windows, so without a
  # rule it sees nothing and reports "no packet arrived" for a reason that has
  # nothing to do with the network.
  [switch] $AllowWakeProbe
)

$wakeProbeRuleName = 'App Management Center wake probe'

$ErrorActionPreference = 'Stop'

function Test-Elevated {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WakeProperty {
  param([string] $AdapterName, [string[]] $Keywords)
  foreach ($keyword in $Keywords) {
    $property = Get-NetAdapterAdvancedProperty -Name $AdapterName `
      -RegistryKeyword $keyword -ErrorAction SilentlyContinue
    if ($property) { return $property }
  }
  return $null
}

# Ask for elevation rather than telling the reader to. Printing instructions
# and exiting is how a run silently changes nothing while looking like it
# worked, which is exactly what happened the first time this was used.
if (-not $ReadOnly -and -not (Test-Elevated)) {
  Write-Output 'Can quyen Administrator. Dang mo cua so nang quyen (bam Yes o UAC)...'
  try {
    $arguments = @(
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', $PSCommandPath
    )
    if ($FixWakeTasks) { $arguments += '-FixWakeTasks' }
    if ($IsolateWake) { $arguments += '-IsolateWake' }
    if ($MaxWifiPower) { $arguments += '-MaxWifiPower' }
    if ($AllowWakeProbe) { $arguments += '-AllowWakeProbe' }
    Start-Process powershell -Verb RunAs -ArgumentList $arguments
  } catch {
    Write-Output 'Khong mo duoc cua so nang quyen. Mo PowerShell bang Run as'
    Write-Output ("administrator roi chay: {0}" -f $PSCommandPath)
    exit 1
  }
  exit 0
}

$adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
  Where-Object { $_.Status -eq 'Up' -or $_.Status -eq 'Disconnected' })

if ($adapters.Count -eq 0) {
  Write-Output 'Khong tim thay card mang vat ly nao.'
  exit 1
}

Write-Output '=== TRUOC ==='
foreach ($adapter in $adapters) {
  $magic = Get-WakeProperty -AdapterName $adapter.Name -Keywords @('*WakeOnMagicPacket')
  $pattern = Get-WakeProperty -AdapterName $adapter.Name -Keywords @('WakeOnPattern', '*WakeOnPattern')
  $armed = @(powercfg -devicequery wake_armed) -contains $adapter.InterfaceDescription
  $magicText = if ($magic) { $magic.DisplayValue } else { 'khong doc duoc' }
  $patternText = if ($pattern) { $pattern.DisplayValue } else { 'khong co' }
  Write-Output ("{0,-12} magic={1,-14} pattern={2,-14} armed={3}" -f `
    $adapter.Name, $magicText, $patternText, $armed)
}

Write-Output ''
Write-Output '=== MAY NGHE GOI DANH THUC ==='
$probeRule = Get-NetFirewallRule -DisplayName $wakeProbeRuleName -ErrorAction SilentlyContinue
if ($probeRule) {
  Write-Output ("Rule firewall: co ({0})" -f $probeRule.Enabled)
} else {
  Write-Output 'Rule firewall: CHUA CO - phep do se khong thay goi nao.'
}
Get-NetConnectionProfile -ErrorAction SilentlyContinue |
  ForEach-Object { "Mang {0}: {1}" -f $_.InterfaceAlias, $_.NetworkCategory }

if ($ReadOnly) {
  Write-Output ''
  Write-Output '(-ReadOnly: khong doi gi)'
  exit 0
}

$changed = 0
foreach ($adapter in $adapters) {
  $pattern = Get-WakeProperty -AdapterName $adapter.Name -Keywords @('WakeOnPattern', '*WakeOnPattern')
  if ($pattern -and [int]$pattern.RegistryValue[0] -ne 0) {
    try {
      Set-NetAdapterAdvancedProperty -Name $adapter.Name `
        -RegistryKeyword $pattern.RegistryKeyword -RegistryValue 0
      Write-Output ("Da tat Wake on Pattern Match tren {0}" -f $adapter.Name)
      $changed += 1
    } catch {
      Write-Output ("Khong tat duoc tren {0}: {1}" -f $adapter.Name, $_.Exception.Message)
    }
  }

  # Turning pattern match off is only useful if the magic packet still gets
  # through, so make sure that half is on.
  $magic = Get-WakeProperty -AdapterName $adapter.Name -Keywords @('*WakeOnMagicPacket')
  if ($magic -and [int]$magic.RegistryValue[0] -eq 0) {
    try {
      Set-NetAdapterAdvancedProperty -Name $adapter.Name `
        -RegistryKeyword $magic.RegistryKeyword -RegistryValue 1
      Write-Output ("Da bat Wake on Magic Packet tren {0}" -f $adapter.Name)
      $changed += 1
    } catch {
      Write-Output ("Khong bat duoc magic packet tren {0}: {1}" -f $adapter.Name, $_.Exception.Message)
    }
  }
}

Write-Output ''
Write-Output '=== SAU ==='
foreach ($adapter in $adapters) {
  $magic = Get-WakeProperty -AdapterName $adapter.Name -Keywords @('*WakeOnMagicPacket')
  $pattern = Get-WakeProperty -AdapterName $adapter.Name -Keywords @('WakeOnPattern', '*WakeOnPattern')
  $magicText = if ($magic) { $magic.DisplayValue } else { 'khong doc duoc' }
  $patternText = if ($pattern) { $pattern.DisplayValue } else { 'khong co' }
  Write-Output ("{0,-12} magic={1,-14} pattern={2}" -f $adapter.Name, $magicText, $patternText)
}

Write-Output ''
Write-Output '=== CAI GI DANG CHAN MAY NGU ==='
# A driver or app holding a power request can make Windows enter sleep and
# come straight back out, which looks identical to a stray wake signal.
powercfg -requests

Write-Output ''
Write-Output '=== THIET BI DUOC PHEP DANH THUC ==='
powercfg -devicequery wake_armed

Write-Output ''
Write-Output '=== LAN DANH THUC GAN NHAT ==='
powercfg -lastwake

Write-Output ''
Write-Output '=== HEN GIO DANH THUC DANG DAT ==='
# A pending wake timer wakes the machine on a schedule and looks exactly like
# the pattern-match problem, so it is worth ruling out in the same pass.
powercfg -waketimers

if ($FixWakeTasks) {
  Write-Output ''
  Write-Output '=== TAT QUYEN DANH THUC CUA SCHEDULED TASK ==='
  $wakers = @(Get-ScheduledTask -ErrorAction SilentlyContinue |
    Where-Object { $_.Settings -and $_.Settings.WakeToRun })
  if ($wakers.Count -eq 0) {
    Write-Output 'Khong co task nao xin danh thuc may.'
  }
  foreach ($task in $wakers) {
    try {
      $task.Settings.WakeToRun = $false
      Set-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath `
        -Settings $task.Settings | Out-Null
      Write-Output ("Da tat: {0}{1}" -f $task.TaskPath, $task.TaskName)
      $changed += 1
    } catch {
      Write-Output ("Khong tat duoc {0}{1}: {2}" -f `
        $task.TaskPath, $task.TaskName, $_.Exception.Message)
    }
  }
}

if ($MaxWifiPower) {
  Write-Output ''
  Write-Output '=== GIU RADIO WI-FI KHONG VAO CHE DO TIET KIEM ==='
  # The power plan governs this too, so report it rather than leave the reader
  # guessing which of the two settings is in force.
  $plan = powercfg -q SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 `
    12bbebe6-58d6-4636-95bb-3217ef867c1a 2>&1
  $acIndex = ($plan | Select-String -Pattern 'Current AC Power Setting Index').ToString()
  Write-Output ("Power plan: {0}" -f $acIndex.Trim())
  if ($acIndex -notmatch '0x00000000') {
    powercfg -setacvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 `
      12bbebe6-58d6-4636-95bb-3217ef867c1a 0
    powercfg -setdcvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 `
      12bbebe6-58d6-4636-95bb-3217ef867c1a 0
    powercfg -setactive SCHEME_CURRENT
    Write-Output 'Da dat power plan ve Maximum Performance.'
    $changed += 1
  }

  foreach ($adapter in $adapters) {
    $lowPower = Get-WakeProperty -AdapterName $adapter.Name -Keywords @('LowPowerEnable')
    if (-not $lowPower) { continue }
    if ([int]$lowPower.RegistryValue[0] -eq 0) {
      Write-Output ("{0}: Power Saving da tat san." -f $adapter.Name)
      continue
    }
    try {
      Set-NetAdapterAdvancedProperty -Name $adapter.Name `
        -RegistryKeyword 'LowPowerEnable' -RegistryValue 0
      Write-Output ("{0}: da tat Power Saving cua driver." -f $adapter.Name)
      $changed += 1
    } catch {
      Write-Output ("{0}: khong tat duoc Power Saving: {1}" -f `
        $adapter.Name, $_.Exception.Message)
    }
  }
}

if ($AllowWakeProbe) {
  Write-Output ''
  Write-Output '=== MO FIREWALL CHO MAY NGHE GOI DANH THUC ==='
  $existing = Get-NetFirewallRule -DisplayName $wakeProbeRuleName -ErrorAction SilentlyContinue
  if ($existing) {
    Write-Output 'Rule da co san.'
  } else {
    try {
      # Ports 9 and 7 only, which carry nothing but wake packets, and every
      # profile because the Wi-Fi here is categorised Public.
      New-NetFirewallRule -DisplayName $wakeProbeRuleName `
        -Direction Inbound -Protocol UDP -LocalPort 9,7 `
        -Action Allow -Profile Any | Out-Null
      Write-Output ("Da tao rule: {0} (UDP 9, 7 vao)" -f $wakeProbeRuleName)
      $changed += 1
    } catch {
      Write-Output ("Khong tao duoc rule: {0}" -f $_.Exception.Message)
    }
  }
  Write-Output ''
  Write-Output ('Go rule sau nay: Remove-NetFirewallRule -DisplayName "{0}"' -f $wakeProbeRuleName)
  Write-Output 'Luu y: rule nay chi phuc vu phep do luc may dang thuc.'
  Write-Output 'Danh thuc luc may ngu khong di qua firewall.'
}

if ($IsolateWake) {
  Write-Output ''
  Write-Output '=== CHI CHO CARD MANG DANH THUC ==='
  $keep = @($adapters | ForEach-Object { $_.InterfaceDescription })
  foreach ($name in @(powercfg -devicequery wake_armed)) {
    $trimmed = "$name".Trim()
    if (-not $trimmed) { continue }
    if ($keep -contains $trimmed) {
      Write-Output ("Giu lai: {0}" -f $trimmed)
      continue
    }
    powercfg -devicedisablewake "$trimmed" | Out-Null
    Write-Output ("Da tat danh thuc: {0}" -f $trimmed)
    $changed += 1
  }
  Write-Output ''
  Write-Output 'Bat lai bang: powercfg -deviceenablewake "<ten thiet bi>"'
}

Write-Output ''
Write-Output ("Da doi {0} cau hinh." -f $changed)
Write-Output 'Buoc tiep theo: rut dien thoai khoi cong USB, cho may ngu, roi kiem tra'
Write-Output 'may co ngu yen khong bang lenh nay (PowerShell thuong cung chay duoc):'
Write-Output ''
Write-Output "  Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-Kernel-Power';Id=@(42,107)} -MaxEvents 4 | Sort-Object TimeCreated | Select-Object TimeCreated, Id"
