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
              const _RemoteControlOptions(),
              const Divider(height: 28),
              const _NotificationOptions(),
              const Divider(height: 28),
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

class _RemoteControlOptions extends GetView<HomeController> {
  const _RemoteControlOptions();

  RemoteControlService get remote => Get.find<RemoteControlService>();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final settings = remote.settings.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(
            icon: Icons.settings_remote_outlined,
            title: 'Remote Control',
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: settings.enabled,
            onChanged: remote.setEnabled,
            contentPadding: EdgeInsets.zero,
            title: const Text('Phone command relay'),
            subtitle: Text(remote.agentStatus.value),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _showControlPairingDialog(context),
                icon: const Icon(Icons.qr_code_2_outlined),
                label: const Text('Pair control app'),
              ),
              OutlinedButton.icon(
                onPressed: () => _showAllowedRootsDialog(context),
                icon: const Icon(Icons.folder_special_outlined),
                label: const Text('Allowed roots'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _HudCardShell(
            active: settings.enabled,
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 17,
                  color: settings.enabled
                      ? AppCyberTheme.neonGreen
                      : AppCyberTheme.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    settings.allowedRoots.isEmpty
                        ? 'Shell is limited to recent project folders.'
                        : 'Shell roots: ${settings.allowedRoots.length}',
                    style: AppCyberTheme.dataTextStyle(
                      size: 10.8,
                      color: AppCyberTheme.textMuted,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  Future<void> _showControlPairingDialog(BuildContext context) async {
    final session = await controller.createPhonePairing();
    if (session == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _PhonePairingDialog(session: session),
    );
  }

  Future<void> _showAllowedRootsDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _AllowedRootsDialog(),
    );
  }
}

class _AllowedRootsDialog extends StatefulWidget {
  const _AllowedRootsDialog();

  @override
  State<_AllowedRootsDialog> createState() => _AllowedRootsDialogState();
}

class _AllowedRootsDialogState extends State<_AllowedRootsDialog> {
  late final TextEditingController _controller;

  RemoteControlService get remote => Get.find<RemoteControlService>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: remote.settings.value.allowedRoots.join('\n'),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppCyberTheme.panelBackgroundStrong,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: AppCyberTheme.isCyber
              ? AppCyberTheme.electricBlue.withValues(alpha: 0.4)
              : AppCyberTheme.lineBlue,
        ),
      ),
      title: const _PanelTitle(
        icon: Icons.folder_special_outlined,
        title: 'Allowed Roots',
      ),
      content: SizedBox(
        width: 460,
        child: TextField(
          controller: _controller,
          minLines: 6,
          maxLines: 10,
          style: AppCyberTheme.dataTextStyle(
            size: 11.5,
            color: AppCyberTheme.textPrimary,
          ),
          decoration: const InputDecoration(
            labelText: 'One folder per line',
            alignLabelWithHint: true,
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await remote.saveAllowedRoots(
              _controller.text.split(RegExp(r'\r?\n')),
            );
            if (context.mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save'),
        ),
      ],
    );
  }
}

