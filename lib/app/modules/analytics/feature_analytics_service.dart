import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import '../../models/auth_models.dart';
import '../../services/app_settings_service.dart';
import '../../services/auth_service.dart';
import 'analytics_outbox.dart';
import 'analytics_transport.dart';

enum AnalyticsSource { module, filePicker, drop, recheck }

extension on AnalyticsSource {
  String get wire => this == AnalyticsSource.filePicker ? 'file_picker' : name;
}

enum AnalyticsFailure { inspection, tool, file, unexpected }

class AnalyticsOperation {
  AnalyticsOperation(
    this.id,
    this.owner,
    this.team,
    this.source,
    this.generation,
  );
  final String id, owner, team;
  final AnalyticsSource source;
  final int generation;
  final watch = Stopwatch()..start();
  bool finished = false;
}

class FeatureAnalyticsService extends GetxService {
  FeatureAnalyticsService({
    required this.settings,
    required this.auth,
    required this.transport,
    Future<AnalyticsOutbox> Function()? openOutbox,
    DateTime Function()? now,
    this.production = kReleaseMode,
    this.buildId = const String.fromEnvironment(
      'AMC_BUILD_ID',
      defaultValue: 'unknown',
    ),
    String? platform,
  }) : _openOutbox = openOutbox ?? AnalyticsOutbox.open,
       _now = now ?? DateTime.now,
       platform = platform ?? Platform.operatingSystem;

  final AppSettingsService settings;
  final AuthService auth;
  final AnalyticsTransport transport;
  final Future<AnalyticsOutbox> Function() _openOutbox;
  final DateTime Function() _now;
  final bool production;
  final String buildId, platform;
  final dropped = 0.obs;
  final rejected = 0.obs;
  final status = ''.obs;
  final canView = false.obs;
  final globalAdmin = false.obs;
  final teams = <Map<String, Object?>>[].obs;
  static const _uuid = Uuid();
  Future<void> _pending = Future.value();
  AnalyticsOutbox? _outbox;
  Timer? _timer;
  Worker? _profileWorker, _settingWorker;
  String? _owner;
  int _generation = 0, _failures = 0, _queued = 0;
  bool _sending = false, _closed = false, _paused = false;
  DateTime? _retryAt;
  String? _activeDay;

  bool get supported => ['windows', 'linux', 'macos'].contains(platform);
  bool get collecting =>
      !_closed &&
      production &&
      supported &&
      settings.analyticsEnabled.value &&
      auth.profile.value?.hasTeam == true;

