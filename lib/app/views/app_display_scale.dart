import 'package:app_management_center/app/services/app_settings_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Wrap the navigator so pages, overlays and dialogs share the same scale.
class AppDisplayScale extends StatelessWidget {
  const AppDisplayScale({
    super.key,
    required this.settings,
    required this.child,
  });

  final AppSettingsService settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final zoom = settings.interfaceScale.value;
      final font = settings.fontScale.value;
      final media = MediaQuery.of(context);
      return LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest / zoom;
          return FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: MediaQuery(
                data: media.copyWith(
                  size: size,
                  devicePixelRatio: media.devicePixelRatio * zoom,
                  padding: media.padding / zoom,
                  viewPadding: media.viewPadding / zoom,
                  viewInsets: media.viewInsets / zoom,
                  systemGestureInsets: media.systemGestureInsets / zoom,
                  textScaler: _FontScaler(media.textScaler, font),
                ),
                child: child,
              ),
            ),
          );
        },
      );
    });
  }
}

/// Keep the platform's nonlinear accessibility scaling as well.
class _FontScaler extends TextScaler {
  const _FontScaler(this.platformScaler, this.factor);
  final TextScaler platformScaler;
  final double factor;

  @override
  double scale(double fontSize) => platformScaler.scale(fontSize) * factor;

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is _FontScaler &&
      other.platformScaler == platformScaler &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(platformScaler, factor);
}
