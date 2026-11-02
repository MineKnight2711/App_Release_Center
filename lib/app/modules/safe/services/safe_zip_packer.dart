import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/safe_item.dart';

/// How the zip is locked.
enum SafeZipEncryption {
  /// WinZip AES-256: strong, but neither Windows Explorer nor the macOS
  /// Finder opens it; the recipient needs 7-Zip, WinRAR, Keka or similar.
  aes256,

  /// Traditional PKWARE encryption: Windows Explorer and `unzip` on macOS
  /// open it with no extra app, at the price of a cipher with known
  /// weaknesses. Only worth it with a long password.
  zipCrypto,
}

const safeZipMinPasswordLength = 8;

/// Why [password] cannot lock a zip, or null when it can.
///
/// Only printable ASCII is allowed. Zip tools disagree on how to turn other
/// characters into bytes (UTF-8 in 7-Zip and Keka, the system code page in
/// Windows Explorer, one byte per UTF-16 unit in the archive package), so a
/// password with Vietnamese diacritics could lock a zip nobody can open.
String? validateSafeZipPassword(String password, String confirmation) {
  if (password.length < safeZipMinPasswordLength) {
    return 'Mật khẩu nén cần ít nhất $safeZipMinPasswordLength ký tự.';
  }
  if (password.codeUnits.any((unit) => unit < 0x20 || unit > 0x7E)) {
    return 'Mật khẩu nén chỉ dùng chữ không dấu, số và ký hiệu ASCII.';
  }
  if (password != confirmation) return 'Hai lần nhập mật khẩu không khớp.';
  return null;
}

class SafeZipEntry {
  const SafeZipEntry(this.path, this.bytes);

  /// Path inside the zip, `/`-separated.
  final String path;
  final Uint8List bytes;
}

/// What one item becomes in the kit, for the dialog's preview.
class SafeKitPlacement {
  const SafeKitPlacement(this.item, this.path);

  final SafeItem item;

  /// Path inside the project folder of the zip; [SafeProjectKit.secretsFile]
  /// for secrets written into the shared text file.
  final String path;
}

/// The files of one project's key kit, before they are zipped.
class SafeProjectKit {
  const SafeProjectKit({
    required this.folder,
    required this.placements,
    required this.entries,
  });

  static const secretsFile = 'secrets.txt';
  static const readmeFile = 'README.txt';

  /// The single top folder everything sits in.
  final String folder;
  final List<SafeKitPlacement> placements;
  final List<SafeZipEntry> entries;

  int get fileCount =>
      placements.where((placement) => placement.path != secretsFile).length;
  int get secretCount => placements.length - fileCount;

  /// Lays out [items] of [project]: files keep the path they had inside the
  /// project where it can be told from their source, so the recipient copies
  /// them straight into place; passwords, keys and notes that never were
  /// files go into one `secrets.txt`. A `README.txt` lists the contents and
  /// holds no secret. [includeSources] writes where each secret was found
  /// on this machine into `secrets.txt`; a share link leaves that out.
  factory SafeProjectKit.build({
    required String project,
    required List<SafeItem> items,
    DateTime? createdAt,
    bool includeSources = true,
  }) {
    final folder = zipSafeSegment(project.isEmpty ? 'keys' : project);
    final used = <String>{};
    final placements = <SafeKitPlacement>[];
    final files = <SafeZipEntry>[];
    final loose = <SafeItem>[];

    for (final item in items) {
      final bytes = _fileBytes(item);
      if (bytes == null) {
        loose.add(item);
        placements.add(SafeKitPlacement(item, secretsFile));
        continue;
      }
      final path = _unique(_pathFor(item, project), used);
      placements.add(SafeKitPlacement(item, path));
      files.add(SafeZipEntry('$folder/$path', bytes));
    }

    final when = createdAt ?? DateTime.now();
    final entries = <SafeZipEntry>[
      SafeZipEntry(
        '$folder/$readmeFile',
        _utf8(_readme(project, placements, when)),
      ),
      if (loose.isNotEmpty)
        SafeZipEntry(
          '$folder/$secretsFile',
          _utf8(_secrets(project, loose, when, includeSources)),
        ),
      ...files,
    ];
    return SafeProjectKit(
      folder: folder,
      placements: placements,
      entries: entries,
    );
  }

