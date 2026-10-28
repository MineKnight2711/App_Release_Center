import 'package:amc_remote_platform/amc_remote_platform.dart';
import 'package:app_management_center/app/modules/swift_desk/services/swift_desk_probe.dart';
import 'package:app_management_center/app/modules/swift_desk/views/swift_desk_probe_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProbeWithoutPermissions extends SwiftDeskProbe {
  int starts = 0;
  int inputGrants = 0;
  bool wasClosed = false;

  @override
  Future<void> initialize() async {
    initialized = true;
    permissions = const RemotePlatformPermissions(screen: false, input: false);
    status = 'Cần cấp quyền ghi màn hình';
    notifyListeners();
  }

  @override
  Future<void> startLoopback({
    bool relayOnly = false,
    String turnUrl = '',
    String turnUser = '',
    String turnPassword = '',
  }) async {
    starts++;
  }

  @override
  Future<void> setInputEnabled(bool enabled) async {
    inputGrants++;
  }

  @override
  Future<void> close() async {
    wasClosed = true;
  }
}

void main() {
  testWidgets(
    'missing screen permission disables capture and never grants input automatically',
    (tester) async {
      final probe = _ProbeWithoutPermissions();
      await tester.pumpWidget(
        MaterialApp(home: SwiftDeskProbeView(probe: probe)),
      );
      await tester.pump();
      expect(find.text('Cần cấp quyền ghi màn hình'), findsOneWidget);
      final start = tester.widget<FilledButton>(
        find.byKey(const Key('swift-desk-loopback')),
      );
      expect(start.onPressed, isNull);
      expect(probe.starts, 0);
      expect(probe.inputGrants, 0);
      expect(probe.inputEnabled, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(probe.wasClosed, isTrue);
    },
  );
}
