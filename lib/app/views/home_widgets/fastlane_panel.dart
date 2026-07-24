part of '../home_view.dart';

class _FastlanePanel extends GetView<HomeController> {
  const _FastlanePanel();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final project = controller.project.value;
      if (project == null) {
        return const Center(child: Text('Choose a project'));
      }

      if (project.fastlaneLanes.isEmpty) {
        return const Center(child: Text('No Fastlane lanes found'));
      }

      return GridView.builder(
        padding: EdgeInsets.zero,
        itemCount: project.fastlaneLanes.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          mainAxisExtent: 148,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemBuilder: (context, index) {
          return _FastlaneLaneCard(lane: project.fastlaneLanes[index]);
        },
      );
    });
  }
}

class _FastlaneLaneCard extends GetView<HomeController> {
  const _FastlaneLaneCard({required this.lane});

  final ReleaseFastlaneLane lane;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isRunning = controller.runner.isBusy;
      final isActive = controller.runner.activeScriptPath.value == lane.key;

      return _HudCardShell(
        active: isActive,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.alt_route_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lane.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              lane.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    lane.command,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppCyberTheme.dataTextStyle(
                      size: 10.8,
                      color: AppCyberTheme.textMuted,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Run ${lane.command}',
                  visualDensity: VisualDensity.compact,
                  onPressed: isRunning
                      ? null
                      : () => controller.runFastlaneLane(lane),
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
      );
    });
  }
}
