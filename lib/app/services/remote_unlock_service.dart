import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:app_management_center/app/models/remote_unlock.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart';

class RemoteUnlockException implements Exception {
  const RemoteUnlockException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Owns the short-lived challenge and encrypted handoff to LogonUI.
///
/// This process never receives the Windows password in plaintext. The phone
/// encrypts it to the provider's machine key and this service only validates
/// and writes the resulting ciphertext.
class RemoteUnlockService {
  RemoteUnlockService({Directory? dataDirectory, Random? random})
    : _dataDirectory = dataDirectory ?? _defaultDataDirectory(),
      _random = random ?? Random.secure();

  static const challengeLifetime = Duration(minutes: 3);
  static const _challengeLength = 32;
  static const _maxCiphertextBytes = 1024;
  static const _windowsChannel = MethodChannel('amc/windows');

  final Directory _dataDirectory;
  final Random _random;
  Uint8List? _challenge;
  DateTime? _challengeExpiresAt;
  final List<DateTime> _acceptedAt = [];

  File get _publicKeyFile =>
      File('${_dataDirectory.path}${Platform.pathSeparator}public-key.json');
  File get _challengeFile =>
      File('${_dataDirectory.path}${Platform.pathSeparator}challenge.bin');
  File get _pendingFile =>
      File('${_dataDirectory.path}${Platform.pathSeparator}pending.bin');

  Future<RemoteUnlockState> diagnostics({
    required bool sessionLocked,
    required bool enabled,
  }) async {
    if (!Platform.isWindows) return const RemoteUnlockState();
    try {
      if (!await _publicKeyFile.exists()) {
        return const RemoteUnlockState(
          error: 'Credential Provider chưa được cài.',
        );
      }
      final key = Map<String, Object?>.from(
        jsonDecode(await _publicKeyFile.readAsString()) as Map,
      );
      if (!sessionLocked || !enabled) {
        await _clearChallenge();
        return RemoteUnlockState(
          installed: true,
          enabled: enabled,
          keyId: _text(key['keyId']),
          modulus: _text(key['modulus']),
          exponent: _text(key['exponent']),
          accountName: _accountName,
        );
      }

      await _ensureChallenge();
      return RemoteUnlockState(
        installed: true,
        enabled: true,
        keyId: _text(key['keyId']),
        modulus: _text(key['modulus']),
        exponent: _text(key['exponent']),
        challenge: base64Url.encode(_challenge!).replaceAll('=', ''),
        expiresAt: _challengeExpiresAt,
        accountName: _accountName,
      );
    } catch (error) {
      return RemoteUnlockState(error: 'Không đọc được bộ mở khóa: $error');
    }
  }

  Future<void> acceptEncryptedEnvelope(String encoded) async {
    if (!Platform.isWindows) {
      throw const RemoteUnlockException('Chỉ hỗ trợ Windows.');
    }
    final now = DateTime.now();
    _acceptedAt.removeWhere((entry) => now.difference(entry).inMinutes >= 10);
    if (_acceptedAt.length >= 3) {
      throw const RemoteUnlockException(
        'Đã chặn tạm thời sau 3 lần mở khóa trong 10 phút.',
      );
    }
    Uint8List ciphertext;
    try {
      ciphertext = base64Url.decode(base64Url.normalize(encoded.trim()));
    } catch (_) {
      throw const RemoteUnlockException('Payload mở khóa không hợp lệ.');
    }
    if (ciphertext.length < 256 || ciphertext.length > _maxCiphertextBytes) {
      throw const RemoteUnlockException(
        'Kích thước payload mở khóa không hợp lệ.',
      );
    }
    if (!await _challengeFile.exists()) {
      throw const RemoteUnlockException('Challenge mở khóa đã hết hạn.');
    }

    _acceptedAt.add(now);
    final temporary = File('${_pendingFile.path}.tmp');
    await temporary.writeAsBytes(ciphertext, flush: true);
    if (await _pendingFile.exists()) await _pendingFile.delete();
    await temporary.rename(_pendingFile.path);
  }

