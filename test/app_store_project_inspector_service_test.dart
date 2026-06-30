import 'package:app_release_center/app/services/app_store_project_inspector_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppStoreProjectInspectorService', () {
    test('parses pubspec version name and build number', () {
      final version = AppStoreProjectInspectorService.parsePubspecVersion('''
name: sample
version: 2.4.0+108
''');

      expect(version?.name, '2.4.0');
      expect(version?.buildNumber, 108);
      expect(version?.display, '2.4.0+108');
    });

    test('detects first non-test bundle ID and ignores test bundle IDs', () {
      final bundleId = AppStoreProjectInspectorService.parseBundleId(r'''
PRODUCT_BUNDLE_IDENTIFIER = com.example.demo.RunnerTests;
PRODUCT_BUNDLE_IDENTIFIER = com.example.demo;
PRODUCT_BUNDLE_IDENTIFIER = "$(PRODUCT_BUNDLE_IDENTIFIER).RunnerTests";
''');

      expect(bundleId, 'com.example.demo');
    });

    test('keeps multiple non-test app bundle IDs in first-seen order', () {
      final bundleIds = AppStoreProjectInspectorService.parseBundleIds(r'''
PRODUCT_BUNDLE_IDENTIFIER = com.example.first;
PRODUCT_BUNDLE_IDENTIFIER = com.example.second;
PRODUCT_BUNDLE_IDENTIFIER = com.example.first;
PRODUCT_BUNDLE_IDENTIFIER = com.example.secondUITests;
''');

      expect(bundleIds, ['com.example.first', 'com.example.second']);
    });

    test(
      'prefers Runner target bundle IDs when target metadata is present',
      () {
        final bundleId = AppStoreProjectInspectorService.parseBundleId(r'''
AAAA1111 /* Debug Extension */ = {
  isa = XCBuildConfiguration;
  buildSettings = {
    PRODUCT_BUNDLE_IDENTIFIER = com.example.extension;
  };
  name = Debug;
};
BBBB2222 /* Build configuration list for PBXNativeTarget "Runner" */ = {
  isa = XCConfigurationList;
  buildConfigurations = (
    CCCC3333 /* Debug */,
    DDDD4444 /* Release */,
  );
  defaultConfigurationName = Release;
};
CCCC3333 /* Debug */ = {
  isa = XCBuildConfiguration;
  buildSettings = {
    PRODUCT_BUNDLE_IDENTIFIER = com.example.runner;
  };
  name = Debug;
};
DDDD4444 /* Release */ = {
  isa = XCBuildConfiguration;
  buildSettings = {
    PRODUCT_BUNDLE_IDENTIFIER = com.example.runner.release;
  };
  name = Release;
};
''');

        expect(bundleId, 'com.example.runner');
      },
    );
  });
}
