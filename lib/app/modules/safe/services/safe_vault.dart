import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/safe_item.dart';

class SafeException implements Exception {
  const SafeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The code did not open the safe. Kept apart from [SafeException] so the
/// door can count failed attempts without counting a damaged file as one.
class SafeWrongCodeException extends SafeException {
  const SafeWrongCodeException() : super('Sai mã két.');
}

/// Argon2id cost, written into the safe so a later change of defaults still
/// derives the same key for a safe made before it.
class SafeKdfParams {
  const SafeKdfParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  /// 64 MiB, 3 passes: about 0.3 s on a laptop, which a person typing once
  /// does not notice and a guessing machine pays on every guess.
  static const standard = SafeKdfParams(
    memoryKiB: 65536,
    iterations: 3,
    parallelism: 1,
  );

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  Map<String, dynamic> toJson() => {
    'algorithm': 'argon2id',
    'memoryKiB': memoryKiB,
    'iterations': iterations,
    'parallelism': parallelism,
  };

  /// Refuses costs no real safe was made with, so a crafted file cannot make
  /// the app allocate gigabytes or spin for minutes.
  factory SafeKdfParams.fromJson(Map<String, dynamic> json) {
    final memory = (json['memoryKiB'] as num?)?.toInt() ?? -1;
    final iterations = (json['iterations'] as num?)?.toInt() ?? -1;
    final parallelism = (json['parallelism'] as num?)?.toInt() ?? -1;
    if (json['algorithm'] != 'argon2id' ||
        memory < 8 ||
        memory > 1024 * 1024 ||
        iterations < 1 ||
        iterations > 20 ||
        parallelism < 1 ||
        parallelism > 16) {
      throw const SafeException('Thông số khoá của két không hợp lệ.');
    }
    return SafeKdfParams(
      memoryKiB: memory,
      iterations: iterations,
      parallelism: parallelism,
    );
  }
}

typedef SafeKeyDeriver =
    Future<List<int>> Function(
      String code,
      List<int> salt,
      SafeKdfParams params,
    );

Future<List<int>> deriveSafeKey(
  String code,
  List<int> salt,
  SafeKdfParams params,
) async {
  final kdf = Argon2id(
    parallelism: params.parallelism,
    memory: params.memoryKiB,
    iterations: params.iterations,
    hashLength: 32,
  );
  final key = await kdf.deriveKeyFromPassword(password: code, nonce: salt);
  return key.extractBytes();
}

/// Argon2id is pure Dart here; off the UI isolate the dial keeps turning
/// while it works.
Future<List<int>> deriveSafeKeyInIsolate(
  String code,
  List<int> salt,
  SafeKdfParams params,
) => Isolate.run(() => deriveSafeKey(code, salt, params));

/// The key an open safe holds. Destroyed when the door shuts.
class SafeSession {
  SafeSession._(this._dataKey, this._header);

  final SecretKeyData _dataKey;

  /// Format, KDF parameters and the wrapped data key: everything in the file
  /// except the sealed contents.
  final Map<String, dynamic> _header;

  bool get isClosed => _dataKey.hasBeenDestroyed;

  void close() {
    if (!_dataKey.hasBeenDestroyed) _dataKey.destroy();
  }
}

class SafeOpened {
  const SafeOpened(this.session, this.contents);

  final SafeSession session;
  final SafeContents contents;
}

/// The safe on disk: one JSON envelope, readable by nobody without the code.
///
/// A random 256-bit data key seals the contents (AES-256-GCM). That key is
/// itself sealed with a key derived from the code (Argon2id), so changing the
/// code rewraps 32 bytes instead of re-encrypting everything, and nothing
/// derived from the code is ever stored. Each block carries its own label as
/// associated data, so the wrapped key and the contents cannot be swapped.
class SafeVault {
  SafeVault({
    required Future<File> Function() locate,
    this.kdfParams = SafeKdfParams.standard,
    SafeKeyDeriver? deriveKey,
  }) : _locate = locate,
       _deriveKey = deriveKey ?? deriveSafeKeyInIsolate;

