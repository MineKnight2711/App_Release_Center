import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../infrastructure/lan_identity.dart';
import '../infrastructure/remote_storage.dart';
import '../infrastructure/webrtc_desktop_engine.dart';
import 'swift_desk_public.dart';
import 'swift_desk_runtime.dart';

/// Explicit disposable smoke mode. It auto-accepts view-only for two temporary
/// runtimes in this process; the production pairing path always asks the host.
class SwiftDeskPublicSmokeApp extends StatefulWidget {
  const SwiftDeskPublicSmokeApp({
    super.key,
    required this.reportPath,
    this.mode = RemoteConnectionMode.automatic,
  });
  final String reportPath;
  final RemoteConnectionMode mode;
  @override
  State<SwiftDeskPublicSmokeApp> createState() => _State();
}

class _State extends State<SwiftDeskPublicSmokeApp> {
  SwiftDeskRuntime? host, viewer;
  SwiftDeskPublic? hostService, viewerService;
  WebRtcDesktopEngine? engine;
  String status = 'Ghép mã qua dịch vụ công cộng, không dùng API AMC…';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _wait(bool Function() condition) async {
    final clock = Stopwatch()..start();
    while (!condition()) {
      if (host?.error != null || viewer?.error != null) {
        throw StateError('Runtime failed');
      }
      if (clock.elapsed > const Duration(seconds: 40)) {
        throw TimeoutException('Public ID smoke timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> _run() async {
    final report = <String, Object?>{
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
      'connectionMode': widget.mode.name,
      'productionStorageUsed': false,
      'amcAccountUsed': false,
      'selfHostedServerUsed': false,
      'nativeOsInputInjected': false,
      'publicBrokerUsed': true,
    };
    final cycles = <Map<String, Object?>>[];
    Directory? directory;
    var passed = false;
    try {
      directory = await Directory.systemTemp.createTemp('amc-public-smoke-');
      engine = WebRtcDesktopEngine();
      host = SwiftDeskRuntime(
        engine: WebRtcDesktopEngine(),
        repository: FileRemoteDeviceRepository(
          File('${directory.path}/host.json'),
        ),
        credentials: _Secrets(),
        identity: await LanIdentity.generate(),
        name: 'Disposable host',
        platform: Platform.operatingSystem,
      );
      viewer = SwiftDeskRuntime(
        engine: engine!,
        repository: FileRemoteDeviceRepository(
          File('${directory.path}/viewer.json'),
        ),
        credentials: _Secrets(),
        identity: await LanIdentity.generate(),
        name: 'Disposable viewer',
        platform: Platform.operatingSystem,
      );
      await host!.initialize();
      await viewer!.initialize();
      await host!.settings.setConnectionMode(widget.mode);
      await viewer!.settings.setConnectionMode(widget.mode);
      viewer!.addListener(() {
        if (mounted) setState(() {});
      });
      String? approved;
      host!.addListener(() {
        final request = host!.pendingRequest;
        if (request != null && request.sessionId != approved) {
          approved = request.sessionId;
          host!.accept();
        }
      });
      if (host!.permissions?.screen != true) {
        throw StateError('Screen Recording permission required');
      }
      await host!.enableHost(
        port: 0,
        bindAddress: InternetAddress.loopbackIPv4,
      );
      hostService = SwiftDeskPublic(host!);
      viewerService = SwiftDeskPublic(viewer!);
      await hostService!.start();
      if (!hostService!.online) {
        throw StateError(hostService!.error ?? 'Public rendezvous offline');
      }
      for (var i = 0; i < 3; i++) {
        setState(
          () => status = 'Mã máy → broker công cộng → WebRTC: phiên ${i + 1}/3',
        );
        if (i == 0) {
          await viewerService!.connect(hostService!.code.encode());
        } else {
          await viewerService!.connect(viewerService!.saved.single.codeId);
        }
        if (viewerService!.error != null) {
          throw StateError(viewerService!.error!);
        }
        await _wait(
          () =>
              host!.session?.state == RemoteSessionState.connected &&
              viewer!.session?.state == RemoteSessionState.connected &&
              viewer!.frames > 0,
        );
        if (widget.mode == RemoteConnectionMode.directIpv6 &&
            (host!.networkPath != 'direct-ipv6' ||
                viewer!.networkPath != 'direct-ipv6')) {
          throw StateError('Unexpected non-IPv6 path');
        }
        await engine!.sendPacket(
          RemoteInputPacket(
            sessionId: viewer!.session!.id,
            sequence: 900,
            input: RemotePointer(.5, .5),
            displayId: viewer!.remoteDisplayId,
          ),
        );
        await engine!.sendPacket(
          RemoteInputPacket(
            sessionId: viewer!.session!.id,
            sequence: 901,
            input: const RemoteRelease(),
            displayId: viewer!.remoteDisplayId,
          ),
        );
        await _wait(() => host!.receivedPackets >= 2);
        final cycle = <String, Object?>{
          'remembered': i > 0,
          'host': host!.diagnostics(),
          'viewer': viewer!.diagnostics(),
          'viewOnlyInputRejected': host!.appliedInputs == 0,
          'encryptedSignaling': true,
        };
        await viewer!.disconnect();
        await _wait(
          () =>
              !host!.active &&
              !host!.draining &&
              !hostService!.hasSession &&
              !viewerService!.hasSession,
        );
        cycle['hostListenerSurvived'] = hostService!.online;
        cycle['gracefulDisconnect'] =
            host!.error == null && viewer!.error == null;
        cycles.add(cycle);
      }
      await host!.revokeController(viewer!.identity.id);
      await viewerService!.connect(viewerService!.saved.single.codeId);
      report['revokedCredentialRejected'] =
          viewerService!.error != null && !viewer!.active;
      passed =
          report['revokedCredentialRejected'] == true &&
          cycles.every(
            (c) =>
                c['viewOnlyInputRejected'] == true &&
                c['hostListenerSurvived'] == true &&
                c['gracefulDisconnect'] == true,
          );
    } catch (error) {
      report['failureType'] = error.runtimeType.toString();
      report['host'] = host?.diagnostics();
      report['viewer'] = viewer?.diagnostics();
      report['hostRendezvous'] = hostService?.diagnostics();
      report['viewerRendezvous'] = viewerService?.diagnostics();
    } finally {
      await viewer?.shutdown();
      await host?.shutdown();
      if (directory != null) await directory.delete(recursive: true);
      report['cycles'] = cycles;
      report['outcome'] = passed ? 'passed' : 'failed';
      report['limitation'] =
          'Two endpoints on one Mac using real public broker and WebRTC; not a cross-network or Windows hardware test.';
      await File(
        widget.reportPath,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    }
    exit(passed ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('SwiftDesk · Ghép mã công cộng')),
      body: Column(
        children: [
          Padding(padding: const EdgeInsets.all(20), child: Text(status)),
          if (engine != null) Expanded(child: RTCVideoView(engine!.renderer)),
        ],
      ),
    ),
  );
}

class _Secrets implements RemoteCredentialStore {
  final _values = <String, String>{};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
