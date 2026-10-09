import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/windows_auto_start_service.dart';
import '../repositories/local_plan_repository.dart';
import 'reminder_scheduler.dart';

class PlanStudioRuntime extends ChangeNotifier {
  PlanStudioRuntime._(this.repository);
  @visibleForTesting
  PlanStudioRuntime.forTesting(this.repository);
  final _autoStart = WindowsAutoStartService();
  static final startupError = ValueNotifier<String?>(null);
  static Future<PlanStudioRuntime>? _opening;
  static Future<PlanStudioRuntime> open() => _opening ??= _open();
  static Future<PlanStudioRuntime> _open() async {
    try {
      return PlanStudioRuntime._(await LocalPlanRepository.open());
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  static const channel = MethodChannel('amc/plan_reminders');
  final LocalPlanRepository repository;
  ReminderScheduler? scheduler;
  SharedPreferences? _preferences;
  void Function(String? itemId)? navigate;
  String Function()? themeName;
  bool background = false, autostart = false, paused = false, quiet = false;
  int quietStart = 22, quietEnd = 8;
  String? error;
  bool _handling = false;
  bool _preview = false;

  Future<void> start({
    required void Function(String?) onOpen,
    required String Function() theme,
  }) async {
    if (!Platform.isWindows || scheduler != null) return;
    navigate = onOpen;
    themeName = theme;
    _preferences = await SharedPreferences.getInstance();
    background = _preferences!.getBool('plan.background') ?? false;
    autostart = _autoStart.isEnabled();
    paused = _preferences!.getBool('plan.paused') ?? false;
    quiet = _preferences!.getBool('plan.quiet') ?? false;
    quietStart = _preferences!.getInt('plan.quietStart') ?? 22;
    quietEnd = _preferences!.getInt('plan.quietEnd') ?? 8;
    channel.setMethodCallHandler(_receive);
    try {
      await channel.invokeMethod<void>('background', background);
    } catch (e) {
      background = false;
      error = '$e';
    }
    scheduler =
        ReminderScheduler(
            repository,
            suppressed: (now) => paused || isQuiet(now),
            publish: (payload) async {
              if (_preview) return;
              if (payload == null) {
                await channel.invokeMethod<void>('hide');
              } else {
                await channel.invokeMethod<void>('show', {
                  ...payload,
                  'theme': themeName?.call(),
                });
              }
            },
          )
          ..addListener(notifyListeners)
          ..start();
    notifyListeners();
  }

  bool isQuiet(DateTime local) =>
      quiet &&
      (quietStart < quietEnd
          ? local.hour >= quietStart && local.hour < quietEnd
          : local.hour >= quietStart || local.hour < quietEnd);

  Future<void> settings({
    bool? runInTray,
    bool? startup,
    bool? pause,
    bool? quietHours,
    int? from,
    int? until,
  }) async {
    if (_preferences == null) {
      throw StateError('Bộ nhắc chưa khởi động. Mở lại AMC để thử lại.');
    }
    if (from != null && (from < 0 || from > 23) ||
        until != null && (until < 0 || until > 23)) {
      throw ArgumentError('Giờ không hợp lệ.');
    }
    if ((from ?? quietStart) == (until ?? quietEnd)) {
      throw ArgumentError('Giờ bắt đầu và kết thúc phải khác nhau.');
    }
    if (runInTray != null) {
      await channel.invokeMethod<void>('background', runInTray);
      background = runInTray;
      await _preferences!.setBool('plan.background', background);
    }
    if (startup != null) {
      await _autoStart.setEnabled(startup);
      autostart = _autoStart.isEnabled();
    }
    if (pause != null) {
      paused = pause;
      await _preferences!.setBool('plan.paused', paused);
    }
    if (quietHours != null) {
      quiet = quietHours;
      await _preferences!.setBool('plan.quiet', quiet);
    }
    if (from != null) {
      quietStart = from;
      await _preferences!.setInt('plan.quietStart', from);
    }
    if (until != null) {
      quietEnd = until;
      await _preferences!.setInt('plan.quietEnd', until);
    }
    error = null;
    await scheduler?.scan(force: true);
    notifyListeners();
  }

  void refreshAutostart() {
    autostart = _autoStart.isEnabled();
    notifyListeners();
  }

  Future<void> preview() async {
    if (scheduler == null) {
      throw StateError('Bộ nhắc chưa khởi động. Mở lại AMC để thử lại.');
    }
    _preview = true;
    try {
      await channel.invokeMethod<void>('show', {
        'preview': true,
        'theme': themeName?.call(),
        'cards': [
          {
            'itemId': 'preview',
            'revision': 0,
            'code': 'BẢN XEM THỬ',
            'title': 'Đến giờ cập nhật tiến độ dự án',
            'project': 'Plan Studio',
            'status': 'Đang làm',
            'statusName': 'inProgress',
            'priority': 'P2',
            'scheduledAt': DateTime.now().toUtc().toIso8601String(),
            'progress': 0.6,
            'progressLabel': '6/10 task hoàn tất',
            'blocked': 1,
            'next': [
              'Kiểm tra bản build Windows',
              'Hoàn thiện checklist nghiệm thu',
            ],
            'reminders': <Map<String, dynamic>>[],
          },
        ],
      });
    } catch (_) {
      _preview = false;
      rethrow;
    }
  }

  @override
  void dispose() {
    scheduler?.removeListener(notifyListeners);
    scheduler?.dispose();
    channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _receive(MethodCall call) async {
    switch (call.method) {
      case 'wake':
        await scheduler?.scan(force: true);
        return null;
      case 'pause':
        await settings(pause: !paused);
        return null;
      case 'today':
        navigate?.call(null);
        return null;
      case 'presented':
        if (!_preview) {
          await repository.reminders.presented(
            (call.arguments as List).cast<String>(),
          );
        }
        return null;
      case 'action':
        if (_handling) {
          throw PlatformException(
            code: 'busy',
            message: 'Đang lưu, vui lòng đợi.',
          );
        }
        _handling = true;
        try {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          if (args['preview'] == true) {
            _preview = false;
            await channel.invokeMethod<void>('hide');
            await scheduler?.scan(force: true);
            return null;
          }
          final action = args['action'] as String;
          final itemId = args['itemId'] as String;
          await repository.applyReminderAction(
            itemId: itemId,
            itemRevision: args['revision'] as int,
            reminderRevisions: {
              for (final r in args['reminders'] as List)
                (r as Map)['id'] as String: r['revision'] as int,
            },
            commandId: args['commandId'] as String,
            action: action,
            minutes: args['minutes'] as int? ?? 10,
            reason: args['reason'] as String? ?? '',
          );
          if (action == 'open') {
            await channel.invokeMethod<void>('restore');
            navigate?.call(itemId);
          }
          await scheduler?.scan(force: true);
          return null;
        } catch (e) {
          await scheduler?.scan(force: true);
          throw PlatformException(code: 'reminder', message: '$e');
        } finally {
          _handling = false;
        }
      default:
        throw MissingPluginException();
    }
  }
}
