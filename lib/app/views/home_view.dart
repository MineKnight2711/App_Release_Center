import 'package:app_release_center/app/controllers/home_controller.dart';
import 'package:app_release_center/app/models/release_project.dart';
import 'package:app_release_center/app/models/release_script.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

part 'home_widgets/flow_panel.dart';
part 'home_widgets/log_panel.dart';
part 'home_widgets/main_panel.dart';
part 'home_widgets/options_panel.dart';
part 'home_widgets/project_panel.dart';
part 'home_widgets/shared_widgets.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Release Center'),
        centerTitle: false,
        actions: [
          Obx(
            () => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _StatusPill(
                label: controller.runner.status.value,
                running: controller.runner.isRunning.value,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1180;
            final content = isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(width: 340, child: _ProjectPanel()),
                      const SizedBox(width: 16),
                      const Expanded(child: _MainPanel()),
                      const SizedBox(width: 16),
                      const SizedBox(width: 340, child: _OptionsPanel()),
                    ],
                  )
                : const SingleChildScrollView(
                    child: Column(
                      children: [
                        _ProjectPanel(),
                        SizedBox(height: 16),
                        SizedBox(height: 520, child: _MainPanel()),
                        SizedBox(height: 16),
                        _OptionsPanel(),
                      ],
                    ),
                  );

            return Padding(padding: const EdgeInsets.all(16), child: content);
          },
        ),
      ),
    );
  }
}
