part of '../home_view.dart';

class _ProjectPanel extends GetView<HomeController> {
  const _ProjectPanel();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite;

        return _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PanelTitle(
                icon: Icons.folder_open_outlined,
                title: 'Project',
              ),
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
              if (hasBoundedHeight)
                const Expanded(child: _RecentProjectsList())
              else
                const SizedBox(height: 420, child: _RecentProjectsList()),
            ],
          ),
        );
      },
    );
  }
}

class _RecentProjectsList extends StatefulWidget {
  const _RecentProjectsList();

  @override
  State<_RecentProjectsList> createState() => _RecentProjectsListState();
}

class _RecentProjectsListState extends State<_RecentProjectsList> {
  final _scrollController = ScrollController();

  HomeController get controller => Get.find<HomeController>();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.recentPaths.isEmpty) {
        return const Center(child: Text('No saved projects'));
      }

      return Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.only(right: 10, bottom: 4),
          itemCount: controller.recentPaths.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final path = controller.recentPaths[index];
            return _RecentProjectTile(path: path);
          },
        ),
      );
    });
  }
}

enum _RecentProjectAction { remove }

class _RecentProjectTile extends GetView<HomeController> {
  const _RecentProjectTile({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final selected =
          controller.project.value?.path.toLowerCase() == path.toLowerCase();

      return GestureDetector(
        onSecondaryTapDown: (details) => _showContextMenu(context, details),
        child: Material(
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
                  const SizedBox(width: 6),
                  Icon(
                    Icons.more_vert,
                    size: 16,
                    color: AppCyberTheme.textMuted.withValues(alpha: 0.72),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Future<void> _showContextMenu(
    BuildContext context,
    TapDownDetails details,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<_RecentProjectAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(details.globalPosition, details.globalPosition),
        Offset.zero & overlay.size,
      ),
      color: AppCyberTheme.panelBackgroundStrong.withValues(alpha: 0.96),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: AppCyberTheme.isCyber
              ? AppCyberTheme.electricBlue.withValues(alpha: 0.42)
              : AppCyberTheme.lineBlue,
        ),
      ),
      items: const [
        PopupMenuItem(
          value: _RecentProjectAction.remove,
          child: Row(
            children: [
              Icon(Icons.remove_circle_outline, size: 18),
              SizedBox(width: 10),
              Text('Remove from recent'),
            ],
          ),
        ),
      ],
    );

    if (action == _RecentProjectAction.remove) {
      await controller.removeRecentProject(path);
    }
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
