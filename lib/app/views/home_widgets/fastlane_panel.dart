part of '../home_view.dart';

class _FastlanePanel extends GetView<HomeController> {
  const _FastlanePanel();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final project = controller.project.value;
      if (project == null) {
        return const _StoreVersionsEmptyState(
          icon: Icons.folder_open_outlined,
          message: 'Chọn một dự án',
        );
      }

      if (project.fastlaneLanes.isEmpty) {
        return const _StoreVersionsEmptyState(
          icon: Icons.alt_route_outlined,
          message: 'Không tìm thấy lane Fastlane nào',
        );
      }

      return GridView.builder(
        padding: EdgeInsets.zero,
        itemCount: project.fastlaneLanes.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 245,
          mainAxisExtent: 152,
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
      final palette = AppCyberTheme.palette;
      final accent = lane.platform == 'ios'
          ? palette.info
          : lane.platform == 'android'
          ? palette.success
          : palette.accent;

      return _HudCardShell(
        active: isActive,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: Icon(
                    lane.platform == 'ios'
                        ? Icons.apple
                        : lane.platform == 'android'
                        ? Icons.android_outlined
                        : Icons.alt_route_outlined,
                    size: 17,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 9),
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
              style: AppCyberTheme.uiTextStyle(
                size: 11.8,
                color: AppCyberTheme.textMuted,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: palette.base.withValues(
                        alpha: palette.isDark ? 0.42 : 0.65,
                      ),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      lane.command,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppCyberTheme.dataTextStyle(
                        size: 10.6,
                        color: AppCyberTheme.textMuted,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Chạy ${lane.command}',
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
                      : const Icon(Icons.play_arrow_rounded),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}