  /// The safe in Application Support, beside AMC's other local data.
  factory SafeVault.local() => SafeVault(
    locate: () async => File(
      p.join(
        (await getApplicationSupportDirectory()).path,
        'safe',
        'amc-safe.vault',
      ),
    ),
  );

  static const format = 'amc-safe';
  static const version = 1;
  static final _keyAad = utf8.encode('amc-safe.v1.key');
  static final _dataAad = utf8.encode('amc-safe.v1.data');
  static final _cipher = AesGcm.with256bits();
  static final _random = Random.secure();

  final Future<File> Function() _locate;
  final SafeKdfParams kdfParams;
  final SafeKeyDeriver _deriveKey;

  Future<void> _queue = Future.value();

  Future<String> get path async => (await _locate()).path;

  Future<bool> exists() async => (await _locate()).exists();

  Future<SafeOpened> create(String code) => _serial(() async {
    final file = await _locate();
    if (await file.exists()) {
      throw const SafeException('Két đã có sẵn trên máy này.');
    }
    final dataKey = SecretKeyData(
      _randomBytes(32),
      overwriteWhenDestroyed: true,
    );
    final session = SafeSession._(dataKey, await _header(code, dataKey));
    const contents = SafeContents();
    await _write(file, session, contents);
    return SafeOpened(session, contents);
  });

  Future<SafeOpened> unlock(String code) => _serial(() async {
    final file = await _locate();
    if (!await file.exists()) {
      throw const SafeException('Chưa có két trên máy này.');
    }
    return _open(await _readEnvelope(file), code);
  });

  Future<void> save(SafeSession session, SafeContents contents) =>
      _serial(() async {
        if (session.isClosed) throw const SafeException('Két đã khoá.');
        await _write(await _locate(), session, contents);
      });

  /// Rewraps the data key under [newCode]. [currentCode] is checked against
  /// the file, not trusted because the safe happens to be open. Backups the
  /// person exported earlier still open with the old code.
  Future<SafeSession> changeCode(
    SafeSession session,
    String currentCode,
    String newCode,
    SafeContents contents,
  ) => _serial(() async {
    final file = await _locate();
    final check = await _open(await _readEnvelope(file), currentCode);
    check.session.close();
    final next = SafeSession._(
      session._dataKey,
      await _header(newCode, session._dataKey),
    );
    await _write(file, next, contents);
    // The previous version is still wrapped under the old code. Someone
    // changing a code that leaked must not leave a copy it still opens.
    final previous = File('${file.path}.bak');
    if (await previous.exists()) await previous.delete();
    return next;
  });

  /// Copies the sealed file as it is: the backup opens with the same code.
  Future<void> exportBackup(String destination) => _serial(() async {
    await (await _locate()).copy(destination);
  });

  /// Replaces this machine's safe with a backup, but only after [code] opens
  /// it. The safe it replaces is kept beside it, not deleted.
  Future<SafeOpened> restoreBackup(String source, String code) =>
      _serial(() async {
        final envelope = await _readEnvelope(File(source));
        final opened = await _open(envelope, code);
        final file = await _locate();
        if (await file.exists()) {
          final stamp = DateTime.now().millisecondsSinceEpoch;
          await file.copy('${file.path}.before-restore-$stamp');
        }
        await _writeRaw(file, jsonEncode(envelope));
        return opened;
      });

