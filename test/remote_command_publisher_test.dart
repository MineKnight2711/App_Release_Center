import 'dart:async';
import 'dart:convert';

import 'package:app_management_center/app/services/remote_command_publisher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'bounds huge git output and preserves the final error and result',
    () async {
      Map<String, Object?>? received;
      final publisher = RemoteCommandPublisher(
        send: (_, body) async {
          received = body;
        },
      );
      final logs = [
        'Xcode archive done.',
        List.filled(100000, 'ios/Đường dẫn\u0000').join(),
        'Lệnh từ xa lỗi: Source thay đổi trong lúc build.',
      ];
      final result = {
        'run': {'status': 'failed', 'message': logs.last},
      };
      await publisher.publish('build', {
        'status': 'failed',
        'logLines': logs,
        'result': result,
      });
      expect(
        utf8.encode(jsonEncode(received!['logLines'])).length,
        lessThanOrEqualTo(24 * 1024),
      );
      expect((received!['logLines'] as List).last, logs.last);
      expect(received!['result'], result);
      expect(logs[1].length, greaterThan(100000));
    },
  );

  test('bounds many escaped Unicode lines by encoded size', () {
    final logs = List.generate(
      600,
      (i) => '$i ${List.filled(2000, '😀\u0000').join()}',
    );
    final tail = RemoteCommandPublisher.logTail(logs);
    expect(tail, isNotEmpty);
    expect(tail.length, lessThanOrEqualTo(500));
    expect(utf8.encode(jsonEncode(tail)).length, lessThanOrEqualTo(24 * 1024));
    expect(tail.last, startsWith('599 '));
    expect(tail.last, contains('log đã rút gọn'));
  });

  test(
    'finishing waits for in-flight progress before publishing failure',
    () async {
      final progress = Completer<void>();
      final events = <String>[];
      final publisher = RemoteCommandPublisher(
        send: (_, body) async {
          if (body['status'] == 'running') await progress.future;
          events.add(body['status']! as String);
        },
      );
      final running = publisher.publish('build', {'status': 'running'});
      final failed = publisher.publish('build', {'status': 'failed'});
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      progress.complete();
      await Future.wait([running, failed]);
      expect(events, ['running', 'failed']);
    },
  );

  test(
    'a rejected progress update cannot block the terminal snapshot',
    () async {
      final events = <String>[];
      final publisher = RemoteCommandPublisher(
        send: (_, body) async {
          if (body['status'] == 'running') {
            throw StateError('network unavailable');
          }
          events.add(body['status']! as String);
        },
      );
      await expectLater(
        publisher.publish('build', {'status': 'running'}),
        throwsStateError,
      );
      await publisher.publish('build', {'status': 'failed'});
      expect(events, ['failed']);
    },
  );

  test('retries terminal receipts after a transient relay failure', () async {
    var attempts = 0;
    final publisher = RemoteCommandPublisher(
      send: (_, body) async {
        if (++attempts < 2) throw StateError('relay unavailable');
      },
    );
    await publisher.publish('build', {'status': 'failed'});
    expect(attempts, 2);
  });
}