class _NotificationOptions extends GetView<HomeController> {
  const _NotificationOptions();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final settings = controller.notificationSettings.value;
      final devices = controller.linkedNotificationDevices.toList();
      final selectedDeviceIds = settings.selectedDeviceIds.toSet();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(
            icon: Icons.notifications_active_outlined,
            title: 'Notifications',
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: settings.enabled,
            onChanged: controller.setNotificationsEnabled,
            contentPadding: EdgeInsets.zero,
            title: const Text('Command notifications'),
            subtitle: const Text('Send command status to selected phones.'),
          ),
          TextField(
            controller: controller.notificationEndpointController,
            style: AppCyberTheme.dataTextStyle(
              size: 11.5,
              color: AppCyberTheme.textPrimary,
            ),
            decoration: const InputDecoration(
              labelText: 'Serverless endpoint',
              hintText: 'https://your-site.web.app/api',
              prefixIcon: Icon(Icons.cloud_queue_outlined),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller.notificationTokenController,
            obscureText: true,
            style: AppCyberTheme.dataTextStyle(
              size: 11.5,
              color: AppCyberTheme.textPrimary,
            ),
            decoration: const InputDecoration(
              labelText: 'Desktop API token',
              prefixIcon: Icon(Icons.key_outlined),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: controller.saveNotificationConfiguration,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
              ),
              FilledButton.icon(
                onPressed: () => _showPhonePairingDialog(context),
                icon: const Icon(Icons.qr_code_2_outlined),
                label: const Text('Link phone'),
              ),
              OutlinedButton.icon(
                onPressed: controller.isLoadingNotificationDevices.value
                    ? null
                    : controller.refreshLinkedNotificationDevices,
                icon: controller.isLoadingNotificationDevices.value
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_outlined),
                label: const Text('Refresh devices'),
              ),
              OutlinedButton.icon(
                onPressed: settings.hasSelectedDevices
                    ? controller.sendTestNotification
                    : null,
                icon: const Icon(Icons.send_to_mobile_outlined),
                label: const Text('Test'),
              ),
            ],
          ),
          if (controller.notificationStatus.value.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              controller.notificationStatus.value,
              style: AppCyberTheme.dataTextStyle(
                size: 10.8,
                color: AppCyberTheme.textMuted,
                weight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (devices.isEmpty)
            Text(
              'No linked phones',
              style: AppCyberTheme.dataTextStyle(
                size: 11,
                color: AppCyberTheme.textMuted,
              ),
            )
          else
            Column(
              children: devices.map((device) {
                final selected = selectedDeviceIds.contains(device.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _HudCardShell(
                    active: selected,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 7,
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: selected,
                          onChanged: (value) =>
                              controller.toggleNotificationDevice(
                                device.id,
                                value ?? false,
                              ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.phone_iphone_outlined,
                          size: 18,
                          color: selected
                              ? AppCyberTheme.neonGreen
                              : AppCyberTheme.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppCyberTheme.dataTextStyle(
                                  size: 11.4,
                                  color: AppCyberTheme.textPrimary,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                device.detail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppCyberTheme.dataTextStyle(
                                  size: 10.4,
                                  color: AppCyberTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Unlink phone',
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              controller.unlinkNotificationDevice(device),
                          icon: const Icon(Icons.link_off_outlined),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      );
    });
  }

  Future<void> _showPhonePairingDialog(BuildContext context) async {
    final session = await controller.createPhonePairing();
    if (session == null || !context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => _PhonePairingDialog(session: session),
    );
  }
}

class _PhonePairingDialog extends StatefulWidget {
  const _PhonePairingDialog({required this.session});

  final NotificationPairingSession session;

  @override
  State<_PhonePairingDialog> createState() => _PhonePairingDialogState();
}

class _PhonePairingDialogState extends State<_PhonePairingDialog> {
  Timer? _pollTimer;
  Timer? _countdownTimer;
  bool _isPolling = false;
  NotificationPairingStatus _status = NotificationPairingStatus.pending;
  LinkedNotificationDevice? _device;
  Duration _initialRemaining = Duration.zero;
  Duration _remaining = Duration.zero;

  HomeController get controller => Get.find<HomeController>();

  @override
  void initState() {
    super.initState();
    _remaining = _remainingUntilExpiry();
    _initialRemaining = _remaining;
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _syncRemaining(),
    );
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    unawaited(_poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch (_status) {
      NotificationPairingStatus.pending => 'Waiting for phone',
      NotificationPairingStatus.linked => 'Linked ${_device?.label ?? ''}',
      NotificationPairingStatus.expired => 'Pairing expired',
    };
    final countdownLabel = _status == NotificationPairingStatus.linked
        ? 'Linked'
        : _status == NotificationPairingStatus.expired
        ? 'Expired'
        : 'Expires in ${_formatRemaining(_remaining)}';
    final countdownColor = _status == NotificationPairingStatus.linked
        ? AppCyberTheme.neonGreen
        : _status == NotificationPairingStatus.expired
        ? Theme.of(context).colorScheme.error
        : _isExpiringSoon
        ? const Color(0xFFF79009)
        : AppCyberTheme.electricBlue;

    return AlertDialog(
      backgroundColor: AppCyberTheme.panelBackgroundStrong,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: AppCyberTheme.isCyber
              ? AppCyberTheme.electricBlue.withValues(alpha: 0.4)
              : AppCyberTheme.lineBlue,
        ),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      title: const _PanelTitle(
        icon: Icons.qr_code_2_outlined,
        title: 'Link Phone',
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: widget.session.pairingUrl,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(color: Colors.black),
                  dataModuleStyle: const QrDataModuleStyle(color: Colors.black),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SelectableText(
              widget.session.pairingCode,
              style: AppCyberTheme.dataTextStyle(
                size: 26,
                color: AppCyberTheme.textPrimary,
                weight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            _MetaChip(
              icon: _status == NotificationPairingStatus.linked
                  ? Icons.check_circle_outline
                  : _status == NotificationPairingStatus.expired
                  ? Icons.error_outline
                  : Icons.hourglass_top_outlined,
              label: statusLabel,
              highlighted: _status == NotificationPairingStatus.linked,
            ),
            const SizedBox(height: 10),
            _PairingCountdown(
              label: countdownLabel,
              progress: _countdownProgress,
              color: countdownColor,
            ),
            const SizedBox(height: 10),
            SelectableText(
              widget.session.pairingUrl,
              maxLines: 2,
              style: AppCyberTheme.dataTextStyle(
                size: 10.8,
                color: AppCyberTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: widget.session.pairingUrl));
          },
          icon: const Icon(Icons.content_copy_outlined),
          label: const Text('Copy link'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_outlined),
          label: const Text('Close'),
        ),
      ],
    );
  }

  bool get _isExpiringSoon =>
      _status == NotificationPairingStatus.pending &&
      _remaining <= const Duration(seconds: 60);

  double get _countdownProgress {
    if (_status == NotificationPairingStatus.linked) return 1;
    final totalMillis = _initialRemaining.inMilliseconds;
    if (totalMillis <= 0) return 0;
    return (_remaining.inMilliseconds / totalMillis).clamp(0.0, 1.0).toDouble();
  }

  void _syncRemaining({bool expireWhenElapsed = true}) {
    final clamped = _remainingUntilExpiry();
    if (!mounted) {
      _remaining = clamped;
      return;
    }

    setState(() {
      _remaining = clamped;
      if (expireWhenElapsed &&
          clamped == Duration.zero &&
          _status == NotificationPairingStatus.pending) {
        _status = NotificationPairingStatus.expired;
      }
    });

    if (_status == NotificationPairingStatus.expired) {
      _pollTimer?.cancel();
      _countdownTimer?.cancel();
    }
  }

  Duration _remainingUntilExpiry() {
    final nextRemaining = widget.session.expiresAt.difference(DateTime.now());
    return nextRemaining.isNegative ? Duration.zero : nextRemaining;
  }

  Future<void> _poll() async {
    if (_isPolling || _status != NotificationPairingStatus.pending) return;
    _isPolling = true;
    try {
      final result = await controller.pollPhonePairing(
        widget.session.pairingId,
      );
      if (!mounted || result == null) return;
      if (_status == NotificationPairingStatus.expired &&
          result.status == NotificationPairingStatus.pending) {
        return;
      }

      setState(() {
        _status = result.status;
        _device = result.device;
      });

      if (result.status != NotificationPairingStatus.pending) {
        _pollTimer?.cancel();
        _countdownTimer?.cancel();
      }
      if (result.status == NotificationPairingStatus.linked && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (mounted) Navigator.of(context).pop();
      }
    } finally {
      _isPolling = false;
    }
  }
}

class _PairingCountdown extends StatelessWidget {
  const _PairingCountdown({
    required this.label,
    required this.progress,
    required this.color,
  });

  final String label;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _HudCardShell(
      active: true,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 15, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppCyberTheme.dataTextStyle(
                    size: 11,
                    color: AppCyberTheme.textPrimary,
                    weight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: progress,
              color: color,
              backgroundColor: color.withValues(alpha: 0.16),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatRemaining(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (duration.inHours > 0) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
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
