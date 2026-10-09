import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// JAR signature blocks (`META-INF/*.EC`) made for these tests with a
/// throwaway keystore and `jarsigner`. Only the public certificate is inside.
final debugSignatureBlock = base64Decode(
  'MIIDHgYJKoZIhvcNAQcCoIIDDzCCAwsCAQExDzANBglghkgBZQMEAgIFADALBgkqhkiG9w0B'
  'BwGgggGJMIIBhTCCASugAwIBAgIIUKmhk865HgEwCgYIKoZIzj0EAwMwNzELMAkGA1UEBhMC'
  'VVMxEDAOBgNVBAoTB0FuZHJvaWQxFjAUBgNVBAMTDUFuZHJvaWQgRGVidWcwHhcNMjYwOTI5'
  'MDkyMTE4WhcNMzYwOTI2MDkyMTE4WjA3MQswCQYDVQQGEwJVUzEQMA4GA1UEChMHQW5kcm9p'
  'ZDEWMBQGA1UEAxMNQW5kcm9pZCBEZWJ1ZzBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABKDK'
  'Szpe6NplmTRe689MTVz4c2PqoXjzdPoYiy8sIarbxKxB2G/6v7MNkGV6uICAEUaiTtwHraJr'
  'VJw1j3WhigSjITAfMB0GA1UdDgQWBBQY8YFMTe7KIuOwngJrevefHK34nDAKBggqhkjOPQQD'
  'AwNIADBFAiA7AW39ko3kF2mPJqQengkZHYnLHNEqRU52jLvXAtooFQIhAOtqo4PU1RlZvLhS'
  'i0U+eXNoeU6LMGcAOF1sIp0reMGrMYIBWTCCAVUCAQEwQzA3MQswCQYDVQQGEwJVUzEQMA4G'
  'A1UEChMHQW5kcm9pZDEWMBQGA1UEAxMNQW5kcm9pZCBEZWJ1ZwIIUKmhk865HgEwDQYJYIZI'
  'AWUDBAICBQCggaUwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN'
  'MjYwOTI5MDkyMTE5WjAqBgkqhkiG9w0BCTQxHTAbMA0GCWCGSAFlAwQCAgUAoQoGCCqGSM49'
  'BAMDMD8GCSqGSIb3DQEJBDEyBDDKYR+pu94o8KLM0fONwPMCb/KTgUh9O/2x6go4qRR0VXLo'
  'SPnShkLXpiP0Q/kDjVcwCgYIKoZIzj0EAwMESDBGAiEA09rZ/IMM5BfCNejMMLis+pQ/J6QT'
  'MlBi8Zg1m7P7nIICIQD4wgv09OJBYplXcZt4nAMi8tpBsu764yZ4Mcn9S/4A8g==',
);

/// `keytool -printcert` on the jar signed with [debugSignatureBlock].
const debugSignatureSha256 =
    '6E:A8:6A:F7:E5:AA:E8:93:36:B7:60:C0:E1:D6:3A:F2:'
    '15:61:BC:CC:F0:F0:69:7D:8E:9F:1A:8A:10:74:81:5F';

