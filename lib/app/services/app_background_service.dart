import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'windows_auto_start_service.dart';

/// One tray and one close policy for the entire AMC process.
class AppBackgroundService extends ChangeNotifier {
  AppBackgroundService({MethodChannel? channel})
    : channel = channel ?? const MethodChannel('amc/background');
  static final shared = AppBackgroundService();
  final MethodChannel channel;
  final _reasons = <String, bool>{};
  final _open = <String, VoidCallback>{};
  final _shutdown = <String, Future<void> Function()>{};
  Future<void> _tail = Future.value();
  Future<void>? _quitting;
  bool _started = false;
  Set<String> get reasons => Set.unmodifiable(_reasons.keys);
  bool get enabled => _reasons.values.any((v) => v);
  void register(
    String owner, {
    VoidCallback? open,
    Future<void> Function()? shutdown,
  }) {
    if (!_started) {
      channel.setMethodCallHandler(_receive);
      _started = true;
    }
    if (open != null) _open[owner] = open;
    if (shutdown != null) _shutdown[owner] = shutdown;
  }

  Future<void> reason(String owner, bool requested) {
    register(owner);
    final done = Completer<void>();
    _tail = _tail.then((_) async {
      final previous = _reasons[owner];
      if (requested) {
        _reasons[owner] = true;
      } else {
        _reasons.remove(owner);
      }
      try {
        if (_quitting == null) {
          await channel.invokeMethod<void>('configure', {
            'enabled': enabled,
            'reminders': _reasons.containsKey('reminders'),
            'remote': _reasons.keys.any((v) => v.startsWith('remote')),
          });
        }
        notifyListeners();
        done.complete();
      } catch (e, st) {
        if (previous == null) {
          _reasons.remove(owner);
        } else {
          _reasons[owner] = previous;
        }
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  Future<void> restore() => channel.invokeMethod<void>('restore');
  Future<void> quit() => _quitting ??= _quit();
  Future<void> _quit() async {
    // All owners drain before native termination; a failed cleanup must not
    // prevent other owners from releasing their keys/capture/database.
    for (final close in _shutdown.values.toList().reversed) {
      try {
        await close().timeout(const Duration(seconds: 15));
      } catch (_) {}
    }
    await channel.invokeMethod<void>('quitNow');
  }

  Future<dynamic> _receive(MethodCall call) async {
    if (call.method == 'quit') {
      await quit();
      return null;
    }
    if (call.method == 'open') {
      _open[call.arguments as String]?.call();
      return null;
    }
    throw MissingPluginException();
  }
}

class DesktopAutoStartService {
  DesktopAutoStartService({
    WindowsAutoStartService? windows,
    MethodChannel? channel,
  }) : _windows = windows ?? WindowsAutoStartService(),
       _channel = channel ?? const MethodChannel('amc/background');
  final WindowsAutoStartService _windows;
  final MethodChannel _channel;
  bool get supported => Platform.isWindows || Platform.isMacOS;
  Future<bool> isEnabled() async => Platform.isWindows
      ? _windows.isEnabled()
      : Platform.isMacOS
      ? await _channel.invokeMethod<bool>('autostart') ?? false
      : false;
  Future<void> setEnabled(bool enabled) async {
    if (Platform.isWindows) {
      await _windows.setEnabled(enabled);
    } else if (Platform.isMacOS) {
      await _channel.invokeMethod<void>('setAutostart', enabled);
    } else {
      throw UnsupportedError('Chỉ hỗ trợ desktop Windows/macOS.');
    }
  }
}
