import 'dart:convert';
import 'dart:io';

import 'package:app_management_center/app/models/wake_diagnostics.dart';
import 'package:app_management_center/app/services/machine_power_service.dart';

/// Reads what the machine can say about being woken up.
///
/// One PowerShell round trip for the lot: each of these takes a couple of
/// hundred milliseconds to start, and none of the answers change between
/// heartbeats, so the caller is expected to cache the result.
class WakeDiagnosticsService {
  WakeDiagnosticsService({MachineProcessRunner? processRunner})
    : _runProcess = processRunner ?? Process.run;

  final MachineProcessRunner _runProcess;

  bool get isSupported => Platform.isWindows;

  Future<WakeDiagnostics> read({
    bool autoStartEnabled = false,
    MachineSleepSupport sleepSupport = const MachineSleepSupport(),
  }) async {
    if (!isSupported) {
      return WakeDiagnostics(autoStartEnabled: autoStartEnabled);
    }

    try {
      final result = await _runProcess('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        _script,
      ]);
      // Parsed regardless of exit code: several of these cmdlets write
      // non-terminating errors on a perfectly normal machine (a Wi-Fi card
      // that rejects power queries, an unencrypted volume) while the script
      // still emits complete JSON. Throwing that away would lose the MAC.
      return parse(
        '${result.stdout}',
        autoStartEnabled: autoStartEnabled,
        sleepSupport: sleepSupport,
      );
    } catch (_) {
      return WakeDiagnostics(autoStartEnabled: autoStartEnabled);
    }
  }

  /// Turns the script's JSON into a [WakeDiagnostics].
  ///
  /// Anything missing or unparseable stays null rather than becoming false:
  /// see the note on [WakeDiagnostics] about why that distinction matters.
  static WakeDiagnostics parse(
    String output, {
    bool autoStartEnabled = false,
    MachineSleepSupport sleepSupport = const MachineSleepSupport(),
  }) {
    Map<String, Object?> json;
    try {
      final decoded = jsonDecode(output.trim());
      json = decoded is Map
          ? Map<String, Object?>.from(decoded)
          : <String, Object?>{};
    } catch (_) {
      json = <String, Object?>{};
    }

    final ipv4 = json['ipv4']?.toString() ?? '';
    final prefixLength = int.tryParse(json['prefixLength']?.toString() ?? '');

    return WakeDiagnostics(
      adapterName: json['adapterName']?.toString() ?? '',
      wirelessAdapter: (json['physicalMediaType']?.toString() ?? '').contains(
        '802.11',
      ),
      macAddress: normalizeMac(json['mac']?.toString() ?? ''),
      ipAddress: ipv4,
      broadcastAddress: broadcastFor(ipv4, prefixLength) ?? '',
      wakeOnMagicPacket: _registryFlag(json['wakeOnMagicPacket']),
      wakeOnPattern: _registryFlag(json['wakeOnPattern']),
      shutdownWakeOnLan: _registryFlag(json['shutdownWakeOnLan']),
      wakeArmed: json['wakeArmed'] is bool ? json['wakeArmed']! as bool : null,
      fastStartupEnabled: _registryFlag(json['hiberbootEnabled']),
      autoSignOnBlocked: _registryFlag(json['disableArso']),
      bitLockerPreBootPin: json['bitlockerPin'] is bool
          ? json['bitlockerPin']! as bool
          : null,
      autoStartEnabled: autoStartEnabled,
      standbySupported: sleepSupport.standby || sleepSupport.modernStandby,
      hibernateSupported: sleepSupport.hibernate,
    );
  }

  /// Normalises a MAC to colon-separated uppercase, or '' when it is not one.
  static String normalizeMac(String value) {
    final hex = value.replaceAll(RegExp('[^0-9a-fA-F]'), '').toUpperCase();
    if (hex.length != 12) return '';
    return [
      for (var index = 0; index < 12; index += 2)
        hex.substring(index, index + 2),
    ].join(':');
  }

  /// The directed broadcast for [ipv4] with [prefixLength], e.g.
  /// 192.168.1.42/24 becomes 192.168.1.255.
  ///
  /// Worth aiming at alongside 255.255.255.255, which some Wi-Fi access points
  /// drop while still forwarding a subnet broadcast.
  static String? broadcastFor(String ipv4, int? prefixLength) {
    if (prefixLength == null || prefixLength < 0 || prefixLength > 32) {
      return null;
    }
    final parts = ipv4.split('.');
    if (parts.length != 4) return null;

    var address = 0;
    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) return null;
      address = (address << 8) | octet;
    }

    final hostBits = 32 - prefixLength;
    final broadcast = hostBits == 32
        ? 0xFFFFFFFF
        : address | ((1 << hostBits) - 1);

    return [
      (broadcast >> 24) & 0xFF,
      (broadcast >> 16) & 0xFF,
      (broadcast >> 8) & 0xFF,
      broadcast & 0xFF,
    ].join('.');
  }

  /// Registry DWORDs where 1 means on, absent means "not set".
  static bool? _registryFlag(Object? value) {
    if (value == null) return null;
    final number = int.tryParse(value.toString());
    return number == null ? null : number != 0;
  }

  /// Assigns each value before building the object: PowerShell 5.1 will not
  /// take an `if` expression as a hashtable value.
  static const _script = r'''
$ErrorActionPreference = 'SilentlyContinue'
# Wired first when one is connected: it is the better wake target and the
# traffic is going there anyway.
$adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
$adapter = $adapters | Where-Object { "$($_.PhysicalMediaType)" -notlike '*802.11*' } | Select-Object -First 1
if (-not $adapter) { $adapter = $adapters | Select-Object -First 1 }
$adapterName = $null
$mediaType = $null
$mac = $null
$ipv4 = $null
$prefixLength = $null
$magic = $null
$pattern = $null
$s5wol = $null
$armed = $null
if ($adapter) {
  $adapterName = $adapter.Name
  $mediaType = [string]$adapter.PhysicalMediaType
  $mac = $adapter.MacAddress
  $ip = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne '127.0.0.1' } | Select-Object -First 1
  if ($ip) {
    $ipv4 = $ip.IPAddress
    $prefixLength = $ip.PrefixLength
  }
  # The driver keyword, not Get-NetAdapterPowerManagement: that cmdlet fails
  # outright on some Wi-Fi cards that do support magic packets, which made a
  # working setup look unreadable.
  $magicProp = Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword '*WakeOnMagicPacket' -ErrorAction SilentlyContinue
  if ($magicProp) { $magic = [int]$magicProp.RegistryValue[0] }
  # Wi-Fi drivers spell this without the asterisk, wired ones with it.
  $patternProp = Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword 'WakeOnPattern' -ErrorAction SilentlyContinue
  if (-not $patternProp) {
    $patternProp = Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword '*WakeOnPattern' -ErrorAction SilentlyContinue
  }
  if ($patternProp) { $pattern = [int]$patternProp.RegistryValue[0] }
  # Only some drivers expose a separate switch for waking from full shutdown.
  $s5Prop = Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword 'S5WakeOnLan' -ErrorAction SilentlyContinue
  if ($s5Prop) { $s5wol = [int]$s5Prop.RegistryValue[0] }
  # Supporting magic packets is not the same as Windows letting the device
  # wake the machine; powercfg is the authority on that.
  $armedList = @(powercfg -devicequery wake_armed)
  $armed = [bool]($armedList -contains $adapter.InterfaceDescription)
}
$hiberboot = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
$disableArso = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DisableAutomaticRestartSignOn -ErrorAction SilentlyContinue).DisableAutomaticRestartSignOn
# Needs admin, and throws outright on an unencrypted volume.
$bitlockerPin = $null
try {
  $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
  if ($volume) {
    $pinProtector = $volume.KeyProtector | Where-Object { "$($_.KeyProtectorType)" -like '*Pin*' }
    $bitlockerPin = [bool]$pinProtector
  }
} catch { $bitlockerPin = $null }
$payload = New-Object PSObject
$payload | Add-Member NoteProperty adapterName $adapterName
$payload | Add-Member NoteProperty physicalMediaType $mediaType
$payload | Add-Member NoteProperty mac $mac
$payload | Add-Member NoteProperty ipv4 $ipv4
$payload | Add-Member NoteProperty prefixLength $prefixLength
$payload | Add-Member NoteProperty wakeOnMagicPacket $magic
$payload | Add-Member NoteProperty wakeOnPattern $pattern
$payload | Add-Member NoteProperty shutdownWakeOnLan $s5wol
$payload | Add-Member NoteProperty wakeArmed $armed
$payload | Add-Member NoteProperty hiberbootEnabled $hiberboot
$payload | Add-Member NoteProperty disableArso $disableArso
$payload | Add-Member NoteProperty bitlockerPin $bitlockerPin
$payload | ConvertTo-Json -Compress
''';
}
