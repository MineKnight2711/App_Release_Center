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

/// Display formatting, matched to the FlowFin phone app so the same number
/// reads identically on both surfaces.
class FlowFinMoney {
  const FlowFinMoney._();

  /// `đ` rather than the Unicode `₫`, the way Vietnamese banks write it.
  static const String symbol = 'đ';

  /// `1250000` -> `1.250.000 đ`.
  static String format(int minor, {bool withSign = false}) {
    final sign = minor < 0 ? '-' : (withSign && minor > 0 ? '+' : '');
    return '$sign${grouped(minor.abs())} $symbol';
  }

  /// Thousands separator only: `1250000` -> `1.250.000`.
  static String grouped(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// Short form for tight spaces: `1,2 tr`, `950 ng`.
  static String compact(int minor) {
    final abs = minor.abs();
    final sign = minor < 0 ? '-' : '';
    if (abs >= 1000000000) {
      return '$sign${(abs / 1000000000).toStringAsFixed(1).replaceAll('.', ',')} tỷ';
    }
    if (abs >= 1000000) {
      return '$sign${(abs / 1000000).toStringAsFixed(1).replaceAll('.', ',')} tr';
    }
    if (abs >= 1000) return '$sign${(abs / 1000).round()} ng';
    return '$sign$abs';
  }

  /// Reads what the user typed (`1.250.000`, `1250000`) as minor units.
  /// Returns null when it cannot be read — the caller must handle that rather
  /// than guess an amount.
  static int? parseInput(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9-]'), '');
    if (cleaned.isEmpty || cleaned == '-') return null;
    return int.tryParse(cleaned);
  }
}

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
  const FlowFinTransactionPage({
    this.items = const [],
    this.nextCursor = '',
    this.incomeMinor = 0,
    this.expenseMinor = 0,
  });

  final List<FlowFinTransaction> items;
  final String nextCursor;

  /// Totals for the whole filtered set, not just this page.
  final int incomeMinor;
  final int expenseMinor;

  bool get hasMore => nextCursor.isNotEmpty;

  factory FlowFinTransactionPage.fromJson(Map<String, Object?> json) {
    final totals = json['totals'];
    final totalsMap = totals is Map ? totals.cast<String, Object?>() : const {};
    return FlowFinTransactionPage(
      items: _mapList(json['items'], FlowFinTransaction.fromJson),
      nextCursor: (json['nextCursor'] as String?) ?? '',
      incomeMinor: parseMinorOr(totalsMap['incomeMinor'], 0),
      expenseMinor: parseMinorOr(totalsMap['expenseMinor'], 0),
    );
  }
}

class FlowFinSnapshot {
  const FlowFinSnapshot({
    required this.id,
    required this.walletId,
    required this.localDate,
    required this.balanceMinor,
    this.source = '',
    this.note = '',
    this.version = 1,
  });

  final String id;
  final String walletId;
  final String localDate;
  final int balanceMinor;
  final String source;
  final String note;
  final int version;

  factory FlowFinSnapshot.fromJson(Map<String, Object?> json) {
    return FlowFinSnapshot(
      id: (json['id'] as String?) ?? '',
      walletId: (json['walletId'] as String?) ?? '',
      localDate: (json['localDate'] as String?) ?? '',
      balanceMinor: parseMinorOr(json['balanceMinor'], 0),
      source: (json['source'] as String?) ?? '',
      note: (json['note'] as String?) ?? '',
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }
}

/// The result of checking a wallet's counted balance against what the ledger
/// expects. A difference is reported, never silently turned into a
/// transaction — the user decides whether to adjust.
class FlowFinReconciliation {
  const FlowFinReconciliation({
    required this.walletId,
    required this.localDate,
    required this.expectedBalanceMinor,
    required this.actualBalanceMinor,
    required this.differenceMinor,
    this.previousBalanceMinor = 0,
    this.previousBalanceDate = '',
    this.estimated = false,
    this.incomeMinor = 0,
    this.expenseMinor = 0,
    this.transferInMinor = 0,
    this.transferOutMinor = 0,
    this.adjustmentMinor = 0,
    this.status = '',
  });

  final String walletId;
  final String localDate;
  final int expectedBalanceMinor;
  final int actualBalanceMinor;
  final int differenceMinor;
  final int previousBalanceMinor;
  final String previousBalanceDate;
  final bool estimated;
  final int incomeMinor;
  final int expenseMinor;
  final int transferInMinor;
  final int transferOutMinor;
  final int adjustmentMinor;
  final String status;

  bool get isBalanced => differenceMinor == 0;

