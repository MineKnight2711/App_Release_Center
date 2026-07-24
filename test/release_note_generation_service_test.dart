import 'dart:io';

import 'package:app_release_center/app/models/release_project.dart';
import 'package:app_release_center/app/services/release_note_generation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('release note app name', () {
    test('parses literal AndroidManifest label', () {
      final label = parseAndroidManifestLabel('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application
      android:name=".App"
      android:label="Customer Portal" />
</manifest>
''');

      expect(label, 'Customer Portal');
    });

    test('resolves AndroidManifest app_name string resource', () async {
      final directory = await Directory.systemTemp.createTemp(
        'app_release_center_release_notes_',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });

      await File(
        p.join(
          directory.path,
          'android',
          'app',
          'src',
          'main',
          'AndroidManifest.xml',
        ),
      ).create(recursive: true);
      await File(
        p.join(
          directory.path,
          'android',
          'app',
          'src',
          'main',
          'AndroidManifest.xml',
        ),
      ).writeAsString('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application android:label="@string/app_name" />
</manifest>
''');

      await File(
        p.join(
          directory.path,
          'android',
          'app',
          'src',
          'main',
          'res',
          'values',
          'strings.xml',
        ),
      ).create(recursive: true);
      await File(
        p.join(
          directory.path,
          'android',
          'app',
          'src',
          'main',
          'res',
          'values',
          'strings.xml',
        ),
      ).writeAsString('''
<resources>
  <string name="app_name">VNeTrip &amp; Friends</string>
</resources>
''');

      final name = await readAndroidAppDisplayName(directory.path);

      expect(name, 'VNeTrip & Friends');
    });

    test(
      'falls back to project directory when Android label is absent',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'demo_release_notes_',
        );
        addTearDown(() async {
          if (directory.existsSync()) {
            await directory.delete(recursive: true);
          }
        });

        final name = await resolveReleaseNoteAppName(
          ReleaseProject(
            path: p.join(directory.path, 'my_android_app'),
            scripts: const [],
            fastlaneLanes: const [],
            hasFirebaseDeployTools: false,
            hasPlayReleaseTools: true,
          ),
        );

        expect(name, 'My Android App');
      },
    );
  });
}
