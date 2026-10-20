import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_management_center/app/modules/safe/controllers/safe_controller.dart';
import 'package:app_management_center/app/modules/safe/models/safe_item.dart';
import 'package:app_management_center/app/modules/safe/services/safe_vault.dart';
import 'package:app_management_center/app/modules/safe/services/safe_zip_packer.dart';
import 'package:app_management_center/app/modules/safe/views/safe_pack_dialog.dart';
import 'package:app_management_center/app/modules/safe/views/safe_view.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _code = 'correct horse battery';

void main() {
  late Directory dir;
  late String clipboard;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('amc-safe-pack');
    clipboard = '';
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

  /// An open safe holding two projects, made from the test's zone.
  Future<SafeController> openSafe(WidgetTester tester) async {
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
      writeClipboard: (text) async => clipboard = text,
      readClipboard: () async => clipboard,
    );
    unawaited(safe.load());
    await settle(tester, () => safe.stage == SafeStage.uncreated);
    unawaited(safe.create(_code, _code));
    await settle(tester, () => safe.isOpen);
    var saved = false;
    unawaited(
      safe
          .putAll([
            safe
                .draft(SafeItemKind.env)
                .copyWith(
                  title: '.env',
                  fileName: '.env',
                  project: 'ShopApp',
                  source: '/work/ShopApp/.env',
                  secret: 'API_KEY=shop-env-secret\n',
                ),
            safe
                .draft(SafeItemKind.file)
                .copyWith(
                  title: 'upload.jks',
                  fileName: 'upload.jks',
                  project: 'ShopApp',
                  source: '/work/ShopApp/android/app/upload.jks',
                  secret: base64Encode([1, 2, 3, 4, 5]),
                ),
            safe
                .draft(SafeItemKind.password)
                .copyWith(
                  title: 'Firebase console',
                  username: 'dev@shop.vn',
                  project: 'ShopApp',
                  secret: 'firebase-password',
                ),
            safe
                .draft(SafeItemKind.env)
                .copyWith(
                  title: '.env',
                  fileName: '.env',
                  project: 'web-admin',
                  secret: 'DB_PASSWORD=web-secret\n',
                ),
          ])
          .then((_) => saved = true),
    );
    await settle(tester, () => saved);
    return safe;
  }

  void sizeWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppCyberTheme.activate(AppThemeChoice.console);
  }

  testWidgets('packs the chosen keys of one project behind a password', (
    tester,
  ) async {
    sizeWindow(tester);
    String? copiedMessage;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedMessage = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final safe = await openSafe(tester);
    final target = p.join(dir.path, 'out', 'shop-keys');
    final written = <String, Uint8List>{};
    final revealed = <String>[];
    final io = SafePackIo(
      pickDestination: (suggested) async {
        expect(suggested, startsWith('ShopApp-keys-'));
        expect(suggested, endsWith('.zip'));
        return target;
      },
      encode: (entries, password, encryption) async =>
          encodeSafeZip(entries, password: password, encryption: encryption),
      write: (path, bytes) async => written[path] = bytes,
      reveal: (path) async => revealed.add(path),
    );

    SafePackResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppCyberTheme.themeData(AppThemeChoice.console),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async => result = await showSafePackDialog(
                  context,
                  safe,
                  project: 'ShopApp',
                  io: io,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    // ShopApp's three items, with where each lands in the zip.
    expect(find.text('Firebase console'), findsOneWidget);
    expect(find.text('→ ShopApp/secrets.txt'), findsOneWidget);
    expect(find.text('→ ShopApp/android/app/upload.jks'), findsOneWidget);
    expect(find.text('Đóng gói 3 mục…'), findsOneWidget);

    // Leave the keystore out.
    final jks = safe.items.singleWhere((item) => item.fileName == 'upload.jks');
    await tester.tap(find.byKey(Key('safe-pack-item-${jks.id}')));
    await tester.pump();
    expect(find.text('Đóng gói 2 mục…'), findsOneWidget);

    // No password yet.
    await tester.tap(find.byKey(const Key('safe-pack-submit')));
    await tester.pump();
    expect(find.byKey(const Key('safe-pack-error')), findsOneWidget);
    expect(written, isEmpty);

    await tester.ensureVisible(find.byKey(const Key('safe-pack-zipcrypto')));
    await tester.tap(find.byKey(const Key('safe-pack-zipcrypto')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('safe-pack-generate')));
    await tester.tap(find.byKey(const Key('safe-pack-generate')));
    await tester.pump();
    final password = tester
        .widget<TextField>(find.byKey(const Key('safe-pack-password')))
        .controller!
        .text;
    expect(validateSafeZipPassword(password, password), isNull);

    await tester.tap(find.byKey(const Key('safe-pack-submit')));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.byKey(const Key('safe-pack-done')), findsOneWidget);

    final path = '$target.zip';
    expect(written.keys, [path]);
    final archive = ZipDecoder().decodeBytes(
      Uint8List.fromList(written[path]!),
      password: password,
    );
    final names = archive.files.map((file) => file.name).toSet();
    expect(names, {
      'ShopApp/README.txt',
      'ShopApp/secrets.txt',
      'ShopApp/.env',
    });
    String text(String name) => utf8.decode(
      archive.files.singleWhere((file) => file.name == name).content
          as List<int>,
    );
    expect(text('ShopApp/.env'), 'API_KEY=shop-env-secret\n');
    expect(text('ShopApp/secrets.txt'), contains('firebase-password'));
    // web-admin stayed out.
    expect(names.any((name) => name.contains('web')), isFalse);

    await tester.tap(find.text('Sao chép lời nhắn gửi kèm'));
    await tester.pump();
    expect(copiedMessage, contains('shop-keys.zip'));
    expect(copiedMessage, contains('unzip'));
    expect(copiedMessage, isNot(contains(password)));

    await tester.tap(find.text('Sao chép mật khẩu'));
    await tester.pump();
    expect(clipboard, password);

    await tester.tap(find.text('Xong'));
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(result?.itemCount, 2);
    expect(result?.encryption, SafeZipEncryption.zipCrypto);

    await safe.lock();
    await pumpFor(tester, const Duration(seconds: 1));
    safe.dispose();
  });

  testWidgets('the pack button opens on the project being browsed', (
    tester,
  ) async {
    sizeWindow(tester);
    final safe = await openSafe(tester);
    safe.setFilter(const SafeFilterProject('web-admin'));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppCyberTheme.themeData(AppThemeChoice.console),
        home: SafeView(controller: safe),
      ),
    );
    await pumpFor(tester, const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('safe-pack')));
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(find.text('Đóng gói bộ keys'), findsOneWidget);
    expect(find.text('Đóng gói 1 mục…'), findsOneWidget);
    expect(find.text('→ web-admin/.env'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Locking the safe closes the dialog with it.
    await safe.lock();
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Đóng gói bộ keys'), findsNothing);
    safe.dispose();
  });
}
