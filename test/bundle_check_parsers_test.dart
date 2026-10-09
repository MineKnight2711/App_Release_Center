import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_management_center/app/modules/bundle_check/models/bundle_check_models.dart';
import 'package:app_management_center/app/modules/bundle_check/services/android_manifest.dart';
import 'package:app_management_center/app/modules/bundle_check/services/bundle_inspector.dart';
import 'package:app_management_center/app/modules/bundle_check/services/bundle_zip.dart';
import 'package:app_management_center/app/modules/bundle_check/services/elf_header.dart';
import 'package:app_management_center/app/modules/bundle_check/services/env_file.dart';
import 'package:app_management_center/app/modules/bundle_check/services/resource_table.dart';
import 'package:app_management_center/app/modules/bundle_check/services/signing_certificate.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bundle_check_fixtures.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('bundle_parsers'));
  tearDown(() => temp.deleteSync(recursive: true));

  group('AndroidManifest proto', () {
    test('đọc package, version, sdk, permission và launcher', () {
      final info = ManifestInfo.parse(
        manifestBytes(
          packageName: 'vn.amc.demo',
          versionCode: 73,
          versionName: '1.5.1',
          minSdk: 24,
          targetSdk: 36,
          cleartext: true,
          permissions: ['android.permission.CAMERA'],
          metaData: {'com.google.android.geo.API_KEY': r'${MAPS_KEY}'},
        ),
      );
      expect(info.packageName, 'vn.amc.demo');
      expect(info.versionCode, 73);
      expect(info.versionName, '1.5.1');
      expect(info.minSdk, 24);
      expect(info.targetSdk, 36);
      expect(info.debuggable, isFalse);
      expect(info.usesCleartextTraffic, isTrue);
      expect(info.permissions, ['android.permission.CAMERA']);
      expect(info.metaData.single.value, r'${MAPS_KEY}');
      expect(info.launcherActivity, 'vn.amc.demo.MainActivity');
    });

    test('debuggable lấy từ giá trị đã compile', () {
      expect(
        ManifestInfo.parse(manifestBytes(debuggable: true)).debuggable,
        isTrue,
      );
    });

    test('element gốc không phải manifest thì báo lỗi', () {
      expect(
        () => ManifestInfo.parse(ProtoElement('application').toBytes()),
        throwsFormatException,
      );
    });
  });

  test('resources.pb trả đúng chuỗi được hỏi', () {
    final values = readStringResources(
      resourcesBytes({'project_id': 'amc-prod', 'app_name': 'Demo'}),
      names: {'project_id', 'google_app_id'},
    );
    expect(values, {'project_id': 'amc-prod'});
  });

  group('ELF', () {
    test('64-bit căn 16 KB', () {
      final info = parseElfHeader(elfBytes(alignment: 0x4000))!;
      expect(info.is64Bit, isTrue);
      expect(info.minLoadAlignment, 0x4000);
    });

    test('32-bit căn 4 KB', () {
      final info = parseElfHeader(elfBytes(is64: false, alignment: 0x1000))!;
      expect(info.is64Bit, isFalse);
      expect(info.minLoadAlignment, 0x1000);
    });

    test('không phải ELF hoặc bị cắt thì trả null', () {
      expect(parseElfHeader(Uint8List.fromList(List.filled(80, 0))), isNull);
      expect(parseElfHeader(Uint8List.sublistView(elfBytes(), 0, 70)), isNull);
    });
  });

  group('Chữ ký', () {
    test('debug key nhận ra và fingerprint khớp keytool', () {
      final cert = parsePkcs7SignerCertificate(debugSignatureBlock);
      expect(cert.isAndroidDebug, isTrue);
      expect(cert.sha256, debugSignatureSha256);
      expect(cert.subject['O'], 'Android');
    });

    test('upload key không phải debug', () {
      final cert = parsePkcs7SignerCertificate(uploadSignatureBlock);
      expect(cert.isAndroidDebug, isFalse);
      expect(cert.commonName, 'Fixture Upload');
      expect(cert.sha256, uploadSignatureSha256);
      expect(cert.notAfter!.isAfter(cert.notBefore!), isTrue);
    });

    test('chuẩn hoá fingerprint dán từ nhiều dạng', () {
      expect(
        SigningCertificate.normalizeFingerprint('fd f9-e9:64'),
        'FD:F9:E9:64',
      );
    });

    test('khối rác báo FormatException', () {
      expect(
        () => parsePkcs7SignerCertificate(Uint8List.fromList([0x30, 0x03, 1])),
        throwsFormatException,
      );
    });
  });

  group('Zip', () {
    test('tên entry kiểu ../ chỉ là khoá tra cứu, không ghi ra đĩa', () async {
      final archive = Archive()
        ..add(ArchiveFile.bytes('../../evil.txt', utf8.encode('x')));
      final path = '${temp.path}/evil.zip';
      File(path).writeAsBytesSync(ZipEncoder().encodeBytes(archive));

      final zip = await BundleZip.open(path);
      final bytes = await zip.read(zip.entry('../../evil.txt')!, maxBytes: 10);
      await zip.close();
      expect(utf8.decode(bytes), 'x');
      expect(File('${temp.parent.path}/evil.txt').existsSync(), isFalse);
    });

    test('entry giải nén vượt trần thì dừng, không nuốt hết bộ nhớ', () async {
      final archive = Archive()
        ..add(ArchiveFile.bytes('bomb.bin', Uint8List(8 * 1024 * 1024)));
      final path = '${temp.path}/bomb.zip';
      File(path).writeAsBytesSync(ZipEncoder().encodeBytes(archive));

      final zip = await BundleZip.open(path);
      final entry = zip.entry('bomb.bin')!;
      expect(entry.compressedSize, lessThan(64 * 1024));
      await expectLater(
        zip.read(entry, maxBytes: 1024 * 1024),
        throwsA(isA<BundleZipException>()),
      );
      expect((await zip.readPrefix(entry, 100)).length, 100);
      await zip.close();
    });

    test('file không phải zip báo lỗi rõ ràng', () async {
      final path = '${temp.path}/not.aab';
      File(path).writeAsStringSync('hello world, definitely not a zip file');
      await expectLater(
        BundleZip.open(path),
        throwsA(isA<BundleZipException>()),
      );
    });
  });

  group('.env', () {
    test('đọc như flutter_dotenv', () {
      final values = parseEnvFile(
        '﻿# comment\n'
        'export API_URL="https://api.amc.vn"\n'
        "TOKEN='abc'\n"
        'EMPTY=\n'
        'INLINE=value # ghi chú\n'
        'bad line\n',
      );
      expect(values, {
        'API_URL': 'https://api.amc.vn',
        'TOKEN': 'abc',
        'EMPTY': '',
        'INLINE': 'value',
      });
    });

    test('nhận ra giá trị mẫu', () {
      for (final value in [
        'change-me',
        'xxx',
        'YOUR_API_KEY',
        '<token>',
        r'${X}',
      ]) {
        expect(isPlaceholderValue(value), isTrue, reason: value);
      }
      expect(isPlaceholderValue('https://api.amc.vn'), isFalse);
    });

    test('nhận ra host máy dev', () {
      expect(pointsAtLocalMachine('http://10.0.2.2:8080/api'), isTrue);
      expect(pointsAtLocalMachine('http://localhost:3000'), isTrue);
      expect(pointsAtLocalMachine('https://abc.ngrok-free.app'), isTrue);
      expect(pointsAtLocalMachine('https://api.amc.vn'), isFalse);
      expect(pointsAtLocalMachine('https://localhost-fan.com'), isFalse);
    });
  });

  test('NOTICES liệt kê package ở đầu mỗi khối', () {
    final packages = parseNoticesPackages(
      'flutter_dotenv\nfirebase_core\n\nMIT License...\nsome text\n'
      '${'-' * 80}\n'
      'skia\n\nBSD...\n',
    );
    expect(packages, {'flutter_dotenv', 'firebase_core', 'skia'});
  });

  test('tìm chuỗi Latin-1 và UTF-16LE trong libapp.so', () {
    final bytes = Uint8List.fromList([
      ...latin1.encode('xx amc-prod yy'),
      ...List<int>.generate(6, (i) => i.isEven ? 'abc'.codeUnitAt(i ~/ 2) : 0),
    ]);
    expect(containsText(bytes, 'amc-prod'), isTrue);
    expect(containsText(bytes, 'abc'), isTrue);
    expect(containsText(bytes, 'amc-dev'), isFalse);
  });

  test('che giá trị: URL giữ host, key chỉ giữ hai đầu', () {
    expect(
      maskValue('https://api.amc.vn/v1?token=secret'),
      'https://api.amc.vn/…',
    );
    expect(maskValue('AIzaSyBo2JJ7667iIrxck'), 'AI••••ck');
    expect(maskValue('abc'), '•••');
    expect(maskValue(''), '(rỗng)');
  });

  test('phát hiện file private key và service account', () {
    expect(looksLikeSecretFile('-----BEGIN PRIVATE KEY-----\nabc'), isTrue);
    expect(
      looksLikeSecretFile('{"type": "service_account", "private_key": "x"}'),
      isTrue,
    );
    expect(looksLikeSecretFile('-----BEGIN PUBLIC KEY-----'), isFalse);
    expect(
      looksLikeSecretFile(
        '<match value="-----BEGIN PRIVATE KEY-----" type="string" offset="0"/>',
      ),
      isFalse,
    );
    expect(
      looksLikeSecretFile(
        '<match value="-----BEGIN RSA PRIVATE KEY-----" type="string" offset="0"/>',
      ),
      isFalse,
    );
  });
}