  Future<SafeOpened> _open(Map<String, dynamic> envelope, String code) async {
    final kdf = _map(envelope['kdf']);
    final params = SafeKdfParams.fromJson(kdf);
    final salt = _decode(kdf['salt']);
    final keyEncryptionKey = SecretKeyData(
      await _deriveKey(code, salt, params),
      overwriteWhenDestroyed: true,
    );
    final List<int> dataKeyBytes;
    try {
      dataKeyBytes = await _cipher.decrypt(
        _box(_map(envelope['key'])),
        secretKey: keyEncryptionKey,
        aad: _keyAad,
      );
    } on SecretBoxAuthenticationError {
      throw const SafeWrongCodeException();
    } finally {
      keyEncryptionKey.destroy();
    }

    final dataKey = SecretKeyData(dataKeyBytes, overwriteWhenDestroyed: true);
    try {
      final clear = await _cipher.decrypt(
        _box(_map(envelope['data'])),
        secretKey: dataKey,
        aad: _dataAad,
      );
      final contents = SafeContents.fromJson(
        jsonDecode(utf8.decode(clear)) as Map<String, dynamic>,
      );
      final header = Map<String, dynamic>.of(envelope)
        ..remove('data')
        ..remove('savedAt');
      return SafeOpened(SafeSession._(dataKey, header), contents);
    } on SecretBoxAuthenticationError {
      dataKey.destroy();
      throw const SafeException('Nội dung két bị hỏng hoặc đã bị sửa.');
    } on FormatException {
      dataKey.destroy();
      throw const SafeException('Nội dung két bị hỏng hoặc đã bị sửa.');
    }
  }

  Future<Map<String, dynamic>> _header(String code, SecretKey dataKey) async {
    final salt = _randomBytes(16);
    final keyEncryptionKey = SecretKeyData(
      await _deriveKey(code, salt, kdfParams),
      overwriteWhenDestroyed: true,
    );
    try {
      final wrapped = await _cipher.encrypt(
        await dataKey.extractBytes(),
        secretKey: keyEncryptionKey,
        nonce: _randomBytes(12),
        aad: _keyAad,
      );
      return {
        'format': format,
        'version': version,
        'kdf': {...kdfParams.toJson(), 'salt': base64Encode(salt)},
        'key': _encodeBox(wrapped),
      };
    } finally {
      keyEncryptionKey.destroy();
    }
  }

  Future<void> _write(
    File file,
    SafeSession session,
    SafeContents contents,
  ) async {
    final sealed = await _cipher.encrypt(
      utf8.encode(jsonEncode(contents.toJson())),
      secretKey: session._dataKey,
      nonce: _randomBytes(12),
      aad: _dataAad,
    );
    await _writeRaw(
      file,
      jsonEncode({
        ...session._header,
        'data': _encodeBox(sealed),
        'savedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  /// Written beside the safe and renamed over it, so a crash mid-write never
  /// leaves half a safe. The version it replaces stays as `.bak`.
  Future<void> _writeRaw(File file, String content) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(content, flush: true);
    if (await file.exists()) await file.copy('${file.path}.bak');
    await temporary.rename(file.path);
  }

  Future<Map<String, dynamic>> _readEnvelope(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic> &&
          decoded['format'] == format &&
          decoded['version'] == version) {
        return decoded;
      }
    } on FormatException {
      // Falls through to the same message as any other foreign file.
    }
    throw const SafeException('Đây không phải tệp két của AMC.');
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final run = _queue.then((_) => action());
    _queue = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  static List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256));

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const SafeException('Đây không phải tệp két của AMC.');
  }

  static List<int> _decode(Object? value) {
    if (value is! String) {
      throw const SafeException('Đây không phải tệp két của AMC.');
    }
    try {
      return base64Decode(value);
    } on FormatException {
      throw const SafeException('Đây không phải tệp két của AMC.');
    }
  }

  static SecretBox _box(Map<String, dynamic> json) => SecretBox(
    _decode(json['cipherText']),
    nonce: _decode(json['nonce']),
    mac: Mac(_decode(json['mac'])),
  );

  static Map<String, String> _encodeBox(SecretBox box) => {
    'nonce': base64Encode(box.nonce),
    'cipherText': base64Encode(box.cipherText),
    'mac': base64Encode(box.mac.bytes),
  };
}