final uploadSignatureBlock = base64Decode(
  'MIIDnAYJKoZIhvcNAQcCoIIDjTCCA4kCAQExDzANBglghkgBZQMEAgIFADALBgkqhkiG9w0B'
  'BwGgggHeMIIB2jCCAX+gAwIBAgIIUUt4I4aJKxwwCgYIKoZIzj0EAwMwYTELMAkGA1UEBhMC'
  'Vk4xFTATBgNVBAcMDEg/IENow60gTWluaDERMA8GA1UEChMIQU1DIFRlc3QxDzANBgNVBAsT'
  'Bk1vYmlsZTEXMBUGA1UEAxMORml4dHVyZSBVcGxvYWQwHhcNMjYwOTI5MDkyMTE4WhcNMzYw'
  'OTI2MDkyMTE4WjBhMQswCQYDVQQGEwJWTjEVMBMGA1UEBwwMSD8gQ2jDrSBNaW5oMREwDwYD'
  'VQQKEwhBTUMgVGVzdDEPMA0GA1UECxMGTW9iaWxlMRcwFQYDVQQDEw5GaXh0dXJlIFVwbG9h'
  'ZDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABHk/LTjT+UKlrf5xguCLGNhlS4vGfpIYlWM6'
  '/jwSsJUF2aTXRNWX6wdI1b3Sj+AbEFcsEdN21Hy5U+zhLAnSDOajITAfMB0GA1UdDgQWBBSh'
  'hTEHuOaSOJ/qrI8mDVaqFCf1vDAKBggqhkjOPQQDAwNJADBGAiEA4ymjGnDC1pgYNvUHFfxZ'
  'QXf0K5ux66UX8ixiarQRiS8CIQCWAa4/qaf2ZpucnMHwd06VdTsvovdms5Xul2XCjP8CfzGC'
  'AYIwggF+AgEBMG0wYTELMAkGA1UEBhMCVk4xFTATBgNVBAcMDEg/IENow60gTWluaDERMA8G'
  'A1UEChMIQU1DIFRlc3QxDzANBgNVBAsTBk1vYmlsZTEXMBUGA1UEAxMORml4dHVyZSBVcGxv'
  'YWQCCFFLeCOGiSscMA0GCWCGSAFlAwQCAgUAoIGlMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0B'
  'BwEwHAYJKoZIhvcNAQkFMQ8XDTI2MDkyOTA5MjExOVowKgYJKoZIhvcNAQk0MR0wGzANBglg'
  'hkgBZQMEAgIFAKEKBggqhkjOPQQDAzA/BgkqhkiG9w0BCQQxMgQwymEfqbveKPCizNHzjcDz'
  'Am/yk4FIfTv9seoKOKkUdFVy6Ej50oZC16Yj9EP5A41XMAoGCCqGSM49BAMDBEcwRQIgS/d2'
  'cqT2t5huYHABhyfjv8sJaj7xK/peBcfnsRH/3PkCIQD3avDe6sGmwsAdxZ2miabtVqi6ub38'
  '5W8jm27PEFTV5Q==',
);

const uploadSignatureSha256 =
    'FD:F9:E9:64:29:1B:71:28:69:C2:AE:51:2B:92:53:F1:'
    '92:B7:A7:AA:3B:F0:35:E4:3E:34:61:F5:7A:9E:5C:AE';

/// Writes protobuf wire format, the inverse of the reader under test.
class ProtoWriter {
  final _bytes = BytesBuilder();

  void _varint(int value) {
    var v = value;
    while (v >= 0x80) {
      _bytes.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    _bytes.addByte(v);
  }

  void varint(int field, int value) {
    _varint(field << 3);
    _varint(value);
  }

  void bytes(int field, List<int> data) {
    _varint(field << 3 | 2);
    _varint(data.length);
    _bytes.add(data);
  }

  void string(int field, String value) => bytes(field, utf8.encode(value));

  void message(int field, ProtoWriter child) => bytes(field, child.toBytes());

  Uint8List toBytes() => _bytes.toBytes();
}

/// An aapt2-proto manifest element, as it sits in an AAB.
class ProtoElement {
  ProtoElement(
    this.name, {
    this.attributes = const {},
    this.children = const [],
  });

  final String name;

  /// Values: String → text, int → compiled int, bool → compiled bool.
  final Map<String, Object> attributes;
  final List<ProtoElement> children;

  ProtoWriter write() {
    final element = ProtoWriter()..string(3, name);
    for (final entry in attributes.entries) {
      final attribute = ProtoWriter()
        ..string(2, entry.key)
        ..string(3, '${entry.value}');
      final value = entry.value;
      if (value is int || value is bool) {
        final primitive = ProtoWriter();
        if (value is int) primitive.varint(6, value);
        if (value is bool) primitive.varint(8, value ? 1 : 0);
        attribute.message(6, ProtoWriter()..message(7, primitive));
      }
      element.message(4, attribute);
    }
    for (final child in children) {
      element.message(5, ProtoWriter()..message(1, child.write()));
    }
    return element;
  }

