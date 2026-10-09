import 'dart:convert';
import 'dart:typed_data';

/// One field of a protobuf message, still pointing into the original buffer.
class ProtoField {
  const ProtoField._(this.number, this.wireType, this.varint, this._bytes);

  final int number;
  final int wireType;
  final int varint;
  final Uint8List? _bytes;

  bool get isLengthDelimited => wireType == 2;

  Uint8List get bytes => _bytes ?? Uint8List(0);

  String get string => utf8.decode(bytes, allowMalformed: true);

  ProtoMessage get message => ProtoMessage.parse(bytes);
}

/// The smallest protobuf reader that gets through `AndroidManifest.xml` and
/// `resources.pb` in an AAB — both are aapt2 protobuf, not binary XML.
///
/// It knows only the wire format; field numbers come from aapt2's
/// `Resources.proto` at the call sites. Unknown fields are kept and ignored,
/// so a newer aapt2 adding fields does not break reading.
class ProtoMessage {
  ProtoMessage._(this.fields);

  factory ProtoMessage.parse(Uint8List data) {
    final fields = <ProtoField>[];
    var cursor = 0;

    (int, int) readVarint(int start) {
      var result = 0;
      var shift = 0;
      var position = start;
      while (true) {
        if (position >= data.length) {
          throw const FormatException('Protobuf bị cắt giữa varint.');
        }
        final byte = data[position++];
        if (shift < 63) result |= (byte & 0x7f) << shift;
        if (byte < 0x80) return (result, position);
        shift += 7;
        if (shift > 70) throw const FormatException('Varint quá dài.');
      }
    }

    while (cursor < data.length) {
      final (key, afterKey) = readVarint(cursor);
      final number = key >> 3;
      final wireType = key & 0x7;
      switch (wireType) {
        case 0:
          final (value, next) = readVarint(afterKey);
          fields.add(ProtoField._(number, wireType, value, null));
          cursor = next;
        case 1:
          if (afterKey + 8 > data.length) {
            throw const FormatException('Protobuf bị cắt giữa fixed64.');
          }
          fields.add(
            ProtoField._(
              number,
              wireType,
              0,
              Uint8List.sublistView(data, afterKey, afterKey + 8),
            ),
          );
          cursor = afterKey + 8;
        case 2:
          final (length, start) = readVarint(afterKey);
          if (length < 0 || start + length > data.length) {
            throw const FormatException('Độ dài field protobuf vượt buffer.');
          }
          fields.add(
            ProtoField._(
              number,
              wireType,
              0,
              Uint8List.sublistView(data, start, start + length),
            ),
          );
          cursor = start + length;
        case 5:
          if (afterKey + 4 > data.length) {
            throw const FormatException('Protobuf bị cắt giữa fixed32.');
          }
          fields.add(
            ProtoField._(
              number,
              wireType,
              0,
              Uint8List.sublistView(data, afterKey, afterKey + 4),
            ),
          );
          cursor = afterKey + 4;
        default:
          throw FormatException('Wire type protobuf lạ: $wireType.');
      }
    }
    return ProtoMessage._(fields);
  }

  final List<ProtoField> fields;

  Iterable<ProtoField> all(int number) {
    return fields.where((field) => field.number == number);
  }

  ProtoField? first(int number) {
    for (final field in fields) {
      if (field.number == number) return field;
    }
    return null;
  }

  bool has(int number) => first(number) != null;

  String? string(int number) {
    final field = first(number);
    return field != null && field.isLengthDelimited ? field.string : null;
  }

  int? varint(int number) {
    final field = first(number);
    return field != null && field.wireType == 0 ? field.varint : null;
  }

  ProtoMessage? message(int number) {
    final field = first(number);
    return field != null && field.isLengthDelimited ? field.message : null;
  }

  Iterable<ProtoMessage> messages(int number) {
    return all(
      number,
    ).where((field) => field.isLengthDelimited).map((field) => field.message);
  }
}
