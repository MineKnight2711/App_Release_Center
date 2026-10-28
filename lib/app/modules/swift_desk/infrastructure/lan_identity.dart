import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

String remoteToken() => base64Url
    .encode(List.generate(32, (_) => Random.secure().nextInt(256)))
    .replaceAll('=', '');
String remoteHash(String value) =>
    sha256.convert(utf8.encode(value)).toString();
bool remoteHashEquals(String a, String b) {
  if (a.length != b.length) return false;
  var different = 0;
  for (var i = 0; i < a.length; i++) {
    different |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return different == 0;
}

class LanIdentity {
  LanIdentity({
    required this.id,
    required this.certificate,
    required this.privateKey,
  });
  final String id, certificate, privateKey;
  String get fingerprint => sha256
      .convert(
        base64.decode(
          certificate
              .replaceAll('-----BEGIN CERTIFICATE-----', '')
              .replaceAll('-----END CERTIFICATE-----', '')
              .replaceAll(RegExp(r'\s'), ''),
        ),
      )
      .toString();
  SecurityContext get context => SecurityContext(withTrustedRoots: false)
    ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_2
    ..useCertificateChainBytes(utf8.encode(certificate))
    ..usePrivateKeyBytes(utf8.encode(privateKey));

  static Future<LanIdentity> load(RemoteCredentialStore secrets) async {
    final existing = await secrets.read('identity');
    if (existing != null) {
      final json = jsonDecode(existing) as Map<String, dynamic>;
      final identity = LanIdentity(
        id: json['id'] as String,
        certificate: json['certificate'] as String,
        privateKey: json['privateKey'] as String,
      );
      final cert = X509Utils.x509CertificateFromPem(
        identity.certificate,
      ).tbsCertificate!;
      if (!isRemoteId(identity.id) ||
          !cert.validity.notAfter.isAfter(DateTime.now())) {
        throw StateError(
          'Chứng chỉ SwiftDesk đã hết hạn. Cần tạo lại danh tính và ghép lại thiết bị.',
        );
      }
      identity.context; // Verify that the saved certificate and key parse.
      return identity;
    }
    final generated = await generate();
    await secrets.write(
      'identity',
      jsonEncode({
        'id': generated.id,
        'certificate': generated.certificate,
        'privateKey': generated.privateKey,
      }),
    );
    return generated;
  }

  static Future<LanIdentity> generate() async {
    final data = await Isolate.run(() {
      final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
      final key = pair.privateKey as RSAPrivateKey;
      final csr = X509Utils.generateRsaCsrPem(
        {'CN': 'AMC Remote Desktop'},
        key,
        pair.publicKey as RSAPublicKey,
      );
      return <String, String>{
        'certificate': X509Utils.generateSelfSignedCertificate(
          key,
          csr,
          365,
          cA: false,
          serialNumber: BigInt.parse(
            remoteHash(remoteToken()).substring(0, 30),
            radix: 16,
          ).toString(),
          notBefore: DateTime.now().toUtc().subtract(
            const Duration(minutes: 5),
          ),
        ),
        'privateKey': CryptoUtils.encodeRSAPrivateKeyToPem(key),
      };
    });
    return LanIdentity(
      id: const Uuid().v4(),
      certificate: data['certificate']!,
      privateKey: data['privateKey']!,
    );
  }
}
