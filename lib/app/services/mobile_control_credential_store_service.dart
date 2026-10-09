import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:get/get.dart';

/// Holds the phone's control token outside preferences.
///
/// The token is a bearer credential for the relay: whoever has it can queue
/// commands against the paired desktop. Builds before this service kept it in
/// `mobile_control_settings` in SharedPreferences, which is a plain JSON file
/// on disk — see [RemoteControlService] for the one-way migration that moves
/// such a token here and scrubs it from preferences.
class MobileControlCredentialStoreService extends GetxService {
  MobileControlCredentialStoreService({SecureKeyValueStore? secureStore})
    : _secureStore = secureStore ?? FlutterSecureKeyValueStore();

  final SecureKeyValueStore _secureStore;

  Future<String?> readControlToken() {
    return _secureStore.read(key: _controlTokenKey);
  }

  Future<void> saveControlToken(String? token) async {
    final trimmed = token?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _secureStore.delete(key: _controlTokenKey);
      return;
    }

    await _secureStore.write(key: _controlTokenKey, value: trimmed);
  }

  Future<void> clearControlToken() {
    return _secureStore.delete(key: _controlTokenKey);
  }
}

const _controlTokenKey = 'remote_control.device_control_token';
