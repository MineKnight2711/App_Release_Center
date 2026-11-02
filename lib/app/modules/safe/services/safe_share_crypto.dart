import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/export.dart' as pc;

import '../models/safe_item.dart';
import 'safe_zip_packer.dart';

/// Why an item could not be sealed for a link, or a link not opened.
class SafeShareException implements Exception {
  const SafeShareException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// PBKDF2-HMAC-SHA256 cost for a share password (OWASP 2023). Browsers run it
/// natively in well under a second; here it runs off the UI isolate.
const safeShareIterations = 600000;
const safeShareMinPasswordLength = 8;

/// Largest item a link carries, as JSON. A keystore or `.p8` is a few KB.
const safeShareMaxPlainBytes = 1024 * 1024;

/// Why [password] cannot lock a link, or null when it can.
///
/// Printable ASCII only: the browser hashes exactly the characters typed, and
/// Vietnamese diacritics can be typed as different code points (NFC/NFD)
/// on another keyboard, which would lock the recipient out.
String? validateSafeSharePassword(String password) {
  if (password.length < safeShareMinPasswordLength) {
    return 'Mật khẩu link cần ít nhất $safeShareMinPasswordLength ký tự.';
  }
  if (password.codeUnits.any((unit) => unit < 0x20 || unit > 0x7E)) {
    return 'Mật khẩu link chỉ dùng chữ không dấu, số và ký hiệu ASCII.';
  }
  return null;
}

/// What travels inside a link: the item as the recipient needs it, without
/// where it sat on this machine. [includeNotes] is off by default because a
/// safe's notes are often for the owner only.
Map<String, Object?> safeSharePayload(
  SafeItem item, {
  bool includeNotes = false,
  String message = '',
  String from = '',
  DateTime? now,
}) => {
  'v': 1,
  ..._itemFields(item, includeNotes),
  ..._senderFields(message, from, now),
};

/// A whole project's keys in one link, laid out like the ZIP of
/// [SafeProjectKit]: each item carries its `path` inside the kit's [folder]
/// (`secrets.txt` for the ones that are not files), and `files` holds the
/// kit's generated `README.txt` and `secrets.txt`, so the page's "download
/// all" gives the same zip. Where the items sat on this machine stays out.
Map<String, Object?> safeShareBundlePayload({
  required String project,
  required List<SafeItem> items,
  bool includeNotes = false,
  String message = '',
  String from = '',
  DateTime? now,
}) {
  final shared = [
    for (final item in items) includeNotes ? item : item.copyWith(notes: ''),
  ];
  final kit = SafeProjectKit.build(
    project: project,
    items: shared,
    createdAt: now,
    includeSources: false,
  );
  final generated = {
    '${kit.folder}/${SafeProjectKit.readmeFile}',
    '${kit.folder}/${SafeProjectKit.secretsFile}',
  };
  return {
    'v': 1,
    'kind': 'bundle',
    'title': project.isEmpty ? 'Bộ keys' : 'Bộ keys $project',
    if (project.isNotEmpty) 'project': project,
    'folder': kit.folder,
    'items': [
      for (final placement in kit.placements)
        {..._itemFields(placement.item, includeNotes), 'path': placement.path},
    ],
    'files': [
      for (final entry in kit.entries)
        if (generated.contains(entry.path))
          {
            'path': entry.path.substring(kit.folder.length + 1),
            'text': utf8.decode(entry.bytes),
          },
    ],
    ..._senderFields(message, from, now),
  };
}

Map<String, Object?> _itemFields(SafeItem item, bool includeNotes) => {
  'kind': item.kind.name,
  'title': item.title,
  if (item.username.isNotEmpty) 'username': item.username,
  if (item.secret.isNotEmpty) 'secret': item.secret,
  if (item.url.isNotEmpty) 'url': item.url,
  if (item.fileName.isNotEmpty) 'fileName': item.fileName,
  if (item.project.isNotEmpty) 'project': item.project,
  if (includeNotes && item.notes.isNotEmpty) 'notes': item.notes,
};

Map<String, Object?> _senderFields(
  String message,
  String from,
  DateTime? now,
) => {
  if (message.trim().isNotEmpty) 'message': message.trim(),
  if (from.trim().isNotEmpty) 'from': from.trim(),
  'sharedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
};

/// One item sealed for a link. [secret] goes only into the link's #fragment;
/// everything else is what the Worker stores.
class SafeShareSeal {
  const SafeShareSeal({
    required this.id,
    required this.secret,
    required this.ciphertext,
    required this.accessHash,
    required this.passwordSalt,
    required this.kdfIterations,
  });

  final String id;
  final String secret;
  final String ciphertext;
  final String accessHash;

  /// Empty when the link has no password.
  final String passwordSalt;
  final int kdfIterations;

  bool get hasPassword => passwordSalt.isNotEmpty;

