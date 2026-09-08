part of '../../home_view.dart';

class _FlowFinSettingsTab extends StatefulWidget {
  const _FlowFinSettingsTab();

  @override
  State<_FlowFinSettingsTab> createState() => _FlowFinSettingsTabState();
}

class _FlowFinSettingsTabState extends State<_FlowFinSettingsTab> {
  final _displayNameController = TextEditingController();
  final _baseUrlController = TextEditingController();
  String _loadedForUserId = '';

  FlowFinController get controller => Get.find<FlowFinController>();

  @override
  void dispose() {
    _displayNameController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  /// Seeds the text fields once the profile arrives, without clobbering an
  /// edit already in progress.
  void _syncControllers() {
    final user = controller.user.value;
    if (user == null || user.id == _loadedForUserId) return;
    _loadedForUserId = user.id;
    _displayNameController.text = user.displayName;
    _baseUrlController.text = controller.settings.value.baseUrlOverrides[
            controller.environment.id] ??
        '';
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      _syncControllers();
      final user = controller.user.value;
      final prefs = controller.notificationPrefs.value;

      return _FlowFinTabScaffold(
        icon: Icons.tune_outlined,
        title: 'Settings',
        error: controller.accountError.value,
        loading: controller.isSavingAccount.value,
        actions: [
          OutlinedButton.icon(
            key: const Key('flowfin-account-refresh'),
            onPressed: controller.loadAccount,
            icon: const Icon(Icons.refresh_outlined, size: 16),
            label: const Text('Refresh'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PanelTitle(
              icon: Icons.person_outline,
              title: 'Profile',
            ),
            const SizedBox(height: 10),
            if (user != null)
              Text(
                '${user.email}${user.emailVerified ? '' : '  ·  not verified'}',
                style: AppCyberTheme.dataTextStyle(
                  size: 11.5,
                  color: AppCyberTheme.textMuted,
                ),
              ),
            const SizedBox(height: 10),
            SizedBox(
              width: 420,
              child: TextField(
                key: const Key('flowfin-display-name'),
                controller: _displayNameController,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Display name'),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                FilledButton(
                  key: const Key('flowfin-account-save'),
                  onPressed: controller.isSavingAccount.value
                      ? null
                      : () => _flowFinRun(
                          context,
                          () => controller.saveAccount(
                            displayName: _displayNameController.text,
                          ),
                          successMessage: 'Profile saved.',
                        ),
                  child: const Text('Save profile'),
                ),
                const SizedBox(width: 10),
                if (controller.accountStatus.value.isNotEmpty)
                  Text(
                    controller.accountStatus.value,
                    style: AppCyberTheme.dataTextStyle(
                      size: 11,
                      color: AppCyberTheme.neonGreen,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            const _PanelTitle(
              icon: Icons.notifications_active_outlined,
              title: 'Notifications',
            ),
            const SizedBox(height: 6),
            const _FlowFinNotice(
              icon: Icons.info_outline,
              message:
                  'These drive FlowFin\'s own reminders and reports. Nothing '
                  'here touches this app\'s notification relay.',
            ),
            const SizedBox(height: 8),
            if (prefs == null)
              const _FlowFinEmpty(
                icon: Icons.notifications_off_outlined,
                message: 'Preferences not loaded yet.',
              )
            else
              _FlowFinPrefsForm(prefs: prefs, controller: controller),
            const SizedBox(height: 22),
            const _PanelTitle(
              icon: Icons.dns_outlined,
              title: 'Connection',
            ),
            const SizedBox(height: 10),
            Text(
              'Active: ${controller.baseUrl}',
              style: AppCyberTheme.dataTextStyle(
                size: 11.5,
                color: AppCyberTheme.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 520,
              child: TextField(
                key: const Key('flowfin-base-url'),
                controller: _baseUrlController,
                decoration: InputDecoration(
                  labelText:
                      'Override for ${controller.environment.label} (blank = default)',
                  hintText: controller.environment.defaultBaseUrl,
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('flowfin-base-url-save'),
              onPressed: () => controller.setBaseUrl(
                controller.environment,
                _baseUrlController.text,
              ),
              child: const Text('Save endpoint'),
            ),
            const SizedBox(height: 22),
            const _PanelTitle(
              icon: Icons.download_outlined,
              title: 'Your data',
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('flowfin-export'),
              onPressed: () => _export(context),
              icon: const Icon(Icons.file_download_outlined, size: 16),
              label: const Text('Export everything as JSON'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _export(BuildContext context) async {
    try {
      final data = await controller.client.exportMyData();
      final location = await file_selector.getSaveLocation(
        suggestedName:
            'flowfin-export-${FlowFinController.isoDate(DateTime.now())}.json',
      );
      if (location == null) return;

      await File(
        location.path,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Exported to ${location.path}')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(controller.describeError(error))),
      );
    }
  }
}

class _FlowFinPrefsForm extends StatefulWidget {
  const _FlowFinPrefsForm({required this.prefs, required this.controller});

  final FlowFinNotificationPrefs prefs;
  final FlowFinController controller;

  @override
  State<_FlowFinPrefsForm> createState() => _FlowFinPrefsFormState();
}

class _FlowFinPrefsFormState extends State<_FlowFinPrefsForm> {
  late FlowFinNotificationPrefs _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.prefs;
  }

  @override
  void didUpdateWidget(covariant _FlowFinPrefsForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prefs != widget.prefs) _draft = widget.prefs;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: const Key('flowfin-pref-checkin'),
            contentPadding: EdgeInsets.zero,
            value: _draft.checkInReminderEnabled,
            title: const Text('Daily check-in reminder'),
            subtitle: Text('At ${_draft.checkInReminderTime}'),
            onChanged: (value) => setState(
              () => _draft = _draft.copyWith(checkInReminderEnabled: value),
            ),
          ),
          SwitchListTile(
            key: const Key('flowfin-pref-budget'),
            contentPadding: EdgeInsets.zero,
            value: _draft.budgetAlertEnabled,
            title: const Text('Budget alerts'),
            onChanged: (value) => setState(
              () => _draft = _draft.copyWith(budgetAlertEnabled: value),
            ),
          ),
          SwitchListTile(
            key: const Key('flowfin-pref-weekly'),
            contentPadding: EdgeInsets.zero,
            value: _draft.weeklyReportEnabled,
            title: const Text('Weekly report'),
            onChanged: (value) => setState(
              () => _draft = _draft.copyWith(weeklyReportEnabled: value),
            ),
          ),
          SwitchListTile(
            key: const Key('flowfin-pref-monthly'),
            contentPadding: EdgeInsets.zero,
            value: _draft.monthlyReportEnabled,
            title: const Text('Monthly report'),
            onChanged: (value) => setState(
              () => _draft = _draft.copyWith(monthlyReportEnabled: value),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('flowfin-prefs-save'),
            onPressed: () => _flowFinRun(
              context,
              () => widget.controller.saveAccount(prefs: _draft),
              successMessage: 'Notification preferences saved.',
            ),
            child: const Text('Save notifications'),
          ),
        ],
      ),
    );
  }
}