  /// The bytes an item is written as, or null when it belongs in the
  /// secrets file instead.
  static Uint8List? _fileBytes(SafeItem item) {
    switch (item.kind) {
      case SafeItemKind.file:
        return item.fileBytes;
      case SafeItemKind.env:
      case SafeItemKind.jsonKey:
        // Whole documents are files even when typed in by hand.
        return _utf8(item.secret);
      case SafeItemKind.apiKey:
      case SafeItemKind.note:
        // A private key read from a .p8 or .pem goes back out as that file.
        return item.fileName.isEmpty ? null : _utf8(item.secret);
      case SafeItemKind.password:
        return null;
    }
  }

  /// The item's path inside its project, from the path it was found at.
  static String _pathFor(SafeItem item, String project) {
    final source = item.source.replaceFirst(RegExp(r':\d+$'), '');
    if (source.isNotEmpty && project.isNotEmpty) {
      // A scan names a project after its folder, plus " (parent)" when two
      // folders share a name.
      final folderName = project.replaceFirst(RegExp(r' \([^)]*\)$'), '');
      final parts = source
          .split(RegExp(r'[\\/]'))
          .where((part) => part.isNotEmpty)
          .toList();
      final at = parts.lastIndexOf(folderName);
      if (at >= 0 && at < parts.length - 1) {
        return parts.sublist(at + 1).map(zipSafeSegment).join('/');
      }
    }
    if (item.fileName.isNotEmpty) return zipSafeSegment(item.fileName);
    final slug = zipSafeSegment(item.title);
    return switch (item.kind) {
      SafeItemKind.env =>
        slug.startsWith('.env') || slug.endsWith('.env') ? slug : '$slug.env',
      SafeItemKind.jsonKey =>
        slug.toLowerCase().endsWith('.json') ? slug : '$slug.json',
      _ => slug,
    };
  }

  static String _unique(String path, Set<String> used) {
    var candidate = path;
    var n = 2;
    while (!used.add(candidate.toLowerCase())) {
      final dot = path.lastIndexOf('.');
      final slash = path.lastIndexOf('/');
      candidate = dot > slash + 1
          ? '${path.substring(0, dot)} ($n)${path.substring(dot)}'
          : '$path ($n)';
      n++;
    }
    return candidate;
  }

  static String _readme(
    String project,
    List<SafeKitPlacement> placements,
    DateTime when,
  ) {
    final buffer = StringBuffer()
      ..writeln(
        'Bộ keys của dự án ${project.isEmpty ? '(không tên)' : project}',
      )
      ..writeln('Đóng gói bằng App Management Center lúc ${_stamp(when)}.')
      ..writeln()
      ..writeln(
        'Các file giữ nguyên đường dẫn tương đối so với thư mục gốc của dự án: '
        'chép chúng vào đúng chỗ đó trong project.',
      );
    final files = placements.where((x) => x.path != secretsFile).toList();
    final secrets = placements.where((x) => x.path == secretsFile).toList();
    if (files.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('FILE');
      for (final placement in files) {
        buffer.writeln('  ${placement.path}  (${placement.item.kind.label})');
      }
    }
    if (secrets.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('TRONG $secretsFile');
      for (final placement in secrets) {
        buffer.writeln(
          '  ${placement.item.title}  (${placement.item.kind.label})',
        );
      }
    }
    buffer
      ..writeln()
      ..writeln(
        'Giữ bộ keys này như mật khẩu: đừng commit vào git, xoá bản giải nén '
        'khi đã dùng xong.',
      );
    return buffer.toString();
  }

