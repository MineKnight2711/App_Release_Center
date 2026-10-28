import 'dart:async';
import 'dart:io';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/lan_host.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/lan_identity.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/remote_storage.dart';
import 'package:app_management_center/app/modules/swift_desk/services/swift_desk_runtime.dart';
import 'package:app_management_center/app/modules/swift_desk/views/swift_desk_view.dart';
import 'package:app_management_center/app/modules/swift_desk/widgets/swift_desk_status.dart';
import 'package:app_management_center/app/modules/swift_desk/widgets/remote_surface.dart';
import 'package:app_management_center/app/modules/swift_desk/widgets/swift_desk_extras.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/remote_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'swift_desk_fakes.dart';

void main() {
  late LanIdentity identity;
  late Directory directory;
  late SwiftDeskRuntime runtime;
  late FakeRemoteNative native;
  late _ModeSettings settings;
  setUpAll(() async {
    identity = await LanIdentity.generate();
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('amc-swiftdesk-widget-');
    native = FakeRemoteNative()
      ..screenAllowed = false
      ..inputAllowed = false;
    settings = _ModeSettings();
    runtime = SwiftDeskRuntime(
      engine: FakeRemoteEngine(),
      repository: FileRemoteDeviceRepository(
        File('${directory.path}/devices.json'),
      ),
      credentials: MemoryRemoteCredentials(),
      identity: identity,
      name: 'Máy thử AMC',
      platform: 'macos',
      native: native,
      settings: settings,
    );
    await runtime.initialize();
  });
  tearDown(() async {
    SwiftDeskRuntime.current.value = null;
    await runtime.shutdown();
    await directory.delete(recursive: true);
  });
  Future<void> show(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(1000, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: SwiftDeskView(runtime: runtime),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'Internet selector saves P2P IPv6 choice and is disabled during a session',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Widget extras() => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: SwiftDeskExtras(runtime: runtime)),
        ),
      );
      await tester.pumpWidget(extras());
      await tester.pump();
      final selector = find.byKey(const Key('swift-desk-connection-mode'));
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chỉ P2P IPv6 · Không qua TURN').last);
      await tester.pumpAndSettle();
      expect(runtime.settings.connectionMode, RemoteConnectionMode.directIpv6);
      expect(find.textContaining('Hai máy cần IPv6'), findsOneWidget);
      runtime.session = RemoteSession(
        id: '12345678-1234-1234-1234-123456789abc',
        peerId: '22345678-1234-1234-1234-123456789abc',
        peerName: 'Host',
        role: RemoteRole.viewer,
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      )..transition(RemoteSessionState.requesting);
      await tester.pumpWidget(extras());
      expect(
        tester.widget<DropdownButton<RemoteConnectionMode>>(selector).onChanged,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed save keeps the visible mode consistent with the mode that a connection will use',
    (tester) async {
      settings.refuseSave = true;
      tester.view.physicalSize = const Size(1000, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SwiftDeskExtras(runtime: runtime),
            ),
          ),
        ),
      );
      await tester.pump();
      final selector = find.byKey(const Key('swift-desk-connection-mode'));
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chỉ P2P IPv6 · Không qua TURN').last);
      await tester.pumpAndSettle();
      expect(settings.connectionMode, RemoteConnectionMode.automatic);
      expect(
        tester.widget<DropdownButton<RemoteConnectionMode>>(selector).value,
        RemoteConnectionMode.automatic,
      );
      expect(find.text('Không lưu được lựa chọn kết nối.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'viewer remains usable without capture permission; host is off and cannot start',
    (tester) async {
      await show(tester);
      final host = tester.widget<SwitchListTile>(
        find.byKey(const Key('swift-desk-host')),
      );
      expect(host.value, isFalse);
      expect(host.onChanged, isNull);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('swift-desk-connect')))
            .onPressed,
        isNotNull,
      );
      expect(native.begins, 0);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('swift-desk-connect')));
      await tester.pump();
      expect(find.textContaining('Mã ghép nối sai'), findsOneWidget);
    },
  );
  testWidgets(
    'approval defaults to view; unavailable native permission cannot be granted',
    (tester) async {
      final request = RemotePairRequest(
        sessionId: '12345678-1234-1234-1234-123456789abc',
        deviceId: '22345678-1234-1234-1234-123456789abc',
        name: 'Viewer',
        platform: 'windows',
        address: '192.168.1.7',
        availableScopes: RemoteScope.values.toSet(),
        remember: true,
        knownDevice: false,
      );
      runtime.pendingRequest = request;
      await show(tester);
      final input = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Cho phép chuột/phím'),
      );
      expect(input.value, isFalse);
      expect(input.onChanged, isNull);
      await tester.tap(find.text('Cho phép clipboard văn bản'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('swift-desk-accept')));
      await tester.pump();
      expect(await request.decision.future, {
        RemoteScope.view,
        RemoteScope.clipboard,
      });
      expect(native.begins, 0);
      expect(tester.takeException(), isNull);
      runtime.pendingRequest = null;
    },
  );
  testWidgets('global status exposes pending approval outside the module', (
    tester,
  ) async {
    final request = RemotePairRequest(
      sessionId: '12345678-1234-1234-1234-123456789abc',
      deviceId: '22345678-1234-1234-1234-123456789abc',
      name: 'Viewer',
      platform: 'windows',
      address: '192.168.1.7',
      availableScopes: RemoteScope.values.toSet(),
      remember: false,
      knownDevice: true,
    );
    runtime.pendingRequest = request;
    runtime.session =
        RemoteSession(
            id: request.sessionId,
            peerId: request.deviceId,
            peerName: request.name,
            role: RemoteRole.host,
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          )
          ..transition(RemoteSessionState.requesting)
          ..transition(RemoteSessionState.awaitingApproval);
    SwiftDeskRuntime.current.value = runtime;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: Text('Module khác của AMC')),
              SwiftDeskGlobalStatus(onOpen: () {}),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Viewer muốn kết nối'), findsOneWidget);
    await tester.tap(find.text('Cho xem màn hình'));
    await tester.pump();
    expect(await request.decision.future, {RemoteScope.view});
    expect(native.begins, 0);
  });
  testWidgets('layout remains readable in dark theme with enlarged text', (
    tester,
  ) async {
    await show(tester, brightness: Brightness.dark, scale: 1.4);
    expect(find.text('Thiết bị đã lưu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  Future<void> showSurface(
    WidgetTester tester, {
    bool clipboard = false,
  }) async {
    runtime.session =
        RemoteSession(
            id: '12345678-1234-1234-1234-123456789abc',
            peerId: '22345678-1234-1234-1234-123456789abc',
            peerName: 'Host',
            role: RemoteRole.viewer,
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          )
          ..transition(RemoteSessionState.requesting)
          ..transition(RemoteSessionState.awaitingApproval);
    runtime.session!.grant({
      RemoteScope.view,
      RemoteScope.input,
      if (clipboard) RemoteScope.clipboard,
    });
    runtime.session!
      ..transition(RemoteSessionState.negotiating)
      ..transition(RemoteSessionState.connected);
    runtime.remoteDisplayId = 'display-1';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteSurface(runtime: runtime, renderer: RTCVideoRenderer()),
        ),
      ),
    );
    await tester.tap(find.text('Bắt đầu điều khiển'));
    await tester.pump();
    expect(runtime.viewerControl, isTrue);
  }

  testWidgets(
    'switching away from AMC releases viewer control and held input',
    (tester) async {
      await showSurface(tester);
      final engine = runtime.engine as FakeRemoteEngine;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(runtime.viewerControl, isFalse);
      expect(engine.sentPackets.last.input, isA<RemoteRelease>());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'pending paste cannot resume after control was released and retaken',
    (tester) async {
      await showSurface(tester, clipboard: true);
      runtime.clipboardEnabled = true;
      await runtime.settings.setFlag('clipboardBeforePaste', true);
      final data = Completer<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') return data.future;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.tap(find.text('Bắt đầu điều khiển'));
      await tester.pump();
      data.complete({'text': 'old pending clipboard'});
      await tester.pump();
      await tester.pump();
      final engine = runtime.engine as FakeRemoteEngine;
      final packet = engine.sentPackets
          .where((p) => p.input is RemoteClipboard)
          .last;
      engine.emit(EngineEventKind.control, {
        'action': 'clipboard-applied',
        'sequence': packet.sequence,
      });
      await tester.pump();
      await tester.pump();
      expect(
        engine.sentPackets.where(
          (p) =>
              p.input is RemoteKey &&
              (p.input as RemoteKey).usage ==
                  PhysicalKeyboardKey.keyV.usbHidUsage &&
              (p.input as RemoteKey).down,
        ),
        isEmpty,
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('button cancels an older coalesced pointer move', (tester) async {
    await showSurface(tester);
    final engine = runtime.engine as FakeRemoteEngine;
    final video = find.byType(RTCVideoView);
    final center = tester.getCenter(video);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: center);
    await mouse.moveTo(center + const Offset(10, 10));
    await mouse.down(center + const Offset(40, 20));
    await tester.pump(const Duration(milliseconds: 20));
    final button = engine.sentPackets.indexWhere(
      (p) => p.input is RemoteButton,
    );
    expect(button, greaterThanOrEqualTo(0));
    expect(
      engine.sentPackets
          .skip(button + 1)
          .where((p) => p.input is RemotePointer),
      isEmpty,
    );
    await mouse.up();
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

class _ModeSettings extends SwiftDeskSettings {
  bool refuseSave = false;
  @override
  Future<void> setConnectionMode(RemoteConnectionMode mode) async {
    if (refuseSave) throw StateError('Không lưu được lựa chọn kết nối.');
    await super.setConnectionMode(mode);
  }
}
