import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../infrastructure/lan_identity.dart';
import '../infrastructure/remote_storage.dart';
import '../infrastructure/webrtc_desktop_engine.dart';
import 'swift_desk_runtime.dart';

/// Local, disposable two-endpoint integration probe. The only listener is
/// loopback. Approval grants view only; injected input is never enabled.
class SwiftDeskLanSmokeApp extends StatefulWidget {
  const SwiftDeskLanSmokeApp({super.key, required this.reportPath});
  final String reportPath;
  @override
  State<SwiftDeskLanSmokeApp> createState() => _SwiftDeskLanSmokeAppState();
}

class _SwiftDeskLanSmokeAppState extends State<SwiftDeskLanSmokeApp> {
  SwiftDeskRuntime? host, viewer;
  WebRtcDesktopEngine? viewerEngine;
  String status = 'Chuẩn bị kiểm tra LAN cục bộ…';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _wait(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final clock = Stopwatch()..start();
    while (!condition()) {
      if (clock.elapsed > timeout) {
        throw TimeoutException('Local LAN smoke condition timed out');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> _run() async {
    final report = <String, Object?>{
      'platform': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
      'loopbackOnly': true,
      'productionStorageUsed': false,
    };
    Directory? directory;
    var outcome = 'failed';
    final cycles = <Map<String, Object?>>[];
    try {
      directory = await Directory.systemTemp.createTemp('amc-swiftdesk-smoke-');
      final hostIdentity = await LanIdentity.generate();
      final viewerIdentity = await LanIdentity.generate();
      host = SwiftDeskRuntime(
        engine: WebRtcDesktopEngine(),
        repository: FileRemoteDeviceRepository(
          File('${directory.path}/host.json'),
        ),
        credentials: _MemorySecrets(),
        identity: hostIdentity,
        name: 'Local smoke host',
        platform: Platform.operatingSystem,
      );
      viewerEngine = WebRtcDesktopEngine();
      viewer = SwiftDeskRuntime(
        engine: viewerEngine!,
        repository: FileRemoteDeviceRepository(
          File('${directory.path}/viewer.json'),
        ),
        credentials: _MemorySecrets(),
        identity: viewerIdentity,
        name: 'Local smoke viewer',
        platform: Platform.operatingSystem,
      );
      await host!.initialize();
      await viewer!.initialize();
      viewer!.addListener(() {
        if (mounted) setState(() {});
      });
      String? approvedRequest;
      host!.addListener(() {
        final request = host!.pendingRequest;
        if (request != null && approvedRequest != request.sessionId) {
          approvedRequest = request.sessionId;
          host!.accept(); // Always view only, including remembered connections.
        }
      });
      if (host!.permissions?.screen != true || host!.displayId == null) {
        outcome = 'blocked';
        report['reason'] =
            'Screen Recording permission is not granted; no prompt was requested.';
      } else {
        await host!.enableHost(
          port: 0,
          bindAddress: InternetAddress.loopbackIPv4,
        );
        for (var cycle = 0; cycle < 3; cycle++) {
          setState(() => status = 'Kiểm tra phiên LAN ${cycle + 1}/3…');
          if (cycle == 0) {
            await viewer!.connectInvitation(
              host!.invitation('127.0.0.1').encode(),
            );
          } else {
            await viewer!.connectSaved(viewer!.devices.single);
          }
          await _wait(
            () =>
                viewer!.session?.state == RemoteSessionState.connected &&
                host!.session?.state == RemoteSessionState.connected,
          );
          await _wait(() => viewer!.frames > 0);
          await viewerEngine!.sendPacket(
            RemoteInputPacket(
              sessionId: viewer!.session!.id,
              sequence: 900,
              input: RemotePointer(.5, .5),
              displayId: viewer!.remoteDisplayId,
            ),
          );
          await viewerEngine!.sendPacket(
            RemoteInputPacket(
              sessionId: viewer!.session!.id,
              sequence: 901,
              input: const RemoteRelease(),
              displayId: viewer!.remoteDisplayId,
            ),
          );
          await _wait(() => host!.receivedPackets >= 2);
          var switched = false;
          if (cycle == 2) {
            await viewer!.changeDisplay(
              viewer!.remoteDisplayId!,
              RemoteQuality.low,
            );
            await _wait(
              () =>
                  viewer!.quality == RemoteQuality.low &&
                  host!.quality == RemoteQuality.low,
            );
            switched = true;
          }
          final result = <String, Object?>{
            'host': host!.diagnostics(),
            'viewer': viewer!.diagnostics(),
            'pointerAndReliableReceived': host!.receivedPackets >= 2,
            'viewOnlyInputRejected':
                host!.appliedInputs == 0 && !host!.allows(RemoteScope.input),
            'displayQualitySwitch': switched,
            'rememberedConnection': cycle > 0,
          };
          await viewer!.disconnect();
          await _wait(() => !host!.active && !host!.draining);
          result['hostListenerSurvived'] = host!.hostEnabled;
          result['nativeInputReleased'] =
              host!.diagnostics()['nativeInputActive'] == false;
          cycles.add(result);
          if (host!.error != null || result['viewOnlyInputRejected'] != true) {
            throw StateError('LAN smoke invariant failed');
          }
        }
        await host!.revokeController(viewerIdentity.id);
        await viewer!.connectSaved(viewer!.devices.single);
        await _wait(() => viewer!.session?.state == RemoteSessionState.failed);
        report['revokedCredentialRejected'] =
            host!.pendingRequest == null && host!.controllers.isEmpty;
        outcome = report['revokedCredentialRejected'] == true
            ? 'passed'
            : 'failed';
      }
    } catch (error) {
      report['failureType'] = error.runtimeType.toString();
      report['host'] = host?.diagnostics();
      report['viewer'] = viewer?.diagnostics();
    } finally {
      await viewer?.shutdown();
      await host?.shutdown();
      if (directory != null) await directory.delete(recursive: true);
      report['cycles'] = cycles;
      report['outcome'] = outcome;
      report['note'] =
          'Two runtimes with real pinned TLS, approval, WebRTC video and two data channels on one Mac. No OS input injected. Cross-machine Windows/macOS QA remains.';
      await File(
        widget.reportPath,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    }
    exit(outcome == 'failed' ? 1 : 0);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      appBar: AppBar(title: const Text('SwiftDesk · Kiểm tra LAN cục bộ')),
      body: Column(
        children: [
          Padding(padding: const EdgeInsets.all(20), child: Text(status)),
          if (viewerEngine != null)
            Expanded(child: RTCVideoView(viewerEngine!.renderer)),
        ],
      ),
    ),
  );
}

class _MemorySecrets implements RemoteCredentialStore {
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
