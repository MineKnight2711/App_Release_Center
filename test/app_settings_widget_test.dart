import 'package:app_management_center/app/services/app_settings_service.dart';
import 'package:app_management_center/app/services/theme_service.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'package:app_management_center/app/views/app_display_scale.dart';
import 'package:app_management_center/app/views/app_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppSettingsService settings;
  late ThemeService theme;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettingsService().init();
    theme = await ThemeService().init();
    Get.put(settings);
    Get.put(theme);
  });
  tearDown(() {
    Get.reset();
    AppCyberTheme.activate(AppThemeChoice.console);
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    Widget? child,
    ValueChanged<MediaQueryData>? onMedia,
  }) async {
    await tester.pumpWidget(
      GetMaterialApp(
        theme: theme.themeData,
        builder: (context, child) => AppDisplayScale(
          settings: settings,
          child: Builder(
            builder: (context) {
              onMedia?.call(MediaQuery.of(context));
              return child!;
            },
          ),
        ),
        home: Scaffold(
          appBar: AppBar(actions: const [AppSettingsButton()]),
          body: child ?? const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'settings stay open through theme, font and widget size changes',
    (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byKey(const Key('open-app-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-theme-defaultTheme')));
      await tester.pumpAndSettle();
      expect(theme.choice.value, AppThemeChoice.defaultTheme);
      expect(find.byType(AppSettingsDialog), findsOneWidget);
      await tester.tap(find.byKey(const Key('font-scale-increase')));
      await tester.pumpAndSettle();
      expect(settings.fontScale.value, 1.05);
      await tester.tap(find.byKey(const Key('interface-scale-increase')));
      await tester.pumpAndSettle();
      expect(settings.interfaceScale.value, 1.05);
      final reset = find.byKey(const Key('reset-display-settings'));
      await tester.ensureVisible(reset);
      await tester.pumpAndSettle();
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(settings.fontScale.value, 1);
      expect(settings.interfaceScale.value, 1);
      expect(theme.choice.value, AppThemeChoice.defaultTheme);
      await tester.tap(find.byTooltip('Đóng'));
      await tester.pumpAndSettle();
      expect(find.byType(AppSettingsDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final zoom in [0.8, 1.4]) {
    testWidgets(
      'small screen settings scroll and close at $zoom zoom with maximum font',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(() async {
          await settings.setInterfaceScale(zoom);
          await settings.setFontScale(AppSettingsService.maxFontScale);
        });
        await pumpApp(tester);
        await tester.tap(find.byKey(const Key('open-app-settings')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const Key('reset-display-settings')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Đóng'));
        await tester.pumpAndSettle();
        expect(find.byType(AppSettingsDialog), findsNothing);
      },
    );
  }

  testWidgets(
    'zoom updates logical layout, insets and hit testing without losing state',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 28);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 14);
      tester.view.viewInsets = const FakeViewPadding(bottom: 84);
      tester.view.systemGestureInsets = const FakeViewPadding(left: 14);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.view.resetSystemGestureInsets);
      var taps = 0;
      MediaQueryData? observedMedia;
      await pumpApp(
        tester,
        onMedia: (media) => observedMedia = media,
        child: Builder(
          builder: (context) {
            return Center(
              child: SizedBox(
                key: const Key('scaled-widget'),
                width: 100,
                height: 40,
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('Tap'),
                ),
              ),
            );
          },
        ),
      );
      await tester.runAsync(() async {
        await settings.setInterfaceScale(1.4);
        await settings.setFontScale(1.3);
      });
      await tester.pumpAndSettle();
      expect(observedMedia!.size.width, closeTo(800 / 1.4, 0.001));
      expect(observedMedia!.padding.top, closeTo(20, 0.001));
      expect(observedMedia!.viewPadding.bottom, closeTo(10, 0.001));
      expect(observedMedia!.viewInsets.bottom, closeTo(60, 0.001));
      expect(observedMedia!.systemGestureInsets.left, closeTo(10, 0.001));
      expect(observedMedia!.textScaler.scale(10), closeTo(13, 0.001));
      final widgetRect = tester.getRect(find.byKey(const Key('scaled-widget')));
      expect(widgetRect.width, closeTo(140, 0.001));
      await tester.tapAt(widgetRect.center);
      expect(taps, 1);
      await tester.runAsync(settings.resetDisplay);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tap'));
      expect(taps, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
