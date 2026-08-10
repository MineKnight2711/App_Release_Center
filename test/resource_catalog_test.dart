import 'dart:convert';

import 'package:app_release_center/app/models/resource_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes catalog metadata without password plaintext', () {
    final bundle = ResourceCatalogBundle(
      projectPath: r'C:\apps\demo',
      resources: [
        ResourceCatalogItem(
          id: 'resource-1',
          kind: ResourceCatalogKind.figma,
          title: 'Design handoff',
          url: 'https://figma.example.com/file/app',
          environment: 'production',
          owner: 'Design',
          tags: const ['ui', 'handoff'],
          updatedAt: DateTime.utc(2026, 8, 3),
        ),
      ],
      passwords: [
        ResourcePasswordEntry(
          id: 'password-1',
          secretKey: 'secret-key-1',
          site: 'Admin',
          loginUrl: 'https://admin.example.com',
          username: 'release@example.com',
          environment: 'staging',
          owner: 'Mobile',
          twoFactorLocation: '1Password',
          tags: const ['admin'],
          updatedAt: DateTime.utc(2026, 8, 3),
        ),
      ],
    );

    final encoded = jsonEncode(bundle.toJson());
    expect(encoded, contains('secret-key-1'));
    expect(encoded, isNot(contains('super-secret-password')));

    final decoded = ResourceCatalogBundle.fromJson(
      jsonDecode(encoded) as Map<String, Object?>,
    );
    expect(decoded.projectPath, r'C:\apps\demo');
    expect(decoded.resources.single.kind, ResourceCatalogKind.figma);
    expect(decoded.passwords.single.username, 'release@example.com');
  });
}
