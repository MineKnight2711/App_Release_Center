import 'dart:io';

import 'package:app_management_center/app/services/app_build_stamp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The whole point of this stamp is telling a fresh build from an installed
/// one. Reading the wrong file makes them look identical, which is the failure
/// it was written to prevent: on Windows a Flutter release only relinks the
/// runner when native code changes, so the .exe keeps yesterday's date while
/// `data/app.so` beside it is new.
void main() {
  late Directory root;
  late File executable;

  setUp(() {
    root = Directory.systemTemp.createTempSync('amc-stamp-');
    executable = File(p.join(root.path, 'app.exe'))..writeAsStringSync('exe');
    Directory(p.join(root.path, 'data')).createSync();
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  DateTime setModified(File file, DateTime when) {
    file.setLastModifiedSync(when);
    return when;
  }

  test('prefers the Dart payload over a stale executable', () {
    final old = DateTime.now().subtract(const Duration(days: 2));
    setModified(executable, old);
    final payload = File(p.join(root.path, 'data', 'app.so'))
      ..writeAsStringSync('aot');
    final fresh = setModified(
      payload,
      DateTime.now().subtract(const Duration(minutes: 5)),
    );

    final stamp = AppBuildStamp(executablePath: executable.path).read();

    expect(stamp, isNotNull);
    expect(
      stamp!.difference(fresh).inSeconds.abs(),
      lessThan(2),
      reason: 'the exe date would have reported a two-day-old build',
    );
  });

  test('falls back to the debug kernel snapshot', () {
    setModified(executable, DateTime.now().subtract(const Duration(days: 3)));
    Directory(p.join(root.path, 'data', 'flutter_assets')).createSync();
    final kernel = File(
      p.join(root.path, 'data', 'flutter_assets', 'kernel_blob.bin'),
    )..writeAsStringSync('kernel');
    final fresh = setModified(
      kernel,
      DateTime.now().subtract(const Duration(minutes: 1)),
    );

    final stamp = AppBuildStamp(executablePath: executable.path).read();

    expect(stamp!.difference(fresh).inSeconds.abs(), lessThan(2));
  });

  test('uses the executable when no payload sits beside it', () {
    final when = setModified(
      executable,
      DateTime.now().subtract(const Duration(hours: 4)),
    );

    final stamp = AppBuildStamp(executablePath: executable.path).read();

    expect(stamp!.difference(when).inSeconds.abs(), lessThan(2));
  });

  test('reports nothing rather than guessing when the path is wrong', () {
    final stamp = AppBuildStamp(
      executablePath: p.join(root.path, 'missing', 'app.exe'),
    ).read();

    expect(stamp, isNull);
  });

  test('reads the real running build', () {
    // Proves the default path resolves to something on this machine, which a
    // test using only temp directories would never catch.
    expect(const AppBuildStamp().read(), isNotNull);
  });
}
