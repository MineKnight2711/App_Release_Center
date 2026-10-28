import 'dart:convert';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SwiftDeskSettings {
  SwiftDeskSettings([this.preferences]);
  final SharedPreferences? preferences;
  final _memory = <String, Object>{};
  RemoteConnectionMode get connectionMode {
    final saved = text('connectionMode');
    if (saved != null) {
      try {
        return parseRemoteConnectionMode(saved);
      } on FormatException {
        /* older/future value */
      }
    }
    return flag('forceRelay')
        ? RemoteConnectionMode.relay
        : RemoteConnectionMode.automatic;
  }

  Future<void> setConnectionMode(RemoteConnectionMode mode) =>
      setText('connectionMode', mode.name);
  bool flag(String key) =>
      (preferences?.getBool('swift_desk.$key') ?? _memory[key]) == true;
  int get port =>
      preferences?.getInt('swift_desk.port') ?? _memory['port'] as int? ?? 9877;
  String? text(String key) =>
      preferences?.getString('swift_desk.$key') ?? _memory[key] as String?;
  Future<void> setFlag(String key, bool value) async {
    if (preferences != null &&
        !await preferences!.setBool('swift_desk.$key', value)) {
      throw StateError('Không lưu được cài đặt.');
    }
    _memory[key] = value;
  }

  Future<void> setText(String key, String value) async {
    if (preferences != null &&
        !await preferences!.setString('swift_desk.$key', value)) {
      throw StateError('Không lưu được metadata.');
    }
    _memory[key] = value;
  }

  Future<void> setPort(int value) async {
    if (value < 1 || value > 65535) {
      throw const FormatException('Cổng phải từ 1 đến 65535.');
    }
    if (preferences != null &&
        !await preferences!.setInt('swift_desk.port', value)) {
      throw StateError('Không lưu được cổng.');
    }
    _memory['port'] = value;
  }

  List<Map<String, dynamic>> metadata(String key) {
    final data = text(key);
    if (data == null) return [];
    return (jsonDecode(data) as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
  }
}

/// Parses only a strict metadata allowlist. Old IDs are notes, never trusted
/// AMC identities; every imported machine must be paired again.
class LegacyRemoteImport {
  static List<Map<String, dynamic>> preview(String source) {
    if (utf8.encode(source).length > 1048576) {
      throw const FormatException('File import tối đa 1 MB.');
    }
    final root = jsonDecode(source);
    final devices = root is Map ? root['savedDevices'] : null;
    if (devices is! List || devices.length > 500) {
      throw const FormatException('Không đúng file cấu hình SwiftDesk.');
    }
    final result = <String, Map<String, dynamic>>{};
    for (final raw in devices) {
      if (raw is! Map) continue;
      final address = raw['ip'];
      final name = raw['name'];
      final port = raw['port'];
      if (address is! String ||
          address.isEmpty ||
          address.length > 128 ||
          name is! String ||
          name.isEmpty ||
          name.length > 80 ||
          RegExp(r'[\x00-\x1f]').hasMatch('$address$name') ||
          port is! int ||
          port < 1 ||
          port > 65535) {
        continue;
      }
      final key = '${address.toLowerCase()}:$port';
      result.putIfAbsent(
        key,
        () => {
          'key': key,
          'name': name,
          'address': address,
          'port': port,
          'platform':
              raw['platform'] is String &&
                  (raw['platform'] as String).length <= 20
              ? raw['platform']
              : 'unknown',
          'needsPairing': true,
        },
      );
    }
    return result.values.toList();
  }

  static Future<int> apply(
    SwiftDeskSettings settings,
    List<Map<String, dynamic>> preview,
  ) async {
    final previous = settings.metadata('legacyDevices');
    final all = {for (final item in previous) item['key'] as String: item};
    final before = all.length;
    for (final item in preview) {
      all.putIfAbsent(item['key'] as String, () => item);
    }
    await settings.setText('legacyDevices', jsonEncode(all.values.toList()));
    return all.length - before;
  }
}
