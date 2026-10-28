import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../infrastructure/cloud_signaling.dart';
import '../infrastructure/lan_identity.dart';
import '../infrastructure/remote_storage.dart';
import '../infrastructure/webrtc_desktop_engine.dart';
import 'swift_desk_cloud.dart';
import 'swift_desk_runtime.dart';

/// Disposable local Worker integration only: no production account/storage,
/// no OS input grant, and no network destination other than 127.0.0.1.
class SwiftDeskCloudSmokeApp extends StatefulWidget {
  const SwiftDeskCloudSmokeApp({
    super.key,
    required this.api,
    required this.reportPath,
    this.mode = RemoteConnectionMode.automatic,
  });
  final Uri api;
  final String reportPath;
  final RemoteConnectionMode mode;
  @override
  State<SwiftDeskCloudSmokeApp> createState() => _State();
}

class _State extends State<SwiftDeskCloudSmokeApp> {
  SwiftDeskRuntime? host, viewer;
  WebRtcDesktopEngine? viewerEngine;
  String status = 'Kiểm tra Internet desktop với Worker cục bộ…';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _wait(bool Function() condition) async {
    final timer = Stopwatch()..start();
    while (!condition()) {
      if (timer.elapsed > const Duration(seconds: 35)) {
        throw TimeoutException('Cloud smoke timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<String> _account() async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        widget.api.resolve('/v1/auth/register'),
      );
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'email': '${remoteToken().toLowerCase()}@desktop-smoke.invalid',
          'displayName': 'Disposable desktop smoke',
          'passwordKey': base64Url
              .encode(sha256.convert(utf8.encode(remoteToken())).bytes)
              .replaceAll('=', ''),
        }),
      );
      final response = await request.close();
      final result =
          jsonDecode(await utf8.decoder.bind(response).join())
              as Map<String, dynamic>;
      if (response.statusCode != 201) {
        throw StateError('Local test account registration failed');
      }
      return result['token'] as String;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _run() async {
    final report = <String, Object?>{
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
      'platform': Platform.operatingSystem,
      'localWorkerOnly': true,
      'productionStorageUsed': false,
      'nativeOsInputInjected': false,
      'connectionMode': widget.mode.name,
    };
    final cycles = <Map<String, Object?>>[];
    Directory? temp;
    var passed = false;
    try {
      if (widget.api.scheme != 'http' || widget.api.host != '127.0.0.1') {
        throw StateError('Smoke only supports a local Worker');
      }
      temp = await Directory.systemTemp.createTemp('amc-cloud-smoke-');
      final hostToken = await _account(), viewerToken = await _account();
      viewerEngine = WebRtcDesktopEngine();
      host = SwiftDeskRuntime(
        engine: WebRtcDesktopEngine(),
        repository: FileRemoteDeviceRepository(File('${temp.path}/host.json')),
        credentials: _Secrets(),
        identity: await LanIdentity.generate(),
        name: 'Disposable host',
        platform: Platform.operatingSystem,
      );
      viewer = SwiftDeskRuntime(
        engine: viewerEngine!,
        repository: FileRemoteDeviceRepository(
          File('${temp.path}/viewer.json'),
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
      final hostCloud = SwiftDeskCloud(
        host!,
        DesktopCloudApi(
          widget.api,
          () async => hostToken,
          allowLocalTest: true,
        ),
      );
      final viewerCloud = SwiftDeskCloud(
        viewer!,
        DesktopCloudApi(
          widget.api,
          () async => viewerToken,
          allowLocalTest: true,
        ),
      );
      viewer!.addListener(() {
        if (mounted) setState(() {});
      });
      String? approved;
      host!.addListener(() {
        final request = host!.pendingRequest;
        if (request != null && approved != request.sessionId) {
          approved = request.sessionId;
          host!.accept();
        }
      });
      if (host!.permissions?.screen != true) {
        throw StateError(
          'Screen Recording permission is required for this local smoke',
        );
      }
      await host!.enableHost(
        port: 0,
        bindAddress: InternetAddress.loopbackIPv4,
      );
      await hostCloud.start();
      if (!hostCloud.online) {
        throw StateError(hostCloud.error ?? 'Local host listener failed');
      }
      final invitation = await hostCloud.invitation();
      if (invitation == null) throw StateError('Local invitation failed');
      for (var i = 0; i < 3; i++) {
        setState(
          () => status = 'Worker → signaling mã hóa → WebRTC: phiên ${i + 1}/3',
        );
        if (i == 0) {
          await viewerCloud.connectInvitation(invitation);
        } else {
          await viewerCloud.connectSaved(viewerCloud.saved.single);
        }
        if (viewerCloud.error != null) {
          throw StateError('Cloud admission failed');
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
          throw StateError('IPv6-only smoke selected an unexpected path');
        }
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
        final cycle = <String, Object?>{
          'host': host!.diagnostics(),
          'viewer': viewer!.diagnostics(),
          'remembered': i > 0,
          'encryptedSignaling': true,
          'viewOnlyInputRejected': host!.appliedInputs == 0,
        };
        await viewer!.disconnect();
        await _wait(() => !host!.active && !host!.draining);
        cycle['hostListenerSurvived'] = hostCloud.online && host!.hostEnabled;
        cycle['gracefulDisconnect'] = host!.error == null;
        cycles.add(cycle);
        if (cycle['hostListenerSurvived'] != true ||
            cycle['gracefulDisconnect'] != true) {
          throw StateError('Cloud cleanup invariant failed');
        }
      }
      await host!.revokeController(viewer!.identity.id);
      await viewerCloud.connectSaved(viewerCloud.saved.single);
      report['revokedCredentialRejected'] =
          viewerCloud.error != null && !viewer!.active;
      passed = report['revokedCredentialRejected'] == true;
    } catch (error) {
      report['failureType'] = error.runtimeType.toString();
      report['host'] = host?.diagnostics();
      report['viewer'] = viewer?.diagnostics();
    } finally {
      await viewer?.shutdown();
      await host?.shutdown();
      if (temp != null) await temp.delete(recursive: true);
      report['cycles'] = cycles;
      report['outcome'] = passed ? 'passed' : 'failed';
      report['limitation'] =
          'Two endpoints on one Mac and a local Cloudflare Worker. No Internet NAT/TURN or Windows hardware validation.';
      await File(
        widget.reportPath,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    }
    exit(passed ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('SwiftDesk · Worker local smoke')),
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
