import 'package:app_management_center/app/models/app_lock.dart';
import 'package:app_management_center/app/services/app_lock_service.dart';
import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_management_center/app/services/project_store_service.dart';
import 'package:app_management_center/app/services/remote_unlock_session_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<_Harness> _buildHarness({
  bool supported = true,
  bool enrolled = true,
  bool approves = true,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = await ProjectStoreService().init();
  final authenticator = _FakeAuthenticator(
    availability: BiometricAvailability(
      supported: supported,
      enrolled: enrolled,
    ),
    approves: approves,
  );
  final lock = await AppLockService(
    store: store,
    authenticator: authenticator,
  ).init();
  final secureStore = _MemorySecureKeyValueStore();
  final sessions = await RemoteUnlockSessionService(
    store: store,
    lock: lock,
    secureStore: secureStore,
  ).init();
  return _Harness(
    store: store,
    authenticator: authenticator,
    lock: lock,
    secureStore: secureStore,
    sessions: sessions,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);

  group('saving the Windows password', () {
    test('keeps it out of preferences and behind one prompt', () async {
      final harness = await _buildHarness();

      await harness.sessions.save(
        accountName: r'TOMMY\miste',
        desktopId: 'default',
        password: 'hunter2',
      );

      expect(harness.authenticator.reasons, [AppLockReason.saveUnlockSession]);
      expect(harness.secureStore.values.values, contains('hunter2'));
      final preferences = await SharedPreferences.getInstance();
      final stored = preferences.getString('remote_unlock_session') ?? '';
      expect(
        stored,
        isNot(contains('hunter2')),
        reason: 'preferences are a plain file on disk',
      );
      expect(stored, contains(r'TOMMY\\miste'));
    });

    test('is refused when nothing is enrolled to prompt with', () async {
      final harness = await _buildHarness(enrolled: false);

      await expectLater(
        harness.sessions.save(
          accountName: r'TOMMY\miste',
          desktopId: 'default',
          password: 'hunter2',
        ),
        throwsA(isA<RemoteUnlockSessionException>()),
      );
      expect(harness.secureStore.values, isEmpty);
      expect(harness.sessions.session.value.exists, isFalse);
    });

    test('is refused when the prompt is declined', () async {
      final harness = await _buildHarness(approves: false);

      await expectLater(
        harness.sessions.save(
          accountName: r'TOMMY\miste',
          desktopId: 'default',
          password: 'hunter2',
        ),
        throwsA(isA<RemoteUnlockSessionException>()),
      );
      expect(harness.secureStore.values, isEmpty);
    });
  });

  group('reading it back', () {
    test('prompts every time, never on a grace period', () async {
      final harness = await _buildHarness();
      await harness.sessions.save(
        accountName: r'TOMMY\miste',
        desktopId: 'default',
        password: 'hunter2',
      );
      harness.authenticator.reasons.clear();

      for (var attempt = 0; attempt < 3; attempt++) {
        expect(
          await harness.sessions.readPassword(
            accountName: r'TOMMY\miste',
            desktopId: 'default',
          ),
          'hunter2',
        );
      }

      expect(harness.authenticator.reasons, [
        AppLockReason.unlockWindows,
        AppLockReason.unlockWindows,
        AppLockReason.unlockWindows,
      ]);
    });

    test('is matched case-insensitively on the account name', () async {
      final harness = await _buildHarness();
      await harness.sessions.save(
        accountName: r'TOMMY\miste',
        desktopId: 'default',
        password: 'hunter2',
      );

      expect(
        await harness.sessions.readPassword(
          accountName: r'tommy\MISTE',
          desktopId: 'default',
        ),
        'hunter2',
      );
    });

    test('refuses a different account without prompting', () async {
      final harness = await _buildHarness();
      await harness.sessions.save(
        accountName: r'TOMMY\miste',
        desktopId: 'default',
        password: 'hunter2',
      );
      harness.authenticator.reasons.clear();

      expect(
        await harness.sessions.readPassword(
          accountName: r'TOMMY\someone-else',
          desktopId: 'default',
        ),
        isNull,
      );
      expect(
        harness.authenticator.reasons,
        isEmpty,
        reason: 'a password for another account is not this account\'s to send',
      );
    });

    test('refuses a different desktop', () async {
      final harness = await _buildHarness();
      await harness.sessions.save(
        accountName: r'TOMMY\miste',
        desktopId: 'default',
        password: 'hunter2',
      );

      expect(
        await harness.sessions.readPassword(
          accountName: r'TOMMY\miste',
          desktopId: 'other-machine',
        ),
        isNull,
      );
    });

    test('hands back nothing when the prompt is declined', () async {
      final harness = await _buildHarness();
      await harness.sessions.save(
        accountName: r'TOMMY\miste',
        desktopId: 'default',
        password: 'hunter2',
      );
      harness.authenticator.approves = false;

      expect(
        await harness.sessions.readPassword(
          accountName: r'TOMMY\miste',
          desktopId: 'default',
        ),
        isNull,
      );
      expect(
        harness.sessions.session.value.exists,
        isTrue,
        reason: 'a declined prompt is not a reason to drop the saved password',
      );
    });
  });

  test('forgetting clears both the secret and its marker', () async {
    final harness = await _buildHarness();
    await harness.sessions.save(
      accountName: r'TOMMY\miste',
      desktopId: 'default',
      password: 'hunter2',
    );

    await harness.sessions.forget();

    expect(harness.secureStore.values, isEmpty);
    expect(harness.sessions.session.value.exists, isFalse);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('remote_unlock_session'), isNull);
  });

  test('a marker whose secret is gone is dropped on startup', () async {
    final harness = await _buildHarness();
    await harness.sessions.save(
      accountName: r'TOMMY\miste',
      desktopId: 'default',
      password: 'hunter2',
    );
    // What a cleared keystore leaves behind: the marker, and nothing else.
    harness.secureStore.values.clear();

    final reopened = await RemoteUnlockSessionService(
      store: harness.store,
      lock: harness.lock,
      secureStore: harness.secureStore,
    ).init();

    expect(reopened.session.value.exists, isFalse);
  });
}

class _Harness {
  _Harness({
    required this.store,
    required this.authenticator,
    required this.lock,
    required this.secureStore,
    required this.sessions,
  });

  final ProjectStoreService store;
  final _FakeAuthenticator authenticator;
  final AppLockService lock;
  final _MemorySecureKeyValueStore secureStore;
  final RemoteUnlockSessionService sessions;
}

class _FakeAuthenticator implements BiometricAuthenticator {
  _FakeAuthenticator({
    required BiometricAvailability availability,
    required this.approves,
  }) : _availability = availability;

  final BiometricAvailability _availability;
  bool approves;
  final reasons = <AppLockReason>[];

  @override
  Future<BiometricAvailability> availability() async => _availability;

  @override
  Future<bool> authenticate(String reason) async {
    reasons.add(
      AppLockReason.values.firstWhere((value) => value.prompt == reason),
    );
    return approves;
  }
}

class _MemorySecureKeyValueStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}
