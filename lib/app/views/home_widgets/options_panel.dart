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
              const _PanelTitle(icon: Icons.tune, title: 'Options'),
              const SizedBox(height: 12),
              if (project?.hasPlayReleaseTools ?? false) ...[
                CheckboxListTile(
                  value: controller.includePlayUpload.value,
                  onChanged: (value) {
                    controller.includePlayUpload.value = value ?? false;
                  },
                  contentPadding: EdgeInsets.zero,
                  title: const Text('CH Play upload'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                AnimatedOpacity(
                  opacity: controller.includePlayUpload.value ? 1 : 0.55,
                  duration: const Duration(milliseconds: 160),
                  child: TextField(
                    controller: controller.releaseNotesController,
                    enabled: controller.includePlayUpload.value,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Release notes',
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                if (project?.imageValidator != null) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: controller.validatePlayImages.value,
                    onChanged: controller.includePlayUpload.value
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
                      icon: const Icon(Icons.image_search),
                      label: const Text('Validate images'),
                    ),
                  ),
                ],
                const Divider(height: 28),
              ],
              TextField(
                controller: controller.customArgsController,
                decoration: const InputDecoration(
                  labelText: 'Custom script arguments',
                  prefixIcon: Icon(Icons.code),
                ),
              ),
              const SizedBox(height: 16),
              const _PanelTitle(icon: Icons.keyboard, title: 'Input'),
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
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Clear log'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: controller.runner.isRunning.value
                          ? controller.stopRun
                          : null,
                      icon: const Icon(Icons.stop),
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
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prompt,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => controller.sendYesNoInput(false),
                  icon: const Icon(Icons.close),
                  label: const Text('No'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => controller.sendYesNoInput(true),
                  icon: const Icon(Icons.check),
                  label: const Text('Yes'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
