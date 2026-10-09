import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class BundleZipException implements Exception {
  const BundleZipException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BundleZipEntry {
  const BundleZipEntry({
    required this.name,
    required this.method,
    required this.flags,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
  });

  final String name;
  final int method;
  final int flags;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;

  bool get isDirectory => name.endsWith('/');
  bool get isEncrypted => flags & 0x1 != 0;
}

/// Reads entries out of an AAB or APK without extracting anything to disk.
///
/// Entry names are only ever lookup keys, never paths, so an entry named
/// `../../evil` cannot write anywhere. Every read carries a byte ceiling: an
/// entry that claims a few KB but inflates to gigabytes stops at the ceiling
/// instead of exhausting memory.
class BundleZip {
  BundleZip._(
    this.path,
    this.length,
    this._file,
    this.entries,
    this.centralDirectoryOffset,
  ) : _byName = {for (final entry in entries) entry.name: entry};

  static const _eocdSignature = 0x06054b50;
  static const _zip64LocatorSignature = 0x07064b50;
  static const _zip64EocdSignature = 0x06064b50;
  static const _centralSignature = 0x02014b50;
  static const _localSignature = 0x04034b50;
  static const _maxCentralDirectoryBytes = 64 * 1024 * 1024;
  static const _chunkSize = 64 * 1024;

  final String path;
  final int length;
  final RandomAccessFile _file;
  final List<BundleZipEntry> entries;

  /// Where the central directory starts. An APK's v2/v3 signing block sits
  /// immediately before it.
  final int centralDirectoryOffset;
  final Map<String, BundleZipEntry> _byName;
  Future<void> _queue = Future.value();

  static Future<BundleZip> open(String path) async {
    final file = await File(path).open();
    try {
      final length = await file.length();
      final (entries, directoryOffset) = await _readCentralDirectory(
        file,
        length,
      );
      return BundleZip._(path, length, file, entries, directoryOffset);
    } catch (_) {
      await file.close();
      rethrow;
    }
  }

  BundleZipEntry? entry(String name) => _byName[name];

  bool contains(String name) => _byName.containsKey(name);

  /// Inflates [entry], failing once the output passes [maxBytes].
  Future<Uint8List> read(BundleZipEntry entry, {required int maxBytes}) {
    return _locked(() => _read(entry, maxBytes: maxBytes, truncate: false));
  }

  /// Inflates only the first [count] bytes of [entry], which is all an ELF
  /// header needs — no point inflating 12 MB of `libapp.so` to read 64 bytes.
  Future<Uint8List> readPrefix(BundleZipEntry entry, int count) {
    return _locked(() => _read(entry, maxBytes: count, truncate: true));
  }

  /// Reads [count] raw bytes at [offset], for structures outside any entry.
  Future<Uint8List> readRaw(int offset, int count) {
    if (offset < 0 || count < 0 || offset + count > length) {
      throw const BundleZipException('Đọc ra ngoài phạm vi file.');
    }
    return _locked(() async {
      await _file.setPosition(offset);
      return _file.read(count);
    });
  }

  Future<void> close() => _locked(_file.close);

  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<Uint8List> _read(
    BundleZipEntry entry, {
    required int maxBytes,
    required bool truncate,
  }) async {
    if (entry.isEncrypted) {
      throw BundleZipException('${entry.name} bị mã hoá, không đọc được.');
    }
    if (entry.method != 0 && entry.method != 8) {
      throw BundleZipException(
        '${entry.name} dùng kiểu nén ${entry.method}, chưa hỗ trợ.',
      );
    }

    await _file.setPosition(entry.localHeaderOffset);
    final header = await _file.read(30);
    if (header.length < 30 || _u32(header, 0) != _localSignature) {
      throw BundleZipException('Header của ${entry.name} bị hỏng.');
    }
    final dataStart =
        entry.localHeaderOffset + 30 + _u16(header, 26) + _u16(header, 28);
    if (dataStart + entry.compressedSize > length) {
      throw BundleZipException('${entry.name} vượt quá kích thước file.');
    }
    await _file.setPosition(dataStart);

    final output = BytesBuilder(copy: false);
    var remaining = entry.compressedSize;

    if (entry.method == 0) {
      if (entry.compressedSize > maxBytes && !truncate) {
        throw _tooLarge(entry, maxBytes);
      }
      final wanted = math.min(entry.compressedSize, maxBytes);
      return Uint8List.fromList(await _file.read(wanted));
    }

    final filter = RawZLibFilter.inflateFilter(raw: true);
    bool drain({bool end = false}) {
      List<int>? chunk;
      while ((chunk = filter.processed(flush: false, end: end)) != null) {
        output.add(chunk!);
        if (truncate && output.length >= maxBytes) return true;
        if (output.length > maxBytes) throw _tooLarge(entry, maxBytes);
      }
      return false;
    }

    while (remaining > 0) {
      final chunk = await _file.read(math.min(_chunkSize, remaining));
      if (chunk.isEmpty) break;
      remaining -= chunk.length;
      filter.process(chunk, 0, chunk.length);
      if (drain()) return _cut(output, maxBytes);
    }
    drain(end: true);
    return _cut(output, maxBytes);
  }

  static Uint8List _cut(BytesBuilder output, int maxBytes) {
    final bytes = output.takeBytes();
    return bytes.length <= maxBytes
        ? bytes
        : Uint8List.sublistView(bytes, 0, maxBytes);
  }

  static BundleZipException _tooLarge(BundleZipEntry entry, int maxBytes) {
    return BundleZipException(
      '${entry.name} giải nén ra quá ${maxBytes ~/ (1024 * 1024)} MB, '
      'dừng để tránh zip bomb.',
    );
  }

  static Future<(List<BundleZipEntry>, int)> _readCentralDirectory(
    RandomAccessFile file,
    int length,
  ) async {
    if (length < 22) {
      throw const BundleZipException('File quá nhỏ, không phải zip.');
    }
    final tailLength = math.min(length, 22 + 0xffff);
    await file.setPosition(length - tailLength);
    final tail = await file.read(tailLength);

    var eocd = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (_u32(tail, i) == _eocdSignature) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) {
      throw const BundleZipException(
        'Không tìm thấy mục lục zip — file không phải AAB/APK hoặc bị cắt dở.',
      );
    }

    var entryCount = _u16(tail, eocd + 10);
    var directorySize = _u32(tail, eocd + 12);
    var directoryOffset = _u32(tail, eocd + 16);

    final needsZip64 =
        entryCount == 0xffff ||
        directorySize == 0xffffffff ||
        directoryOffset == 0xffffffff;
    if (needsZip64 &&
        eocd >= 20 &&
        _u32(tail, eocd - 20) == _zip64LocatorSignature) {
      final recordOffset = _u64(tail, eocd - 20 + 8);
      await file.setPosition(recordOffset);
      final record = await file.read(56);
      if (record.length < 56 || _u32(record, 0) != _zip64EocdSignature) {
        throw const BundleZipException('Mục lục zip64 bị hỏng.');
      }
      entryCount = _u64(record, 32);
      directorySize = _u64(record, 40);
      directoryOffset = _u64(record, 48);
    }

    if (directorySize > _maxCentralDirectoryBytes ||
        directoryOffset + directorySize > length) {
      throw const BundleZipException('Mục lục zip có kích thước bất thường.');
    }

    await file.setPosition(directoryOffset);
    final directory = await file.read(directorySize);
    final entries = <BundleZipEntry>[];
    var cursor = 0;
    while (cursor + 46 <= directory.length &&
        _u32(directory, cursor) == _centralSignature) {
      final flags = _u16(directory, cursor + 8);
      final method = _u16(directory, cursor + 10);
      var compressed = _u32(directory, cursor + 20);
      var uncompressed = _u32(directory, cursor + 24);
      final nameLength = _u16(directory, cursor + 28);
      final extraLength = _u16(directory, cursor + 30);
      final commentLength = _u16(directory, cursor + 32);
      var localOffset = _u32(directory, cursor + 42);

      final nameStart = cursor + 46;
      final extraStart = nameStart + nameLength;
      final next = extraStart + extraLength + commentLength;
      if (next > directory.length) {
        throw const BundleZipException('Mục lục zip bị cắt dở.');
      }
      final name = utf8.decode(
        directory.sublist(nameStart, extraStart),
        allowMalformed: true,
      );

      if (compressed == 0xffffffff ||
          uncompressed == 0xffffffff ||
          localOffset == 0xffffffff) {
        var extra = extraStart;
        final extraEnd = extraStart + extraLength;
        while (extra + 4 <= extraEnd) {
          final id = _u16(directory, extra);
          final size = _u16(directory, extra + 2);
          if (id == 0x0001) {
            var field = extra + 4;
            if (uncompressed == 0xffffffff && field + 8 <= extraEnd) {
              uncompressed = _u64(directory, field);
              field += 8;
            }
            if (compressed == 0xffffffff && field + 8 <= extraEnd) {
              compressed = _u64(directory, field);
              field += 8;
            }
            if (localOffset == 0xffffffff && field + 8 <= extraEnd) {
              localOffset = _u64(directory, field);
            }
            break;
          }
          extra += 4 + size;
        }
      }

      entries.add(
        BundleZipEntry(
          name: name,
          method: method,
          flags: flags,
          compressedSize: compressed,
          uncompressedSize: uncompressed,
          localHeaderOffset: localOffset,
        ),
      );
      cursor = next;
    }

    if (entries.length != entryCount) {
      throw BundleZipException(
        'Mục lục zip khai $entryCount mục nhưng đọc được ${entries.length}.',
      );
    }
    return (entries, directoryOffset);
  }

  static int _u16(List<int> bytes, int offset) {
    return bytes[offset] | bytes[offset + 1] << 8;
  }

  static int _u32(List<int> bytes, int offset) {
    return bytes[offset] |
        bytes[offset + 1] << 8 |
        bytes[offset + 2] << 16 |
        bytes[offset + 3] << 24;
  }

  static int _u64(List<int> bytes, int offset) {
    return _u32(bytes, offset) + _u32(bytes, offset + 4) * 0x100000000;
  }
}
