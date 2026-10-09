import 'dart:typed_data';

/// What the 16 KB page-size check needs from a native library.
class ElfInfo {
  const ElfInfo({required this.is64Bit, required this.loadAlignments});

  final bool is64Bit;

  /// `p_align` of every `PT_LOAD` segment.
  final List<int> loadAlignments;

  int? get minLoadAlignment => loadAlignments.isEmpty
      ? null
      : loadAlignments.reduce((a, b) => a < b ? a : b);
}

/// Reads the program headers from the first bytes of an ELF file.
///
/// Returns null when [bytes] is not a little-endian ELF or is too short to
/// reach the program header table — the caller reports "unreadable" rather
/// than guessing an alignment.
ElfInfo? parseElfHeader(Uint8List bytes) {
  if (bytes.length < 52 ||
      bytes[0] != 0x7f ||
      bytes[1] != 0x45 ||
      bytes[2] != 0x4c ||
      bytes[3] != 0x46) {
    return null;
  }
  final elfClass = bytes[4];
  if (bytes[5] != 1) return null; // Android ABIs are all little-endian.
  final data = ByteData.sublistView(bytes);

  final bool is64Bit;
  final int programHeaderOffset;
  final int entrySize;
  final int entryCount;
  if (elfClass == 2) {
    if (bytes.length < 64) return null;
    is64Bit = true;
    programHeaderOffset = data.getUint64(0x20, Endian.little);
    entrySize = data.getUint16(0x36, Endian.little);
    entryCount = data.getUint16(0x38, Endian.little);
  } else if (elfClass == 1) {
    is64Bit = false;
    programHeaderOffset = data.getUint32(0x1c, Endian.little);
    entrySize = data.getUint16(0x2a, Endian.little);
    entryCount = data.getUint16(0x2c, Endian.little);
  } else {
    return null;
  }

  final minimumEntry = is64Bit ? 56 : 32;
  if (entrySize < minimumEntry ||
      programHeaderOffset + entrySize * entryCount > bytes.length) {
    return null;
  }

  const loadSegment = 1;
  final alignments = <int>[];
  for (var index = 0; index < entryCount; index++) {
    final base = programHeaderOffset + index * entrySize;
    if (data.getUint32(base, Endian.little) != loadSegment) continue;
    alignments.add(
      is64Bit
          ? data.getUint64(base + 0x30, Endian.little)
          : data.getUint32(base + 0x1c, Endian.little),
    );
  }
  return ElfInfo(is64Bit: is64Bit, loadAlignments: alignments);
}
