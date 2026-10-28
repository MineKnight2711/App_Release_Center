library;

import 'dart:convert';

export 'src/models.dart';
export 'src/session.dart';
export 'src/ports.dart';

/// Small, versioned input vocabulary used by the engine spike. Further input
/// types must be added explicitly; unknown messages never reach the OS.
sealed class RemoteInput {
  const RemoteInput();
  Map<String, Object> toJson();

  static RemoteInput fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'pointer':
        final x = json['x'];
        final y = json['y'];
        if (x is! num || y is! num) {
          throw const FormatException('Invalid pointer coordinates');
        }
        return RemotePointer(x.toDouble(), y.toDouble());
      case 'text':
        final text = json['text'];
        if (text is! String) throw const FormatException('Invalid text');
        return RemoteText(text);
      case 'button':
        if (json['button'] is! String ||
            json['down'] is! bool ||
            json['x'] is! num ||
            json['y'] is! num) {
          throw const FormatException('Invalid button');
        }
        return RemoteButton(
          button: json['button'] as String? ?? '',
          down: json['down'] == true,
          x: (json['x'] as num?)?.toDouble() ?? double.nan,
          y: (json['y'] as num?)?.toDouble() ?? double.nan,
        );
      case 'wheel':
        if (json['dx'] is! num || json['dy'] is! num) {
          throw const FormatException('Invalid wheel');
        }
        return RemoteWheel(
          (json['dx'] as num?)?.toDouble() ?? double.nan,
          (json['dy'] as num?)?.toDouble() ?? double.nan,
        );
      case 'key':
        if (json['down'] is! bool || json['usage'] is! int) {
          throw const FormatException('Invalid key');
        }
        return RemoteKey(json['usage'] as int, down: json['down'] as bool);
      case 'release':
        return const RemoteRelease();
      case 'clipboard':
        if (json['text'] is! String) {
          throw const FormatException('Invalid clipboard');
        }
        return RemoteClipboard(json['text'] as String);
      default:
        throw const FormatException('Unsupported input type');
    }
  }
}

final class RemoteButton extends RemoteInput {
  RemoteButton({
    required this.button,
    required this.down,
    required this.x,
    required this.y,
  }) {
    RemotePointer(x, y);
    if (!{'left', 'middle', 'right'}.contains(button)) {
      throw const FormatException('Invalid button');
    }
  }
  final String button;
  final bool down;
  final double x, y;
  @override
  Map<String, Object> toJson() => {
    'type': 'button',
    'button': button,
    'down': down,
    'x': x,
    'y': y,
  };
}

final class RemoteWheel extends RemoteInput {
  RemoteWheel(this.dx, this.dy) {
    if (!dx.isFinite || !dy.isFinite || dx.abs() > 2400 || dy.abs() > 2400) {
      throw const FormatException('Invalid wheel');
    }
  }
  final double dx, dy;
  @override
  Map<String, Object> toJson() => {'type': 'wheel', 'dx': dx, 'dy': dy};
}

final class RemoteKey extends RemoteInput {
  RemoteKey(this.usage, {required this.down}) {
    final key = usage & 0xffff;
    if (usage >> 16 != 7 ||
        !((key >= 4 && key <= 0x64 && key != 0x48) ||
            (key >= 0xe0 && key <= 0xe7))) {
      throw const FormatException('Unsupported physical key');
    }
  }
  final int usage;
  final bool down;
  @override
  Map<String, Object> toJson() => {'type': 'key', 'usage': usage, 'down': down};
}

final class RemoteRelease extends RemoteInput {
  const RemoteRelease();
  @override
  Map<String, Object> toJson() => {'type': 'release'};
}

final class RemoteClipboard extends RemoteInput {
  RemoteClipboard(this.text) {
    if (utf8.encode(text).length > 16384 || text.contains('\u0000')) {
      throw const FormatException('Clipboard text is too large');
    }
  }
  final String text;
  @override
  Map<String, Object> toJson() => {'type': 'clipboard', 'text': text};
}

final class RemotePointer extends RemoteInput {
  RemotePointer(this.x, this.y) {
    if (!x.isFinite || !y.isFinite || x < 0 || x > 1 || y < 0 || y > 1) {
      throw const FormatException('Pointer must be within the selected screen');
    }
  }
  final double x;
  final double y;

  @override
  Map<String, Object> toJson() => {'type': 'pointer', 'x': x, 'y': y};
}

final class RemoteText extends RemoteInput {
  RemoteText(this.text) {
    if (text.isEmpty || text.length > 1024 || text.contains('\u0000')) {
      throw const FormatException(
        'Text must contain 1–1024 non-NUL code units',
      );
    }
  }
  final String text;

  @override
  Map<String, Object> toJson() => {'type': 'text', 'text': text};
}

final class RemoteInputPacket {
  RemoteInputPacket({
    required this.sessionId,
    required this.sequence,
    required this.input,
    this.displayId,
  }) {
    if (sessionId.isEmpty || sessionId.length > 128 || sequence < 0) {
      throw const FormatException('Invalid input envelope');
    }
  }

  static const version = 1;
  final String sessionId;
  final int sequence;
  final RemoteInput input;
  final String? displayId;

  String encode() => jsonEncode({
    'version': version,
    'sessionId': sessionId,
    'sequence': sequence,
    'input': input.toJson(),
    if (displayId != null) 'displayId': displayId,
  });

  static RemoteInputPacket decode(String value) {
    if (value.length > 100000) throw const FormatException('Input too large');
    final data = jsonDecode(value);
    if (data is! Map<String, dynamic> ||
        data['version'] != version ||
        data['sessionId'] is! String ||
        data['sequence'] is! int ||
        data['input'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid input envelope');
    }
    if (data['displayId'] != null &&
        (data['displayId'] is! String ||
            (data['displayId'] as String).length > 128)) {
      throw const FormatException('Invalid display');
    }
    return RemoteInputPacket(
      sessionId: data['sessionId'] as String,
      sequence: data['sequence'] as int,
      input: RemoteInput.fromJson(data['input'] as Map<String, dynamic>),
      displayId: data['displayId'] as String?,
    );
  }
}

/// A fail-closed gate for the single reliable channel in the spike. It is not
/// authentication: production will supply the verified peer/session grant.
final class RemoteInputGate {
  RemoteInputGate({required this.sessionId, required this.expiresAt});

  final String sessionId;
  final DateTime expiresAt;
  bool _enabled = false;
  bool _closed = false;
  int _lastSequence = -1;
  int _lastPointer = -1;

  void setEnabled(bool value) {
    if (_closed && value) throw StateError('Session has ended');
    _enabled = value;
  }

  bool accept(RemoteInputPacket packet, {required DateTime now}) {
    if (_closed ||
        !_enabled ||
        !now.isBefore(expiresAt) ||
        packet.sessionId != sessionId) {
      return false;
    }
    if (packet.input is RemotePointer) {
      if (packet.sequence <= _lastPointer) return false;
      _lastPointer = packet.sequence;
    } else {
      if (packet.sequence <= _lastSequence) return false;
      _lastSequence = packet.sequence;
      if (packet.input is RemoteButton && packet.sequence > _lastPointer) {
        _lastPointer = packet.sequence;
      }
    }
    return true;
  }

  void close() {
    _closed = true;
    _enabled = false;
  }
}
