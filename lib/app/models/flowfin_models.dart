/// Dart mirror of the FlowFin API payloads.
///
/// FlowFin's hard rule: money is an integer count of the currency's smallest
/// unit, and it crosses the wire as a *string* so it never passes through a
/// JSON float. Nothing in this file may hold an amount in a `double`.
library;

/// Parses an `amountMinor`-style field.
///
/// The API always sends a string, but it also accepts integers on input, so
/// both are tolerated here. Anything else is a contract violation.
int parseMinor(Object? value, {String field = 'amountMinor'}) {
  if (value is int) return value;
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) return parsed;
  }
  throw FormatException('$field must be an integer string, got: $value');
}

int parseMinorOr(Object? value, int fallback) {
  try {
    return parseMinor(value);
  } on FormatException {
    return fallback;
  }
}

/// Renders a minor amount back onto the wire.
String formatMinor(int value) => '$value';

class FlowFinSession {
  const FlowFinSession({
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresAt,
    required this.refreshTokenExpiresAt,
    this.user,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessTokenExpiresAt;
  final DateTime refreshTokenExpiresAt;
  final FlowFinUser? user;

  /// Treated as expired slightly early so a request never leaves with a token
  /// that dies in flight.
  bool isAccessTokenExpired({DateTime? now, Duration skew = const Duration(seconds: 30)}) {
    final reference = (now ?? DateTime.now().toUtc()).add(skew);
    return !accessTokenExpiresAt.isAfter(reference);
  }

  bool isRefreshTokenExpired({DateTime? now}) {
    return !refreshTokenExpiresAt.isAfter(now ?? DateTime.now().toUtc());
  }

  FlowFinSession copyWith({FlowFinUser? user}) {
    return FlowFinSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessTokenExpiresAt: accessTokenExpiresAt,
      refreshTokenExpiresAt: refreshTokenExpiresAt,
      user: user ?? this.user,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'accessTokenExpiresAt': accessTokenExpiresAt.toIso8601String(),
      'refreshTokenExpiresAt': refreshTokenExpiresAt.toIso8601String(),
      if (user != null) 'user': user!.toJson(),
    };
  }

  factory FlowFinSession.fromJson(Map<String, Object?> json) {
    final rawUser = json['user'];
    return FlowFinSession(
      accessToken: (json['accessToken'] as String?) ?? '',
      refreshToken: (json['refreshToken'] as String?) ?? '',
      accessTokenExpiresAt: _parseTime(json['accessTokenExpiresAt']),
      refreshTokenExpiresAt: _parseTime(json['refreshTokenExpiresAt']),
      user: rawUser is Map<String, Object?> ? FlowFinUser.fromJson(rawUser) : null,
    );
  }
}

class FlowFinUser {
  const FlowFinUser({
    required this.id,
    required this.email,
    this.displayName = '',
    this.currency = 'VND',
    this.locale = 'vi',
    this.timezone = 'Asia/Ho_Chi_Minh',
    this.emailVerified = false,
  });

