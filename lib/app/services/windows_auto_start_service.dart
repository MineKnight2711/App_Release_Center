import 'dart:io';

import 'package:app_management_center/app/services/machine_power_service.dart'
    show MachineProcessRunner;
import 'package:path/path.dart' as p;

/// Puts a shortcut to this app in the Windows Startup folder.
///
/// Without it the remote agent never comes back after a reboot: the app is a
/// user application, so nothing starts it until someone opens it by hand. That
/// makes "restart my machine from my phone" a one-way trip, whether or not the
/// machine has a PIN.
///
/// The shortcut's presence is the state — there is no preference mirroring it,
/// so removing it outside the app cannot leave a switch lying about.
class WindowsAutoStartService {
  WindowsAutoStartService({
    MachineProcessRunner? processRunner,
    String? startupDirectory,
    String? executablePath,
  }) : _runProcess = processRunner ?? Process.run,
       _startupDirectoryOverride = startupDirectory,
       _executablePathOverride = executablePath;

  final MachineProcessRunner _runProcess;
  final String? _startupDirectoryOverride;
  final String? _executablePathOverride;

  static const shortcutName = 'App Management Center.lnk';

  bool get isSupported => Platform.isWindows;

  String get _executablePath =>
      _executablePathOverride ?? Platform.resolvedExecutable;

  String? get startupDirectory {
    if (_startupDirectoryOverride != null) return _startupDirectoryOverride;
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.trim().isEmpty) return null;
    return p.join(
      appData,
      'Microsoft',
      'Windows',
      'Start Menu',
      'Programs',
      'Startup',
    );
  }

  String? get shortcutPath {
    final directory = startupDirectory;
    return directory == null ? null : p.join(directory, shortcutName);
  }

  /// Wraps [value] as a PowerShell single-quoted literal, where the escape for
  /// a quote is doubling it.
  static String _psLiteral(String value) => "'${value.replaceAll("'", "''")}'";

  bool isEnabled() {
    if (!isSupported) return false;
    final path = shortcutPath;
    return path != null && File(path).existsSync();
  }

  Future<void> setEnabled(bool enabled) async {
    if (!isSupported) {
      throw UnsupportedError('Chỉ hỗ trợ Windows.');
    }
    final path = shortcutPath;
    if (path == null) {
      throw const FileSystemException('Không đọc được thư mục Startup.');
    }

    if (!enabled) {
      final shortcut = File(path);
      if (shortcut.existsSync()) shortcut.deleteSync();
      return;
    }

    Directory(p.dirname(path)).createSync(recursive: true);
    // A .lnk is a COM object, so PowerShell builds it rather than Dart.
    final script = [
      r'$shell = New-Object -ComObject WScript.Shell',
      r'$link = $shell.CreateShortcut(' '${_psLiteral(path)})',
      r'$link.TargetPath = ' '${_psLiteral(_executablePath)}',
      r'$link.WorkingDirectory = '
          '${_psLiteral(p.dirname(_executablePath))}',
      r'$link.Save()',
    ].join('; ');

    final result = await _runProcess('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      script,
    ]);
    if (result.exitCode != 0) {
      throw ProcessException(
        'powershell.exe',
        const ['-Command', '<create startup shortcut>'],
        '${result.stderr}'.trim(),
        result.exitCode,
      );
    }
  }
}
