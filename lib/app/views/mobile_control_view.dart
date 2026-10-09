import 'dart:async';
import 'dart:io';

import 'package:app_management_center/app/models/app_lock.dart';
import 'package:app_management_center/app/models/remote_unlock_session.dart';
import 'package:app_management_center/app/services/app_lock_service.dart';
import 'package:app_management_center/app/services/remote_unlock_session_service.dart';
import 'package:app_management_center/app/models/remote_control.dart';
import 'package:app_management_center/app/models/wake_diagnostics.dart';
import 'package:app_management_center/app/services/machine_power_service.dart';
import 'package:app_management_center/app/services/wake_on_lan_service.dart';
import 'package:app_management_center/app/services/remote_unlock_service.dart';
import 'package:app_management_center/app/services/remote_control_service.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';
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
  final _unlockPasswordController = TextEditingController();
  Timer? _refreshTimer;
  Timer? _countdownTimer;
  bool _isWorking = false;
  String? _feedbackType;
  String? _selectedProjectPath;
  MachinePowerAction? _powerCountdownAction;
  DateTime? _powerCountdownEndsAt;
  Timer? _wakeTimer;
  DateTime? _wakeWaitingSince;
  String _wakeMessage = '';
  bool _wakeFailed = false;

  /// Long enough to change your mind, short enough not to feel broken.
  static const _powerDelaySeconds = 15;

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
    _countdownTimer?.cancel();
    _wakeTimer?.cancel();
    _endpointController.dispose();
    _pairingCodeController.dispose();
    _pairingIdController.dispose();
    _shellController.dispose();
    _cwdController.dispose();
    _stdinController.dispose();
    _unlockPasswordController.dispose();
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
          title: const Text('Điều khiển release'),
          actions: [
            IconButton(
              tooltip: 'Làm mới',
              onPressed: _isWorking ? null : () => unawaited(_refresh()),
              icon: const Icon(Icons.refresh_outlined),
            ),
            if (mobileSettings.isLinked)
              IconButton(
                tooltip: 'Bỏ liên kết',
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
        _SectionTitle(icon: Icons.link_outlined, title: 'Ghép điện thoại'),
        const SizedBox(height: 12),
        Text(
          'Dán cả link ghép từ máy tính vào ô nào cũng được — ba ô sẽ tự điền.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _endpointController,
          keyboardType: TextInputType.url,
          // Paste the whole pairing link here and the other two fill in.
          onChanged: _absorbPairingLink,
          decoration: const InputDecoration(
            labelText: 'Relay endpoint',
            hintText: 'https://amc-relay.example.workers.dev/api',
            prefixIcon: Icon(Icons.cloud_queue_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pairingCodeController,
          textCapitalization: TextCapitalization.characters,
          onChanged: _absorbPairingLink,
          decoration: const InputDecoration(
            labelText: 'Mã ghép',
            hintText: '8 ký tự',
            prefixIcon: Icon(Icons.password_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pairingIdController,
          decoration: const InputDecoration(
            labelText: 'Pairing id (không bắt buộc)',
            helperText:
                'Bỏ trống cũng được. Chỉ cần khi có nhiều mã ghép cùng hiệu lực.',
            helperMaxLines: 2,
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
          label: const Text('Liên kết'),
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
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.desktop_windows_outlined), text: 'Máy tính'),
              Tab(icon: Icon(Icons.terminal_outlined), text: 'Chạy'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildMachineTab(context, state),
                _buildRunTab(context, state, command),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMachineTab(BuildContext context, RemoteDesktopState? state) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _DesktopStatusCard(state: state),
          const SizedBox(height: 14),
          _PowerPanel(
            state: state,
            countdownAction: _powerCountdownAction,
            countdownRemaining: _countdownRemaining(),
            command: remote.activeMobileCommand.value,
            errorMessage: _feedbackType != 'unlock'
                ? remote.mobileStatus.value
                : '',
            onAction: _isWorking ? null : _requestPowerAction,
            onCancelCountdown: _cancelPowerCountdown,
          ),
          const SizedBox(height: 14),
          _WakePanel(
            wake: state?.wake ?? const WakeDiagnostics(),
            online: state?.online == true,
            waiting: _wakeWaitingSince != null,
            message: _wakeMessage,
            showBlockers: _wakeFailed,
            onWake: _sendWake,
          ),
          const SizedBox(height: 14),
          _AppLockPanel(lock: _appLock, onChanged: () => setState(() {})),
          const SizedBox(height: 14),
          _UnlockPanel(
            state: state,
            passwordController: _unlockPasswordController,
            busy: _isWorking,
            command: remote.activeMobileCommand.value,
            errorMessage: _feedbackType == 'unlock'
                ? remote.mobileStatus.value
                : '',
            session: _unlockSessions?.session.value,
            canSaveSession: _unlockSessions?.canSave ?? false,
            onUnlock: _sendUnlock,
            onSavedUnlock: _sendSavedUnlock,
            onForgetSession: _forgetUnlockSession,
          ),
        ],
      ),
    );
  }

  Widget _buildRunTab(
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

  /// Fills the whole form when a pairing link is pasted into either text
  /// field, so the id and code never have to be typed out by hand.
  void _absorbPairingLink(String value) {
    final link = PairingLink.tryParse(value);
    if (link == null) return;
    setState(() {
      _endpointController.text = link.endpointBaseUrl;
      _pairingCodeController.text = link.pairingCode;
      _pairingIdController.text = link.pairingId;
    });
  }

  Future<void> _link() async {
    await _withBusy(() async {
      await remote.linkMobileDevice(
        endpointBaseUrl: _endpointController.text,
        pairingCode: _pairingCodeController.text,
        pairingId: _pairingIdController.text,
        deviceName: Platform.localHostname.isEmpty
            ? 'Điện thoại Android'
            : Platform.localHostname,
      );
      await _refresh();
    });
  }

  /// Asks the app lock to vouch for one irreversible command.
  ///
  /// Answers true when the lock is off or not installed, so the caller reads
  /// as "may I proceed" and the phone behaves exactly as before for anyone who
  /// has not turned the lock on.
  Future<bool> _confirmWithLock(AppLockReason reason) async {
    if (!Get.isRegistered<AppLockService>()) return true;
    final allowed = await Get.find<AppLockService>().confirmSensitiveAction(
      reason,
    );
    if (!allowed) {
      _feedbackType = reason == AppLockReason.unlockWindows
          ? 'unlock'
          : 'power';
      remote.activeMobileCommand.value = null;
      remote.mobileStatus.value = 'Chưa xác thực nên lệnh chưa được gửi.';
    }
    return allowed;
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

  Duration? _countdownRemaining() {
    final endsAt = _powerCountdownEndsAt;
    if (endsAt == null) return null;
    final left = endsAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> _requestPowerAction(MachinePowerAction action) async {
    final state = remote.desktopState.value;
    // Without a heartbeat there is no desktop id to address, and the relay
    // refuses a power command that does not name its target. Returning in
    // silence here left the previous status line on screen -- usually the
    // "Da lien ket" from pairing -- so a dead press looked like a successful
    // one, and the machine being unreachable never got said out loud.
    if (state == null) {
      _feedbackType = 'power';
      remote.activeMobileCommand.value = null;
      remote.mobileStatus.value =
          'Chưa nhận được tín hiệu từ máy tính. Kiểm tra máy tính đã bật '
          'App Management Center và bật điều khiển từ xa chưa.';
      return;
    }

    final needsConfirmation =
        action == MachinePowerAction.shutdown ||
        action == MachinePowerAction.restart;
    var force = false;

    if (needsConfirmation) {
      final choice = await _confirmDisruptiveAction(action, state);
      if (choice == null) return;
      force = choice;
    }

    // Only the two that cannot be taken back. Asking for a face before "lock
    // my screen" would train the person to approve prompts without reading
    // them, which is what makes the shutdown prompt worth anything.
    if (needsConfirmation &&
        !await _confirmWithLock(AppLockReason.powerAction)) {
      return;
    }

    final delaySeconds = needsConfirmation ? _powerDelaySeconds : 0;
    // Clear the last outcome first: leaving it on screen makes a fresh press
    // look like it failed the same way, which is how "nothing happens" reads.
    remote.mobileStatus.value = '';
    remote.activeMobileCommand.value = null;
    _feedbackType = 'power';
    await _withBusy(() async {
      await remote.enqueuePowerCommand(
        desktopId: state.desktopId,
        action: action,
        delaySeconds: delaySeconds,
        force: force,
      );
      if (delaySeconds > 0) _startPowerCountdown(action, delaySeconds);
    });
  }

  /// Returns null to abandon, false to proceed normally, true to proceed even
  /// though a release is running.
  Future<bool?> _confirmDisruptiveAction(
    MachinePowerAction action,
    RemoteDesktopState state,
  ) async {
    final label = action == MachinePowerAction.shutdown
        ? 'Tắt máy'
        : 'Khởi động lại';

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$label ${state.displayName}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Máy sẽ $label sau $_powerDelaySeconds giây. '
              'Bạn vẫn huỷ được trong lúc đếm ngược.',
            ),
            if (state.isRunning) ...[
              const SizedBox(height: 14),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(
                    dialogContext,
                  ).colorScheme.errorContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_outlined,
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Máy đang chạy: ${state.status}.\n'
                          'Máy tính sẽ từ chối lệnh này trừ khi bạn chọn vẫn làm.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Huỷ'),
          ),
          if (state.isRunning)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              child: Text('Vẫn $label'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(label),
            ),
        ],
      ),
    );
  }

  void _startPowerCountdown(MachinePowerAction action, int seconds) {
    _countdownTimer?.cancel();
    setState(() {
      _powerCountdownAction = action;
      _powerCountdownEndsAt = DateTime.now().add(Duration(seconds: seconds));
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final remaining = _countdownRemaining();
      if (remaining == null || remaining == Duration.zero) {
        timer.cancel();
        setState(_clearPowerCountdown);
        return;
      }
      setState(() {});
    });
  }

  void _clearPowerCountdown() {
    _powerCountdownAction = null;
    _powerCountdownEndsAt = null;
  }

  Future<void> _cancelPowerCountdown() async {
    final state = remote.desktopState.value;
    _countdownTimer?.cancel();
    if (mounted) setState(_clearPowerCountdown);
    if (state == null) return;
    await _withBusy(
      () => remote.enqueuePowerCommand(
        desktopId: state.desktopId,
        action: MachinePowerAction.cancel,
      ),
      showBusy: false,
    );
  }

  /// How long to keep watching for the machine to report in. Booting from off
  /// and signing back in takes a good deal longer than resuming from sleep.
  static const _wakeWaitSeconds = 90;

  Future<void> _sendWake() async {
    final state = remote.desktopState.value;
    final wake = state?.wake;
    if (wake == null || !wake.canAttemptWake) return;

    // Sending to a machine that is already on is a reachability test, not a
    // wake attempt: there is nothing to wait for, and the answer comes from
    // whether the machine reports the packet arriving.
    final probing = state?.online == true;

    setState(() {
      _wakeFailed = false;
      _wakeMessage = probing
          ? 'Đang gửi gói thử…'
          : 'Đang gửi tín hiệu đánh thức…';
    });

    try {
      final sent = await const WakeOnLanService().sendMagicPacket(
        wake.macAddress,
        broadcastAddress: wake.broadcastAddress,
        hostAddress: wake.ipAddress,
        repeatCount: 10,
      );
      if (!mounted) return;
      if (sent == 0) {
        setState(() {
          _wakeMessage =
              'Không gửi được gói nào. Kiểm tra điện thoại có đang '
              'ở cùng mạng Wi-Fi nhà không.';
          _wakeFailed = true;
        });
        return;
      }
      if (probing) {
        setState(() {
          _wakeMessage =
              'Đã gửi $sent gói. Xem dòng ngay dưới. Lưu ý kết quả này chỉ '
              'nói về lúc máy đang thức — đánh thức lúc ngủ do card mạng lo, '
              'không đi qua firewall.';
        });
        // Give the next heartbeat time to carry the observation back.
        await Future<void>.delayed(const Duration(seconds: 4));
        if (mounted) await _refresh();
        return;
      }

      setState(() {
        _wakeWaitingSince = DateTime.now();
        _wakeMessage = 'Đã gửi tín hiệu đánh thức. Đang chờ máy báo về…';
      });
      _startWakeWatch();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _wakeMessage = 'Gửi tín hiệu lỗi: $error';
        _wakeFailed = true;
      });
    }
  }

  /// Signs in with the password typed into the field, optionally saving it.
  Future<void> _sendUnlock({bool remember = false}) async {
    final state = remote.desktopState.value;
    if (state == null || !state.sessionLocked || !state.remoteUnlock.ready) {
      return;
    }
    final password = _unlockPasswordController.text;
    if (password.isEmpty) return;

    if (remember) {
      // Saving prompts on its own, and that prompt stands in for this one:
      // asking twice in a row for the same press teaches people to tap
      // through prompts without reading them.
      final saved = await _rememberUnlockPassword(state, password);
      if (!saved) return;
    } else if (!await _confirmWithLock(AppLockReason.unlockWindows)) {
      return;
    }

    await _submitUnlock(state, password);
  }

  /// Signs in with the saved password, released by one biometric prompt.
  Future<void> _sendSavedUnlock() async {
    final state = remote.desktopState.value;
    if (state == null || !state.sessionLocked || !state.remoteUnlock.ready) {
      return;
    }
    final sessions = _unlockSessions;
    if (sessions == null) return;

    remote.mobileStatus.value = '';
    remote.activeMobileCommand.value = null;
    _feedbackType = 'unlock';
    final password = await sessions.readPassword(
      accountName: state.remoteUnlock.accountName,
      desktopId: state.desktopId,
    );
    if (password == null) {
      remote.mobileStatus.value =
          'Chưa xác thực được nên chưa gửi mật khẩu đã lưu.';
      return;
    }
    await _submitUnlock(state, password);
  }

  Future<bool> _rememberUnlockPassword(
    RemoteDesktopState state,
    String password,
  ) async {
    final sessions = _unlockSessions;
    if (sessions == null) return false;
    try {
      await sessions.save(
        accountName: state.remoteUnlock.accountName,
        desktopId: state.desktopId,
        password: password,
      );
      return true;
    } on RemoteUnlockSessionException catch (error) {
      _feedbackType = 'unlock';
      remote.activeMobileCommand.value = null;
      remote.mobileStatus.value = error.message;
      return false;
    }
  }

  Future<void> _submitUnlock(RemoteDesktopState state, String password) async {
    remote.mobileStatus.value = '';
    remote.activeMobileCommand.value = null;
    _feedbackType = 'unlock';
    try {
      final envelope = RemoteUnlockService.encryptPassword(
        state: state.remoteUnlock,
        password: password,
      );
      _unlockPasswordController.clear();
      await _withBusy(() async {
        await remote.enqueueUnlockCommand(
          desktopId: state.desktopId,
          encryptedEnvelope: envelope,
        );
      });
    } finally {
      _unlockPasswordController.clear();
    }
  }

  Future<void> _forgetUnlockSession() async {
    await _unlockSessions?.forget();
    _feedbackType = 'unlock';
    remote.mobileStatus.value = '';
  }

  RemoteUnlockSessionService? get _unlockSessions =>
      Get.isRegistered<RemoteUnlockSessionService>()
      ? Get.find<RemoteUnlockSessionService>()
      : null;

  AppLockService? get _appLock =>
      Get.isRegistered<AppLockService>() ? Get.find<AppLockService>() : null;

  void _startWakeWatch() {
    _wakeTimer?.cancel();
    _wakeTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (remote.desktopState.value?.online == true) {
        timer.cancel();
        setState(() {
          _wakeWaitingSince = null;
          _wakeFailed = false;
          _wakeMessage = 'Máy đã lên.';
        });
        return;
      }

      final since = _wakeWaitingSince;
      if (since == null ||
          DateTime.now().difference(since).inSeconds >= _wakeWaitSeconds) {
        timer.cancel();
        setState(() {
          _wakeWaitingSince = null;
          // Not just "failed": the machine may well have powered on and simply
          // have nothing running to report in, so the checks below matter more
          // than the verdict.
          _wakeFailed = true;
          _wakeMessage = 'Sau $_wakeWaitSeconds giây vẫn chưa thấy máy báo về.';
        });
      } else {
        setState(() {});
      }
    });
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
      remote.mobileStatus.value = explainRemoteControlError('$error');
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
    // A locked machine is still reachable and still runs commands. Collapsing
    // it into "offline" would tell the user to go walk over to it for nothing.
    final locked = online && state?.sessionLocked == true;
    final (icon, color, badge) = switch ((online, locked)) {
      (false, _) => (Icons.cloud_off_outlined, Colors.orange, 'Offline'),
      (true, true) => (
        Icons.lock_outline,
        const Color(0xFFB54708),
        'Đang khóa',
      ),
      (true, false) => (
        Icons.cloud_done_outlined,
        const Color(0xFF039855),
        'Đang mở',
      ),
    };

    return _PanelShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  state?.displayName ?? 'Không thấy máy tính',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _StatusBadge(label: badge),
            ],
          ),
          const SizedBox(height: 10),
          Text(state?.status ?? 'Đang chờ tín hiệu'),
          const SizedBox(height: 8),
          Text('${state?.projects.length ?? 0} projects available'),
          _BuildStampLine(
            stamp: state?.buildStamp,
            online: state?.online == true,
          ),
        ],
      ),
    );
  }
}