  final String id;
  final String email;
  final String displayName;
  final String currency;
  final String locale;
  final String timezone;
  final bool emailVerified;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'currency': currency,
      'locale': locale,
      'timezone': timezone,
      'emailVerified': emailVerified,
    };
  }

  factory FlowFinUser.fromJson(Map<String, Object?> json) {
    return FlowFinUser(
      id: (json['id'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      displayName: (json['displayName'] as String?) ?? '',
      currency: (json['currency'] as String?) ?? 'VND',
      locale: (json['locale'] as String?) ?? 'vi',
      timezone: (json['timezone'] as String?) ?? 'Asia/Ho_Chi_Minh',
      emailVerified: (json['emailVerified'] as bool?) ?? false,
    );
  }
}

class FlowFinWallet {
  const FlowFinWallet({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
    required this.initialBalanceMinor,
    this.color = '',
    this.icon = '',
    this.includeInTotal = true,
    this.archivedAt,
    this.sortOrder = 0,
    this.version = 1,
  });

  final String id;
  final String name;
  final String type;
  final String currency;
  final int initialBalanceMinor;
  final String color;
  final String icon;
  final bool includeInTotal;
  final String? archivedAt;
  final int sortOrder;
  final int version;

  bool get isArchived => archivedAt != null && archivedAt!.isNotEmpty;

  factory FlowFinWallet.fromJson(Map<String, Object?> json) {
    return FlowFinWallet(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      type: (json['type'] as String?) ?? '',
      currency: (json['currency'] as String?) ?? 'VND',
      initialBalanceMinor: parseMinorOr(json['initialBalanceMinor'], 0),
      color: (json['color'] as String?) ?? '',
      icon: (json['icon'] as String?) ?? '',
      includeInTotal: (json['includeInTotal'] as bool?) ?? true,
      archivedAt: json['archivedAt'] as String?,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }
}

class FlowFinCategory {
  const FlowFinCategory({
    required this.id,
    required this.name,
    required this.kind,
    this.icon = '',
    this.color = '',
    this.isDefault = false,
    this.sortOrder = 0,
    this.archivedAt,
    this.version = 1,
  });

  final String id;
  final String name;

  /// `income` or `expense`.
  final String kind;
  final String icon;
  final String color;
  final bool isDefault;
  final int sortOrder;
  final String? archivedAt;
  final int version;

  bool get isArchived => archivedAt != null && archivedAt!.isNotEmpty;

  factory FlowFinCategory.fromJson(Map<String, Object?> json) {
    return FlowFinCategory(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      kind: (json['kind'] as String?) ?? 'expense',
      icon: (json['icon'] as String?) ?? '',
      color: (json['color'] as String?) ?? '',
      isDefault: (json['isDefault'] as bool?) ?? false,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      archivedAt: json['archivedAt'] as String?,
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }
}

class FlowFinTransaction {
  const FlowFinTransaction({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.currency,
    required this.walletId,
    required this.localDate,
    this.toWalletId,
    this.categoryId,
    this.occurredAt = '',
    this.note = '',
    this.source = '',
    this.version = 1,
  });

  final String id;

  /// `income`, `expense` or `transfer`. A transfer is neither income nor
  /// expense and never counts against a budget.
  final String type;
  final int amountMinor;
  final String currency;
  final String walletId;
  final String localDate;
  final String? toWalletId;
  final String? categoryId;
  final String occurredAt;
  final String note;
  final String source;
  final int version;

  bool get isTransfer => type == 'transfer';

  factory FlowFinTransaction.fromJson(Map<String, Object?> json) {
    return FlowFinTransaction(
      id: (json['id'] as String?) ?? '',
      type: (json['type'] as String?) ?? 'expense',
      amountMinor: parseMinorOr(json['amountMinor'], 0),
      currency: (json['currency'] as String?) ?? 'VND',
      walletId: (json['walletId'] as String?) ?? '',
      localDate: (json['localDate'] as String?) ?? '',
      toWalletId: json['toWalletId'] as String?,
      categoryId: json['categoryId'] as String?,
      occurredAt: (json['occurredAt'] as String?) ?? '',
      note: (json['note'] as String?) ?? '',
      source: (json['source'] as String?) ?? '',
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }
}

class FlowFinBudget {
  const FlowFinBudget({
    required this.id,
    required this.scope,
    required this.periodKey,
    required this.limitMinor,
    required this.currency,
    this.categoryId,
    this.version = 1,
  });

  final String id;

  /// `total` or `category`.
  final String scope;
  final String periodKey;
  final int limitMinor;
  final String currency;
  final String? categoryId;
  final int version;

  factory FlowFinBudget.fromJson(Map<String, Object?> json) {
    return FlowFinBudget(
      id: (json['id'] as String?) ?? '',
      scope: (json['scope'] as String?) ?? 'total',
      periodKey: (json['periodKey'] as String?) ?? '',
      limitMinor: parseMinorOr(json['limitMinor'], 0),
      currency: (json['currency'] as String?) ?? 'VND',
      categoryId: json['categoryId'] as String?,
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }
}

class FlowFinInsight {
  const FlowFinInsight({
    required this.id,
    required this.title,
    this.summary = '',
    this.insightType = '',
    this.periodKey = '',
    this.status = '',
    this.severity = '',
    this.observations = const [],
    this.suggestions = const [],
    this.generatedAt = '',
  });

  final String id;
  final String title;
  final String summary;
  final String insightType;
  final String periodKey;
  final String status;
  final String severity;
  final List<String> observations;
  final List<String> suggestions;
  final String generatedAt;

  factory FlowFinInsight.fromJson(Map<String, Object?> json) {
    return FlowFinInsight(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      summary: (json['summary'] as String?) ?? '',
      insightType: (json['insightType'] as String?) ?? '',
      periodKey: (json['periodKey'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      severity: (json['severity'] as String?) ?? '',
      observations: _stringList(json['observations']),
      suggestions: _stringList(json['suggestions']),
      generatedAt: (json['generatedAt'] as String?) ?? '',
    );
  }
}

class FlowFinWalletBalance {
  const FlowFinWalletBalance({
    required this.walletId,
    required this.balanceMinor,
    this.asOfDate = '',
    this.estimated = false,
  });

  final String walletId;
  final int balanceMinor;
  final String asOfDate;
  final bool estimated;

  factory FlowFinWalletBalance.fromJson(Map<String, Object?> json) {
    return FlowFinWalletBalance(
      walletId: (json['walletId'] as String?) ?? '',
      balanceMinor: parseMinorOr(json['balanceMinor'], 0),
      asOfDate: (json['asOfDate'] as String?) ?? '',
      estimated: (json['estimated'] as bool?) ?? false,
    );
  }
}

class FlowFinStatsOverview {
  const FlowFinStatsOverview({
    required this.from,
    required this.to,
    required this.totalBalanceMinor,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.netMinor,
    this.transferCount = 0,
    this.walletBalances = const [],
    this.estimated = false,
    this.missingCheckInWalletIds = const [],
  });

  final String from;
  final String to;
  final int totalBalanceMinor;
  final int incomeMinor;
  final int expenseMinor;
  final int netMinor;
  final int transferCount;
  final List<FlowFinWalletBalance> walletBalances;

  /// True while a wallet has not been checked in up to [to]; every balance on
  /// this object is then an estimate and the UI must say so.
  final bool estimated;
  final List<String> missingCheckInWalletIds;

  factory FlowFinStatsOverview.fromJson(Map<String, Object?> json) {
    return FlowFinStatsOverview(
      from: (json['from'] as String?) ?? '',
      to: (json['to'] as String?) ?? '',
      totalBalanceMinor: parseMinorOr(json['totalBalanceMinor'], 0),
      incomeMinor: parseMinorOr(json['incomeMinor'], 0),
      expenseMinor: parseMinorOr(json['expenseMinor'], 0),
      netMinor: parseMinorOr(json['netMinor'], 0),
      transferCount: (json['transferCount'] as num?)?.toInt() ?? 0,
      walletBalances: _mapList(json['walletBalances'], FlowFinWalletBalance.fromJson),
      estimated: (json['estimated'] as bool?) ?? false,
      missingCheckInWalletIds: _stringList(json['missingCheckInWalletIds']),
    );
  }
}

class FlowFinBootstrap {
  const FlowFinBootstrap({
    required this.user,
    this.wallets = const [],
    this.categories = const [],
    this.budgets = const [],
    this.latestInsight,
    this.cursor = '',
    this.serverTime = '',
  });

  final FlowFinUser user;
  final List<FlowFinWallet> wallets;
  final List<FlowFinCategory> categories;
  final List<FlowFinBudget> budgets;

  /// Null whenever AI has produced nothing yet, or the AI path is down. The
  /// dashboard must still render — the database is the source of truth and AI
  /// only interprets it.
  final FlowFinInsight? latestInsight;
  final String cursor;
  final String serverTime;

  factory FlowFinBootstrap.fromJson(Map<String, Object?> json) {
    final rawUser = json['user'];
    final rawInsight = json['latestInsight'];
    return FlowFinBootstrap(
      user: rawUser is Map<String, Object?>
          ? FlowFinUser.fromJson(rawUser)
          : const FlowFinUser(id: '', email: ''),
      wallets: _mapList(json['wallets'], FlowFinWallet.fromJson),
      categories: _mapList(json['categories'], FlowFinCategory.fromJson),
      budgets: _mapList(json['budgets'], FlowFinBudget.fromJson),
      latestInsight: rawInsight is Map<String, Object?>
          ? FlowFinInsight.fromJson(rawInsight)
          : null,
      cursor: (json['cursor'] as String?) ?? '',
      serverTime: (json['serverTime'] as String?) ?? '',
    );
  }
}

class FlowFinTransactionPage {
  const FlowFinTransactionPage({this.items = const [], this.nextCursor = ''});

  final List<FlowFinTransaction> items;
  final String nextCursor;

  bool get hasMore => nextCursor.isNotEmpty;

  factory FlowFinTransactionPage.fromJson(Map<String, Object?> json) {
    return FlowFinTransactionPage(
      items: _mapList(json['items'], FlowFinTransaction.fromJson),
      nextCursor: (json['nextCursor'] as String?) ?? '',
    );
  }
}

List<T> _mapList<T>(Object? raw, T Function(Map<String, Object?>) build) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((entry) => build(entry.cast<String, Object?>()))
      .toList(growable: false);
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return raw.whereType<String>().toList(growable: false);
}

DateTime _parseTime(Object? raw) {
  if (raw is String) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed.toUtc();
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
