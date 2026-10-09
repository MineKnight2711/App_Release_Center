import 'dart:convert';

import 'package:app_management_center/app/models/flowfin_models.dart';
import 'package:app_management_center/app/models/flowfin_settings.dart';
import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:get/get.dart';

/// Holds FlowFin sessions in the platform secure store.
///
/// Sessions are namespaced per environment so signing in to staging never
/// hands a token to production, and signing out of one leaves the other alone.
/// Tokens are never written to preferences, to Firestore, or to any log.
class FlowFinCredentialStoreService extends GetxService {
  FlowFinCredentialStoreService({SecureKeyValueStore? secureStore})
    : _secureStore = secureStore ?? FlutterSecureKeyValueStore();

  final SecureKeyValueStore _secureStore;

  Future<FlowFinSession?> readSession(FlowFinEnvironment environment) async {
    final raw = await _secureStore.read(key: _sessionKey(environment));
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final session = FlowFinSession.fromJson(decoded.cast<String, Object?>());
      if (session.accessToken.isEmpty || session.refreshToken.isEmpty) {
        return null;
      }
      return session;
    } on FormatException {
      // A corrupt entry is worth dropping rather than blocking sign-in.
      await deleteSession(environment);
      return null;
    }
  }

  Future<void> saveSession(
    FlowFinEnvironment environment,
    FlowFinSession session,
  ) {
    return _secureStore.write(
      key: _sessionKey(environment),
      value: jsonEncode(session.toJson()),
    );
  }

  Future<void> deleteSession(FlowFinEnvironment environment) {
    return _secureStore.delete(key: _sessionKey(environment));
  }

  Future<bool> hasSession(FlowFinEnvironment environment) async {
    return await readSession(environment) != null;
  }

  static String _sessionKey(FlowFinEnvironment environment) {
    return 'flowfin.session.${environment.id}';
  }
}
