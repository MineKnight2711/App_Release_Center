import 'dart:io';

import 'package:app_management_center/app/modules/safe/controllers/safe_controller.dart';
import 'package:app_management_center/app/modules/safe/models/safe_item.dart';
import 'package:app_management_center/app/modules/safe/services/safe_vault.dart';
import 'package:app_management_center/app/modules/safe/views/safe_view.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _testKdf = SafeKdfParams(memoryKiB: 64, iterations: 1, parallelism: 1);
const _code = 'correct horse battery';

void main() {
  late Directory dir;
  late String clipboard;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('amc-safe-view');
    clipboard = '';
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  SafeController newSafe() => SafeController(
    vault: SafeVault(
      locate: () async => File(p.join(dir.path, 'amc-safe.vault')),
      kdfParams: _testKdf,
      deriveKey: deriveSafeKey,
    ),
    writeClipboard: (text) async => clipboard = text,
    readClipboard: () async => clipboard,
  );

  Future<void> pumpSafe(
    WidgetTester tester,
    SafeController safe, {
    Size size = const Size(1400, 900),
    AppThemeChoice theme = AppThemeChoice.console,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppCyberTheme.activate(theme);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppCyberTheme.themeData(theme),
        home: SafeView(controller: safe),
      ),
    );
    // Lets the real file check in load() finish.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }

  /// Steps fake time forward. The open safe's countdown ticks every second,
  /// so the tree never settles while it is open.
  Future<void> pumpFor(WidgetTester tester, Duration duration) async {
    const step = Duration(milliseconds: 100);
    for (var elapsed = Duration.zero; elapsed < duration; elapsed += step) {
      await tester.pump(step);
    }
  }

  /// Gives real disk and Argon2 work time to land, then lets the door
  /// animation run out.
  Future<void> settleIo(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await pumpFor(tester, const Duration(seconds: 2));
  }

  Future<SafeController> lockedSafeWith(
    WidgetTester tester,
    List<SafeItem Function(SafeController)> items,
  ) async {
    // Seeded by a controller of its own, made and used wholly in the real
    // zone: the vault queues its work on futures, and a queue begun in the
    // test's fake zone never advances inside runAsync.
    await tester.runAsync(() async {
      final seed = newSafe();
      await seed.load();
      await seed.create(_code, _code);
      for (final build in items) {
        await seed.put(build(seed));
      }
      await seed.lock();
      seed.dispose();
    });
    return newSafe();
  }

  testWidgets('a new safe is made at the door and opens onto an empty inside', (
    tester,
  ) async {
    final safe = newSafe();
    await pumpSafe(tester, safe);

    expect(find.text('TẠO KÉT'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('safe-code')), _code);
    await tester.enterText(
      find.byKey(const Key('safe-code-confirm')),
      'mismatch 123',
    );
    await tester.tap(find.byKey(const Key('safe-submit')));
    await tester.pump();
    expect(find.text('Hai lần nhập mã không khớp.'), findsOneWidget);
    await pumpFor(tester, const Duration(milliseconds: 600));

    await tester.enterText(find.byKey(const Key('safe-code-confirm')), _code);
    await tester.tap(find.byKey(const Key('safe-submit')));
    await settleIo(tester, () => safe.isOpen);

    expect(safe.isOpen, isTrue);
    expect(find.text('Két đang trống'), findsOneWidget);
    expect(find.byKey(const Key('safe-lock')), findsOneWidget);
    // The code is gone from the door's fields once the safe is open.
    expect(find.text(_code), findsNothing);

    await tester.tap(find.byKey(const Key('safe-lock')));
    await settleIo(tester, () => !safe.isOpen);
    expect(find.text('MỞ KÉT'), findsOneWidget);
    safe.dispose();
  });

  testWidgets('a wrong code is refused and the safe stays shut', (
    tester,
  ) async {
    final safe = await lockedSafeWith(tester, []);
    await pumpSafe(tester, safe);

    await tester.enterText(find.byKey(const Key('safe-code')), 'not the code');
    await tester.tap(find.byKey(const Key('safe-submit')));
    await settleIo(tester, () => safe.refusals > 0);

    expect(safe.isOpen, isFalse);
    expect(find.byKey(const Key('safe-door-message')), findsOneWidget);
    expect(find.text('Sai mã két.'), findsOneWidget);
    safe.dispose();
  });

  testWidgets('an opened box hides the secret until asked, and copies it', (
    tester,
  ) async {
    final safe = await lockedSafeWith(tester, [
      (safe) => safe
          .draft(SafeItemKind.password)
          .copyWith(title: 'GitHub', username: 'dat', secret: 'hunter2-secret'),
      (safe) => safe
          .draft(SafeItemKind.env)
          .copyWith(
            title: 'Prod env',
            secret: 'API_URL=https://api\nTOKEN=abc',
          ),
    ]);
    await pumpSafe(tester, safe);
    await tester.enterText(find.byKey(const Key('safe-code')), _code);
    await tester.tap(find.byKey(const Key('safe-submit')));
    await settleIo(tester, () => safe.isOpen);

    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('Prod env'), findsOneWidget);
    expect(find.text('hunter2-secret'), findsNothing);

    await tester.tap(find.text('GitHub'));
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(find.byKey(const Key('safe-detail-title')), findsOneWidget);
    expect(find.text('hunter2-secret'), findsNothing);

    final secretRow = find.byKey(const Key('safe-detail-secret'));
    await tester.tap(
      find.descendant(of: secretRow, matching: find.byTooltip('Hiện')),
    );
    await tester.pump();
    expect(find.text('hunter2-secret'), findsOneWidget);

    await tester.tap(
      find.descendant(of: secretRow, matching: find.byTooltip('Sao chép')),
    );
    await tester.pump();
    expect(clipboard, 'hunter2-secret');
    await pumpFor(tester, const Duration(seconds: 3));

    // Searching by an env key name finds the env box only.
    await tester.enterText(find.byKey(const Key('safe-search')), 'token');
    await tester.pump();
    expect(find.text('Prod env'), findsWidgets);
    expect(find.text('GitHub'), findsWidgets); // still open in the detail panel
    expect(safe.visibleItems.map((item) => item.title), ['Prod env']);

    await safe.lock();
    await pumpFor(tester, const Duration(seconds: 1));
    expect(clipboard, '');
    safe.dispose();
  });

  for (final (name, size) in [
    ('narrow', const Size(480, 820)),
    ('medium', const Size(900, 640)),
    ('wide', const Size(1600, 1000)),
  ]) {
    testWidgets('the door and the inside fit a $name window', (tester) async {
      final safe = await lockedSafeWith(tester, [
        for (final kind in SafeItemKind.values)
          (safe) => safe
              .draft(kind)
              .copyWith(
                title:
                    'A rather long title for a ${kind.label} box that goes on',
                username: 'someone@example.com',
                secret: kind == SafeItemKind.jsonKey
                    ? '{"client_email":"ci@x.iam"}'
                    : 'value=1',
                fileName: kind == SafeItemKind.file
                    ? 'upload-keystore.jks'
                    : '',
              ),
      ]);
      await pumpSafe(
        tester,
        safe,
        size: size,
        theme: AppThemeChoice.defaultTheme,
      );
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byKey(const Key('safe-code')), _code);
      await tester.tap(find.byKey(const Key('safe-submit')));
      await settleIo(tester, () => safe.isOpen);
      expect(tester.takeException(), isNull);
      expect(safe.isOpen, isTrue);

      await tester.tap(
        find.textContaining('A rather long title for a Env').first,
      );
      await pumpFor(tester, const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('safe-detail-title')), findsOneWidget);

      await safe.lock();
      await pumpFor(tester, const Duration(seconds: 1));
      safe.dispose();
    });
  }
}
