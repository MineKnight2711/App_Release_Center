import 'package:app_management_center/app/services/release_runner_service.dart';
import 'package:app_management_center/app/views/home_view.dart';
import 'package:app_management_center/app/views/pause_motion_when_inactive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PauseMotionWhenInactive', () {
    tearDown(() {
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
    });

    testWidgets('asks for reduced motion only while the window is inactive', (
      tester,
    ) async {
      final seen = <bool>[];
      await tester.pumpWidget(
        PauseMotionWhenInactive(
          child: Builder(
            builder: (context) {
              seen.add(MediaQuery.disableAnimationsOf(context));
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(seen.last, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(seen.last, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(seen.last, isFalse);
    });

    testWidgets('keeps what the user typed across a focus change', (
      tester,
    ) async {
      final text = TextEditingController();
      addTearDown(text.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => PauseMotionWhenInactive(child: child!),
          home: Scaffold(body: _StatefulField(controller: text)),
        ),
      );
      await tester.enterText(find.byType(TextField), 'y');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(_StatefulField.mounts, 1);
      expect(find.text('y'), findsOneWidget);
    });
  });

  group('GlobalCommandProgress', () {
    Future<ReleaseRunnerService> pumpRunning(
      WidgetTester tester, {
      required bool disableAnimations,
    }) async {
      final runner = ReleaseRunnerService();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
          home: Scaffold(
            bottomNavigationBar: GlobalCommandProgress(runner: runner),
          ),
        ),
      );
      runner.beginWorkflow(totalSteps: 2, label: 'Build');
      runner.beginWorkflowStep('Build release APK');
      await tester.pump();
      // Let the progress tween finish; only a looping animation is left.
      await tester.pump(const Duration(seconds: 1));
      return runner;
    }

    testWidgets('loops the charge wave while a command runs', (tester) async {
      final runner = await pumpRunning(tester, disableAnimations: false);
      expect(tester.binding.hasScheduledFrame, isTrue);

      runner.finishWorkflow(success: true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('draws no frames under reduced motion, yet shows progress', (
      tester,
    ) async {
      final runner = await pumpRunning(tester, disableAnimations: true);
      expect(tester.binding.hasScheduledFrame, isFalse);

      runner.completeWorkflowStep(success: true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('BƯỚC 1/2  |  50%'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}

class _StatefulField extends StatefulWidget {
  const _StatefulField({required this.controller});

  final TextEditingController controller;
  static int mounts = 0;

  @override
  State<_StatefulField> createState() => _StatefulFieldState();
}

class _StatefulFieldState extends State<_StatefulField> {
  @override
  void initState() {
    super.initState();
    _StatefulField.mounts++;
  }

  @override
  Widget build(BuildContext context) =>
      TextField(controller: widget.controller);
}
