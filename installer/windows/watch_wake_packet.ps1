# Listens for the phone's Wake-on-LAN packet while this machine is awake.
#
# When the phone's wake button does nothing, the question is which half is
# broken: the packet never reaching this machine, or the sleeping network card
# not acting on it. Nothing in the sleeping case is observable, so the way to
# split it is to listen while awake and press the button.
#
#   Packet shows up here -> the network path is fine, the sleeping card is the
#     problem (a Wi-Fi card that drops its association in sleep cannot hear
#     anything, whatever its "Wake on Magic Packet" setting says).
#   Nothing shows up     -> the phone is not on this network, or the access
#     point is not passing broadcast between clients.
#
# Needs no elevation.
#
#   powershell -ExecutionPolicy Bypass -File watch_wake_packet.ps1
#   powershell -ExecutionPolicy Bypass -File watch_wake_packet.ps1 -Seconds 120

[CmdletBinding()]
param(
  [int] $Seconds = 90,

  # Both are conventional for Wake-on-LAN; the app sends to each.
  [int[]] $Ports = @(9, 7)
)

$ErrorActionPreference = 'Stop'

$adapter = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
  Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
if (-not $adapter) {
  Write-Output 'Khong tim thay card mang dang hoat dong.'
  exit 1
}

$ip = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 `
  -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne '127.0.0.1' } |
  Select-Object -First 1

$expectedMac = ($adapter.MacAddress -replace '[^0-9A-Fa-f]', '').ToUpper()

Write-Output ("Card    : {0} ({1})" -f $adapter.Name, $adapter.MacAddress)
if ($ip) {
  Write-Output ("Dia chi : {0}/{1}" -f $ip.IPAddress, $ip.PrefixLength)
}
Write-Output ''

$listeners = @()
foreach ($port in $Ports) {
  try {
    $client = New-Object System.Net.Sockets.UdpClient($port)
    $listeners += [pscustomobject]@{ Port = $port; Client = $client }
    Write-Output ("Dang nghe UDP {0}" -f $port)
  } catch {
    # Port 7/9 are sometimes taken by Simple TCP/IP Services; losing one is
    # not fatal because the app sends to both.
    Write-Output ("Khong mo duoc UDP {0}: {1}" -f $port, $_.Exception.Message)
  }
}

if ($listeners.Count -eq 0) {
  Write-Output 'Khong mo duoc cong nao. Dung script va thu lai.'
  exit 1
}

Write-Output ''
Write-Output ("Bay gio bam nut Danh thuc tren dien thoai. Dang cho {0} giay..." -f $Seconds)
Write-Output '(Ctrl+C de dung som)'
Write-Output ''

$deadline = (Get-Date).AddSeconds($Seconds)
$seen = 0

try {
  while ((Get-Date) -lt $deadline) {
    foreach ($listener in $listeners) {
      while ($listener.Client.Available -gt 0) {
        $remote = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $bytes = $listener.Client.Receive([ref] $remote)
        $seen += 1

        $hex = -join ($bytes | ForEach-Object { $_.ToString('X2') })
        # A magic packet is six 0xFF bytes then the MAC sixteen times over.
        $isMagic = $bytes.Length -eq 102 -and $hex.StartsWith('FFFFFFFFFFFF')
        $forThisMachine = $isMagic -and $hex.Substring(12, 12) -eq $expectedMac

        $verdict = if ($forThisMachine) {
          'MAGIC PACKET dung MAC may nay'
        } elseif ($isMagic) {
          'magic packet nhung MAC khac: ' + $hex.Substring(12, 12)
        } else {
          ('goi UDP la, {0} byte' -f $bytes.Length)
        }

        Write-Output ("[{0}] cong {1} <- {2}  {3}" -f `
          (Get-Date -Format 'HH:mm:ss'), $listener.Port, $remote.Address, $verdict)
      }
    }
    Start-Sleep -Milliseconds 150
  }
} finally {
  foreach ($listener in $listeners) { $listener.Client.Close() }
}

Write-Output ''
if ($seen -eq 0) {
  Write-Output 'KHONG nhan duoc goi nao.'
  Write-Output 'Nghia la goi tin khong tran tu dien thoai den may nay. Kiem tra:'
  Write-Output '  - Dien thoai dang dung Wi-Fi nha, khong phai 4G'
  Write-Output '  - Dien thoai va may cung mang (cung dai 192.168.x.x)'
  Write-Output '  - Router khong bat AP isolation / Client isolation'
} else {
  Write-Output ("Da nhan {0} goi. Duong mang OK." -f $seen)
  Write-Output 'Neu goi den duoc luc may thuc nhung khong danh thuc duoc luc may ngu,'
  Write-Output 'thi card mang ngu cung ngu theo - xem README phan Waking the machine.'
}