  Uint8List toBytes() => (ProtoWriter()..message(1, write())).toBytes();
}

Uint8List manifestBytes({
  String packageName = 'vn.amc.demo',
  int versionCode = 12,
  String versionName = '1.2.0',
  int minSdk = 24,
  int targetSdk = 36,
  bool debuggable = false,
  bool? cleartext,
  List<String> permissions = const ['android.permission.INTERNET'],
  Map<String, String> metaData = const {},
}) {
  return ProtoElement(
    'manifest',
    attributes: {
      'package': packageName,
      'versionCode': versionCode,
      'versionName': versionName,
    },
    children: [
      ProtoElement(
        'uses-sdk',
        attributes: {'minSdkVersion': minSdk, 'targetSdkVersion': targetSdk},
      ),
      for (final permission in permissions)
        ProtoElement('uses-permission', attributes: {'name': permission}),
      ProtoElement(
        'application',
        attributes: {
          if (debuggable) 'debuggable': true,
          'usesCleartextTraffic': ?cleartext,
        },
        children: [
          ProtoElement(
            'activity',
            attributes: {'name': '$packageName.MainActivity'},
            children: [
              ProtoElement(
                'intent-filter',
                children: [
                  ProtoElement(
                    'action',
                    attributes: {'name': 'android.intent.action.MAIN'},
                  ),
                  ProtoElement(
                    'category',
                    attributes: {'name': 'android.intent.category.LAUNCHER'},
                  ),
                ],
              ),
            ],
          ),
          for (final entry in metaData.entries)
            ProtoElement(
              'meta-data',
              attributes: {'name': entry.key, 'value': entry.value},
            ),
        ],
      ),
    ],
  ).toBytes();
}

/// A `resources.pb` holding default-configuration string values.
Uint8List resourcesBytes(Map<String, String> strings) {
  final type = ProtoWriter()..string(2, 'string');
  for (final entry in strings.entries) {
    final item = ProtoWriter()
      ..message(2, ProtoWriter()..string(1, entry.value));
    final configValue = ProtoWriter()
      ..bytes(1, const [])
      ..message(2, ProtoWriter()..message(4, item));
    type.message(
      3,
      ProtoWriter()
        ..string(2, entry.key)
        ..message(6, configValue),
    );
  }
  final package = ProtoWriter()
    ..string(2, 'vn.amc.demo')
    ..message(3, type);
  return (ProtoWriter()..message(2, package)).toBytes();
}

/// The start of an ELF shared object with two `PT_LOAD` segments.
Uint8List elfBytes({
  bool is64 = true,
  int alignment = 0x4000,
  String body = '',
}) {
  final headerSize = is64 ? 64 : 52;
  final entrySize = is64 ? 56 : 32;
  final out = ByteData(headerSize + entrySize * 2);
  out
    ..setUint32(0, 0x464c457f, Endian.little)
    ..setUint8(4, is64 ? 2 : 1)
    ..setUint8(5, 1);
  if (is64) {
    out
      ..setUint64(0x20, headerSize, Endian.little)
      ..setUint16(0x36, entrySize, Endian.little)
      ..setUint16(0x38, 2, Endian.little);
  } else {
    out
      ..setUint32(0x1c, headerSize, Endian.little)
      ..setUint16(0x2a, entrySize, Endian.little)
      ..setUint16(0x2c, 2, Endian.little);
  }
  for (var i = 0; i < 2; i++) {
    final base = headerSize + i * entrySize;
    out.setUint32(base, 1, Endian.little);
    if (is64) {
      out.setUint64(base + 0x30, alignment, Endian.little);
    } else {
      out.setUint32(base + 0x1c, alignment, Endian.little);
    }
  }
  return Uint8List.fromList([
    ...out.buffer.asUint8List(),
    ...latin1.encode(body),
  ]);
}

/// Writes a small but structurally real AAB to [path].
File writeAab(
  String path, {
  Uint8List? manifest,
  Uint8List? resources,
  Uint8List? signatureBlock,
  String signatureName = 'META-INF/UPLOAD.EC',
  Map<String, String> envFiles = const {'.env': 'API_URL=https://api.amc.vn\n'},
  List<String> abis = const ['arm64-v8a', 'armeabi-v7a', 'x86_64'],
  int alignment = 0x4000,
  String libAppStrings = '',
  bool kernelBlob = false,
  bool bundleConfig = true,
  List<String> notices = const ['flutter_dotenv', 'firebase_core'],
  Map<String, List<int>> extra = const {},
}) {
  final archive = Archive();
  void add(String name, List<int> data) {
    archive.add(ArchiveFile.bytes(name, data));
  }

  if (bundleConfig) add('BundleConfig.pb', const [0x0a, 0x00]);
  add('base/manifest/AndroidManifest.xml', manifest ?? manifestBytes());
  add('base/resources.pb', resources ?? resourcesBytes({'app_name': 'Demo'}));
  for (final abi in abis) {
    final is64 = abi.contains('64');
    add(
      'base/lib/$abi/libflutter.so',
      elfBytes(is64: is64, alignment: alignment),
    );
    add(
      'base/lib/$abi/libapp.so',
      elfBytes(is64: is64, alignment: alignment, body: libAppStrings),
    );
  }
  for (final entry in envFiles.entries) {
    add('base/assets/flutter_assets/${entry.key}', utf8.encode(entry.value));
  }
  final noticesText = [
    for (final package in notices) '$package\n\nLicense text for $package.\n',
  ].join('${'-' * 80}\n');
  add(
    'base/assets/flutter_assets/NOTICES.Z',
    gzip.encode(utf8.encode(noticesText)),
  );
  if (kernelBlob) add('base/assets/flutter_assets/kernel_blob.bin', [1, 2, 3]);
  if (signatureBlock != null) add(signatureName, signatureBlock);
  for (final entry in extra.entries) {
    add(entry.key, entry.value);
  }
  final file = File(path)..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
  return file;
}

/// A PNG as `screencap` writes it: 8-bit RGBA, one filter per row.
Uint8List pngOf(
  int width,
  int height,
  List<int> Function(int x, int y) rgb, {
  int filter = 0,
}) {
  final stride = width * 4;
  final raw = <int>[];
  final previous = List<int>.filled(stride, 0);
  for (var y = 0; y < height; y++) {
    final row = <int>[];
    for (var x = 0; x < width; x++) {
      row.addAll([...rgb(x, y), 255]);
    }
    raw.add(filter);
    for (var i = 0; i < stride; i++) {
      final left = i >= 4 ? row[i - 4] : 0;
      raw.add(switch (filter) {
        1 => (row[i] - left) & 0xff,
        2 => (row[i] - previous[i]) & 0xff,
        _ => row[i],
      });
    }
    previous.setAll(0, row);
  }

  final out = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  void chunk(String type, List<int> data) {
    final body = [...type.codeUnits, ...data];
    out
      ..add(_u32(data.length))
      ..add(body)
      ..add(_u32(_crc32(body)));
  }

  chunk('IHDR', [..._u32(width), ..._u32(height), 8, 6, 0, 0, 0]);
  chunk('IDAT', zlib.encode(raw));
  chunk('IEND', const []);
  return out.toBytes();
}

List<int> _u32(int v) => [
  v >> 24 & 0xff,
  v >> 16 & 0xff,
  v >> 8 & 0xff,
  v & 0xff,
];

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var k = 0; k < 8; k++) {
      crc = crc & 1 != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return crc ^ 0xffffffff;
}
