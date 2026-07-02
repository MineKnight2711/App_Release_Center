import 'dart:async';
import 'dart:io';

import 'package:app_release_center/app/models/remote_control.dart';
import 'package:app_release_center/app/services/remote_control_service.dart';
import 'package:app_release_center/app/theme/cyber_theme.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class MobileControlView extends StatefulWidget {
  const MobileControlView({super.key});

  @override
  State<MobileControlView> createState() => _MobileControlViewState();
}

class _MobileControlViewState extends State<MobileControlView> {
  final _endpointController = TextEditingController();
  final _pairingCodeController = TextEditingController();
  final _pairingIdController = TextEditingController();
  final _shellController = TextEditingController();
  final _cwdController = TextEditingController();
  final _stdinController = TextEditingController();
  Timer? _refreshTimer;
  bool _isWorking = false;
  String? _selectedProjectPath;

  RemoteControlService get remote => Get.find<RemoteControlService>();

  @override
  void initState() {
    super.initState();
    _endpointController.text = remote.mobileSettings.value.endpointBaseUrl;
    _startRefreshTimer();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _endpointController.dispose();
    _pairingCodeController.dispose();
    _pairingIdController.dispose();
    _shellController.dispose();
    _cwdController.dispose();
    _stdinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final mobileSettings = remote.mobileSettings.value;
      final state = remote.desktopState.value;
      final command = remote.activeMobileCommand.value;

      return Scaffold(
        appBar: AppBar(
          title: const Text('Release Remote'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _isWorking ? null : () => unawaited(_refresh()),
              icon: const Icon(Icons.refresh_outlined),
            ),
            if (mobileSettings.isLinked)
              IconButton(
                tooltip: 'Unlink',
                onPressed: () => unawaited(remote.clearMobileLink()),
                icon: const Icon(Icons.link_off_outlined),
              ),
          ],
        ),
        body: SafeArea(
          child: mobileSettings.isLinked
              ? _buildConsole(context, state, command)
              : _buildPairing(context),
        ),
      );
    });
  }

  Widget _buildPairing(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle(icon: Icons.link_outlined, title: 'Pair Phone'),
        const SizedBox(height: 12),
        TextField(
          controller: _endpointController,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Relay endpoint',
            hintText: 'https://your-domain.example.com/api',
            prefixIcon: Icon(Icons.cloud_queue_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pairingCodeController,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Pairing code',
            prefixIcon: Icon(Icons.password_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pairingIdController,
          decoration: const InputDecoration(
            labelText: 'Pairing id',
            prefixIcon: Icon(Icons.tag_outlined),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _isWorking ? null : () => unawaited(_link()),
          icon: _isWorking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.phone_android_outlined),
          label: const Text('Link'),
        ),
        const SizedBox(height: 12),
        Obx(() => _StatusText(remote.mobileStatus.value)),
      ],
    );
  }

  Widget _buildConsole(
    BuildContext context,
    RemoteDesktopState? state,
    RemoteCommand? command,
  ) {
    final projects = state?.projects ?? const <RemoteProjectSummary>[];
    final selectedProject = _selectedProject(projects);
    if (selectedProject != null && _cwdController.text.isEmpty) {
      _cwdController.text = selectedProject.path;
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _DesktopStatusCard(state: state),
          const SizedBox(height: 14),
          _ShellPanel(
            project: selectedProject,
            cwdController: _cwdController,
            shellController: _shellController,
            onRun: _isWorking ? null : _runShell,
          ),
          const SizedBox(height: 14),
          _ProjectActionsPanel(
            projects: projects,
            selectedProjectPath: selectedProject?.path,
            onSelected: (path) {
              setState(() {
                _selectedProjectPath = path;
                _cwdController.text = path;
              });
            },
            onRunScript: _isWorking ? null : _runScript,
            onRunLane: _isWorking ? null : _runLane,
          ),
          const SizedBox(height: 14),
          _CommandPanel(
            command: command,
            desktopState: state,
            stdinController: _stdinController,
            onSendInput: command?.isActive == true ? _sendInput : null,
            onStop: command?.isActive == true ? _stopCommand : null,
            onYes: command?.isActive == true
                ? () => _sendInputValue('y')
                : null,
            onNo: command?.isActive == true ? () => _sendInputValue('n') : null,
          ),
        ],
      ),
    );
  }

  RemoteProjectSummary? _selectedProject(List<RemoteProjectSummary> projects) {
    if (projects.isEmpty) return null;
    final selectedPath = _selectedProjectPath;
    if (selectedPath != null) {
      for (final project in projects) {
        if (project.path == selectedPath) return project;
      }
    }
    _selectedProjectPath = projects.first.path;
    return projects.first;
  }

  Future<void> _link() async {
    await _withBusy(() async {
      await remote.linkMobileDevice(
        endpointBaseUrl: _endpointController.text,
        pairingCode: _pairingCodeController.text,
        pairingId: _pairingIdController.text,
        deviceName: Platform.localHostname.isEmpty
            ? 'Android phone'
            : Platform.localHostname,
      );
      await _refresh();
    });
  }

  Future<void> _refresh() async {
    if (!remote.mobileSettings.value.isLinked) return;
    await _withBusy(() async {
      await remote.refreshMobileDesktopState();
      final active = remote.activeMobileCommand.value;
      if (active != null && active.commandId.isNotEmpty) {
        await remote.refreshMobileCommand(active.commandId);
      }
    }, showBusy: false);
  }

  Future<void> _runShell() async {
    final command = _shellController.text.trim();
    if (command.isEmpty) return;
    await _withBusy(() async {
      await remote.enqueueShellCommand(
        command: command,
        workingDirectory: _cwdController.text.trim(),
      );
      _shellController.clear();
    });
  }

  Future<void> _runScript(
    RemoteProjectSummary project,
    RemoteScriptSummary script,
  ) async {
    await _withBusy(
      () => remote.enqueueScript(project: project, script: script),
    );
  }

  Future<void> _runLane(
    RemoteProjectSummary project,
    RemoteFastlaneSummary lane,
  ) async {
    await _withBusy(
      () => remote.enqueueFastlaneLane(project: project, lane: lane),
    );
  }

  Future<void> _sendInput() async {
    final value = _stdinController.text;
    if (value.trim().isEmpty) return;
    _stdinController.clear();
    await _sendInputValue(value);
  }

  Future<void> _sendInputValue(String value) async {
    final command = remote.activeMobileCommand.value;
    if (command == null) return;
    await _withBusy(
      () => remote.sendMobileInput(command.commandId, value),
      showBusy: false,
    );
  }

  Future<void> _stopCommand() async {
    final command = remote.activeMobileCommand.value;
    if (command == null) return;
    await _withBusy(
      () => remote.stopMobileCommand(command.commandId),
      showBusy: false,
    );
  }

  Future<void> _withBusy(
    Future<void> Function() action, {
    bool showBusy = true,
  }) async {
    if (_isWorking && showBusy) return;
    if (showBusy && mounted) setState(() => _isWorking = true);
    try {
      await action();
    } catch (error) {
      remote.mobileStatus.value = error.toString();
    } finally {
      if (showBusy && mounted) setState(() => _isWorking = false);
    }
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_refresh()),
    );
  }
}

