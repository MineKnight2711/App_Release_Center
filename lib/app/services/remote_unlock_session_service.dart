import 'package:app_management_center/app/models/app_lock.dart';
import 'package:app_management_center/app/models/remote_unlock_session.dart';
import 'package:app_management_center/app/services/app_lock_service.dart';
import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_management_center/app/services/project_store_service.dart';
import 'package:get/get.dart';

class RemoteUnlockSessionException implements Exception {
  const RemoteUnlockSessionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Remembers the Windows password so the phone can sign in without it being
/// typed again, and hands it back only to a biometric prompt.
///
/// The trade this makes is explicit: a Windows password now sits on the phone.
/// Three things pay for it, and all three are enforced here rather than left
/// to callers, because a bypass anywhere would undo the whole arrangement.
///
/// 1. The password lives in secure storage (Android Keystore), never in
///    preferences, which are a plain JSON file on disk.
/// 2. [readPassword] prompts every single time. There is no grace period and
///    no "the app was already unlocked, so this is fine" — unlocking the app
///    proves someone opened it, while this proves who is signing in to Windows
///    right now.
/// 3. Saving is refused outright on a phone with nothing enrolled, since the
///    prompt is the only thing standing in front of the password and a prompt
///    nobody can answer is not a lock.
class RemoteUnlockSessionService extends GetxService {
  RemoteUnlockSessionService({
    required ProjectStoreService store,
    required AppLockService lock,
    SecureKeyValueStore? secureStore,
    DateTime Function()? now,
  }) : _store = store,
       _lock = lock,
       _secureStore = secureStore ?? FlutterSecureKeyValueStore(),
       _now = now ?? DateTime.now;

  final ProjectStoreService _store;
  final AppLockService _lock;
  final SecureKeyValueStore _secureStore;
  final DateTime Function() _now;

  final session = const RemoteUnlockSession.none().obs;

  Future<RemoteUnlockSessionService> init() async {
    session.value = _store.remoteUnlockSession;
    // A marker with no password behind it is left over from an uninstall or a
    // cleared keystore. Dropping it keeps the console from offering a one-tap
    // unlock that could only fail.
    if (session.value.exists && await _readStoredPassword() == null) {
      await forget();
    }
    return this;
  }

  bool get canSave => _lock.availability.value.usable;

  /// Saves [password] for one account on one desktop.
  ///
  /// Asks for biometrics first: the person saving a Windows password should be
  /// the person who owns the phone, not whoever picked it up while it was
  /// unlocked.
  Future<void> save({
    required String accountName,
    required String desktopId,
    required String password,
  }) async {
    if (password.isEmpty) {
      throw const RemoteUnlockSessionException('Chưa nhập mật khẩu Windows.');
    }
    if (accountName.trim().isEmpty || desktopId.trim().isEmpty) {
      throw const RemoteUnlockSessionException(
        'Chưa biết máy tính và tài khoản để lưu phiên.',
      );
    }
    if (!canSave) {
      throw const RemoteUnlockSessionException(
        'Máy chưa có khuôn mặt, vân tay hay mã PIN nào được đăng ký. '
        'Thiết lập trong cài đặt bảo mật của Android rồi lưu lại — không có '
        'nó thì mật khẩu Windows nằm trên máy mà không có gì canh.',
      );
    }
    if (!await _lock.confirmUnconditionally(AppLockReason.saveUnlockSession)) {
      throw const RemoteUnlockSessionException(
        'Chưa xác thực nên mật khẩu không được lưu.',
      );
    }

    await _secureStore.write(key: _passwordKey, value: password);
    final saved = RemoteUnlockSession(
      accountName: accountName.trim(),
      desktopId: desktopId.trim(),
      savedAt: _now(),
    );
    await _store.saveRemoteUnlockSession(saved);
    session.value = saved;
  }

  /// Returns the saved password after a successful prompt, or null.
  ///
  /// Null covers every refusal — no saved session, a session that belongs to
  /// another machine, a failed or cancelled prompt — because none of them
  /// should produce a password and the caller treats them the same way.
  Future<String?> readPassword({
    required String accountName,
    required String desktopId,
  }) async {
    final current = session.value;
    if (!current.matches(accountName: accountName, desktopId: desktopId)) {
      return null;
    }
    if (!await _lock.confirmUnconditionally(AppLockReason.unlockWindows)) {
      return null;
    }

    final password = await _readStoredPassword();
    if (password == null) {
      // The marker outlived the secret. Say so by clearing it rather than
      // failing the same way again on the next press.
      await forget();
    }
    return password;
  }

  Future<void> forget() async {
    await _secureStore.delete(key: _passwordKey);
    await _store.clearRemoteUnlockSession();
    session.value = const RemoteUnlockSession.none();
  }

  Future<String?> _readStoredPassword() async {
    final stored = await _secureStore.read(key: _passwordKey);
    if (stored == null || stored.isEmpty) return null;
    return stored;
  }
}

const _passwordKey = 'remote_unlock.saved_windows_password';
