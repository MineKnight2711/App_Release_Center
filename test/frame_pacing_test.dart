import 'package:app_management_center/app/views/frame_pacing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Duration ms(int value) => Duration(milliseconds: value);

  FramePacer pacer() =>
      FramePacer(unattendedInterval: ms(33), inputGrace: ms(1000));

  test('draws the first frame at once', () {
    expect(pacer().delayFor(ms(5000)), Duration.zero);
  });

  test('holds an animation frame until its slot comes round', () {
    final pacing = pacer()..frameStarted(ms(1000));

    // The next vsync of a 240 Hz panel is far too soon.
    expect(pacing.delayFor(ms(1004)), ms(29));
    expect(pacing.delayFor(ms(1033)), Duration.zero);
    expect(pacing.delayFor(ms(1500)), Duration.zero);
  });

  test('keeps the display rate while the user is interacting', () {
    final pacing = pacer()
      ..frameStarted(ms(1000))
      ..inputReceived(ms(1002));

    expect(pacing.delayFor(ms(1004)), Duration.zero);

    // Still unpaced while the fling after a scroll gesture plays out.
    pacing.frameStarted(ms(1900));
    expect(pacing.delayFor(ms(1904)), Duration.zero);

    // Once input has gone quiet, animation frames are paced again.
    pacing.frameStarted(ms(2100));
    expect(pacing.delayFor(ms(2104)), ms(29));
  });
}
