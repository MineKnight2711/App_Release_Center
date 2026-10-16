import 'dart:async';

import 'package:app_management_center/app/models/ios_release.dart';
import 'package:app_management_center/app/models/release_workflow.dart';
import 'package:app_management_center/app/models/remote_control.dart';
import 'package:app_management_center/app/services/remote_control_service.dart';
import 'package:flutter/material.dart';

/// CH Play and App Store releases, run on the desktop from the phone.
///
/// The desktop does the work with its own release flows; this tab offers the
/// same choices and buttons as the desktop dialogs and follows what happens.
class MobileReleaseTab extends StatefulWidget {
  const MobileReleaseTab({super.key, required this.remote});

  final RemoteControlService remote;

  @override
  State<MobileReleaseTab> createState() => _MobileReleaseTabState();
}

class _ReleaseTarget {
  const _ReleaseTarget({
    required this.platform,
    required this.key,
    required this.name,
    required this.detail,
    this.track = '',
  });

  /// `android` or `ios`.
  final String platform;

  /// The project's path for CH Play, its id for App Store.
  final String key;
  final String name;
  final String detail;
  final String track;

  String get id => '$platform:$key';
}

class _MobileReleaseTabState extends State<MobileReleaseTab> {
  static const _tracks = ['internal', 'alpha', 'beta', 'production'];

  final _version = TextEditingController();
  final _notes = TextEditingController();
  Timer? _overviewTimer;
  Timer? _followTimer;

  Map<String, Object?>? _overview;
  Map<String, Object?>? _iosProject;
  String? _targetId;
  String? _error;
  bool _loading = true;

  // CH Play preparation.
  String _track = 'internal';
  bool _productionConfirmed = false;
  bool _newAndroid = false;

  // App Store preparation.
  bool _newIos = false;
  bool _reuseBuild = false;
  bool _loadingBuilds = false;
  List<IosStoreBuild>? _builds;
  IosStoreBuild? _selectedBuild;

  /// The step this phone sent and is following.
  RemoteCommand? _command;
  String _commandPlatform = '';