  factory FlowFinReconciliation.fromJson(Map<String, Object?> json) {
    return FlowFinReconciliation(
      walletId: (json['walletId'] as String?) ?? '',
      localDate: (json['localDate'] as String?) ?? '',
      expectedBalanceMinor: parseMinorOr(json['expectedBalanceMinor'], 0),
      actualBalanceMinor: parseMinorOr(json['actualBalanceMinor'], 0),
      differenceMinor: parseMinorOr(json['differenceMinor'], 0),
      previousBalanceMinor: parseMinorOr(json['previousBalanceMinor'], 0),
      previousBalanceDate: (json['previousBalanceDate'] as String?) ?? '',
      estimated: (json['estimated'] as bool?) ?? false,
      incomeMinor: parseMinorOr(json['incomeMinor'], 0),
      expenseMinor: parseMinorOr(json['expenseMinor'], 0),
      transferInMinor: parseMinorOr(json['transferInMinor'], 0),
      transferOutMinor: parseMinorOr(json['transferOutMinor'], 0),
      adjustmentMinor: parseMinorOr(json['adjustmentMinor'], 0),
      status: (json['status'] as String?) ?? '',
    );
  }
}

class FlowFinTimelinePoint {
  const FlowFinTimelinePoint({
    required this.key,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.netMinor,
  });

  final String key;
  final int incomeMinor;
  final int expenseMinor;
  final int netMinor;

  factory FlowFinTimelinePoint.fromJson(Map<String, Object?> json) {
    return FlowFinTimelinePoint(
      key: (json['key'] as String?) ?? '',
      incomeMinor: parseMinorOr(json['incomeMinor'], 0),
      expenseMinor: parseMinorOr(json['expenseMinor'], 0),
      netMinor: parseMinorOr(json['netMinor'], 0),
    );
  }
}

class FlowFinTimeline {
  const FlowFinTimeline({this.bucket = 'day', this.points = const []});

  final String bucket;
  final List<FlowFinTimelinePoint> points;

  factory FlowFinTimeline.fromJson(Map<String, Object?> json) {
    return FlowFinTimeline(
      bucket: (json['bucket'] as String?) ?? 'day',
      points: _mapList(json['points'], FlowFinTimelinePoint.fromJson),
    );
  }
}

class FlowFinBreakdownItem {
  const FlowFinBreakdownItem({
    required this.id,
    required this.name,
    required this.amountMinor,
    this.color = '',
    this.percent = 0,
    this.transactionCount = 0,
  });

  final String id;
  final String name;
  final int amountMinor;
  final String color;

  /// Display only, rounded to one decimal by the API. Never use it for money.
  final double percent;
  final int transactionCount;

