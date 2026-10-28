import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:amc_remote_core/amc_remote_core.dart';
import '../../../services/ch_play_credential_store_service.dart';

class AmcRemoteCredentials implements RemoteCredentialStore {
  AmcRemoteCredentials({SecureKeyValueStore? store})
    : _store = store ?? SecureKeyValueStore.platform();
  final SecureKeyValueStore _store;
  String _key(String key) => 'swift_desk.v1.$key';
  @override
  Future<String?> read(String key) => _store.read(key: _key(key));
  @override
  Future<void> write(String key, String value) =>
      _store.write(key: _key(key), value: value);
  @override
  Future<void> delete(String key) => _store.delete(key: _key(key));
}

/// One app-owned writer. No raw credentials or old SwiftDesk config are ever
/// serialized here; corrupt files fail visibly rather than resetting trust.
class FileRemoteDeviceRepository implements RemoteDeviceRepository {
  FileRemoteDeviceRepository(this.file);
  final File file;
  bool _loaded = false;
  final _devices = <String, RemoteDevice>{};
  final _controllers = <String, TrustedRemoteController>{};
  final _history = <RemoteSessionRecord>[];
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        await _load();
        result.complete(await operation());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<void> _load() async {
    if (_loaded) return;
    if (await file.exists()) {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (json['version'] != 1) {
        throw const FormatException('Sai phiên bản dữ liệu SwiftDesk.');
      }
      final devices = (json['devices'] as List)
          .map((v) => RemoteDevice.fromJson(v as Map<String, dynamic>))
          .toList();
      final controllers = (json['controllers'] as List)
          .map(
            (v) => TrustedRemoteController.fromJson(v as Map<String, dynamic>),
          )
          .toList();
      _devices.addEntries(devices.map((v) => MapEntry(v.endpoint.deviceId, v)));
      _controllers.addEntries(controllers.map((v) => MapEntry(v.id, v)));
      _history.addAll(
        ((json['history'] as List?) ?? [])
            .map((v) => RemoteSessionRecord.fromJson(v as Map<String, dynamic>))
            .take(50),
      );
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'version': 1,
        'devices': _devices.values.map((v) => v.toJson()).toList(),
        'controllers': _controllers.values.map((v) => v.toJson()).toList(),
        'history': _history.map((v) => v.toJson()).toList(),
      }),
      flush: true,
    );
    await temp.rename(file.path);
  }

  @override
  Future<List<RemoteDevice>> devices() =>
      _serial(() async => List.unmodifiable(_devices.values));
  @override
  Future<List<TrustedRemoteController>> controllers() =>
      _serial(() async => List.unmodifiable(_controllers.values));
  @override
  Future<void> saveDevice(RemoteDevice device) => _serial(() async {
    final old = _devices[device.endpoint.deviceId];
    _devices[device.endpoint.deviceId] = device;
    try {
      await _persist();
    } catch (_) {
      if (old == null) {
        _devices.remove(device.endpoint.deviceId);
      } else {
        _devices[device.endpoint.deviceId] = old;
      }
      rethrow;
    }
  });
  @override
  Future<void> removeDevice(String id) => _serial(() async {
    final old = _devices.remove(id);
    try {
      await _persist();
    } catch (_) {
      if (old != null) _devices[id] = old;
      rethrow;
    }
  });
  @override
  Future<void> saveController(TrustedRemoteController controller) =>
      _serial(() async {
        final old = _controllers[controller.id];
        _controllers[controller.id] = controller;
        try {
          await _persist();
        } catch (_) {
          if (old == null) {
            _controllers.remove(controller.id);
          } else {
            _controllers[controller.id] = old;
          }
          rethrow;
        }
      });
  @override
  Future<void> removeController(String id) => _serial(() async {
    final old = _controllers.remove(id);
    try {
      await _persist();
    } catch (_) {
      if (old != null) _controllers[id] = old;
      rethrow;
    }
  });
  @override
  Future<List<RemoteSessionRecord>> history() =>
      _serial(() async => List.unmodifiable(_history));
  @override
  Future<void> appendHistory(RemoteSessionRecord record) => _serial(() async {
    final old = List<RemoteSessionRecord>.of(_history);
    _history.removeWhere((v) => v.sessionId == record.sessionId);
    _history.insert(0, record);
    if (_history.length > 50) _history.removeRange(50, _history.length);
    try {
      await _persist();
    } catch (_) {
      _history
        ..clear()
        ..addAll(old);
      rethrow;
    }
  });
}
