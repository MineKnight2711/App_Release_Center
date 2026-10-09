import 'dart:io';
import 'dart:typed_data';

/// How much of a screenshot is a single colour, from 0 to 1.
///
/// Reads the 8-bit RGB/RGBA non-interlaced PNGs `screencap` writes, samples a
/// grid of pixels and returns the share closest to the most common colour. A
/// value near 1 after the app has had time to draw means a blank or stuck
/// screen. Returns null for any PNG it does not understand rather than
/// guessing.
double? dominantColorShare(Uint8List png, {int grid = 48}) {
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (png.length < 33) return null;
  for (var i = 0; i < signature.length; i++) {
    if (png[i] != signature[i]) return null;
  }
  final data = ByteData.sublistView(png);
  var cursor = 8;
  int? width;
  int? height;
  int? channels;
  final idat = BytesBuilder(copy: false);
  while (cursor + 8 <= png.length) {
    final length = data.getUint32(cursor);
    final type = String.fromCharCodes(png.sublist(cursor + 4, cursor + 8));
    final start = cursor + 8;
    if (start + length > png.length) return null;
    if (type == 'IHDR') {
      width = data.getUint32(start);
      height = data.getUint32(start + 4);
      final bitDepth = png[start + 8];
      final colorType = png[start + 9];
      final interlace = png[start + 12];
      if (bitDepth != 8 || interlace != 0) return null;
      channels = switch (colorType) {
        2 => 3,
        6 => 4,
        _ => null,
      };
      if (channels == null) return null;
    } else if (type == 'IDAT') {
      idat.add(Uint8List.sublistView(png, start, start + length));
    } else if (type == 'IEND') {
      break;
    }
    cursor = start + length + 4;
  }
  if (width == null || height == null || channels == null) return null;
  if (width == 0 || height == 0 || width * height > 40000000) return null;

  final List<int> raw;
  try {
    raw = zlib.decode(idat.takeBytes());
  } on FormatException {
    return null;
  }
  final stride = width * channels;
  if (raw.length < height * (stride + 1)) return null;

  // Undo the per-row filters (PNG spec §9) into a flat pixel buffer.
  final pixels = Uint8List(height * stride);
  for (var row = 0; row < height; row++) {
    final filter = raw[row * (stride + 1)];
    final source = row * (stride + 1) + 1;
    final target = row * stride;
    for (var x = 0; x < stride; x++) {
      final value = raw[source + x];
      final left = x >= channels ? pixels[target + x - channels] : 0;
      final up = row > 0 ? pixels[target - stride + x] : 0;
      final upLeft = row > 0 && x >= channels
          ? pixels[target - stride + x - channels]
          : 0;
      final predicted = switch (filter) {
        0 => 0,
        1 => left,
        2 => up,
        3 => (left + up) >> 1,
        4 => _paeth(left, up, upLeft),
        _ => -1,
      };
      if (predicted < 0) return null;
      pixels[target + x] = (value + predicted) & 0xff;
    }
  }

  final counts = <int, int>{};
  var samples = 0;
  for (var gy = 0; gy < grid; gy++) {
    final y = (gy * (height - 1)) ~/ (grid - 1);
    for (var gx = 0; gx < grid; gx++) {
      final x = (gx * (width - 1)) ~/ (grid - 1);
      final offset = y * stride + x * channels;
      // Quantise to 4 bits per channel so anti-aliasing and gradients that
      // are visually one colour count as one.
      final key =
          (pixels[offset] >> 4) << 8 |
          (pixels[offset + 1] >> 4) << 4 |
          pixels[offset + 2] >> 4;
      counts[key] = (counts[key] ?? 0) + 1;
      samples++;
    }
  }
  final top = counts.values.reduce((a, b) => a > b ? a : b);
  return top / samples;
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}
