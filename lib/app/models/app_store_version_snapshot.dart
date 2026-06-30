enum AppStoreComparisonStatus {
  notChecked,
  missingCredentials,
  missingBundleId,
  missingLocalVersion,
  upToDate,
  localBehind,
  localAhead,
  failed,
}

class AppStoreLocalVersion {
  const AppStoreLocalVersion({
    required this.name,
    required this.buildNumber,
    required this.raw,
  });

  final String name;
  final int buildNumber;
  final String raw;

  String get display => '$name+$buildNumber';

  static AppStoreLocalVersion? parse(String value) {
    final trimmed = value.trim();
    final match = RegExp(r'^([^+]+)\+(\d+)$').firstMatch(trimmed);
    if (match == null) return null;

    final buildNumber = int.tryParse(match.group(2)!);
    if (buildNumber == null) return null;

    return AppStoreLocalVersion(
      name: match.group(1)!.trim(),
      buildNumber: buildNumber,
      raw: trimmed,
    );
  }
}

class AppStoreVersionSnapshot {
  const AppStoreVersionSnapshot({
    this.localVersion,
    this.testFlightBuildNumber,
    this.status = AppStoreComparisonStatus.notChecked,
    this.message = '',
    this.lastCheckedAt,
    this.isRefreshing = false,
  });

  final AppStoreLocalVersion? localVersion;
  final int? testFlightBuildNumber;
  final AppStoreComparisonStatus status;
  final String message;
  final DateTime? lastCheckedAt;
  final bool isRefreshing;

  String get localDisplay => localVersion?.display ?? '-';
  String get testFlightDisplay => testFlightBuildNumber?.toString() ?? '-';

  AppStoreVersionSnapshot copyWith({
    AppStoreLocalVersion? localVersion,
    bool clearLocalVersion = false,
    int? testFlightBuildNumber,
    bool clearTestFlightBuildNumber = false,
    AppStoreComparisonStatus? status,
    String? message,
    DateTime? lastCheckedAt,
    bool clearLastCheckedAt = false,
    bool? isRefreshing,
  }) {
    return AppStoreVersionSnapshot(
      localVersion: clearLocalVersion
          ? null
          : localVersion ?? this.localVersion,
      testFlightBuildNumber: clearTestFlightBuildNumber
          ? null
          : testFlightBuildNumber ?? this.testFlightBuildNumber,
      status: status ?? this.status,
      message: message ?? this.message,
      lastCheckedAt: clearLastCheckedAt
          ? null
          : lastCheckedAt ?? this.lastCheckedAt,
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }
}
