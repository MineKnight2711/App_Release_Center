/// Stable product IDs. Never use project names, commands, URLs or task text.
enum AnalyticsFeature {
  bundleCheck('bundle.check'),
  releaseAndroid('release.android'),
  iosBuild('release.ios.build', platforms: {'macos'}),
  iosUpload('release.ios.upload', platforms: {'macos'}),
  planCreate('plan.create'),
  planBulkCreate('plan.bulk_create'),
  planAiGenerate('plan.ai_generate'),
  qaRun('qa.run'),
  apiSend('api.send');

  const AnalyticsFeature(
    this.id, {
    this.platforms = const {'windows', 'macos', 'linux'},
  });
  final String id;
  final Set<String> platforms;
}

enum AnalyticsResult {
  passed,
  issuesFound,
  succeeded,
  warning,
  saved,
  generated,
  responseReceived,
  submitted,
  verificationRequired,
}

extension AnalyticsResultWire on AnalyticsResult {
  String get wire => switch (this) {
    AnalyticsResult.issuesFound => 'issues_found',
    AnalyticsResult.responseReceived => 'response_received',
    AnalyticsResult.verificationRequired => 'verification_required',
    _ => name,
  };
}
