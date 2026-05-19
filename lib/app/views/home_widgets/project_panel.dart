part of '../home_view.dart';

class _ProjectPanel extends GetView<HomeController> {
  const _ProjectPanel();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(icon: Icons.folder_open_outlined, title: 'Project'),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: controller.pickProjectDirectory,
              icon: const Icon(Icons.drive_folder_upload_outlined),
              label: const Text('Choose directory'),
            ),
          ),
          const SizedBox(height: 16),
          Obx(() {
            final project = controller.project.value;
            final error = controller.projectError.value;

            if (controller.isLoadingProject.value) {
              return const LinearProgressIndicator();
            }

            if (project == null) {
              return Text(
                error.isEmpty ? 'No project selected' : error,
                style: TextStyle(
                  color: error.isEmpty
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.error,
                ),
              );
            }

            return _ProjectSummary(project: project);
          }),
          const SizedBox(height: 20),
          const _PanelTitle(icon: Icons.history_outlined, title: 'Recent'),
          const SizedBox(height: 8),
          SizedBox(
            height: 260,
            child: Obx(() {
              if (controller.recentPaths.isEmpty) {
                return const Center(child: Text('No saved projects'));
              }

              return ListView.separated(
                itemCount: controller.recentPaths.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final path = controller.recentPaths[index];
                  return _RecentProjectTile(path: path);
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _ProjectSummary extends StatelessWidget {
  const _ProjectSummary({required this.project});

  final ReleaseProject project;

  @override
  Widget build(BuildContext context) {
    return _HudCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            project.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            project.path,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppCyberTheme.dataTextStyle(
              size: 11.2,
              color: AppCyberTheme.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(
                icon: Icons.terminal_outlined,
                label: '${project.scripts.length} auto tools',
              ),
              if (project.fastlaneLanes.isNotEmpty)
                _MetaChip(
                  icon: Icons.alt_route_outlined,
                  label: '${project.fastlaneLanes.length} fastlane lanes',
                ),
              if (project.pubspecVersion != null)
                _MetaChip(
                  icon: Icons.sell_outlined,
                  label: project.pubspecVersion!,
                ),
              if (project.hasPlayReleaseTools)
                const _MetaChip(icon: Icons.android_outlined, label: 'CH Play'),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentProjectTile extends GetView<HomeController> {
  const _RecentProjectTile({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final selected =
          controller.project.value?.path.toLowerCase() == path.toLowerCase();

      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => controller.loadProject(path),
          child: _HudCardShell(
            active: selected,
            child: Row(
              children: [
                Icon(
                  selected ? Icons.check_circle : Icons.folder,
                  size: 20,
                  color: selected
                      ? AppCyberTheme.neonGreen
                      : AppCyberTheme.electricBlue.withValues(alpha: 0.82),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.basename(path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Text(
                        path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppCyberTheme.dataTextStyle(
                          size: 10.8,
                          color: AppCyberTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