  FeatureAnalyticsService start() {
    _owner = auth.profile.value?.uid;
    _profileWorker = ever(auth.profile, (_) => _identityChanged());
    _settingWorker = ever(settings.analyticsEnabled, (_) => _consentChanged());
    if (production && supported) {
      _serialize(() async {
        final box = await _box();
        if (!collecting || _owner == null) {
          await box.clear();
        } else {
          await box.retainOwner(_owner!);
        }
      }, critical: true);
    }
    _timer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(flush()),
    );
    unawaited(refreshAccess());
    return this;
  }

  Future<AnalyticsOutbox> _box() async => _outbox ??= await _openOutbox();
  void _serialize(Future<void> Function() action, {bool critical = false}) {
    if (_closed) return;
    if (!critical && _queued >= 1000) {
      dropped.value++;
      return;
    }
    _queued++;
    _pending = _pending
        .then((_) => action())
        .catchError((Object _) {
          dropped.value++;
          status.value = 'Chưa ghi được hàng đợi thống kê.';
        })
        .whenComplete(() => _queued--);
  }

  Future<void> get settled => _pending;

  void _identityChanged() {
    final owner = auth.profile.value?.uid;
    _generation++;
    _activeDay = null;
    _paused = false;
    _retryAt = null;
    transport.cancel();
    canView.value = false;
    globalAdmin.value = false;
    teams.clear();
    if (_owner != owner && production && supported) {
      _serialize(() async => (await _box()).clear(), critical: true);
    }
    _owner = owner;
    unawaited(refreshAccess());
  }

  void _consentChanged() {
    _generation++;
    _activeDay = null;
    transport.cancel();
    _paused = false;
    if (!settings.analyticsEnabled.value && production && supported) {
      _serialize(() async => (await _box()).clear(), critical: true);
    }
  }

  Future<void> refreshAccess() async {
    final generation = _generation;
    if (auth.profile.value == null) return;
    try {
      final access = await transport.request('access');
      if (_closed || generation != _generation) return;
      globalAdmin.value = access['global'] == true;
      teams.assignAll(
        (access['teams'] as List).map(
          (e) => Map<String, Object?>.from(e as Map),
        ),
      );
      canView.value = globalAdmin.value || teams.isNotEmpty;
    } catch (_) {
      /* Backend may not yet have the analytics migration. */
    }
  }

  /// Called only by real input, never by timers, rebuilds, or tray activity.
  void active() {
    if (!collecting) return;
    final profile = auth.profile.value!;
    final day =
        '${profile.uid}:${profile.teamId}:${_now().toUtc().toIso8601String().substring(0, 10)}';
    if (_activeDay == day) return;
    _activeDay = day;
    _record('app.active_day', profile, AnalyticsSource.module, feature: 'app');
    _record('feature.eligible_day', profile, AnalyticsSource.module);
  }

  void opened() {
    active();
    final profile = auth.profile.value;
    if (collecting && profile != null) {
      _record('feature.opened', profile, AnalyticsSource.module);
    }
  }

  AnalyticsOperation? begin(AnalyticsSource source) {
    active();
    if (!collecting) return null;
    final profile = auth.profile.value!;
    final operation = AnalyticsOperation(
      _uuid.v4(),
      profile.uid,
      profile.teamId,
      source,
      _generation,
    );
    _record('action.started', profile, source, operation: operation);
    return operation;
  }

  void complete(AnalyticsOperation? operation, {required bool issuesFound}) =>
      _finish(operation, result: issuesFound ? 'issues_found' : 'passed');
  void fail(AnalyticsOperation? operation, AnalyticsFailure failure) =>
      _finish(operation, failure: failure);

  void _finish(
    AnalyticsOperation? operation, {
    String? result,
    AnalyticsFailure? failure,
  }) {
    if (operation == null || operation.finished) return;
    operation.finished = true;
    operation.watch.stop();
    final profile = auth.profile.value;
    if (!collecting ||
        profile == null ||
        operation.generation != _generation ||
        operation.owner != profile.uid ||
        operation.team != profile.teamId) {
      return;
    }
    _record(
      failure == null ? 'action.completed' : 'action.failed',
      profile,
      operation.source,
      operation: operation,
      result: result,
      failure: failure,
    );
  }

  void _record(
    String name,
    CurrentUserProfile profile,
    AnalyticsSource source, {
    String feature = 'bundle.check',
    AnalyticsOperation? operation,
    String? result,
    AnalyticsFailure? failure,
  }) {
    final generation = _generation;
    final now = _now().toUtc();
    final event = <String, Object?>{
      'schema_version': 1,
      'event_id': _uuid.v4(),
      'team_id': profile.teamId,
      'occurred_at': now.toIso8601String(),
      'feature_id': feature,
      'event_name': name,
      'platform': platform,
      'build_id': RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(buildId)
          ? buildId
          : 'unknown',
      'source': source.wire,
      if (operation != null) 'operation_id': operation.id,
      if (result != null || failure != null)
        'duration_ms': operation!.watch.elapsedMilliseconds.clamp(0, 86400000),
      'result_category': ?result,
      if (failure != null) 'error_code': failure.name,
    };
    _serialize(() async {
      if (generation != _generation || !collecting) return;
      dropped.value += await (await _box()).add(profile.uid, event, now);
    });
  }

  Future<void> flush() async {
    if (!collecting ||
        _sending ||
        _paused ||
        (_retryAt?.isAfter(_now()) ?? false)) {
      return;
    }
    final owner = auth.profile.value!.uid;
    final generation = _generation;
    _sending = true;
    try {
      await settled;
      final box = await _box();
      final events = await box.batch(owner, _now());
      if (events.isEmpty || generation != _generation || !collecting) return;
      final response = await transport.request(
        'events',
        body: {'expected_user_id': owner, 'events': events},
      );
      if (generation != _generation || !collecting) return;
      final submitted = events.map((e) => e['event_id']).toSet();
      final ids = <String>[];
      for (final ack in (response['ack'] as List)) {
        if (ack is! Map || !submitted.contains(ack['event_id'])) continue;
        if (['accepted', 'duplicate', 'rejected'].contains(ack['status'])) {
          ids.add(ack['event_id'] as String);
          if (ack['status'] == 'rejected') rejected.value++;
        }
      }
      await box.acknowledge(owner, ids);
      _failures = 0;
      _retryAt = null;
      status.value = 'Đã đồng bộ ${ids.length} sự kiện.';
    } catch (error) {
      if (generation != _generation) return;
      _failures++;
      final retry = error is AnalyticsHttpException ? error.retryAfter : null;
      _retryAt = _now().add(
        retry ??
            Duration(
              seconds:
                  min(3600, 30 * (1 << min(_failures, 6))) +
                  Random().nextInt(15),
            ),
      );
      if (error is AnalyticsHttpException &&
          [400, 401, 403, 413].contains(error.status)) {
        _paused = true;
      }
      status.value = _paused
          ? 'Tạm dừng đồng bộ; cần xác thực hoặc kiểm tra cấu hình.'
          : 'Chờ gửi lại thống kê khi kết nối sẵn sàng.';
    } finally {
      _sending = false;
    }
  }

  Future<void> shutdown() async {
    if (_closed) return;
    _closed = true;
    _generation++;
    _timer?.cancel();
    _profileWorker?.dispose();
    _settingWorker?.dispose();
    transport.cancel();
    await _pending;
    try {
      await _outbox?.close();
    } catch (_) {
      /* Analytics must not block app shutdown. */
    }
  }

  @override
  void onClose() {
    unawaited(shutdown());
    super.onClose();
  }
}