  /// The page URL the Worker returned, with the key after the `#`.
  String link(String pageUrl) => '$pageUrl#$secret';
}

/// The share format, version 1. The page that opens links
/// (`cloudflare/amc-api/src/sharePage.html`) does the same with Web Crypto:
///
///     context    = "amc-share.v1:" + id
///     ikm        = secret ‖ PBKDF2-SHA256(password, salt, iterations)?
///     encKey     = HKDF-SHA256(ikm, salt: context, info: "enc")
///     accessKey  = HKDF-SHA256(ikm, salt: context, info: "access")
///     accessHash = SHA-256(base64url(accessKey))
///     ciphertext = nonce ‖ AES-256-GCM(encKey, json, aad: context) ‖ tag
///
/// Byte strings travel as unpadded base64url.
class SafeShareCrypto {
  SafeShareCrypto({Random? random, this.iterations = safeShareIterations})
    : _random = random ?? Random.secure();

  static const _contextPrefix = 'amc-share.v1:';
  static final _aes = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  final Random _random;
  final int iterations;

  Future<SafeShareSeal> seal(
    Map<String, Object?> payload, {
    String password = '',
  }) async {
    final plain = utf8.encode(jsonEncode(payload));
    if (plain.length > safeShareMaxPlainBytes) {
      throw SafeShareException(
        'Nội dung lớn ${formatByteSize(plain.length)}, quá giới hạn '
        '${formatByteSize(safeShareMaxPlainBytes)} của link. Bỏ bớt mục '
        'hoặc gửi bằng file ZIP.',
      );
    }
    final id = base64UrlNoPad(_bytes(16));
    final secret = _bytes(32);
    final salt = password.isEmpty ? const <int>[] : _bytes(16);
    final keys = await _deriveKeys(id, secret, password, salt, iterations);
    final sealed = await _aes.encrypt(
      plain,
      secretKey: SecretKey(keys.enc),
      nonce: _bytes(12),
      aad: utf8.encode('$_contextPrefix$id'),
    );
    return SafeShareSeal(
      id: id,
      secret: base64UrlNoPad(secret),
      ciphertext: base64UrlNoPad(sealed.concatenation()),
      accessHash: await accessHashOf(keys.access),
      passwordSalt: salt.isEmpty ? '' : base64UrlNoPad(salt),
      kdfIterations: salt.isEmpty ? 0 : iterations,
    );
  }

  /// What the opening page does, for tests and for checking a link.
  Future<Map<String, Object?>> open({
    required String id,
    required String secret,
    required String ciphertext,
    String password = '',
    String passwordSalt = '',
    int kdfIterations = 0,
  }) async {
    final keys = await _deriveKeys(
      id,
      base64UrlDecodeNoPad(secret),
      password,
      passwordSalt.isEmpty ? const [] : base64UrlDecodeNoPad(passwordSalt),
      kdfIterations,
    );
    final box = SecretBox.fromConcatenation(
      base64UrlDecodeNoPad(ciphertext),
      nonceLength: 12,
      macLength: 16,
    );
    try {
      final clear = await _aes.decrypt(
        box,
        secretKey: SecretKey(keys.enc),
        aad: utf8.encode('$_contextPrefix$id'),
      );
      return Map<String, Object?>.from(jsonDecode(utf8.decode(clear)) as Map);
    } on SecretBoxAuthenticationError {
      throw const SafeShareException('Sai khoá hoặc mật khẩu của link.');
    }
  }

  /// The proof of the fragment (and password) the page sends to open a link.
  Future<String> accessKey({
    required String id,
    required String secret,
    String password = '',
    String passwordSalt = '',
    int kdfIterations = 0,
  }) async {
    final keys = await _deriveKeys(
      id,
      base64UrlDecodeNoPad(secret),
      password,
      passwordSalt.isEmpty ? const [] : base64UrlDecodeNoPad(passwordSalt),
      kdfIterations,
    );
    return base64UrlNoPad(keys.access);
  }

  static Future<String> accessHashOf(List<int> accessKey) async {
    final digest = await Sha256().hash(utf8.encode(base64UrlNoPad(accessKey)));
    return base64UrlNoPad(digest.bytes);
  }

  static Future<({List<int> enc, List<int> access})> _deriveKeys(
    String id,
    List<int> secret,
    String password,
    List<int> salt,
    int iterations,
  ) async {
    final ikm = [
      ...secret,
      if (salt.isNotEmpty)
        ...await Isolate.run(() => _pbkdf2(password, salt, iterations)),
    ];
    final context = utf8.encode('$_contextPrefix$id');
    Future<List<int>> derive(String info) async {
      final key = await _hkdf.deriveKey(
        secretKey: SecretKey(ikm),
        nonce: context,
        info: utf8.encode(info),
      );
      return key.extractBytes();
    }

    return (enc: await derive('enc'), access: await derive('access'));
  }

  /// pointycastle's PBKDF2 is about three times faster than the
  /// cryptography package's pure-Dart one at this cost.
  static Uint8List _pbkdf2(String password, List<int> salt, int iterations) {
    final kdf = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
      ..init(pc.Pbkdf2Parameters(Uint8List.fromList(salt), iterations, 32));
    return kdf.process(Uint8List.fromList(utf8.encode(password)));
  }

  List<int> _bytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256));
}

String base64UrlNoPad(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

List<int> base64UrlDecodeNoPad(String text) {
  try {
    return base64Url.decode(base64Url.normalize(text));
  } on FormatException {
    throw const SafeShareException('Link hỏng: khoá không đọc được.');
  }
}
