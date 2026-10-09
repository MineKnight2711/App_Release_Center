import 'dart:io';

import 'package:app_management_center/app/modules/bundle_check/services/android_toolchain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('keystore_resolution_');
    Directory(p.join(root.path, 'android', 'app')).createSync(recursive: true);
  });
  tearDown(() => root.deleteSync(recursive: true));

  void configure(String path, [String gradle = '']) {
    File(p.join(root.path, 'android', 'key.properties')).writeAsStringSync(
      'storeFile=$path\nkeyAlias=upload\nstorePassword=test-only\n',
    );
    File(
      p.join(root.path, 'android', 'app', 'build.gradle'),
    ).writeAsStringSync(gradle);
  }

  String key(String relative) {
    final file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('fixture');
    return p.normalize(file.path);
  }

  test('custom Gradle helper resolves relative to Android root, like eMed', () {
    final expected = key('keystore/upload.jks');
    key('android/keystore/upload.jks');
    configure('../keystore/upload.jks', '''
      def resolveKeystoreFile = { rawPath ->
        def path = rawPath
        def candidate = new File(path)
        candidate.isAbsolute() ? candidate : rootProject.file(path)
      }
      storeFile releaseKeystoreFile
    ''');
    expect(readProjectKeystore(root.path)!.path, expected);
  });

  test('Flutter file() keeps module-relative paths', () {
    final expected = key('android/keys/upload.jks');
    key('keys/upload.jks');
    configure(
      '../keys/upload.jks',
      "storeFile file(keyProperties['storeFile'])",
    );
    expect(readProjectKeystore(root.path)!.path, expected);
  });

  test('Kotlin rootProject.file uses Android root', () {
    final expected = key('keys/upload.jks');
    configure('../keys/upload.jks');
    File(
      p.join(root.path, 'android', 'app', 'build.gradle.kts'),
    ).writeAsStringSync(
      'storeFile = rootProject.file(keyProperties["storeFile"] as String)',
    );
    expect(readProjectKeystore(root.path)!.path, expected);
  });

  test('unknown layout accepts only a unique existing configured path', () {
    final expected = key('custom/secrets/upload.jks');
    configure('custom/secrets/upload.jks');
    expect(readProjectKeystore(root.path)!.path, expected);
    key('android/custom/secrets/upload.jks');
    expect(
      () => readProjectKeystore(root.path),
      throwsA(isA<BundleToolException>()),
    );
  });

  test('absolute path outside project is preserved', () {
    final external = Directory.systemTemp.createTempSync('external_key_');
    try {
      final file = File(p.join(external.path, 'upload.jks'))
        ..writeAsStringSync('fixture');
      configure(file.path);
      expect(readProjectKeystore(root.path)!.path, p.normalize(file.path));
    } finally {
      external.deleteSync(recursive: true);
    }
  });

  test('explicit Gradle base never falls back to a different existing key', () {
    key('keys/upload.jks');
    configure(
      '../keys/upload.jks',
      "storeFile file(keyProperties['storeFile'])",
    );
    final found = readProjectKeystore(root.path)!;
    expect(found.path, p.join(root.path, 'android', 'keys', 'upload.jks'));
    expect(File(found.path).existsSync(), isFalse);
  });
}
