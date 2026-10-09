// ignore_for_file: invalid_use_of_visible_for_testing_member
// Isolated Windows QA harness. Never opens the user's Plan Studio database or
// writes preferences. Build with: flutter build windows -t tool/plan_reminder_smoke.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_management_center/app/modules/plan_studio/models/work_item.dart';
import 'package:app_management_center/app/modules/plan_studio/repositories/local_plan_repository.dart';
import 'package:app_management_center/app/modules/plan_studio/services/plan_studio_runtime.dart';
import 'package:app_management_center/app/modules/plan_studio/views/plan_studio_view.dart';
import 'package:app_management_center/app/modules/plan_studio/views/reminder_popup_view.dart';
import 'package:app_management_center/app/modules/plan_studio/views/reminder_settings_view.dart';
import 'package:app_management_center/app/modules/plan_studio/views/today_view.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.contains('--plan-reminder-window')) {
    runApp(const ReminderPopupApp());
    return;
  }
  SharedPreferences.setMockInitialValues({});
  final temp = await Directory.systemTemp.createTemp('amc-reminder-qa-');
  final repository = await LocalPlanRepository.open(
    path: '${temp.path}/studio.sqlite',
  );
  final project = await repository.ensureProject(temp.path);
  final plan = await repository.save(
    WorkItem(
      id: 'qa-plan',
      projectId: project.id,
      title: 'Phát hành bản Windows · kiểm tra nhắc hẹn',
      type: WorkType.plan,
      dueAtUtc: DateTime.now()
          .add(const Duration(hours: 1))
          .toUtc()
          .toIso8601String(),
    ),
  );
  for (var n = 0; n < 5; n++) {
    await repository.save(
      WorkItem(
        id: 'qa-task-$n',
        projectId: project.id,
        title: [
          'Kiểm tra bản build',
          'Chốt checklist',
          'Kiểm tra migration',
          'Kiểm tra DPI',
          'Nghiệm thu',
        ][n],
        parentId: plan.id,
        status: n < 3 ? WorkStatus.done : WorkStatus.ready,
      ),
    );
  }
  final runtime = PlanStudioRuntime.forTesting(repository);
  final navigator = GlobalKey<NavigatorState>();
  runApp(
    MaterialApp(
      navigatorKey: navigator,
      theme: AppCyberTheme.themeData(AppThemeChoice.console),
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Plan Studio · dữ liệu QA tạm thời'),
          ),
          body: Padding(
            padding: const EdgeInsets.all(32),
            child: ListView(
              children: [
                Text('Kho thử: ${temp.path}'),
                const SizedBox(height: 16),
                const TextField(
                  decoration: InputDecoration(
                    labelText: 'Gõ tại đây để kiểm tra popup không lấy focus',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () async {
                    final current = (await repository.items()).firstWhere(
                      (i) => i.id == plan.id,
                    );
                    await repository.reminders.add(
                      current.id,
                      current.revision,
                      DateTime.now().add(const Duration(seconds: 8)),
                    );
                  },
                  child: const Text('Nhắc plan sau 8 giây'),
                ),
                OutlinedButton(
                  onPressed: () => runtime.preview(),
                  child: const Text('Thử popup'),
                ),
                OutlinedButton(
                  onPressed: () => runtime.settings(runInTray: true),
                  child: const Text('Bật tray cho phiên QA'),
                ),
                OutlinedButton(
                  onPressed: () => showReminderSettings(context, runtime),
                  child: const Text('Cài đặt nhắc'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlanStudioView(repository: repository),
                    ),
                  ),
                  child: const Text('Mở board QA'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await runtime.start(
    theme: () => 'console',
    onOpen: (id) {
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => id == null
              ? TodayView(repository: repository)
              : PlanStudioView(repository: repository, initialItemId: id),
        ),
      );
    },
  );
}
