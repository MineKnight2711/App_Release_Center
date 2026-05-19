part of '../home_view.dart';

class _OptionsPanel extends GetView<HomeController> {
  const _OptionsPanel();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Obx(() {
        final project = controller.project.value;

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PanelTitle(icon: Icons.tune_outlined, title: 'Options'),
              const SizedBox(height: 12),
              if (project?.hasFirebaseDeployTools ?? false) ...[
                CheckboxListTile(
                  value: controller.includeFirebaseDeploy.value,
                  onChanged: (value) {
                    controller.includeFirebaseDeploy.value = value ?? true;
                  },
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Firebase App Distribution'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
              if (project?.hasPlayReleaseTools ?? false) ...[
                Text(
                  'CH Play upload',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<PlayUploadChoice>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: PlayUploadChoice.ask,
                        icon: Icon(Icons.help_outline),
                        label: Text('Ask'),
                      ),
                      ButtonSegment(
                        value: PlayUploadChoice.upload,
                        icon: Icon(Icons.cloud_upload_outlined),
                        label: Text('Upload'),
                      ),
                      ButtonSegment(
                        value: PlayUploadChoice.skip,
                        icon: Icon(Icons.block_outlined),
                        label: Text('Skip'),
                      ),
                    ],
                    selected: {controller.playUploadChoice.value},
                    onSelectionChanged: (selected) {
                      controller.playUploadChoice.value = selected.first;
                    },
                  ),
                ),
                const SizedBox(height: 10),
                AnimatedOpacity(
                  opacity:
                      controller.playUploadChoice.value == PlayUploadChoice.skip
                      ? 0.55
                      : 1,
                  duration: const Duration(milliseconds: 160),
                  child: TextField(
                    controller: controller.releaseNotesController,
                    enabled:
                        controller.playUploadChoice.value !=
                        PlayUploadChoice.skip,
                    maxLines: 5,
                    style: AppCyberTheme.dataTextStyle(
                      size: 11.5,
                      color: AppCyberTheme.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Release notes',
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: controller.uploadPlayListingImages.value,
                  onChanged:
                      controller.playUploadChoice.value != PlayUploadChoice.skip
                      ? (value) {
                          controller.uploadPlayListingImages.value =
                              value ?? true;
                        }
                      : null,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Upload Play images and app icon'),
                  subtitle: const Text(
                    'Includes icon, feature graphic, and screenshots.',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (project?.imageValidator != null) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: controller.validatePlayImages.value,
                    onChanged:
                        controller.playUploadChoice.value !=
                                PlayUploadChoice.skip &&
                            controller.uploadPlayListingImages.value
                        ? (value) {
                            controller.validatePlayImages.value = value ?? true;
                          }
                        : null,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Validate Play images first'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: controller.runner.isRunning.value
                          ? null
                          : controller.validateImages,
                      icon: const Icon(Icons.image_search_outlined),
                      label: const Text('Validate images'),
                    ),
                  ),
                ],
                const Divider(height: 28),
              ],
              TextField(
                controller: controller.customArgsController,
                style: AppCyberTheme.dataTextStyle(
                  size: 11.5,
                  color: AppCyberTheme.textPrimary,
                ),
                decoration: const InputDecoration(
                  labelText: 'Custom script arguments',
                  prefixIcon: Icon(Icons.code_outlined),
                ),
              ),
              const SizedBox(height: 16),
              const _PanelTitle(icon: Icons.keyboard_outlined, title: 'Input'),
              const SizedBox(height: 10),
              if (controller.runner.yesNoPrompt.value != null)
                _YesNoPromptActions(
                  prompt: controller.runner.yesNoPrompt.value!,
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller.stdinController,
                        enabled: controller.runner.isRunning.value,
                        onSubmitted: (_) => controller.sendInput(),
                        style: AppCyberTheme.dataTextStyle(
                          size: 11.5,
                          color: AppCyberTheme.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Send to script',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Send input',
                      onPressed: controller.runner.isRunning.value
                          ? controller.sendInput
                          : null,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: controller.clearLog,
                      icon: const Icon(Icons.clear_all_outlined),
                      label: const Text('Clear log'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: controller.runner.isRunning.value
                          ? controller.stopRun
                          : null,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Stop'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _YesNoPromptActions extends GetView<HomeController> {
  const _YesNoPromptActions({required this.prompt});

  final String prompt;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: _HudCardShell(
        active: true,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              prompt,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppCyberTheme.dataTextStyle(
                size: 11.2,
                color: AppCyberTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => controller.sendYesNoInput(false),
                    icon: const Icon(Icons.close_outlined),
                    label: const Text('No'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => controller.sendYesNoInput(true),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Yes'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
