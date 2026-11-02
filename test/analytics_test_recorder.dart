import 'package:app_management_center/app/models/auth_models.dart';
import 'package:app_management_center/app/modules/analytics/analytics_transport.dart';
import 'package:app_management_center/app/modules/analytics/feature_analytics_service.dart';
import 'package:app_management_center/app/services/app_settings_service.dart';
import 'package:app_management_center/app/services/auth_service.dart';
export 'package:app_management_center/app/modules/analytics/feature_analytics_service.dart';

/// Captures calls made by domain services; deliberately records repeated terminal
/// calls too, so producer tests can detect duplicate instrumentation.
class AnalyticsRecorder extends FeatureAnalyticsService {
  AnalyticsRecorder()
    : super(
        settings: AppSettingsService(),
        auth: AuthService(sessionStore: _Session()),
        transport: AnalyticsTransport(
          baseUrl: Uri.parse('https://unused.invalid'),
          readToken: () async => null,
        ),
      );
  final events = <Map<String, String>>[];
  @override
  AnalyticsOperation? begin(
    AnalyticsSource source, {
    AnalyticsFeature feature = AnalyticsFeature.bundleCheck,
  }) {
    final operation = AnalyticsOperation(
      '${events.length}',
      'user',
      'team',
      source,
      0,
      feature,
    );
    events.add({
      'name': 'started',
      'feature': feature.id,
      'source': source.name,
    });
    return operation;
  }

  void _record(AnalyticsOperation? op, String name, [String? result]) {
    if (op == null) return;
    events.add({
      'name': name,
      'feature': op.feature.id,
      'result': result ?? '',
    });
  }

  @override
  void succeed(
    AnalyticsOperation? operation, {
    AnalyticsResult result = AnalyticsResult.succeeded,
  }) => _record(operation, 'completed', result.wire);
  @override
  void fail(AnalyticsOperation? operation, AnalyticsFailure failure) =>
      _record(operation, 'failed', failure.name);
  @override
  void cancel(AnalyticsOperation? operation) => _record(operation, 'cancelled');
}

class _Session implements AuthSessionStore {
  @override
  AuthSessionMetadata? get authSession => null;
  @override
  Future<void> clearAuthSession() async {}
  @override
  Future<void> saveAuthSession(AuthSessionMetadata session) async {}
}
