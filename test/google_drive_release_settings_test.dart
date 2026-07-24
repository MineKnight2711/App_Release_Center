import 'package:app_release_center/app/models/google_drive_release_settings.dart';
import 'package:app_release_center/app/services/project_store_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'defaults Drive fallback to disabled when settings are missing',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await ProjectStoreService().init();

      expect(store.googleDriveReleaseSettings.useDriveFallbackEnabled, isFalse);
      expect(
        store.googleDriveReleaseSettings.sendApkLinkToTelegramEnabled,
        isFalse,
      );
      expect(
        store.googleDriveReleaseSettings.includeReleaseNotesInTelegramLink,
        isFalse,
      );
      expect(store.googleDriveReleaseSettings.oauthClientId, isEmpty);
      expect(store.googleDriveReleaseSettings.folderId, isEmpty);
    },
  );

  test('persists Drive fallback settings', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await ProjectStoreService().init();

    await store.saveGoogleDriveReleaseSettings(
      const GoogleDriveReleaseSettings(
        useDriveFallbackEnabled: true,
        sendApkLinkToTelegramEnabled: true,
        includeReleaseNotesInTelegramLink: true,
        oauthClientId: 'client-id.apps.googleusercontent.com',
        folderId: 'folder-id',
      ),
    );

    expect(store.googleDriveReleaseSettings.useDriveFallbackEnabled, isTrue);
    expect(
      store.googleDriveReleaseSettings.sendApkLinkToTelegramEnabled,
      isTrue,
    );
    expect(
      store.googleDriveReleaseSettings.includeReleaseNotesInTelegramLink,
      isTrue,
    );
    expect(
      store.googleDriveReleaseSettings.oauthClientId,
      'client-id.apps.googleusercontent.com',
    );
    expect(store.googleDriveReleaseSettings.folderId, 'folder-id');
  });

  test('invalid legacy Drive settings fall back to safe defaults', () async {
    SharedPreferences.setMockInitialValues({
      'google_drive_release_settings': 'not-json',
    });
    final store = await ProjectStoreService().init();

    expect(store.googleDriveReleaseSettings.useDriveFallbackEnabled, isFalse);
    expect(
      store.googleDriveReleaseSettings.sendApkLinkToTelegramEnabled,
      isFalse,
    );
    expect(
      store.googleDriveReleaseSettings.includeReleaseNotesInTelegramLink,
      isFalse,
    );
    expect(store.googleDriveReleaseSettings.oauthClientId, isEmpty);
    expect(store.googleDriveReleaseSettings.folderId, isEmpty);
  });
}
