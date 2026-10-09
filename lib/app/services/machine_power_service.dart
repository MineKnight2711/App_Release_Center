import 'dart:io';

/// What a power command asks the machine to do.
enum MachinePowerAction {
  shutdown,
  restart,
  sleep,
  hibernate,
  lock,
  logoff,

  /// Turns the screen off without suspending the machine.
  ///
  /// The stand-in for sleep where Wake-on-LAN cannot work: a laptop that
  /// drops its Wi-Fi association when suspended can never be woken remotely,
  /// but one that stays awake with its screen off stays reachable. It costs
  /// power, and it is the only way to keep phone control over Wi-Fi alone.
  displayOff,

  /// Aborts a shutdown or restart that is still counting down.
  cancel,
}

MachinePowerAction? machinePowerActionFromName(String name) {
  // Compared case-insensitively on both sides: the wire name is the enum's
  // own spelling, and a camelCase one like displayOff never matched an input
  // that had been lowercased first.
  final wanted = name.trim().toLowerCase();
  for (final action in MachinePowerAction.values) {
    if (action.name.toLowerCase() == wanted) return action;
  }
  return null;
}

/// Sleep states the machine reports as available, read from `powercfg /a`.
class MachineSleepSupport {
  const MachineSleepSupport({
    this.standby = false,
    this.hibernate = false,
    this.modernStandby = false,
  });

  /// S3, the state a magic packet can reliably wake from.
  final bool standby;

  /// S4, requested explicitly through [MachinePowerAction.hibernate].
  final bool hibernate;

  /// S0 low power idle. Present instead of S3 on most recent laptops.
  final bool modernStandby;

  /// Kept on the wire for older phone builds that used the rundll32 command.
  /// New builds call the typed Windows API and never turn Sleep into Hibernate.
  bool get sleepFallsBackToHibernate => hibernate && !standby && !modernStandby;

  Map<String, Object?> toJson() {
    return {
      'standby': standby,
      'hibernate': hibernate,
      'modernStandby': modernStandby,
      'sleepFallsBackToHibernate': sleepFallsBackToHibernate,
    };
  }
}

typedef MachineProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Turns a power request into the Windows command that performs it.
///
/// Nothing here forces applications to close. A release that is still writing
/// an artifact deserves the chance to finish or to prompt, so `/f` only ever
/// appears when the caller asks for it explicitly.
class MachinePowerService {
  MachinePowerService({MachineProcessRunner? processRunner})
    : _runProcess = processRunner ?? Process.run;

  final MachineProcessRunner _runProcess;

  bool get isSupported => Platform.isWindows;

  /// Kept so existing callers that only ever shut the machine down still read
  /// naturally. See [perform] for everything else.
  Future<void> shutdown() => perform(MachinePowerAction.shutdown);

  Future<void> perform(
    MachinePowerAction action, {
    int delaySeconds = 0,
    bool force = false,
  }) async {
    if (!isSupported) throw UnsupportedError('Chỉ hỗ trợ Windows.');

    final delay = delaySeconds < 0 ? 0 : delaySeconds;
    final (executable, arguments) = _commandFor(action, delay, force);
    final result = await _runProcess(executable, arguments);
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        '${result.stderr}'.trim(),
        result.exitCode,
      );
    }
  }

  /// Reads which sleep states this machine actually offers.
  ///
  /// Returns everything false when `powercfg` cannot be read, which reads as
  /// "unknown" to callers rather than as a promise the machine cannot keep.
  Future<MachineSleepSupport> readSleepSupport() async {
    if (!isSupported) return const MachineSleepSupport();

    try {
      final result = await _runProcess('powercfg.exe', ['/a']);
      if (result.exitCode != 0) return const MachineSleepSupport();
      return parseSleepSupport('${result.stdout}');
    } catch (_) {
      return const MachineSleepSupport();
    }
  }

  /// Whether the machine is sitting at the lock screen.
  ///
  /// A locked session still runs this app, so the phone must be able to tell
  /// "locked" from "offline" — they look the same from outside but only one of
  /// them can still take commands. LogonUI owns the lock screen, so its
  /// presence is the practical signal.
  Future<bool> isSessionLocked() async {
    if (!isSupported) return false;

    try {
      final result = await _runProcess('tasklist.exe', [
        '/fi',
        'IMAGENAME eq LogonUI.exe',
        '/nh',
      ]);
      if (result.exitCode != 0) return false;
      return '${result.stdout}'.toLowerCase().contains('logonui.exe');
    } catch (_) {
      return false;
    }
  }

  /// Parses `powercfg /a` output.
  ///
  /// The command lists available states first and unavailable ones under a
  /// second heading, so a name appearing anywhere is not enough — only the
  /// lines above that heading count.
  static MachineSleepSupport parseSleepSupport(String output) {
    final available = StringBuffer();
    for (final line in output.split(RegExp(r'\r?\n'))) {
      final lower = line.toLowerCase();
      // Both the English and Vietnamese builds mark the unavailable block.
      if (lower.contains('following sleep states are not available') ||
          lower.contains('không có sẵn')) {
        break;
      }
      available.writeln(lower);
    }

    final text = available.toString();
    return MachineSleepSupport(
      standby: text.contains('standby (s3)'),
      hibernate: text.contains('hibernate'),
      modernStandby: text.contains('standby (s0 low power idle)'),
    );
  }

  (String, List<String>) _commandFor(
    MachinePowerAction action,
    int delaySeconds,
    bool force,
  ) {
    switch (action) {
      case MachinePowerAction.shutdown:
        return ('shutdown.exe', ['/s', '/t', '$delaySeconds', if (force) '/f']);
      case MachinePowerAction.restart:
        // /g over /r: it signs the user back in and reopens registered apps,
        // which is what brings this agent back on a machine with a PIN.
        return ('shutdown.exe', ['/g', '/t', '$delaySeconds', if (force) '/f']);
      case MachinePowerAction.logoff:
        return ('shutdown.exe', ['/l']);
      case MachinePowerAction.cancel:
        return ('shutdown.exe', ['/a']);
      case MachinePowerAction.hibernate:
        return ('shutdown.exe', ['/h']);
      case MachinePowerAction.lock:
        return ('rundll32.exe', ['user32.dll,LockWorkStation']);
      case MachinePowerAction.displayOff:
        // WM_SYSCOMMAND / SC_MONITORPOWER with lParam 2. No command line does
        // this, so the message goes out through user32 directly. Add-Type
        // takes the signature on one line, which keeps this a single argument.
        return (
          'powershell.exe',
          [
            '-NoProfile',
            '-NonInteractive',
            '-WindowStyle',
            'Hidden',
            '-Command',
            r'''(Add-Type '[DllImport("user32.dll")]public static extern int SendMessage(int hWnd,int hMsg,int wParam,int lParam);' -Name Display -Namespace Native -PassThru)::SendMessage(0xFFFF,0x0112,0xF170,2) | Out-Null''',
          ],
        );
      case MachinePowerAction.sleep:
        return (
          'powershell.exe',
          [
            '-NoProfile',
            '-NonInteractive',
            '-WindowStyle',
            'Hidden',
            '-Command',
            r'Add-Type -AssemblyName System.Windows.Forms; '
                r'$slept = [System.Windows.Forms.Application]::SetSuspendState('
                r'[System.Windows.Forms.PowerState]::Suspend, $false, $false); '
                r'if (-not $slept) { exit 1 }',
          ],
        );
    }
  }
}
