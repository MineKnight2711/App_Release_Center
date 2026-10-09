import 'dart:convert';
import 'dart:io';

import '../models/qa_models.dart';
import 'safe_process_runner.dart';

class DeviceDiscoveryService {
  const DeviceDiscoveryService([
    this._processRunner = const SafeProcessRunner(),
  ]);

  final SafeProcessRunner _processRunner;

  Future<List<DeviceInfo>> discover() async {
    final running = await _processRunner.start(
      suite: const QaSuite(
        id: 'device-discovery',
        name: 'Flutter Devices',
        executable: 'flutter',
        arguments: ['devices', '--machine'],
      ),
      workingDirectory: Directory.current.path,
    );
    final output = await running.output.toList();
    final exitCode = await running.exitCode;
    if (exitCode != 0) {
      throw StateError(output.join('\n'));
    }
    return parseDevices(
      output.where((line) => !line.startsWith('[stderr]')).join('\n'),
    ).where((device) {
      final platform = device.platform.toLowerCase();
      return platform.startsWith('android') || platform.startsWith('ios');
    }).toList();
  }

  List<DeviceInfo> parseDevices(String raw) {
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start < 0 || end < start) return const [];
    final items = jsonDecode(raw.substring(start, end + 1)) as List<dynamic>;
    return items
        .map((item) {
          final json = Map<String, dynamic>.from(item as Map);
          return DeviceInfo(
            id: json['id']?.toString() ?? 'unknown',
            name: json['name']?.toString() ?? 'Unknown device',
            platform: json['targetPlatform']?.toString() ?? 'unknown',
            category: json['category']?.toString() ?? 'unknown',
            isEmulator: json['emulator'] as bool? ?? false,
            platformVersion: json['sdk']?.toString(),
            ephemeral: json['ephemeral'] as bool? ?? false,
          );
        })
        .toList(growable: false);
  }
}
