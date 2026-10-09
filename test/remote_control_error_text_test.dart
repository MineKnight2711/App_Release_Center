import 'package:app_management_center/app/models/remote_control.dart';
import 'package:flutter_test/flutter_test.dart';

/// The relay answers in English and states only the rule it enforced. Both of
/// the messages below describe a setup step rather than a fault to wait out,
/// and both cost real debugging time before they said so.
void main() {
  group('scope refusal', () {
    // Verbatim from the relay, via the phone's own error wrapper.
    const refusal =
        'enqueue command lỗi: This device is not allowed to send power '
        'commands.';

    test('explains that permissions are fixed at pairing time', () {
      final text = explainRemoteControlError(refusal);

      expect(text, contains(refusal), reason: 'keep the original wording too');
      expect(text, contains('Quyền chốt tại lúc ghép'));
      expect(text, contains('ghép lại điện thoại'));
    });

    test('covers the other scoped command types too', () {
      for (final kind in ['power', 'window', 'unlock']) {
        final text = explainRemoteControlError(
          'This device is not allowed to send $kind commands.',
        );
        expect(text, contains('ghép lại điện thoại'), reason: kind);
      }
    });
  });

  group('pairing refusal', () {
    test('names both causes, since the relay only implies expiry', () {
      final text = explainRemoteControlError(
        'link device lỗi: Pairing session is invalid or expired.',
      );

      expect(text, contains('10 phút'));
      expect(text, contains('endpoint'));
    });
  });

  test('anything else is passed through untouched', () {
    for (final message in [
      'HTTP 500',
      'SocketException: Connection refused',
      '',
    ]) {
      expect(explainRemoteControlError(message), message);
    }
  });
}