class _DesktopStatusCard extends StatelessWidget {
  const _DesktopStatusCard({required this.state});

  final RemoteDesktopState? state;

  @override
  Widget build(BuildContext context) {
    final online = state?.online == true && state?.remoteControlEnabled == true;
    return _PanelShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                color: online ? const Color(0xFF039855) : Colors.orange,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  state?.displayName ?? 'Desktop unavailable',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _StatusBadge(label: online ? 'Online' : 'Offline'),
            ],
          ),
          const SizedBox(height: 10),
          Text(state?.status ?? 'Waiting for heartbeat'),
          const SizedBox(height: 8),
          Text('${state?.projects.length ?? 0} projects available'),
        ],
      ),
    );
  }
}

class _ShellPanel extends StatelessWidget {
  const _ShellPanel({
    required this.project,
    required this.cwdController,
    required this.shellController,
    required this.onRun,
  });

  final RemoteProjectSummary? project;
  final TextEditingController cwdController;
  final TextEditingController shellController;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    return _PanelShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(icon: Icons.terminal_outlined, title: 'Shell'),
          const SizedBox(height: 10),
          TextField(
            controller: cwdController,
            decoration: const InputDecoration(
              labelText: 'Working directory',
              prefixIcon: Icon(Icons.folder_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: shellController,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: project == null
                  ? 'Command'
                  : 'Command for ${project!.name}',
              prefixIcon: const Icon(Icons.code_outlined),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onRun,
              icon: const Icon(Icons.play_arrow_outlined),
              label: const Text('Run Shell'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectActionsPanel extends StatelessWidget {
  const _ProjectActionsPanel({
    required this.projects,
    required this.selectedProjectPath,
    required this.onSelected,
    required this.onRunScript,
    required this.onRunLane,
  });

  final List<RemoteProjectSummary> projects;
  final String? selectedProjectPath;
  final ValueChanged<String> onSelected;
  final void Function(RemoteProjectSummary project, RemoteScriptSummary script)?
  onRunScript;
  final void Function(RemoteProjectSummary project, RemoteFastlaneSummary lane)?
  onRunLane;

  @override
  Widget build(BuildContext context) {
    final project = projects.isEmpty
        ? null
        : projects.firstWhere(
            (entry) => entry.path == selectedProjectPath,
            orElse: () => projects.first,
          );

    return _PanelShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(icon: Icons.account_tree_outlined, title: 'Actions'),
          const SizedBox(height: 10),
          if (projects.isEmpty)
            const Text('No projects from desktop heartbeat.')
          else ...[
            DropdownButtonFormField<String>(
              initialValue: project?.path,
              items: projects
                  .map(
                    (project) => DropdownMenuItem(
                      value: project.path,
                      child: Text(project.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) onSelected(value);
              },
              decoration: const InputDecoration(
                labelText: 'Project',
                prefixIcon: Icon(Icons.folder_open_outlined),
              ),
            ),
            const SizedBox(height: 12),
            ...project!.scripts.map(
              (script) => _ActionTile(
                icon: Icons.play_circle_outline,
                title: script.label,
                subtitle: script.fileName,
                onTap: onRunScript == null
                    ? null
                    : () => onRunScript!(project, script),
              ),
            ),
            ...project.fastlaneLanes.map(
              (lane) => _ActionTile(
                icon: Icons.alt_route_outlined,
                title: lane.label,
                subtitle: lane.command,
                onTap: onRunLane == null
                    ? null
                    : () => onRunLane!(project, lane),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommandPanel extends StatelessWidget {
  const _CommandPanel({
    required this.command,
    required this.desktopState,
    required this.stdinController,
    required this.onSendInput,
    required this.onStop,
    required this.onYes,
    required this.onNo,
  });

  final RemoteCommand? command;
  final RemoteDesktopState? desktopState;
  final TextEditingController stdinController;
  final VoidCallback? onSendInput;
  final VoidCallback? onStop;
  final VoidCallback? onYes;
  final VoidCallback? onNo;

  @override
  Widget build(BuildContext context) {
    final lines = command?.logLines.isNotEmpty == true
        ? command!.logLines
        : desktopState?.logLines ?? const <String>[];
    final prompt = command?.yesNoPrompt ?? desktopState?.yesNoPrompt;

    return _PanelShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: _SectionTitle(
                  icon: Icons.receipt_long_outlined,
                  title: 'Run',
                ),
              ),
              if (command != null) _StatusBadge(label: command!.status),
            ],
          ),
          if (prompt != null) ...[
            const SizedBox(height: 10),
            Text(prompt),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onNo,
                    icon: const Icon(Icons.close_outlined),
                    label: const Text('No'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onYes,
                    icon: const Icon(Icons.check_outlined),
                    label: const Text('Yes'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: stdinController,
                  enabled: onSendInput != null,
                  decoration: const InputDecoration(
                    labelText: 'Send input',
                    prefixIcon: Icon(Icons.keyboard_outlined),
                  ),
                  onSubmitted: (_) => onSendInput?.call(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Send',
                onPressed: onSendInput,
                icon: const Icon(Icons.send_outlined),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Stop',
                onPressed: onStop,
                icon: const Icon(Icons.stop_circle_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 180, maxHeight: 360),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                lines.isEmpty ? 'No output' : lines.join('\n'),
                style: AppCyberTheme.dataTextStyle(size: 11.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton.filledTonal(
        onPressed: onTap,
        icon: const Icon(Icons.play_arrow_outlined),
      ),
    );
  }
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Text(value, style: Theme.of(context).textTheme.bodySmall);
  }
}
