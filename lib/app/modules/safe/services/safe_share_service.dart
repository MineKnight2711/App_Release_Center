import 'package:get/get.dart';

import '../../../data/amc_api_client.dart';
import '../../../services/auth_service.dart';
import '../models/safe_item.dart';
import 'safe_share_crypto.dart';

enum SafeShareStatus {
  active('Đang mở'),
  expired('Hết hạn'),
  usedUp('Hết lượt xem'),
  locked('Đã khoá: sai mật khẩu nhiều lần');

  const SafeShareStatus(this.label);

  final String label;

  static SafeShareStatus parse(Object? value) => switch (value) {
    'active' => active,
    'used-up' => usedUp,
    'locked' => locked,
    _ => expired,
  };
}

/// A link as its owner's account sees it: never the key, so never the link
/// itself again after it was made.
class SafeShareLink {
  const SafeShareLink({
    required this.id,
    required this.itemId,
    required this.status,
    required this.passwordProtected,
    required this.maxViews,
    required this.views,
    required this.failedAttempts,
    required this.createdAt,
    required this.expiresAt,
    required this.lastViewedAt,
  });

  final String id;
  final String itemId;
  final SafeShareStatus status;
  final bool passwordProtected;

  /// Null when the link opens any number of times until it expires.
  final int? maxViews;
  final int views;
  final int failedAttempts;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? lastViewedAt;

  bool get isActive => status == SafeShareStatus.active;

  /// The project a whole-kit link was made for, or null for a single item.
  String? get bundleProject => itemId.startsWith(bundleItemPrefix)
      ? itemId.substring(bundleItemPrefix.length)
      : null;

  /// Marks a link's [itemId] as a project's kit rather than one item.
  static const bundleItemPrefix = 'bundle:';

  factory SafeShareLink.fromJson(Map<String, Object?> json) {
    DateTime time(Object? value) =>
        DateTime.tryParse('$value')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return SafeShareLink(
      id: '${json['id']}',
      itemId: '${json['itemId'] ?? ''}',
      status: SafeShareStatus.parse(json['status']),
      passwordProtected: json['passwordProtected'] == true,
      maxViews: (json['maxViews'] as num?)?.toInt(),
      views: (json['views'] as num?)?.toInt() ?? 0,
      failedAttempts: (json['failedAttempts'] as num?)?.toInt() ?? 0,
      createdAt: time(json['createdAt']),
      expiresAt: time(json['expiresAt']),
      lastViewedAt: json['lastViewedAt'] == null
          ? null
          : time(json['lastViewedAt']),
    );
  }
}

/// How a new link behaves.
class SafeShareOptions {
  const SafeShareOptions({
    this.expiresIn = const Duration(days: 1),
    this.maxViews = 3,
    this.password = '',
    this.includeNotes = false,
    this.message = '',
    this.from = '',
  });

  static const expiryChoices = [
    Duration(hours: 1),
    Duration(days: 1),
    Duration(days: 3),
    Duration(days: 7),
    Duration(days: 30),
  ];

  /// Null stands for no limit.
  static const viewChoices = <int?>[1, 3, 10, null];

  final Duration expiresIn;
  final int? maxViews;

  /// Empty for a link that opens with the link alone.
  final String password;
  final bool includeNotes;
  final String message;
  final String from;
}

/// A link just made. [link] carries the key and exists only here: the
/// account stores no copy of it.
class SafeShareCreated {
  const SafeShareCreated({
    required this.share,
    required this.link,
    required this.password,
  });

  final SafeShareLink share;
  final String link;
  final String password;
}

/// Makes, lists and revokes the share links of this account's safe items.
class SafeShareService {
  SafeShareService({
    required AmcApiClient api,
    SafeShareCrypto? crypto,
    this.senderName = '',
  }) : _api = api,
       _crypto = crypto ?? SafeShareCrypto();

  /// The app's service, or null when this build has no AMC server.
  static SafeShareService? resolve() {
    if (!Get.isRegistered<AmcApiClient>()) return null;
    final profile = Get.isRegistered<AuthService>()
        ? Get.find<AuthService>().profile.value
        : null;
    final name = profile == null
        ? ''
        : profile.displayName.trim().isNotEmpty
        ? profile.displayName.trim()
        : profile.email;
    return SafeShareService(api: Get.find<AmcApiClient>(), senderName: name);
  }