class _PowerPanel extends StatelessWidget {
  const _PowerPanel({
    required this.state,
    required this.countdownAction,
    required this.countdownRemaining,
    required this.command,
    required this.errorMessage,
    required this.onAction,
    required this.onCancelCountdown,
  });

  final RemoteDesktopState? state;
  final MachinePowerAction? countdownAction;
  final Duration? countdownRemaining;

  /// The power command last sent, so its outcome shows here rather than only
  /// on the Chạy tab nobody is looking at while pressing these buttons.
  final RemoteCommand? command;

  /// Why the relay refused to queue the command at all.
  final String errorMessage;

  final void Function(MachinePowerAction action)? onAction;
  final Future<void> Function() onCancelCountdown;

  @override
  Widget build(BuildContext context) {
    final desktop = state;
    final reachable = desktop?.online == true;
    final allowed = desktop?.powerControlEnabled == true;
    final enabled = reachable && allowed && onAction != null;
    final sleepEnabled = enabled && desktop?.sleepSupported == true;
    final hibernateEnabled = enabled && desktop?.hibernateSupported == true;

    return _PanelShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.power_settings_new_outlined,
            title: 'Nguồn máy',
          ),
          const SizedBox(height: 10),
          if (!allowed && reachable)
            _PowerNotice(
              icon: Icons.lock_outline,
              message:
                  'Máy tính chưa bật quyền điều khiển nguồn. '
                  'Bật trong Options > Điều khiển rồi ghép lại điện thoại.',
            )
          else if (!reachable)
            const _PowerNotice(
              icon: Icons.cloud_off_outlined,
              message:
                  'Máy đang offline nên không nhận được lệnh nguồn. '
                  'Dùng nút Đánh thức bên dưới để bật lại từ trạng thái ngủ.',
            ),
          if (countdownAction != null && countdownRemaining != null) ...[
            _CountdownCard(
              action: countdownAction!,
              remaining: countdownRemaining!,
              onCancel: onCancelCountdown,
            ),
            const SizedBox(height: 12),
          ],
          if (desktop?.isRunning == true) ...[
            _PowerNotice(
              icon: Icons.play_circle_outline,
              message:
                  'Đang chạy: ${desktop!.status}. '
                  'Tắt hay khởi động lại sẽ phải xác nhận thêm.',
            ),
            const SizedBox(height: 4),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _PowerButton(
                icon: Icons.lock_outlined,
                label: 'Khóa',
                onPressed: enabled
                    ? () => onAction!(MachinePowerAction.lock)
                    : null,
              ),
              _PowerButton(
                icon: Icons.bedtime_outlined,
                label: 'Ngủ',
                onPressed: sleepEnabled
                    ? () => onAction!(MachinePowerAction.sleep)
                    : null,
              ),
              _PowerButton(
                icon: Icons.mode_night_outlined,
                label: 'Ngủ đông',
                onPressed: hibernateEnabled
                    ? () => onAction!(MachinePowerAction.hibernate)
                    : null,
              ),
              _PowerButton(
                icon: Icons.restart_alt_outlined,
                label: 'Khởi động lại',
                onPressed: enabled
                    ? () => onAction!(MachinePowerAction.restart)
                    : null,
              ),
              _PowerButton(
                icon: Icons.power_settings_new_outlined,
                label: 'Tắt máy',
                destructive: true,
                onPressed: enabled
                    ? () => onAction!(MachinePowerAction.shutdown)
                    : null,
              ),
            ],
          ),
          _PowerOutcome(command: command, errorMessage: errorMessage),
        ],
      ),
    );
  }
}

