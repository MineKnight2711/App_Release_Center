import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where secrets lived before [EncryptedFileSecretStore], read once per key.
abstract interface class LegacySecretSource {
  Future<String?> read(String key);
  Future<void> delete(String key);
}

/// The macOS credential store: one AES-256-GCM encrypted file, no keychain.
///
/// AMC ships ad-hoc signed, and the legacy keychain trusts an item only for
/// the exact binary that saved it, so every new build asked for the login
/// password once per item. This file needs no prompt. It sits under ~/Library
/// (0700) and its key comes from the Mac's hardware UUID, so a copy taken off
/// this machine (a backup, a zip, Migration Assistant) does not decrypt.
/// Unlike the keychain it does not stop another process running as the same
/// user: that is the price of never prompting.
///
/// Secrets still in the keychain move over on first read, which asks for the
/// password one last time for that item; the keychain copy is then deleted.
class EncryptedFileSecretStore {
  EncryptedFileSecretStore({
    required Future<File> Function() locate,
    required Future<List<int>> Function() machineSecret,
    this.legacy,
  }) : _locate = locate,
       _machineSecret = machineSecret;

  /// The one instance every credential service shares, so they never
  /// overwrite each other's changes.
  static final shared = EncryptedFileSecretStore(
    locate: () async => File(
      p.join((await getApplicationSupportDirectory()).path, 'secrets.json'),
    ),
    machineSecret: _hardwareUuid,
    legacy: const _LegacyKeychain(),
  );

  final Future<File> Function() _locate;
  final Future<List<int>> Function() _machineSecret;
  final LegacySecretSource? legacy;

  static final _cipher = AesGcm.with256bits();
  static final _kdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _kdfInfo = utf8.encode('amc.secret-store.v1');

  Future<void> _queue = Future.value();
  _Contents? _contents;

  Future<String?> read(String key) => _serial(() async {
    final contents = await _load();
    final stored = contents.values[key];
    if (stored != null || !_awaitsLegacy(contents, key)) return stored;

    // A denied prompt throws here and leaves the key to be asked again.
    final moved = await legacy!.read(key);
    contents.settled.add(key);
    if (moved != null) contents.values[key] = moved;
    await _save(contents);
    if (moved != null) await _forgetLegacy(key);
    return moved;
  });

  Future<void> write(String key, String value) => _serial(() async {
    final contents = await _load();
    final staleInLegacy = _awaitsLegacy(contents, key);
    contents.values[key] = value;
    if (legacy != null) contents.settled.add(key);
    await _save(contents);
    if (staleInLegacy) await _forgetLegacy(key);
  });

  Future<void> delete(String key) => _serial(() async {
    final contents = await _load();
    final staleInLegacy = _awaitsLegacy(contents, key);
    final removed = contents.values.remove(key) != null;
    // Settling a deleted key keeps its keychain copy from coming back.
    if (legacy != null) contents.settled.add(key);
    if (removed || staleInLegacy) await _save(contents);
    if (staleInLegacy) await _forgetLegacy(key);
  });

  bool _awaitsLegacy(_Contents contents, String key) =>
      legacy != null && !contents.settled.contains(key);

  /// Deleting a keychain item does not prompt. If it fails anyway the copy
  /// stays behind, but it is never read again.
  Future<void> _forgetLegacy(String key) async {
    try {
      await legacy!.delete(key);
    } catch (error) {
      debugPrint('Could not delete the keychain copy of $key: $error');
    }
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final run = _queue.then((_) => action());
    _queue = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<_Contents> _load() async {
    final cached = _contents;
    if (cached != null) return cached;

    final file = await _locate();
    if (!await file.exists()) return _contents = _Contents();
    final raw = await file.readAsString();
    // Outside the try: a machine secret that cannot be read must fail loudly,
    // not discard a file that is fine.
    final secret = await _machineSecret();
    try {
      final envelope = jsonDecode(raw) as Map<String, dynamic>;
      final clearText = await _cipher.decrypt(
        SecretBox(
          base64Decode(envelope['cipherText'] as String),
          nonce: base64Decode(envelope['nonce'] as String),
          mac: Mac(base64Decode(envelope['mac'] as String)),
        ),
        secretKey: await _key(secret, base64Decode(envelope['salt'] as String)),
      );
      return _contents = _Contents.fromJson(
        jsonDecode(utf8.decode(clearText)) as Map<String, dynamic>,
      );
    } catch (error) {
      // Encrypted on another Mac, or damaged. Keep it for recovery and start
      // empty: the credentials have to be entered again.
      final aside =
          '${file.path}.unreadable-${DateTime.now().millisecondsSinceEpoch}';
      await file.rename(aside);
      debugPrint(
        'Secret store could not be decrypted, moved to $aside: $error',
      );
      return _contents = _Contents();
    }
  }

  Future<void> _save(_Contents contents) async {
    final file = await _locate();
    await file.parent.create(recursive: true);
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(contents.toJson())),
      secretKey: await _key(await _machineSecret(), salt),
    );
    // Written beside the file and renamed over it, so a crash mid-write
    // never leaves half a store.
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'version': 1,
        'salt': base64Encode(salt),
        'nonce': base64Encode(box.nonce),
        'cipherText': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      }),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  Future<SecretKey> _key(List<int> secret, List<int> salt) =>
      _kdf.deriveKey(secretKey: SecretKey(secret), nonce: salt, info: _kdfInfo);

  static Future<List<int>>? _uuid;

  /// The hardware UUID, which survives macOS updates (unlike kern.uuid).
  static Future<List<int>> _hardwareUuid() => _uuid ??= () async {
    final result = await Process.run('/usr/sbin/ioreg', [
      '-rd1',
      '-c',
      'IOPlatformExpertDevice',
    ]);
    final match = RegExp(
      r'"IOPlatformUUID" = "([0-9A-Fa-f-]+)"',
    ).firstMatch('${result.stdout}');
    if (result.exitCode != 0 || match == null) {
      _uuid = null;
      throw StateError(
        'Không đọc được Hardware UUID của máy nên không mở được kho bí mật.',
      );
    }
    return utf8.encode(match.group(1)!);
  }();
}

class _Contents {
  _Contents();

  _Contents.fromJson(Map<String, dynamic> json) {
    values.addAll(
      (json['values'] as Map<String, dynamic>).cast<String, String>(),
    );
    settled.addAll((json['settled'] as List<dynamic>).cast<String>());
  }

  final values = <String, String>{};

  /// Keys whose keychain copy has been dealt with: moved, absent, or
  /// overwritten here. The keychain is never consulted for them again.
  final settled = <String>{};

  Map<String, dynamic> toJson() => {
    'values': values,
    'settled': settled.toList(),
  };
}

/// Where AMC kept secrets until the encrypted file replaced it.
class _LegacyKeychain implements LegacySecretSource {
  const _LegacyKeychain();

  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