  static String _secrets(
    String project,
    List<SafeItem> items,
    DateTime when,
    bool includeSources,
  ) {
    final buffer = StringBuffer()
      ..writeln('Bí mật của dự án ${project.isEmpty ? '(không tên)' : project}')
      ..writeln('Đóng gói lúc ${_stamp(when)} · ${items.length} mục');
    for (final item in items) {
      buffer
        ..writeln()
        ..writeln('== ${item.title} (${item.kind.label}) ==');
      void line(String label, String value) {
        if (value.trim().isNotEmpty) buffer.writeln('$label: $value');
      }

      switch (item.kind) {
        case SafeItemKind.password:
          line('Tài khoản', item.username);
          line('Mật khẩu', item.secret);
          line('Trang web', item.url);
        case SafeItemKind.note:
          buffer.writeln(item.secret.trimRight());
        default:
          line('Giá trị', item.secret);
          line('Trang web', item.url);
      }
      line('Ghi chú', item.notes);
      if (includeSources) line('Nguồn', item.source);
    }
    return buffer.toString();
  }

  static String _stamp(DateTime when) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(when.hour)}:${two(when.minute)} '
        '${two(when.day)}/${two(when.month)}/${when.year}';
  }
}

Uint8List _utf8(String text) => Uint8List.fromList(utf8.encode(text));

const _vietnameseFold = {
  'a': 'àáảãạăằắẳẵặâầấẩẫậ',
  'e': 'èéẻẽẹêềếểễệ',
  'i': 'ìíỉĩị',
  'o': 'òóỏõọôồốổỗộơờớởỡợ',
  'u': 'ùúủũụưừứửữự',
  'y': 'ỳýỷỹỵ',
  'd': 'đ',
};

/// A path segment every zip tool reads the same way: Vietnamese folded to
/// ASCII, anything else outside safe ASCII replaced. Windows Explorer still
/// mangles UTF-8 names in some zips, and a project name is often Vietnamese.
String zipSafeSegment(String value) {
  final buffer = StringBuffer();
  for (final rune in value.trim().runes) {
    var char = String.fromCharCode(rune);
    final lower = char.toLowerCase();
    for (final entry in _vietnameseFold.entries) {
      if (entry.value.contains(lower)) {
        char = char == lower ? entry.key : entry.key.toUpperCase();
        break;
      }
    }
    final unit = char.codeUnitAt(0);
    final allowed =
        char.length == 1 &&
        unit >= 0x20 &&
        unit < 0x7F &&
        !r'\/:*?"<>|'.contains(char);
    buffer.write(allowed ? char : '_');
  }
  final cleaned = buffer
      .toString()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^\.+$'), '_');
  return cleaned.isEmpty ? '_' : cleaned;
}

/// Encodes [entries] as a password-protected zip.
Uint8List encodeSafeZip(
  List<SafeZipEntry> entries, {
  required String password,
  required SafeZipEncryption encryption,
  DateTime? modified,
}) {
  final when = modified ?? DateTime.now();
  switch (encryption) {
    case SafeZipEncryption.aes256:
      final archive = Archive();
      for (final entry in entries) {
        archive.add(ArchiveFile.bytes(entry.path, entry.bytes));
      }
      return ZipEncoder(password: password).encodeBytes(
        archive,
        level: DeflateLevel.defaultCompression,
        modified: when,
      );
    case SafeZipEncryption.zipCrypto:
      return _ZipCryptoWriter(password, when).write(entries);
  }
}

/// [encodeSafeZip] off the UI isolate: AES derives a key per file, which
/// takes a moment for a kit of keystores.
Future<Uint8List> encodeSafeZipInIsolate(
  List<SafeZipEntry> entries, {
  required String password,
  required SafeZipEncryption encryption,
}) => Isolate.run(
  () => encodeSafeZip(entries, password: password, encryption: encryption),
);

/// A zip writer for traditional PKWARE encryption, which the archive package
/// only reads. Files are deflated, then encrypted behind the 12-byte header
/// the format defines.
class _ZipCryptoWriter {
  _ZipCryptoWriter(this.password, this.modified);

  final String password;
  final DateTime modified;
  final _random = Random.secure();

  late int _k0, _k1, _k2;

  void _initKeys() {
    _k0 = 0x12345678;
    _k1 = 0x23456789;
    _k2 = 0x34567890;
    for (final unit in password.codeUnits) {
      _updateKeys(unit & 0xff);
    }
  }