/// Says what happened to the last power command.
///
/// Without this the buttons fail in silence: a command the relay rejects for
/// a missing scope, or one the desktop refuses because a release is running,
/// looks exactly like a button that does nothing at all.
class _PowerOutcome extends StatelessWidget {
  const _PowerOutcome({required this.command, required this.errorMessage});

  final RemoteCommand? command;
  final String errorMessage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (errorMessage.isNotEmpty) {
      return _OutcomeLine(
        icon: Icons.error_outline,
        color: scheme.error,
        title: 'Không gửi được lệnh',
        detail: errorMessage,
      );
    }

    final entry = command;
    if (entry == null || entry.type != 'power') return const SizedBox.shrink();

    return switch (entry.status) {
      'failed' => _OutcomeLine(
        icon: Icons.cancel_outlined,
        color: scheme.error,
        title: 'Máy tính từ chối lệnh',
        detail: entry.error ?? 'Không rõ lý do.',
      ),
      'completed' => _OutcomeLine(
        icon: Icons.check_circle_outline,
        color: const Color(0xFF039855),
        title: 'Máy tính đã nhận lệnh',
        detail: entry.logLines.isEmpty ? '' : entry.logLines.last,
      ),
      'canceled' => const _OutcomeLine(
        icon: Icons.undo_outlined,
        color: null,
        title: 'Lệnh đã bị huỷ',
        detail: '',
      ),
      _ => const _OutcomeLine(
        icon: Icons.hourglass_empty_outlined,
        color: null,
        title: 'Đang chờ máy tính nhận lệnh…',
        detail: 'Máy tính phải đang mở app và bật điều khiển từ xa.',
      ),
    };
  }
}

