import 'package:app_release_center/app/models/ch_play_version_snapshot.dart';
import 'package:app_release_center/app/services/ch_play_version_check_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChPlayVersionCheckService', () {
    test('parses latest STORE_CODE_ONLY marker from Fastlane output', () {
      final code = ChPlayVersionCheckService.parseStoreVersionCode('''
Fetching version code
STORE_CODE_ONLY:12
STORE_CODE_ONLY:15
''');

      expect(code, 15);
    });

    test('parses Fastlane current version code success output', () {
      final code = ChPlayVersionCheckService.parseStoreVersionCode(
        "Current version code on (track production): 150",
      );

      expect(code, 150);
    });

    test('returns null when Fastlane output has no clean marker', () {
      final code = ChPlayVersionCheckService.parseStoreVersionCode(
        'Current local version: 1.2.3+12',
      );

      expect(code, isNull);
    });

    test('compares local and store version codes', () {
      expect(
        ChPlayVersionCheckService.compare(10, 12),
        ChPlayComparisonStatus.localBehind,
      );
      expect(
        ChPlayVersionCheckService.compare(12, 10),
        ChPlayComparisonStatus.localAhead,
      );
      expect(
        ChPlayVersionCheckService.compare(12, 12),
        ChPlayComparisonStatus.upToDate,
      );
    });
  });
}
