import 'dart:io';
import 'dart:typed_data';

import 'package:app_management_center/app/modules/safe/controllers/safe_controller.dart';
import 'package:app_management_center/app/modules/safe/services/safe_sounds.dart';
import 'package:app_management_center/app/modules/safe/services/safe_vault.dart';
import 'package:app_management_center/app/modules/safe/views/safe_view.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

const _code = 'correct horse battery';

class RecordingOutput implements SafeSoundOutput {
  final played = <SafeSound>[];
  int prepared = 0;
  bool failNext = false;

  @override
  Future<void> prepare() async => prepared++;

  @override
  Future<void> play(SafeSound sound) async {
    if (failNext) {
      failNext = false;
      throw StateError('no audio device');
    }
    played.add(sound);
  }
}

void main() {
  group('SafeSounds', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test(
      'is on by default, warms up, and remembers being turned off',
      () async {
        final output = RecordingOutput();
        final sounds = SafeSounds(output: output);
        await sounds.load();
        expect(sounds.enabled, isTrue);
        await pumpEventQueue();
        expect(output.prepared, 1);

        sounds.play(SafeSound.tick);
        await pumpEventQueue();
        expect(output.played, [SafeSound.tick]);

        await sounds.setEnabled(false);
        sounds.play(SafeSound.unlock);
        await pumpEventQueue();
        expect(output.played, [SafeSound.tick]);

        final again = SafeSounds(output: RecordingOutput());
        await again.load();
        expect(again.enabled, isFalse);
      },
    );

    test('goes quiet after the output fails once', () async {
      final output = RecordingOutput()..failNext = true;
      final sounds = SafeSounds(output: output);
      await sounds.load();
      sounds.play(SafeSound.tick);
      await pumpEventQueue();
      sounds.play(SafeSound.tick);
      await pumpEventQueue();
      expect(output.played, isEmpty);
    });
  });

  test('every sound ships as a 16-bit mono WAV asset', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/sounds/safe/'));
    for (final name in [
      'tick_1',
      'tick_2',
      'tick_3',
      ...[
        SafeSound.denied,
        SafeSound.unlock,
        SafeSound.lock,
      ].map((s) => s.name),
    ]) {
      final file = File('assets/sounds/safe/$name.wav');
      expect(file.existsSync(), isTrue, reason: name);
      final bytes = ByteData.sublistView(file.readAsBytesSync());
      expect(
        String.fromCharCodes(file.readAsBytesSync().sublist(0, 4)),
        'RIFF',
      );
      expect(bytes.getUint16(22, Endian.little), 1, reason: '$name channels');
      expect(bytes.getUint16(34, Endian.little), 16, reason: '$name bits');
      final seconds = bytes.getUint32(40, Endian.little) / 2 / 44100;
      expect(seconds, inInclusiveRange(0.03, 2.0), reason: name);
    }
  });

  group('in the safe', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('amc-safe-sounds');
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Future<void> pumpFor(WidgetTester tester, Duration duration) async {
      const step = Duration(milliseconds: 100);
      for (var elapsed = Duration.zero; elapsed < duration; elapsed += step) {
        await tester.pump(step);
      }
    }

    Future<void> settle(WidgetTester tester, bool Function() done) async {
      for (var i = 0; i < 150 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(done(), isTrue);
    }

    testWidgets('clicks while typing, buzzes on a wrong code, and plays the '
        'door opening and closing', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      AppCyberTheme.activate(AppThemeChoice.console);

      final safe = SafeController(
        vault: SafeVault(
          locate: () async => File(p.join(dir.path, 'safe.vault')),
          kdfParams: const SafeKdfParams(
            memoryKiB: 64,
            iterations: 1,
            parallelism: 1,
          ),
          deriveKey: deriveSafeKey,
        ),
        writeClipboard: (_) async {},
        readClipboard: () async => '',
      );
      final output = RecordingOutput();
      final sounds = SafeSounds(output: output);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppCyberTheme.themeData(AppThemeChoice.console),
          home: SafeView(controller: safe, sounds: sounds),
        ),
      );
      await settle(tester, () => safe.stage == SafeStage.uncreated);
      await tester.pump();

      // Set a code: one click per character in each field.
      await tester.enterText(find.byKey(const Key('safe-code')), 'abc');
      await tester.enterText(find.byKey(const Key('safe-code-confirm')), 'ab');
      await tester.pump();
      expect(output.played.where((s) => s == SafeSound.tick), hasLength(2));
      output.played.clear();

      await tester.enterText(find.byKey(const Key('safe-code')), _code);
      await tester.enterText(find.byKey(const Key('safe-code-confirm')), _code);
      output.played.clear();
      await tester.tap(find.byKey(const Key('safe-submit')));
      await settle(tester, () => safe.isOpen);
      await pumpFor(tester, const Duration(milliseconds: 200));
      // The fields are cleared quietly as the door opens.
      expect(output.played, [SafeSound.unlock]);
      await pumpFor(tester, const Duration(seconds: 2));

      output.played.clear();
      await tester.tap(find.byKey(const Key('safe-lock')));
      await settle(tester, () => !safe.isOpen);
      await pumpFor(tester, const Duration(milliseconds: 200));
      expect(output.played, [SafeSound.lock]);
      await pumpFor(tester, const Duration(seconds: 2));

      output.played.clear();
      await tester.enterText(find.byKey(const Key('safe-code')), 'wrong code');
      await tester.pump();
      output.played.clear();
      await tester.tap(find.byKey(const Key('safe-submit')));
      await settle(tester, () => safe.refusals > 0);
      await pumpFor(tester, const Duration(milliseconds: 600));
      // The buzz, and no click for the field being emptied.
      expect(output.played, [SafeSound.denied]);

      // Muted from the app bar: nothing more is heard.
      await tester.tap(find.byKey(const Key('safe-sounds')));
      await tester.pump();
      expect(sounds.enabled, isFalse);
      output.played.clear();
      await tester.enterText(find.byKey(const Key('safe-code')), 'abc');
      await tester.pump();
      expect(output.played, isEmpty);

      safe.dispose();
    });
  });
}