class _OutcomeLine extends StatelessWidget {
  const _OutcomeLine({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color? color;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: color),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  SelectableText(
                    detail,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WakePanel extends StatelessWidget {
  const _WakePanel({
    required this.wake,
    required this.online,
    required this.waiting,
    required this.message,
    required this.showBlockers,
    required this.onWake,
  });

  final WakeDiagnostics wake;
  final bool online;
  final bool waiting;
  final String message;
  final bool showBlockers;
  final Future<void> Function() onWake;

  @override
  Widget build(BuildContext context) {
    final blockers = wake.blockers;
    final fatal = blockers.any((blocker) => blocker.fatal);

    return _PanelShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.wb_sunny_outlined,
            title: 'Đánh thức / bật máy',
          ),
          const SizedBox(height: 10),
          Text(
            online
                // Sending while the machine is on is the only way to find out
                // whether the packet can reach it at all: nothing inside a
                // sleeping machine is observable, so hiding the button here
                // left the one useful test out of reach.
                ? 'Máy đang bật. Gửi thử một gói để kiểm tra điện thoại có '
                      'tới được máy không — kết quả hiện ngay dưới.'
                : 'Chỉ gửi được khi điện thoại ở cùng mạng Wi-Fi với máy. '
                      'Gói đánh thức được gửi trực tiếp trong mạng LAN, không '
                      'đi qua relay hay Internet.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: online
                ? OutlinedButton.icon(
                    onPressed: waiting || !wake.canAttemptWake
                        ? null
                        : () => unawaited(onWake()),
                    icon: const Icon(Icons.network_check_outlined),
                    label: const Text('Gửi thử gói đánh thức'),
                  )
                : FilledButton.icon(
                    onPressed: waiting || fatal || !wake.canAttemptWake
                        ? null
                        : () => unawaited(onWake()),
                    icon: waiting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wb_sunny_outlined),
                    label: Text(waiting ? 'Đang chờ máy lên…' : 'Đánh thức'),
                  ),
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ],
          _PacketReachReport(wake: wake),
          // Held back until an attempt fails, or the list reads as a wall of
          // warnings for something that may well work on this machine.
          if ((showBlockers || fatal) && blockers.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Những thứ đang cản:',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ...blockers.map((blocker) => _BlockerTile(blocker: blocker)),
          ],
        ],
      ),
    );
  }
}

