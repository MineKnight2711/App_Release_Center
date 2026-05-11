part of '../home_view.dart';

class _FlowPanel extends GetView<HomeController> {
  const _FlowPanel();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(icon: Icons.account_tree, title: 'CI/CD Flow'),
          const SizedBox(height: 12),
          Expanded(
            child: Obx(() {
              final project = controller.project.value;
              if (project == null) {
                return const Center(child: Text('Choose a project'));
              }

              if (project.scripts.isEmpty) {
                return const Center(child: Text('No auto tools found'));
              }

              return GridView.builder(
                itemCount: project.scripts.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 240,
                  mainAxisExtent: 156,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemBuilder: (context, index) {
                  return _ScriptCard(script: project.scripts[index]);
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _ScriptCard extends GetView<HomeController> {
  const _ScriptCard({required this.script});

  final ReleaseScript script;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Obx(() {
      final isRunning = controller.runner.isRunning.value;
      final isActive = controller.runner.activeScriptPath.value == script.path;

      return Card(
        color: isActive ? colorScheme.tertiaryContainer : colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_iconFor(script.kind), size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      script.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                script.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      script.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Run ${script.label}',
                    onPressed: isRunning
                        ? null
                        : () => controller.runScript(script),
                    icon: isActive
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }

  IconData _iconFor(ReleaseScriptKind kind) {
    return switch (kind) {
      ReleaseScriptKind.release => Icons.rocket_launch,
      ReleaseScriptKind.versionCode => Icons.pin,
      ReleaseScriptKind.versionName => Icons.sell,
      ReleaseScriptKind.commit => Icons.commit,
      ReleaseScriptKind.merge => Icons.call_merge,
      ReleaseScriptKind.deploy => Icons.cloud_upload,
      ReleaseScriptKind.imageValidation => Icons.image_search,
      ReleaseScriptKind.shell => Icons.terminal,
      ReleaseScriptKind.dartTool => Icons.data_object,
    };
  }
}