  factory FlowFinBreakdownItem.fromJson(Map<String, Object?> json) {
    return FlowFinBreakdownItem(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      amountMinor: parseMinorOr(json['amountMinor'], 0),
      color: (json['color'] as String?) ?? '',
      percent: (json['percent'] as num?)?.toDouble() ?? 0,
      transactionCount: (json['transactionCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class FlowFinBreakdown {
  const FlowFinBreakdown({
    this.groupBy = 'category',
    this.kind = 'expense',
    this.totalMinor = 0,
    this.items = const [],
  });

  final String groupBy;
  final String kind;
  final int totalMinor;
  final List<FlowFinBreakdownItem> items;

  factory FlowFinBreakdown.fromJson(Map<String, Object?> json) {
    return FlowFinBreakdown(
      groupBy: (json['groupBy'] as String?) ?? 'category',
      kind: (json['kind'] as String?) ?? 'expense',
      totalMinor: parseMinorOr(json['totalMinor'], 0),
      items: _mapList(json['items'], FlowFinBreakdownItem.fromJson),
    );
  }
}

class FlowFinNotificationPrefs {
  const FlowFinNotificationPrefs({
    this.checkInReminderEnabled = false,
    this.checkInReminderTime = '20:00',
    this.budgetAlertEnabled = false,
    this.weeklyReportEnabled = false,
    this.weeklyReportDow = 1,
    this.monthlyReportEnabled = false,
    this.monthlyReportDay = 1,
    this.reportHour = 8,
    this.version = 1,
  });

  final bool checkInReminderEnabled;
  final String checkInReminderTime;
  final bool budgetAlertEnabled;
  final bool weeklyReportEnabled;
  final int weeklyReportDow;
  final bool monthlyReportEnabled;
  final int monthlyReportDay;
  final int reportHour;
  final int version;

  FlowFinNotificationPrefs copyWith({
    bool? checkInReminderEnabled,
    String? checkInReminderTime,
    bool? budgetAlertEnabled,
    bool? weeklyReportEnabled,
    int? weeklyReportDow,
    bool? monthlyReportEnabled,
    int? monthlyReportDay,
    int? reportHour,
  }) {
    return FlowFinNotificationPrefs(
      checkInReminderEnabled:
          checkInReminderEnabled ?? this.checkInReminderEnabled,
      checkInReminderTime: checkInReminderTime ?? this.checkInReminderTime,
      budgetAlertEnabled: budgetAlertEnabled ?? this.budgetAlertEnabled,
      weeklyReportEnabled: weeklyReportEnabled ?? this.weeklyReportEnabled,
      weeklyReportDow: weeklyReportDow ?? this.weeklyReportDow,
      monthlyReportEnabled: monthlyReportEnabled ?? this.monthlyReportEnabled,
      monthlyReportDay: monthlyReportDay ?? this.monthlyReportDay,
      reportHour: reportHour ?? this.reportHour,
      version: version,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'checkInReminderEnabled': checkInReminderEnabled,
      'checkInReminderTime': checkInReminderTime,
      'budgetAlertEnabled': budgetAlertEnabled,
      'weeklyReportEnabled': weeklyReportEnabled,
      'weeklyReportDow': weeklyReportDow,
      'monthlyReportEnabled': monthlyReportEnabled,
      'monthlyReportDay': monthlyReportDay,
      'reportHour': reportHour,
    };
  }

  factory FlowFinNotificationPrefs.fromJson(Map<String, Object?> json) {
    return FlowFinNotificationPrefs(
      checkInReminderEnabled:
          (json['checkInReminderEnabled'] as bool?) ?? false,
      checkInReminderTime: (json['checkInReminderTime'] as String?) ?? '20:00',
      budgetAlertEnabled: (json['budgetAlertEnabled'] as bool?) ?? false,
      weeklyReportEnabled: (json['weeklyReportEnabled'] as bool?) ?? false,
      weeklyReportDow: (json['weeklyReportDow'] as num?)?.toInt() ?? 1,
      monthlyReportEnabled: (json['monthlyReportEnabled'] as bool?) ?? false,
      monthlyReportDay: (json['monthlyReportDay'] as num?)?.toInt() ?? 1,
      reportHour: (json['reportHour'] as num?)?.toInt() ?? 8,
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }
}

class FlowFinImportItem {
  const FlowFinImportItem({
    required this.id,
    required this.batchId,
    required this.amountMinor,
    required this.localDate,
    this.status = '',
    this.direction = '',
    this.merchant = '',
    this.description = '',
    this.rawText = '',
    this.confidence = 0,
    this.suggestedCategoryId,
    this.suggestedWalletId,
    this.duplicateOf,
    this.transactionId,
    this.version = 1,
  });

  final String id;
  final String batchId;
  final int amountMinor;
  final String localDate;
  final String status;

  /// `in` or `out`.
  final String direction;
  final String merchant;
  final String description;
  final String rawText;
  final double confidence;
  final String? suggestedCategoryId;
  final String? suggestedWalletId;
  final String? duplicateOf;
  final String? transactionId;
  final int version;

  bool get isDuplicate => duplicateOf != null && duplicateOf!.isNotEmpty;

  factory FlowFinImportItem.fromJson(Map<String, Object?> json) {
    return FlowFinImportItem(
      id: (json['id'] as String?) ?? '',
      batchId: (json['batchId'] as String?) ?? '',
      amountMinor: parseMinorOr(json['amountMinor'], 0),
      localDate: (json['localDate'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      direction: (json['direction'] as String?) ?? '',
      merchant: (json['merchant'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      rawText: (json['rawText'] as String?) ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      suggestedCategoryId: json['suggestedCategoryId'] as String?,
      suggestedWalletId: json['suggestedWalletId'] as String?,
      duplicateOf: json['duplicateOf'] as String?,
      transactionId: json['transactionId'] as String?,
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }
}

class FlowFinImportBatch {
  const FlowFinImportBatch({
    required this.id,
    this.source = '',
    this.status = '',
    this.engine = '',
    this.itemCount = 0,
    this.lastError = '',
    this.createdAt = '',
    this.expiresAt = '',
    this.items = const [],
  });

  final String id;
  final String source;
  final String status;
  final String engine;
  final int itemCount;
  final String lastError;
  final String createdAt;
  final String expiresAt;
  final List<FlowFinImportItem> items;

  factory FlowFinImportBatch.fromJson(Map<String, Object?> json) {
    return FlowFinImportBatch(
      id: (json['id'] as String?) ?? '',
      source: (json['source'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      engine: (json['engine'] as String?) ?? '',
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      lastError: (json['lastError'] as String?) ?? '',
      createdAt: (json['createdAt'] as String?) ?? '',
      expiresAt: (json['expiresAt'] as String?) ?? '',
      items: _mapList(json['items'], FlowFinImportItem.fromJson),
    );
  }
}

/// One line of a confirmed import: which parsed item becomes which transaction.
class FlowFinImportConfirmEntry {
  const FlowFinImportConfirmEntry({
    required this.itemId,
    required this.transactionId,
    required this.walletId,
    this.categoryId,
    this.note,
  });

  final String itemId;

  /// Client-generated, so resending the same confirmation never creates a
  /// second transaction.
  final String transactionId;
  final String walletId;
  final String? categoryId;
  final String? note;

  Map<String, Object?> toJson() {
    return {
      'itemId': itemId,
      'transactionId': transactionId,
      'walletId': walletId,
      if (categoryId != null && categoryId!.isNotEmpty) 'categoryId': categoryId,
      if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
    };
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