/// The app-wide biometric lock.
///
/// Separate from the saved Windows password and not required by it: this one
/// guards the console itself — the log, the project list, the power controls —
/// for anyone who wants the phone app shut when the phone is not in their hand.
class _AppLockPanel extends StatelessWidget {
  const _AppLockPanel({required this.lock, required this.onChanged});

  final AppLockService? lock;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final service = lock;
    if (service == null) return const SizedBox.shrink();

    return Obx(() {
      final usable = service.availability.value.usable;
      return _PanelShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
              icon: Icons.phonelink_lock_outlined,
              title: 'Khóa ứng dụng',
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              value: service.settings.value.enabled && usable,
              onChanged: usable && !service.isPrompting.value
                  ? (value) async {
                      await service.setEnabled(value);
                      onChanged();
                    }
                  : null,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Hỏi sinh trắc học khi mở app'),
              subtitle: Text(
                usable
                    ? 'Khóa lại sau ${service.settings.value.graceSeconds} giây '
                          'kể từ khi thoát ra nền.'
                    : 'Máy chưa đăng ký khuôn mặt, vân tay hay mã PIN.',
              ),
            ),
            if (service.settings.value.enabled && usable)
              SwitchListTile(
                value: service.settings.value.protectSensitiveActions,
                onChanged: (value) async {
                  await service.setProtectSensitiveActions(value);
                  onChanged();
                },
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Hỏi lại khi tắt hoặc khởi động lại máy'),
                subtitle: const Text(
                  'Mở khóa Windows luôn hỏi, không tắt được.',
                ),
              ),
            if (service.status.value.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  service.status.value,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _UnlockPanel extends StatefulWidget {
  const _UnlockPanel({
    required this.state,
    required this.passwordController,
    required this.busy,
    required this.command,
    required this.errorMessage,
    required this.session,
    required this.canSaveSession,
    required this.onUnlock,
    required this.onSavedUnlock,
    required this.onForgetSession,
  });

  final RemoteDesktopState? state;
  final TextEditingController passwordController;
  final bool busy;
  final RemoteCommand? command;
  final String errorMessage;

  /// The saved Windows password marker, or null when the phone app has no
  /// session service (desktop builds, or a device that never registered one).
  final RemoteUnlockSession? session;
  final bool canSaveSession;
  final Future<void> Function({bool remember}) onUnlock;
  final Future<void> Function() onSavedUnlock;
  final Future<void> Function() onForgetSession;

  @override
  State<_UnlockPanel> createState() => _UnlockPanelState();
}

class _UnlockPanelState extends State<_UnlockPanel> {
  bool _remember = false;

  Future<void> _submit() => widget.onUnlock(remember: _remember);

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final busy = widget.busy;
    final command = widget.command;
    final errorMessage = widget.errorMessage;
    final passwordController = widget.passwordController;
    final desktop = state;
    final unlock = desktop?.remoteUnlock;
    final locked = desktop?.online == true && desktop?.sessionLocked == true;
    final ready = locked && unlock?.ready == true && !busy;
    final session = widget.session;
    // A password saved for another account or another machine is not offered:
    // sending it would burn a failed Windows sign-in on the wrong account.
    final saved =
        session != null &&
        desktop != null &&
        unlock != null &&
        session.matches(
          accountName: unlock.accountName,
          desktopId: desktop.desktopId,
        );

    String? notice;
    if (desktop?.online != true) {
      notice = 'Đánh thức máy trước khi gửi yêu cầu mở khóa.';
    } else if (desktop?.sessionLocked != true) {
      notice = 'Máy đang mở, không cần nhập mật khẩu.';
    } else if (unlock?.installed != true) {
      notice = 'Máy chưa cài Credential Provider mở khóa.';
    } else if (unlock?.enabled != true) {
      notice = 'Máy chưa bật quyền mở khóa từ xa.';
    } else if (unlock?.ready != true) {
      notice = unlock?.error.isNotEmpty == true
          ? unlock!.error
          : 'Đang chờ challenge bảo mật mới từ máy.';
    }

    return _PanelShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.key_outlined,
            title: 'Mở khóa Windows',
          ),
          const SizedBox(height: 10),
          if (notice != null)
            Text(notice, style: Theme.of(context).textTheme.bodySmall)
          else if (saved) ...[
            // One press, one prompt. The password never reappears on screen —
            // showing it back would put a Windows password in a text field
            // that any shoulder or screenshot can read.
            Text(
              'Đã lưu mật khẩu cho ${session.accountName}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: ready
                    ? () => unawaited(widget.onSavedUnlock())
                    : null,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Đăng nhập bằng sinh trắc học'),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: busy
                    ? null
                    : () => unawaited(widget.onForgetSession()),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Xóa mật khẩu đã lưu'),
              ),
            ),
          ] else ...[
            TextField(
              controller: passwordController,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: ready ? (_) => unawaited(_submit()) : null,
              decoration: InputDecoration(
                labelText: 'Mật khẩu Windows',
                helperText: unlock!.accountName,
                prefixIcon: const Icon(Icons.password_outlined),
              ),
            ),
            if (widget.canSaveSession)
              CheckboxListTile(
                value: _remember,
                onChanged: busy
                    ? null
                    : (value) => setState(() => _remember = value == true),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: const Text('Lưu mật khẩu cho lần sau'),
                subtitle: const Text(
                  'Lần sau chỉ cần khuôn mặt hoặc vân tay. Mật khẩu nằm trong '
                  'kho khóa của Android và mỗi lần dùng đều phải xác thực lại.',
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Chưa đăng ký khuôn mặt, vân tay hay mã PIN nên chưa lưu '
                  'được mật khẩu.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: ready ? () => unawaited(_submit()) : null,
                icon: const Icon(Icons.lock_open_outlined),
                label: const Text('Mở khóa'),
              ),
            ),
          ],
          if (errorMessage.isNotEmpty)
            _OutcomeLine(
              icon: Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
              title: 'Không gửi được yêu cầu',
              detail: errorMessage,
            )
          else if (command?.type == 'unlock')
            _OutcomeLine(
              icon: command?.status == 'failed'
                  ? Icons.cancel_outlined
                  : Icons.hourglass_empty_outlined,
              color: command?.status == 'failed'
                  ? Theme.of(context).colorScheme.error
                  : null,
              title: command?.status == 'failed'
                  ? 'Windows từ chối mở khóa'
                  : command?.status == 'completed'
                  ? 'Đã chuyển tới màn hình khóa'
                  : 'Đang chờ máy nhận yêu cầu…',
              detail: command?.error ?? '',
            ),
        ],
      ),
    );
  }
}