  Future<void> launchInstaller() async {
    if (!Platform.isWindows) {
      throw const RemoteUnlockException('Chỉ hỗ trợ Windows.');
    }
    final script = File(
      '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}install_remote_unlock.ps1',
    );
    if (!await script.exists()) {
      throw const RemoteUnlockException(
        'Không tìm thấy install_remote_unlock.ps1 trong bộ cài.',
      );
    }
    final launchedAt = DateTime.now().subtract(const Duration(seconds: 2));
    try {
      await _windowsChannel.invokeMethod<void>('installRemoteUnlock');
    } on MissingPluginException {
      throw const RemoteUnlockException(
        'App Windows đang chạy chưa có bộ cài native. Hãy khởi động lại bản mới.',
      );
    } on PlatformException catch (error) {
      final message = error.code == 'uac_cancelled'
          ? 'Bạn đã hủy yêu cầu quyền quản trị.'
          : (error.message ?? 'Không mở được trình cài mở khóa Windows.');
      throw RemoteUnlockException(message);
    }
    for (var attempt = 0; attempt < 60; attempt++) {
      if (await _publicKeyFile.exists()) {
        final modified = await _publicKeyFile.lastModified();
        if (modified.isAfter(launchedAt)) return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw const RemoteUnlockException(
      'Trình cài đã chạy nhưng Credential Provider chưa được đăng ký. '
      'Hãy kiểm tra cửa sổ PowerShell hoặc thử lại.',
    );
  }

  Future<void> _ensureChallenge() async {
    final now = DateTime.now();
    if (_challenge != null &&
        _challengeExpiresAt != null &&
        await _challengeFile.exists() &&
        _challengeExpiresAt!.difference(now) > const Duration(seconds: 30)) {
      return;
    }
    _challenge = Uint8List.fromList(
      List<int>.generate(_challengeLength, (_) => _random.nextInt(256)),
    );
    _challengeExpiresAt = now.add(challengeLifetime);

    final account = utf8.encode(_accountName);
    final bytes = BytesBuilder(copy: false)
      ..add(ascii.encode('AMCCH1'))
      ..add(_uint64le(_challengeExpiresAt!.millisecondsSinceEpoch))
      ..add(_challenge!)
      ..add(_uint16le(account.length))
      ..add(account);
    await _dataDirectory.create(recursive: true);
    final temporary = File('${_challengeFile.path}.tmp');
    await temporary.writeAsBytes(bytes.takeBytes(), flush: true);
    if (await _challengeFile.exists()) await _challengeFile.delete();
    await temporary.rename(_challengeFile.path);
    if (await _pendingFile.exists()) await _pendingFile.delete();
  }

  Future<void> _clearChallenge() async {
    _challenge = null;
    _challengeExpiresAt = null;
    for (final file in [_challengeFile, _pendingFile]) {
      if (await file.exists()) await file.delete();
    }
  }

  static String encryptPassword({
    required RemoteUnlockState state,
    required String password,
  }) {
    if (!state.ready) {
      throw const RemoteUnlockException('Máy chưa sẵn sàng nhận mở khóa.');
    }
    if (password.isEmpty) {
      throw const RemoteUnlockException('Mật khẩu không được để trống.');
    }
    final challenge = _decodeBase64Url(state.challenge);
    if (challenge.length != _challengeLength) {
      throw const RemoteUnlockException('Challenge mở khóa không hợp lệ.');
    }
    final username = utf8.encode(state.accountName);
    final secret = utf8.encode(password);
    if (username.length > 255 || secret.length > 240) {
      throw const RemoteUnlockException('Tên tài khoản hoặc mật khẩu quá dài.');
    }
    final expiresAt = DateTime.now().add(const Duration(seconds: 45));
    if (!expiresAt.isBefore(state.expiresAt!)) {
      throw const RemoteUnlockException('Challenge mở khóa sắp hết hạn.');
    }
    final plain = BytesBuilder(copy: false)
      ..add(ascii.encode('AMC1'))
      ..addByte(1)
      ..add(_uint64le(expiresAt.millisecondsSinceEpoch))
      ..add(challenge)
      ..add(_uint16le(username.length))
      ..add(_uint16le(secret.length))
      ..add(username)
      ..add(secret);

    final key = RSAPublicKey(
      _bigInt(_decodeBase64Url(state.modulus)),
      _bigInt(_decodeBase64Url(state.exponent)),
    );
    final cipher = OAEPEncoding.withSHA256(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(key));
    final payload = plain.takeBytes();
    if (payload.length > cipher.inputBlockSize) {
      throw const RemoteUnlockException('Payload mở khóa vượt giới hạn RSA.');
    }
    try {
      final encrypted = cipher.process(payload);
      return base64Url.encode(encrypted).replaceAll('=', '');
    } finally {
      // Best-effort cleanup of mutable buffers that contained the password.
      secret.fillRange(0, secret.length, 0);
      payload.fillRange(0, payload.length, 0);
    }
  }

  static Directory _defaultDataDirectory() {
    final root = Platform.environment['ProgramData'] ?? r'C:\ProgramData';
    return Directory(
      '$root${Platform.pathSeparator}App Management Center'
      '${Platform.pathSeparator}Remote Unlock',
    );
  }

  static String get _accountName {
    final domain = Platform.environment['USERDOMAIN']?.trim() ?? '';
    final user = Platform.environment['USERNAME']?.trim() ?? '';
    return domain.isEmpty ? user : '$domain\\$user';
  }
}

Uint8List _uint16le(int value) =>
    Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);

Uint8List _uint64le(int value) =>
    Uint8List(8)..buffer.asByteData().setUint64(0, value, Endian.little);

Uint8List _decodeBase64Url(String value) =>
    Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));

BigInt _bigInt(Uint8List bytes) {
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

String _text(Object? value) => value?.toString().trim() ?? '';