  RemoteControlService get remote => widget.remote;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshOverview());
    // Releases started at the desktop show up here too.
    _overviewTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_command == null) unawaited(_refreshOverview(quiet: true));
    });
  }

  @override
  void dispose() {
    _overviewTimer?.cancel();
    _followTimer?.cancel();
    _version.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<_ReleaseTarget> get _targets {
    final overview = _overview;
    if (overview == null) return const [];
    List<Map<String, Object?>> list(String key) => (overview[key] is List
        ? (overview[key]! as List)
              .whereType<Map>()
              .map((entry) => Map<String, Object?>.from(entry))
              .toList()
        : const []);
    return [
      for (final project in list('android'))
        _ReleaseTarget(
          platform: 'android',
          key: '${project['path']}',
          name: '${project['name']}',
          detail: '${project['applicationId']}',
          track: '${project['track']}',
        ),
      for (final project in list('ios'))
        _ReleaseTarget(
          platform: 'ios',
          key: '${project['id']}',
          name: '${project['name']}',
          detail: '${project['bundleId']}',
        ),
    ];
  }

  _ReleaseTarget? get _target =>
      _targets.where((target) => target.id == _targetId).firstOrNull;

  Future<void> _refreshOverview({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final overview = await remote.releaseControl({'action': 'overview'});
      if (!mounted) return;
      setState(() {
        _overview = overview;
        if (!quiet) _error = null;
        final targets = _targets;
        if (_targetId == null ||
            !targets.any((target) => target.id == _targetId)) {
          _targetId = targets.firstOrNull?.id;
          _onTargetChanged();
        }
      });
    } catch (error) {
      if (mounted && !quiet) setState(() => _error = error.toString());
    } finally {
      if (mounted && !quiet) setState(() => _loading = false);
    }
  }

  void _onTargetChanged() {
    final target = _target;
    _newAndroid = false;
    _newIos = false;
    _productionConfirmed = false;
    _iosProject = null;
    _builds = null;
    _selectedBuild = null;
    _reuseBuild = false;
    if (target == null) return;
    if (target.platform == 'android') {
      _track = _tracks.contains(target.track) ? target.track : 'internal';
    } else {
      unawaited(_loadIosProject(target.key));
    }
  }

  Future<void> _loadIosProject(String projectId) async {
    try {
      final project = await remote.releaseControl({
        'action': 'project',
        'projectId': projectId,
      });
      if (!mounted || _target?.key != projectId) return;
      setState(() {
        _iosProject = project;
        _version.text = '${project['version'] ?? ''}';
        _notes.text = '${project['notes'] ?? ''}';
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  /// Sends one step and follows it until the desktop reports it finished.
  Future<void> _send(String platform, Map<String, Object?> payload) async {
    setState(() => _error = null);
    try {
      final command = await remote.enqueueRelease({
        'platform': platform,
        ...payload,
      });
      if (!mounted) return;
      setState(() {
        _command = command;
        _commandPlatform = platform;
      });
      _followTimer?.cancel();
      _followTimer = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => unawaited(_poll()),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _poll() async {
    final command = _command;
    if (command == null) return;
    try {
      final latest = await remote.fetchMobileCommand(command.commandId);
      if (!mounted) return;
      setState(() => _command = latest);
      if (latest.isActive) return;
      _followTimer?.cancel();
      setState(() {
        _loadingBuilds = false;
        if (latest.status == 'failed') {
          _error = latest.error ?? 'Máy tính báo lỗi.';
        } else if (latest.status == 'canceled') {
          _error = 'Đã dừng trên máy tính.';
        }
      });
      final builds = latest.result['builds'];
      if (builds is List) {
        setState(() {
          _builds = builds
              .whereType<Map>()
              .map((b) => IosStoreBuild.fromJson(Map<String, dynamic>.from(b)))
              .toList();
        });
      }
      await _refreshOverview(quiet: true);
      final target = _target;
      if (target?.platform == 'ios') await _loadIosProject(target!.key);
      if (mounted) {
        setState(() {
          _command = null;
          // A new run is now on screen; leave the preparation view.
          if (latest.status == 'completed') {
            _newAndroid = false;
            _newIos = false;
          }
        });
      }
    } catch (_) {
      // The next tick tries again; the step keeps running on the desktop.
    }
  }

  Future<void> _stop(String platform) async {
    final command = _command;
    try {
      if (command != null && command.isActive) {
        await remote.stopMobileCommand(command.commandId);
      } else {
        // Started at the desktop, or by an earlier session of this app.
        final target = _target;
        await remote.releaseControl({
          'action': 'cancel',
          'platform': platform,
          if (target != null && platform == 'ios') 'projectId': target.key,
        });
        await _refreshOverview(quiet: true);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final target = _target;
    return RefreshIndicator(
      onRefresh: () => _refreshOverview(),
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _projectPicker(context),
          if (_error != null) ...[
            const SizedBox(height: 10),
            _Notice(
              icon: Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
              message: _error!,
            ),
          ],
          const SizedBox(height: 14),
          if (_loading && _overview == null)
            const Center(child: CircularProgressIndicator())
          else if (target == null)
            const _Notice(
              icon: Icons.info_outline,
              message:
                  'Máy tính chưa có dự án nào trong mục CH Play hoặc App Store.',
            )
          else if (target.platform == 'android')
            _android(context, target)
          else
            _ios(context, target),
        ],
      ),
    );
  }

  Widget _projectPicker(BuildContext context) {
    final targets = _targets;
    return _Panel(
      children: [
        const _Title(icon: Icons.rocket_launch_outlined, title: 'Release'),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: const Key('mobile-release-project'),
          initialValue: _targetId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Dự án'),
          items: [
            for (final target in targets)
              DropdownMenuItem(
                value: target.id,
                child: Text(
                  '${target.name} · ${target.platform == 'android' ? 'CH Play' : 'App Store'}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _command?.isActive == true
              ? null
              : (id) => setState(() {
                  _targetId = id;
                  _error = null;
                  _onTargetChanged();
                }),
        ),
      ],
    );
  }

  // --- CH Play -----------------------------------------------------------------

  ReleaseWorkflowRun? _androidRun(_ReleaseTarget target) {
    Object? json;
    if (_commandPlatform == 'android' && _command != null) {
      json = _command!.result['androidRun'];
    }
    json ??= _overview?['androidRun'];
    if (json is! Map) return null;
    final run = ReleaseWorkflowRun.fromJson(Map<String, Object?>.from(json));
    return run.projectPath == target.key ? run : null;
  }

  Widget _android(BuildContext context, _ReleaseTarget target) {
    final run = _androidRun(target);
    final following =
        _commandPlatform == 'android' && _command?.isActive == true;
    final preparing = following && _command?.payload['action'] == 'prepare';
    final busy = following || _overview?['androidBusy'] == true;
    if (run == null || _newAndroid || preparing) {
      return _Panel(
        children: [
          _Title(icon: Icons.android, title: target.name),
          Text(target.detail, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final track in _tracks)
                ButtonSegment(value: track, label: Text(track)),
            ],
            selected: {_track},
            onSelectionChanged: busy
                ? null
                : (selection) => setState(() {
                    _track = selection.first;
                    _productionConfirmed = false;
                  }),
          ),
          if (_track == 'production')
            CheckboxListTile(
              value: _productionConfirmed,
              onChanged: busy
                  ? null
                  : (value) =>
                        setState(() => _productionConfirmed = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Tôi hiểu bản này lên thẳng track production.'),
              subtitle: const Text(
                'Luồng sẽ commit, push, build và upload mà không hỏi thêm.',
              ),
            ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const Key('mobile-release-android-prepare'),
            onPressed: busy || (_track == 'production' && !_productionConfirmed)
                ? null
                : () => _send('android', {
                    'action': 'prepare',
                    'projectPath': target.key,
                    'track': _track,
                  }),
            icon: preparing
                ? const _Spinner()
                : const Icon(Icons.manage_search),
            label: Text(preparing ? 'Đang chạy preflight…' : 'Xem lại release'),
          ),
          if (preparing) _log(context),
        ],
      );
    }
    final started = run.startedAt != null;
    return _Panel(
      children: [
        _Title(icon: Icons.android, title: run.projectName),
        Text(
          '${run.currentVersion} → ${run.proposedVersion} · ${run.track} · '
          'nhánh ${run.currentBranch}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (run.changedFiles.isNotEmpty)
          Text(
            '${run.changedFiles.length} file thay đổi sẽ được commit.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 10),
        for (final step in run.steps) _StepRow(step: step),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (run.isRunning || following)
              OutlinedButton.icon(
                onPressed: () async {
                  if (await _confirm(
                    'Dừng release?',
                    'Những thay đổi về version, Git hay upload đã xong sẽ '
                        'không được hoàn tác.',
                    'Dừng',
                  )) {
                    await _stop('android');
                  }
                },
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Dừng'),
              )
            else if (run.retryableStep != null)
              FilledButton.icon(
                onPressed: () => _send('android', {'action': 'retry'}),
                icon: const Icon(Icons.replay_outlined),
                label: const Text('Chạy lại bước lỗi'),
              )
            else if (!started)
              FilledButton.icon(
                key: const Key('mobile-release-android-start'),
                onPressed: () async {
                  if (run.track == 'production' &&
                      !await _confirm(
                        'Release lên production?',
                        '${run.projectName} ${run.proposedVersion} sẽ lên thẳng '
                            'production: commit, push, build và upload.',
                        'Bắt đầu',
                      )) {
                    return;
                  }
                  await _send('android', {
                    'action': 'start',
                    'confirmProduction': run.track == 'production',
                  });
                },
                icon: const Icon(Icons.rocket_launch),
                label: const Text('Bắt đầu release'),
              ),
            if (!run.isRunning && !following)
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _newAndroid = true;
                  _productionConfirmed = false;
                }),
                icon: const Icon(Icons.add),
                label: const Text('Release mới'),
              ),
          ],
        ),
        if (run.isRunning || following) _log(context),
      ],
    );
  }

  // --- App Store ---------------------------------------------------------------

  IosReleaseRun? _iosRun(_ReleaseTarget target) {
    Object? json;
    if (_commandPlatform == 'ios' && _command != null) {
      json = _command!.result['iosRun'];
    }
    if (json == null) {
      final runs = _iosProject?['runs'];
      final current = _overview?['iosCurrent'];
      if (current is Map && current['project'] is Map) {
        final project = current['project'] as Map;
        if (project['id'] == target.key && _overview?['iosBusy'] == true) {
          json = current;
        }
      }
      json ??= runs is List ? runs.firstOrNull : null;
    }
    if (json is! Map) return null;
    try {
      return iosRunFromWire(Map<String, dynamic>.from(json));
    } catch (_) {
      return null;
    }
  }

  Widget _ios(BuildContext context, _ReleaseTarget target) {
    final project = _iosProject;
    final host = '${project?['host'] ?? _overview?['iosHost'] ?? ''}';
    final following = _commandPlatform == 'ios' && _command?.isActive == true;
    final action = _command?.payload['action'];
    final preparing = following && (action == 'prepare' || action == 'inspect');
    final busy = following || project?['busy'] == true;
    final run = _iosRun(target);
    final header = [
      _Title(icon: Icons.apple, title: target.name),
      Text(
        '${target.detail}${host.isEmpty ? '' : ' · build trên $host'}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      if (project != null && host.isEmpty)
        const _Notice(
          icon: Icons.warning_amber_outlined,
          message:
              'Máy tính không build iOS được và chưa ghép Mac build. Ghép Mac '
              'trong bảng release iOS trên máy tính.',
        ),
    ];
    if (project == null) {
      return _Panel(
        children: [
          ...header,
          const SizedBox(height: 12),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (run == null || _newIos || preparing) {
      final ready = _builds?.where((build) => build.isReady).toList();
      return _Panel(
        children: [
          ...header,
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Build mới')),
              ButtonSegment(
                value: true,
                label: Text('Build TestFlight có sẵn'),
              ),
            ],
            selected: {_reuseBuild},
            onSelectionChanged: busy
                ? null
                : (selection) => setState(() {
                    _reuseBuild = selection.first;
                    _selectedBuild = null;
                  }),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _version,
            enabled: !busy,
            decoration: const InputDecoration(labelText: 'Marketing version'),
            onChanged: (_) => setState(() {
              _builds = null;
              _selectedBuild = null;
            }),
          ),
          if (_reuseBuild) ...[
            const SizedBox(height: 10),
            if (ready == null)
              OutlinedButton.icon(
                onPressed: busy || _loadingBuilds
                    ? null
                    : () {
                        setState(() => _loadingBuilds = true);
                        unawaited(
                          _send('ios', {
                            'action': 'inspect',
                            'projectId': target.key,
                            'version': _version.text.trim(),
                          }),
                        );
                      },
                icon: _loadingBuilds
                    ? const _Spinner()
                    : const Icon(Icons.cloud_sync),
                label: const Text('Lấy build TestFlight'),
              )
            else if (ready.isEmpty)
              const Text('Không có build VALID cho version này.')
            else
              DropdownButtonFormField<String>(
                initialValue: _selectedBuild?.id,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Build TestFlight',
                ),
                items: [
                  for (final build in ready)
                    DropdownMenuItem(
                      value: build.id,
                      child: Text('${build.version}+${build.number}'),
                    ),
                ],
                onChanged: (id) => setState(
                  () => _selectedBuild = ready.firstWhere((b) => b.id == id),
                ),
              ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _notes,
            enabled: !busy,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Release notes',
              hintText: 'What to Test / What\'s New',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const Key('mobile-release-ios-prepare'),
            onPressed:
                busy ||
                    host.isEmpty ||
                    _version.text.trim().isEmpty ||
                    (_reuseBuild && _selectedBuild == null)
                ? null
                : () => _send('ios', {
                    'action': 'prepare',
                    'projectId': target.key,
                    'version': _version.text.trim(),
                    'notes': _notes.text.trim(),
                    if (_reuseBuild && _selectedBuild != null)
                      'existingBuild': _selectedBuild!.toJson(),
                  }),
            icon: preparing && action == 'prepare'
                ? const _Spinner()
                : const Icon(Icons.manage_search),
            label: Text(
              preparing && action == 'prepare'
                  ? 'Đang chạy preflight…'
                  : 'Xem lại release',
            ),
          ),
          if (preparing && action == 'prepare') _log(context),
        ],
      );
    }

    final statuses = run.stageStatuses(
      running: following ? run.lastAction : null,
    );
    final primary = iosPrimaryStep(run);
    final secondary = iosSecondaryStep(run, primary);
    return _Panel(
      children: [
        ...header,
        const SizedBox(height: 8),
        Text(
          '${run.version}+${run.buildNumber} · ${_iosStatusLabel(run)}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (run.message.isNotEmpty)
          Text(run.message, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        for (final stage in IosReleaseStage.values)
          _StageRow(
            label: _iosStageLabel(stage, run),
            status: statuses[stage]!,
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (busy)
              OutlinedButton.icon(
                onPressed: () async {
                  if (await _confirm(
                    'Dừng luồng iOS?',
                    'Bản đã upload lên Apple không bị hoàn tác; kiểm tra lại '
                        'Apple trước khi thử lại.',
                    'Dừng',
                  )) {
                    await _stop('ios');
                  }
                },
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Dừng'),
              )
            else ...[
              FilledButton(
                key: Key('mobile-release-ios-${primary.id}'),
                onPressed: () => _iosAction(target, run, primary),
                child: Text(primary.label),
              ),
              if (secondary != null)
                OutlinedButton(
                  onPressed: () => _iosAction(target, run, secondary),
                  child: Text(secondary.label),
                ),
              if (run.status == IosReleaseStatus.verificationRequired &&
                  run.ipaPath != null)
                TextButton(
                  onPressed: () async {
                    if (await _confirm(
                      'Thử upload lại?',
                      'Apple chưa hiển thị ${run.version}+${run.buildNumber}. '
                          'Chỉ tiếp tục nếu đã kiểm tra lần upload trước thất bại.',
                      'Đã kiểm tra, thử lại',
                    )) {
                      await _send('ios', {
                        'action': 'retryUpload',
                        'projectId': target.key,
                        'runId': run.id,
                      });
                    }
                  },
                  child: const Text('Thử upload lại'),
                ),
            ],
          ],
        ),
        if (busy) _log(context),
      ],
    );
  }

  Future<void> _iosAction(
    _ReleaseTarget target,
    IosReleaseRun run,
    IosNextStep step,
  ) async {
    if (step.id == 'new') {
      setState(() => _newIos = true);
      return;
    }
    if (step.isStoreAction &&
        !await _confirm(
          '${step.label}?',
          '${run.project.name} ${run.version}+${run.buildNumber}'
              '${run.settings.notes.isEmpty ? '' : '\n\n${run.settings.notes}'}',
          step.label,
        )) {
      return;
    }
    await _send('ios', {
      'action': switch (step.id) {
        'testflight' => 'continue',
        final id => id,
      },
      'projectId': target.key,
      'runId': run.id,
    });
  }

  Widget _log(BuildContext context) {
    final lines = _command?.isActive == true
        ? _command!.logLines
        : (_overview?['logTail'] is List
              ? (_overview!['logTail']! as List).map((line) => '$line').toList()
              : const <String>[]);
    if (lines.isEmpty) return const SizedBox.shrink();
    final tail = lines.length > 14 ? lines.sublist(lines.length - 14) : lines;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            tail.join('\n'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
      ),
    );
  }
}

String _iosStatusLabel(IosReleaseRun run) => switch (run.status) {
  IosReleaseStatus.prepared => 'Đã xem lại',
  IosReleaseStatus.building => 'Đang build',
  IosReleaseStatus.built => 'Đã build IPA',
  IosReleaseStatus.uploading => 'Đang upload',
  IosReleaseStatus.processing => 'Apple đang xử lý',
  IosReleaseStatus.verificationRequired => 'Cần kiểm tra Apple',
  IosReleaseStatus.ready => 'TestFlight sẵn sàng',
  IosReleaseStatus.draft => 'Đã chuẩn bị App Store',
  IosReleaseStatus.submitted =>
    run.succeeded('release') ? 'Đang phát hành' : 'Đang review',
  IosReleaseStatus.released => 'Đã phát hành',
  IosReleaseStatus.failed => 'Lỗi',
  IosReleaseStatus.canceled => 'Đã dừng',
};

String _iosStageLabel(IosReleaseStage stage, IosReleaseRun run) =>
    switch (stage) {
      IosReleaseStage.prepare => 'Preflight',
      IosReleaseStage.build => 'Build IPA',
      IosReleaseStage.upload => 'Upload',
      IosReleaseStage.processing => 'Apple xử lý',
      IosReleaseStage.appStore => 'App Store',
      IosReleaseStage.review => 'Review',
      IosReleaseStage.release =>
        run.settings.automaticRelease ? 'Tự phát hành' : 'Phát hành',
    };

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final ReleaseWorkflowStepRun step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusIcon(status: step.status),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.label),
                if ((step.error ?? '').isNotEmpty)
                  Text(
                    step.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({required this.label, required this.status});

  final String label;
  final ReleaseStepStatus status;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          _StatusIcon(status: status),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final ReleaseStepStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (status == ReleaseStepStatus.running) return const _Spinner();
    final (icon, color) = switch (status) {
      ReleaseStepStatus.succeeded => (Icons.check_circle, Colors.green),
      ReleaseStepStatus.failed => (Icons.error, scheme.error),
      ReleaseStepStatus.canceled => (Icons.stop_circle, scheme.error),
      ReleaseStepStatus.warning => (Icons.warning_amber, Colors.orange),
      ReleaseStepStatus.skipped => (
        Icons.remove_circle_outline,
        scheme.outline,
      ),
      _ => (Icons.radio_button_unchecked, scheme.outline),
    };
    return Icon(icon, size: 18, color: color);
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // A Material, not a coloured box: the checkboxes inside paint their ink
    // on the nearest Material, which a coloured box would cover.
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message, this.color});

  final IconData icon;
  final String message;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}