/// Says whether the wake packet can reach the machine at all.
///
/// The machine records packets aimed at its own MAC while it is awake, so
/// tapping wake with the machine on separates the two causes that look
/// identical from the phone: the packet never arriving, versus arriving and
/// the sleeping card ignoring it. Nothing is observed while asleep — the app
/// is not running then — which the wording has to be careful about.
/// Shows which desktop build is answering.
///
/// A desktop running an older copy behaves like a broken feature: the phone
/// asks for something the build does not have, nothing happens, and there is
/// nothing on screen to suggest why. Naming the build makes that visible.
class _BuildStampLine extends StatelessWidget {
  const _BuildStampLine({required this.stamp, required this.online});

  final DateTime? stamp;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final value = stamp;

    // A build too old to report its own date is exactly the case this line
    // exists for, so staying silent here defeated the purpose: the indicator
    // disappeared precisely when the desktop was stale.
    if (value == null) {
      if (!online) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'Không rõ bản build — máy tính đang chạy bản cũ chưa gửi thông tin '
          'này. Build lại rồi mở đúng bản mới.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
        ),
      );
    }

    final age = DateTime.now().difference(value);
    final stale = age.inDays >= 1;
    final day = '${value.day}/${value.month}';
    final time =
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        stale
            ? 'Máy đang chạy bản build $day $time — đã ${age.inDays} ngày. '
                  'Cài lại bản mới nếu bạn vừa build.'
            : 'Bản build $day $time',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: stale ? Theme.of(context).colorScheme.error : null,
        ),
      ),
    );
  }
}

