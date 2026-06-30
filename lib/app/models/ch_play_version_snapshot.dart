enum ChPlayComparisonStatus {
  notChecked,
  missingCredentials,
  missingLocalVersion,
  upToDate,
  localBehind,
  localAhead,
  failed,
}

class ChPlayLocalVersion {
  const ChPlayLocalVersion({
    required this.name,
    required this.code,
    required this.raw,
  });

  final String name;
  final int code;
  final String raw;

  String get display => '$name+$code';

  static ChPlayLocalVersion? parse(String value) {
    final trimmed = value.trim();
    final match = RegExp(r'^([^+]+)\+(\d+)$').firstMatch(trimmed);
    if (match == null) return null;

    final code = int.tryParse(match.group(2)!);
    if (code == null) return null;

    return ChPlayLocalVersion(
      name: match.group(1)!.trim(),
      code: code,
      raw: trimmed,
    );
  }
}

class ChPlayVersionSnapshot {
  const ChPlayVersionSnapshot({
    this.localVersion,
    this.storeVersionCode,
    this.status = ChPlayComparisonStatus.notChecked,
    this.message = '',
    this.lastCheckedAt,
    this.isRefreshing = false,
  });

  final ChPlayLocalVersion? localVersion;
  final int? storeVersionCode;
  final ChPlayComparisonStatus status;
  final String message;
  final DateTime? lastCheckedAt;
  final bool isRefreshing;

  String get localDisplay => localVersion?.display ?? '-';
  String get storeDisplay => storeVersionCode?.toString() ?? '-';

  ChPlayVersionSnapshot copyWith({
    ChPlayLocalVersion? localVersion,
    bool clearLocalVersion = false,
    int? storeVersionCode,
    bool clearStoreVersionCode = false,
    ChPlayComparisonStatus? status,
    String? message,
    DateTime? lastCheckedAt,
    bool clearLastCheckedAt = false,
    bool? isRefreshing,
  }) {
    return ChPlayVersionSnapshot(
      localVersion: clearLocalVersion
          ? null
          : localVersion ?? this.localVersion,
      storeVersionCode: clearStoreVersionCode
          ? null
          : storeVersionCode ?? this.storeVersionCode,
      status: status ?? this.status,
      message: message ?? this.message,
      lastCheckedAt: clearLastCheckedAt
          ? null
          : lastCheckedAt ?? this.lastCheckedAt,
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }
}