  void _updateKeys(int byte) {
    _k0 = getCrc32Byte(_k0, byte);
    _k1 = (_k1 + (_k0 & 0xff)) & 0xffffffff;
    _k1 = (_k1 * 134775813 + 1) & 0xffffffff;
    _k2 = getCrc32Byte(_k2, (_k1 >> 24) & 0xff);
  }

  int _streamByte() {
    final temp = (_k2 | 2) & 0xffff;
    return ((temp * (temp ^ 1)) >> 8) & 0xff;
  }

  Uint8List _encrypt(List<int> plain) {
    final out = Uint8List(plain.length);
    for (var i = 0; i < plain.length; i++) {
      final byte = plain[i];
      out[i] = byte ^ _streamByte();
      _updateKeys(byte);
    }
    return out;
  }

  Uint8List write(List<SafeZipEntry> entries) {
    final out = BytesBuilder(copy: false);
    final central = BytesBuilder(copy: false);
    final (dosTime, dosDate) = _dosDateTime(modified);
    var offset = 0;

    for (final entry in entries) {
      final name = utf8.encode(entry.path);
      final crc = getCrc32(entry.bytes);
      final deflated = Uint8List.fromList(
        ZLibCodec(raw: true, level: 6).encode(entry.bytes),
      );
      final stored = deflated.length >= entry.bytes.length;
      final payload = stored ? entry.bytes : deflated;
      final method = stored ? 0 : 8;

      _initKeys();
      final header = Uint8List.fromList(
        List<int>.generate(11, (_) => _random.nextInt(256)) +
            [(crc >> 24) & 0xff],
      );
      final encrypted = BytesBuilder(copy: false)
        ..add(_encrypt(header))
        ..add(_encrypt(payload));
      final data = encrypted.takeBytes();

      // Bit 0: encrypted. Bit 11: the name is UTF-8.
      const flags = 0x0001 | 0x0800;
      final local = _Writer()
        ..u32(0x04034b50)
        ..u16(20)
        ..u16(flags)
        ..u16(method)
        ..u16(dosTime)
        ..u16(dosDate)
        ..u32(crc)
        ..u32(data.length)
        ..u32(entry.bytes.length)
        ..u16(name.length)
        ..u16(0)
        ..bytes(name);
      final localBytes = local.take();
      out
        ..add(localBytes)
        ..add(data);

      central.add(
        (_Writer()
              ..u32(0x02014b50)
              ..u16(0x0314) // made by: Unix, spec 2.0
              ..u16(20)
              ..u16(flags)
              ..u16(method)
              ..u16(dosTime)
              ..u16(dosDate)
              ..u32(crc)
              ..u32(data.length)
              ..u32(entry.bytes.length)
              ..u16(name.length)
              ..u16(0)
              ..u16(0)
              ..u16(0)
              ..u16(0)
              ..u32(0x81a40000) // -rw-r--r--
              ..u32(offset)
              ..bytes(name))
            .take(),
      );
      offset += localBytes.length + data.length;
    }

    final directory = central.takeBytes();
    out
      ..add(directory)
      ..add(
        (_Writer()
              ..u32(0x06054b50)
              ..u16(0)
              ..u16(0)
              ..u16(entries.length)
              ..u16(entries.length)
              ..u32(directory.length)
              ..u32(offset)
              ..u16(0))
            .take(),
      );
    return out.takeBytes();
  }

  static (int, int) _dosDateTime(DateTime when) {
    final local = when.toLocal();
    final year = local.year.clamp(1980, 2107);
    final time = (local.hour << 11) | (local.minute << 5) | (local.second ~/ 2);
    final date = ((year - 1980) << 9) | (local.month << 5) | local.day;
    return (time, date);
  }
}

class _Writer {
  final _builder = BytesBuilder(copy: false);

  void u16(int value) => _builder.add([value & 0xff, (value >> 8) & 0xff]);

  void u32(int value) => _builder.add([
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ]);

  void bytes(List<int> value) => _builder.add(value);

  Uint8List take() => _builder.takeBytes();
}