class _PacketReachReport extends StatelessWidget {
  const _PacketReachReport({required this.wake});

  final WakeDiagnostics wake;

  @override
  Widget build(BuildContext context) {
    if (!wake.canAttemptWake) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final seenAt = wake.lastPacketAt;

    final (icon, color, text) = switch (seenAt) {
      null when !wake.probeListening => (
        Icons.help_outline,
        null,
        'Máy chưa mở được cổng nghe. Thường là vì máy tính đang chạy bản '
            'build cũ chưa có phần này — xem dòng bản build ở trên. Nếu bản '
            'build đã mới thì cổng 9 đang bị tiến trình khác giữ.',
      ),
      null => (
        Icons.hourglass_empty_outlined,
        null,
        'Chưa ghi nhận gói đánh thức nào tới máy. Hai khả năng ngang nhau: '
            'gói không tới được, hoặc Windows Firewall chặn không cho máy '
            'thấy nó. Chạy configure_wake.ps1 -AllowWakeProbe trên máy tính '
            'rồi thử lại thì mới phân biệt được.',
      ),
      // A packet from the machine's own address never left the host, so the
      // firewall never filtered it and it says nothing about the phone's
      // route. Reading one of those as success cost a round of debugging.
      _ when wake.lastPacketFrom == wake.ipAddress && wake.ipAddress.isNotEmpty
          => (
            Icons.info_outline,
            null,
            'Gói ghi nhận lúc ${_clock(seenAt)} đến từ chính máy tính '
                '(${wake.lastPacketFrom}), không phải từ điện thoại. Gói nội '
                'bộ không đi qua firewall nên chưa nói lên điều gì về đường '
                'từ điện thoại. Bấm gửi thử lại và xem địa chỉ có đổi không.',
          ),
      _ => (
        Icons.check_circle_outline,
        const Color(0xFF039855),
        'Gói đánh thức tới được máy — lần cuối ${_clock(seenAt)}'
            '${wake.lastPacketFrom.isEmpty ? '' : ' từ ${wake.lastPacketFrom}'}. '
            'Đường mạng ổn, nên nếu lúc ngủ vẫn không dậy thì vướng ở card '
            'mạng hoặc router, không phải ở điện thoại.',
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color ?? scheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  static String _clock(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _BlockerTile extends StatelessWidget {
  const _BlockerTile({required this.blocker});

  final WakeBlocker blocker;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            blocker.fatal ? Icons.block_outlined : Icons.error_outline_outlined,
            size: 18,
            color: blocker.fatal ? scheme.error : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  blocker.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: blocker.fatal ? scheme.error : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  blocker.detail,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (blocker.fix.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Cách sửa: ${blocker.fix}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({
    required this.action,
    required this.remaining,
    required this.onCancel,
  });

  final MachinePowerAction action;
  final Duration remaining;
  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    final label = action == MachinePowerAction.shutdown
        ? 'Tắt máy'
        : 'Khởi động lại';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$label sau ${remaining.inSeconds}s',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            FilledButton.icon(
              onPressed: () => unawaited(onCancel()),
              icon: const Icon(Icons.undo_outlined),
              label: const Text('Huỷ'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PowerNotice extends StatelessWidget {
  const _PowerNotice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 150,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          foregroundColor: destructive ? scheme.error : null,
        ),
        icon: Icon(icon),
        label: Text(label),
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
              labelText: 'Thư mục làm việc',
              prefixIcon: Icon(Icons.folder_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: shellController,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: project == null ? 'Lệnh' : 'Lệnh cho ${project!.name}',
              prefixIcon: const Icon(Icons.code_outlined),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onRun,
              icon: const Icon(Icons.play_arrow_outlined),
              label: const Text('Chạy shell'),
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
          _SectionTitle(icon: Icons.account_tree_outlined, title: 'Thao tác'),
          const SizedBox(height: 10),
          if (projects.isEmpty)
            const Text('Máy tính chưa gửi về dự án nào.')
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
                labelText: 'Dự án',
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
                  title: 'Chạy',
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
                    label: const Text('Không'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onYes,
                    icon: const Icon(Icons.check_outlined),
                    label: const Text('Có'),
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
                    labelText: 'Gửi cho script',
                    prefixIcon: Icon(Icons.keyboard_outlined),
                  ),
                  onSubmitted: (_) => onSendInput?.call(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Gửi',
                onPressed: onSendInput,
                icon: const Icon(Icons.send_outlined),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Dừng',
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
                lines.isEmpty ? 'Chưa có output' : lines.join('\n'),
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