  /// Whether this app run has an AMC account signed in, when it can tell.
  static bool? get signedIn => Get.isRegistered<AuthService>()
      ? Get.find<AuthService>().isAuthenticated
      : null;

  final AmcApiClient _api;
  final SafeShareCrypto _crypto;

  /// Shown to the recipient as who sent the item.
  final String senderName;

  Future<SafeShareCreated> create(
    SafeItem item,
    SafeShareOptions options,
  ) async {
    _checkPassword(options);
    return _upload(
      safeSharePayload(
        item,
        includeNotes: options.includeNotes,
        message: options.message,
        from: options.from.isEmpty ? senderName : options.from,
      ),
      itemId: item.id,
      options: options,
    );
  }

  /// One link for [items] of [project], laid out like its ZIP kit.
  Future<SafeShareCreated> createBundle({
    required String project,
    required List<SafeItem> items,
    required SafeShareOptions options,
  }) async {
    if (items.isEmpty) {
      throw const SafeShareException('Chọn ít nhất một mục để chia sẻ.');
    }
    _checkPassword(options);
    return _upload(
      safeShareBundlePayload(
        project: project,
        items: items,
        includeNotes: options.includeNotes,
        message: options.message,
        from: options.from.isEmpty ? senderName : options.from,
      ),
      itemId: '${SafeShareLink.bundleItemPrefix}$project',
      options: options,
    );
  }

  void _checkPassword(SafeShareOptions options) {
    if (options.password.isEmpty) return;
    final problem = validateSafeSharePassword(options.password);
    if (problem != null) throw SafeShareException(problem);
  }

  Future<SafeShareCreated> _upload(
    Map<String, Object?> payload, {
    required String itemId,
    required SafeShareOptions options,
  }) async {
    final seal = await _crypto.seal(payload, password: options.password);
    final response = await _api.post(
      '/shares',
      body: {
        'id': seal.id,
        'itemId': itemId,
        'ciphertext': seal.ciphertext,
        'accessHash': seal.accessHash,
        if (seal.hasPassword) 'passwordSalt': seal.passwordSalt,
        if (seal.hasPassword) 'kdfIterations': seal.kdfIterations,
        'expiresInHours': options.expiresIn.inHours.clamp(1, 30 * 24),
        'maxViews': options.maxViews,
      },
      timeout: const Duration(seconds: 60),
    );
    final share = response['share'];
    final url = response['url']?.toString() ?? '';
    if (share is! Map || url.isEmpty) {
      throw const SafeShareException('Server trả về link không đầy đủ.');
    }
    return SafeShareCreated(
      share: SafeShareLink.fromJson(Map<String, Object?>.from(share)),
      link: seal.link(url),
      password: options.password,
    );
  }

  Future<List<SafeShareLink>> list() async {
    final response = await _api.get('/shares');
    final shares = response['shares'];
    if (shares is! List) return const [];
    return [
      for (final share in shares)
        if (share is Map)
          SafeShareLink.fromJson(Map<String, Object?>.from(share)),
    ];
  }

  /// The link stops working at once, for everyone who has it.
  Future<void> revoke(String shareId) =>
      _api.delete('/shares/${Uri.encodeComponent(shareId)}');
}

/// "1 giờ", "3 ngày": how a link's lifetime reads in the dialog.
String formatShareDuration(Duration value) {
  if (value.inDays >= 1 && value.inHours % 24 == 0) {
    return '${value.inDays} ngày';
  }
  return '${value.inHours} giờ';
}

String formatShareViews(int? maxViews) => switch (maxViews) {
  null => 'Không giới hạn',
  1 => '1 lần',
  final count => '$count lần',
};

/// The note to send with a link to [title]: how to open it, never the
/// password.
String safeShareMessage(String title, SafeShareCreated created) {
  final share = created.share;
  String two(int n) => n.toString().padLeft(2, '0');
  final expires = share.expiresAt;
  final until =
      '${two(expires.hour)}:${two(expires.minute)} '
      '${two(expires.day)}/${two(expires.month)}/${expires.year}';
  final views = switch (share.maxViews) {
    null => '',
    1 => ' Link chỉ mở được 1 lần rồi tự huỷ, nhớ lưu lại ngay.',
    final count => ' Link mở được $count lần.',
  };
  final password = created.password.isEmpty
      ? ''
      : ' Mật khẩu mình gửi riêng qua kênh khác.';
  return 'Mình gửi "$title" qua link bảo mật của AMC: ${created.link} '
      '(hết hạn lúc $until).$views$password';
}
