import 'dart:async';

import 'package:amc_remote_platform/amc_remote_platform.dart';
import 'package:app_management_center/app/modules/swift_desk/services/swift_desk_probe.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Permissions extends AmcRemotePlatform {
  final entered = Completer<void>();
  Completer<RemotePlatformPermissions>? pending;
  int inputGrants = 0;

  @override
  Future<RemotePlatformPermissions> permissions({bool request = false}) {
    if (!entered.isCompleted) entered.complete();
    return pending?.future ??
        Future.value(
          const RemotePlatformPermissions(screen: false, input: false),
        );
  }

  @override
  Future<void> beginInput(String sessionId, String displayId) async {
    inputGrants++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const rtc = MethodChannel('FlutterWebRTC.Method');
  const texture = MethodChannel('FlutterWebRTC/Texture42');
  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(rtc, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'initialize':
            case 'videoRendererSetSrcObject':
            case 'videoRendererDispose':
              return null;
            case 'createVideoRenderer':
              return {'textureId': 42};
            default:
              throw StateError('Unexpected media operation: ${call.method}');
          }
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(texture, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(rtc, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(texture, null);
  });

  test(
    'input cannot be granted without a connected host and does not destroy the initialized engine',
    () async {
      final platform = _Permissions();
      final probe = SwiftDeskProbe(platform: platform);
      await probe.initialize();
      await probe.setInputEnabled(true);
      expect(platform.inputGrants, 0);
      expect(probe.inputEnabled, isFalse);
      expect(probe.error, contains('Chỉ host đã kết nối'));
      expect(probe.initialized, isTrue);
      expect(calls, isNot(contains('videoRendererDispose')));
      await probe.close();
      await probe.close();
      expect(
        calls.where((method) => method == 'videoRendererDispose'),
        hasLength(1),
      );
    },
  );

  test(
    'closing during permission lookup drains initialization and releases its texture once',
    () async {
      final platform = _Permissions()
        ..pending = Completer<RemotePlatformPermissions>();
      final probe = SwiftDeskProbe(platform: platform);
      var notifications = 0;
      probe.addListener(() => notifications++);
      final opening = probe.initialize();
      await platform.entered.future;
      final beforeClose = notifications;
      final closing = probe.close();
      platform.pending!.complete(
        const RemotePlatformPermissions(screen: false, input: false),
      );
      await opening;
      await closing;
      expect(probe.hasSession, isFalse);
      expect(probe.inputEnabled, isFalse);
      expect(notifications, beforeClose);
      expect(
        calls.where((method) => method == 'createVideoRenderer'),
        hasLength(1),
      );
      expect(
        calls.where((method) => method == 'videoRendererDispose'),
        hasLength(1),
      );
    },
  );

  test(
    'concurrent initialization has one owner and denied capture never opens a peer',
    () async {
      final platform = _Permissions()
        ..pending = Completer<RemotePlatformPermissions>();
      final probe = SwiftDeskProbe(platform: platform);
      final first = probe.initialize();
      await platform.entered.future;
      await probe.initialize();
      platform.pending!.complete(
        const RemotePlatformPermissions(screen: false, input: false),
      );
      await first;
      expect(probe.sources, isEmpty);
      expect(probe.hasSession, isFalse);
      expect(
        calls.where((method) => method == 'createVideoRenderer'),
        hasLength(1),
      );
      await probe.close();
    },
  );
}
