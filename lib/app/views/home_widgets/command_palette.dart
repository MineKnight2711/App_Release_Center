part of '../home_view.dart';

/// One row in the command palette.
///
/// [id] is stable across sessions so the most-recently-used list survives a
/// restart. Ids that name project-scoped things embed the identifier rather
/// than the index, so the entry keeps meaning when the list around it changes.
class _PaletteCommand {
  const _PaletteCommand({
    required this.id,
    required this.group,
    required this.icon,
    required this.title,
    required this.run,
    this.subtitle = '',
    this.keywords = const [],
    this.enabled = true,
    this.disabledReason = '',
  });

  final String id;
  final String group;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> keywords;
  final bool enabled;
  final String disabledReason;
  final Future<void> Function(BuildContext context) run;

  /// Everything a query is matched against, cheapest field first.
  String get haystack => [title, subtitle, group, ...keywords].join(' ');
}

/// A match with the score used to order results.
class _PaletteMatch {
  const _PaletteMatch({required this.command, required this.score});

  final _PaletteCommand command;
  final int score;
}

/// Vietnamese letters mapped to the ASCII key people actually type.
///
/// Typing without diacritics is the norm, so the palette has to match `tai
/// nguyen` against "Tài nguyên"; folding both sides makes that one comparison
/// instead of a special case.
const _paletteDiacriticFolding = <String, String>{
  'à': 'a',
  'á': 'a',
  'ả': 'a',
  'ã': 'a',
  'ạ': 'a',
  'ă': 'a',
  'ằ': 'a',
  'ắ': 'a',
  'ẳ': 'a',
  'ẵ': 'a',
  'ặ': 'a',
  'â': 'a',
  'ầ': 'a',
  'ấ': 'a',
  'ẩ': 'a',
  'ẫ': 'a',
  'ậ': 'a',
  'è': 'e',
  'é': 'e',
  'ẻ': 'e',
  'ẽ': 'e',
  'ẹ': 'e',
  'ê': 'e',
  'ề': 'e',
  'ế': 'e',
  'ể': 'e',
  'ễ': 'e',
  'ệ': 'e',
  'ì': 'i',
  'í': 'i',
  'ỉ': 'i',
  'ĩ': 'i',
  'ị': 'i',
  'ò': 'o',
  'ó': 'o',
  'ỏ': 'o',
  'õ': 'o',
  'ọ': 'o',
  'ô': 'o',
  'ồ': 'o',
  'ố': 'o',
  'ổ': 'o',
  'ỗ': 'o',
  'ộ': 'o',
  'ơ': 'o',
  'ờ': 'o',
  'ớ': 'o',
  'ở': 'o',
  'ỡ': 'o',
  'ợ': 'o',
  'ù': 'u',
  'ú': 'u',
  'ủ': 'u',
  'ũ': 'u',
  'ụ': 'u',
  'ư': 'u',
  'ừ': 'u',
  'ứ': 'u',
  'ử': 'u',
  'ữ': 'u',
  'ự': 'u',
  'ỳ': 'y',
  'ý': 'y',
  'ỷ': 'y',
  'ỹ': 'y',
  'ỵ': 'y',
  'đ': 'd',
};

/// Lowercases [value] and strips Vietnamese diacritics.
String _foldForPaletteSearch(String value) {
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final character = String.fromCharCode(rune);
    buffer.write(_paletteDiacriticFolding[character] ?? character);
  }
  return buffer.toString();
}

/// Scores [query] against [text] as a case- and diacritic-insensitive
/// subsequence.
///
/// Returns null when the characters of [query] do not appear in order. The
/// score rewards matches that start a word and matches that run consecutively,
/// so typing `fdep` ranks "Fastlane: Deploy" above "Đi tới Fastlane".
int? _scorePaletteMatch(String text, String query) {
  if (query.isEmpty) return 0;
  final haystack = _foldForPaletteSearch(text);
  final needle = _foldForPaletteSearch(query);

  var score = 0;
  var cursor = 0;
  var previousIndex = -2;

  for (final rune in needle.runes) {
    final character = String.fromCharCode(rune);
    if (character == ' ') continue;
    final index = haystack.indexOf(character, cursor);
    if (index < 0) return null;

    if (index == previousIndex + 1) {
      score += 8;
    }
    if (index == 0 ||
        haystack[index - 1] == ' ' ||
        haystack[index - 1] == ':') {
      score += 12;
    }
    score -= (index - cursor).clamp(0, 8);

    previousIndex = index;
    cursor = index + 1;
  }

  // Shorter titles win ties: they are the more direct answer to the query.
  return score - (haystack.length ~/ 24);
}

/// Builds the full command list for the current state of the app.
///
/// Rebuilt on every keystroke, which keeps `enabled` honest: a lane that just
/// became unavailable because a run started goes grey without extra plumbing.
List<_PaletteCommand> _buildPaletteCommands({
  required HomeController controller,
  required AppShellController shell,
}) {
  final project = controller.project.value;
  final isBusy = controller.runner.isBusy;
  final hasProject = project != null;

  const noProject = 'Chọn dự án trước đã';
  const busy = 'Đang có lệnh chạy';

  String projectGate() => !hasProject ? noProject : (isBusy ? busy : '');

  final commands = <_PaletteCommand>[
    _PaletteCommand(
      id: 'project.choose',
      group: 'Dự án',
      icon: Icons.drive_folder_upload_outlined,
      title: 'Mở thư mục dự án…',
      subtitle: 'Chọn thư mục rồi chạy trình thiết lập',
      keywords: const ['folder', 'thu muc', 'chon', 'du an'],
      run: (context) async {
        final loaded = await controller.pickProjectDirectory();
        if (!loaded || !context.mounted) return;
        await _runProjectSetupWizard(context);
      },
    ),
  ];

  // Recent projects come next: switching project is the single most common
  // reason to reach for the mouse, and the palette removes the file dialog.
  for (final path in controller.recentPaths) {
    final isCurrent = project?.path == path;
    commands.add(
      _PaletteCommand(
        id: 'project.open:$path',
        group: 'Dự án',
        icon: isCurrent
            ? Icons.radio_button_checked_outlined
            : Icons.folder_outlined,
        title: p.basename(path),
        subtitle: isCurrent ? 'Đang mở · $path' : path,
        keywords: [path],
        enabled: !isCurrent && !isBusy,
        disabledReason: isCurrent ? 'Đang mở' : busy,
        run: (context) => controller.loadProject(path),
      ),
    );
  }

  commands.addAll([
    _PaletteCommand(
      id: 'release.run',
      group: 'Release',
      icon: Icons.rocket_launch_outlined,
      title: controller.releaseWorkflow.currentRun.value != null
          ? 'Theo dõi release'
          : 'Chạy release',
      subtitle: 'Mở bảng theo dõi luồng release',
      keywords: const ['deploy', 'phat hanh', 'workflow'],
      enabled:
          controller.releaseWorkflow.currentRun.value != null ||
          (hasProject && !isBusy),
      disabledReason: projectGate(),
      run: (context) => showReleaseWorkflowDialog(context),
    ),
    _PaletteCommand(
      id: 'release.notes',
      group: 'Release',
      icon: Icons.auto_awesome_outlined,
      title: 'Tạo release note',
      subtitle: 'Soạn note từ các commit kể từ bản release trước',
      keywords: const ['ai', 'gemini', 'changelog', 'ghi chu'],
      enabled: hasProject && !controller.isGeneratingReleaseNotes.value,
      disabledReason: hasProject ? 'Đang tạo rồi' : noProject,
      run: (_) => controller.generateReleaseNotes(),
    ),
    _PaletteCommand(
      id: 'release.refreshStores',
      group: 'Release',
      icon: Icons.refresh_outlined,
      title: 'Làm mới bản trên store',
      subtitle: 'Đọc lại phiên bản đang có trên CH Play và App Store',
      keywords: const ['play', 'appstore', 'phien ban'],
      run: (_) => controller.refreshAllStoreProjects(),
    ),
  ]);

  for (final lane in project?.fastlaneLanes ?? const <ReleaseFastlaneLane>[]) {
    commands.add(
      _PaletteCommand(
        id: 'fastlane.lane:${lane.key}',
        group: 'Fastlane',
        icon: Icons.alt_route_outlined,
        title: 'Fastlane: ${lane.label}',
        subtitle: lane.command,
        keywords: [lane.name, lane.platform ?? '', lane.summary],
        enabled: !isBusy,
        disabledReason: busy,
        run: (_) => controller.runFastlaneLane(lane),
      ),
    );
  }

  for (final script in project?.scripts ?? const <ReleaseScript>[]) {
    commands.add(
      _PaletteCommand(
        id: 'script.run:${script.fileName}',
        group: 'Script',
        icon: Icons.terminal_outlined,
        title: 'Script: ${script.label}',
        subtitle: '${script.fileName} — ${script.description}',
        keywords: [script.fileName],
        enabled: !isBusy,
        disabledReason: busy,
        run: (_) => controller.runScript(script),
      ),
    );
  }

  commands.addAll([
    _PaletteCommand(
      id: 'tool.apiTool',
      group: 'Công cụ',
      icon: Icons.api_outlined,
      title: 'API Tool',
      subtitle: 'Gửi và lưu request HTTP',
      keywords: const ['http', 'request', 'postman'],
      run: (context) => showApiToolDialog(context),
    ),
    _PaletteCommand(
      id: 'tool.apiMonitor',
      group: 'Công cụ',
      icon: Icons.query_stats_outlined,
      title: 'API Monitor',
      subtitle: 'Mở dashboard giám sát',
      keywords: const ['dashboard', 'log', 'giam sat'],
      run: (context) => showApiMonitorDialog(context),
    ),
    _PaletteCommand(
      id: 'tool.apiMonitor.window',
      group: 'Công cụ',
      icon: Icons.open_in_new_outlined,
      title: 'API Monitor ở cửa sổ riêng',
      subtitle: 'Để dashboard nằm cạnh app',
      keywords: const ['dashboard', 'cua so'],
      run: (_) => Get.find<ApiMonitorService>().openStandaloneWindow(),
    ),
    _PaletteCommand(
      id: 'tool.apiMonitor.browser',
      group: 'Công cụ',
      icon: Icons.public_outlined,
      title: 'API Monitor trên trình duyệt',
      subtitle: 'Mở URL dashboard ngoài app',
      keywords: const ['dashboard', 'trinh duyet'],
      run: (_) => Get.find<ApiMonitorService>().openInBrowser(),
    ),
    _PaletteCommand(
      id: 'tool.apiMonitor.copyUrl',
      group: 'Công cụ',
      icon: Icons.copy_outlined,
      title: 'Sao chép URL dashboard API Monitor',
      keywords: const ['clipboard', 'url'],
      run: (_) => Get.find<ApiMonitorService>().copyDashboardUrl(),
    ),
    _PaletteCommand(
      id: 'tool.flowfin',
      group: 'Công cụ',
      icon: Icons.account_balance_wallet_outlined,
      title: 'FlowFin',
      subtitle: 'Ví, ngân sách và giao dịch',
      keywords: const ['tien', 'chi tieu', 'ngan sach', 'vi'],
      run: (context) => showFlowFinDialog(context),
    ),
    if (Get.isRegistered<AuthService>())
      _PaletteCommand(
        id: 'tool.team',
        group: 'Công cụ',
        icon: Icons.groups_outlined,
        title: 'Nhóm',
        subtitle: 'Quản lý ai dùng chung workspace này',
        keywords: const ['thanh vien', 'moi', 'nhom'],
        run: (context) => showTeamManagementDialog(context),
      ),
  ]);

  commands.addAll([
    _PaletteCommand(
      id: 'maintenance.flutterClean',
      group: 'Bảo trì',
      icon: Icons.cleaning_services_outlined,
      title: 'Flutter clean',
      subtitle: 'Xoá artifact build trong dự án này',
      enabled: hasProject && !isBusy,
      disabledReason: projectGate(),
      run: (context) =>
          _runExtendedAction(context, _ExtendedAction.flutterClean),
    ),
    _PaletteCommand(
      id: 'maintenance.flutterPubGet',
      group: 'Bảo trì',
      icon: Icons.download_for_offline_outlined,
      title: 'Flutter pub get',
      subtitle: 'Tải dependency của Dart và Flutter',
      enabled: hasProject && !isBusy,
      disabledReason: projectGate(),
      run: (context) =>
          _runExtendedAction(context, _ExtendedAction.flutterPubGet),
    ),
    _PaletteCommand(
      id: 'maintenance.pullBranch',
      group: 'Bảo trì',
      icon: Icons.call_received_outlined,
      title: 'Pull branch từ remote',
      subtitle: 'Chạy git pull cho một remote và branch',
      keywords: const ['git', 'branch'],
      enabled: hasProject && !isBusy,
      disabledReason: projectGate(),
      run: (context) =>
          _runExtendedAction(context, _ExtendedAction.pullRemoteBranch),
    ),
    _PaletteCommand(
      id: 'maintenance.cloneCicd',
      group: 'Bảo trì',
      icon: Icons.android_outlined,
      title: 'Clone Android CI/CD',
      subtitle: 'Xem trước rồi dựng Fastlane và bộ auto tool',
      enabled: hasProject && !isBusy,
      disabledReason: projectGate(),
      run: (context) =>
          _runExtendedAction(context, _ExtendedAction.cloneAndroidCicd),
    ),
    _PaletteCommand(
      id: 'maintenance.generateJks',
      group: 'Bảo trì',
      icon: Icons.vpn_key_outlined,
      title: 'Tạo Android JKS',
      subtitle: 'Tạo upload keystore và cấu hình ký',
      keywords: const ['keystore', 'ky', 'sign'],
      enabled: hasProject && !isBusy,
      disabledReason: projectGate(),
      run: (context) =>
          _runExtendedAction(context, _ExtendedAction.generateAndroidJks),
    ),
    _PaletteCommand(
      id: 'maintenance.updateFastlane',
      group: 'Bảo trì',
      icon: Icons.system_update_alt_outlined,
      title: 'Kiểm tra và cập nhật Fastlane',
      subtitle: 'Chạy fastlane --version rồi gem update cho user',
      enabled: hasProject && !isBusy,
      disabledReason: projectGate(),
      run: (context) =>
          _runExtendedAction(context, _ExtendedAction.updateFastlaneWithGem),
    ),
    _PaletteCommand(
      id: 'maintenance.checkDependencies',
      group: 'Bảo trì',
      icon: Icons.health_and_safety_outlined,
      title: 'Kiểm tra dependency CI/CD',
      subtitle: 'Chạy trình chẩn đoán toolchain',
      keywords: const ['doctor', 'git', 'jdk'],
      enabled: !controller.isCheckingCiCdDependencies.value,
      disabledReason: 'Đang kiểm tra rồi',
      run: (_) => controller.checkCiCdDependencies(),
    ),
  ]);

  for (final tab in ShellFlowTab.values) {
    commands.add(
      _PaletteCommand(
        id: 'goto.flow:${tab.name}',
        group: 'Đi tới',
        icon: tab.paletteIcon,
        title: 'Đi tới ${tab.paletteLabel}',
        subtitle: 'Bảng Tự động hoá',
        run: (_) async => shell.showFlowTab(tab),
      ),
    );
  }

  for (final tab in ShellOptionsTab.values) {
    commands.add(
      _PaletteCommand(
        id: 'goto.options:${tab.name}',
        group: 'Đi tới',
        icon: tab.icon,
        title: 'Đi tới tuỳ chọn ${tab.label}',
        subtitle: 'Bảng Tuỳ chọn',
        run: (_) async => shell.showOptionsTab(tab),
      ),
    );
  }

  commands.addAll([
    _PaletteCommand(
      id: 'run.stop',
      group: 'Điều khiển',
      icon: Icons.stop_circle_outlined,
      title: 'Dừng lệnh đang chạy',
      enabled: controller.runner.isRunning.value,
      disabledReason: 'Không có lệnh nào đang chạy',
      run: (_) => controller.stopRun(),
    ),
    _PaletteCommand(
      id: 'run.clearLog',
      group: 'Điều khiển',
      icon: Icons.clear_all_outlined,
      title: 'Xoá log',
      run: (_) async => controller.clearLog(),
    ),
  ]);

  return commands;
}

extension _ShellFlowTabPaletteMeta on ShellFlowTab {
  IconData get paletteIcon {
    return switch (this) {
      ShellFlowTab.storeVersions => Icons.shop_two_outlined,
      ShellFlowTab.fastlaneFlow => Icons.schema_outlined,
      ShellFlowTab.fastlaneCommand => Icons.alt_route_outlined,
    };
  }

  String get paletteLabel {
    return switch (this) {
      ShellFlowTab.storeVersions => 'Bản trên store',
      ShellFlowTab.fastlaneFlow => 'Luồng Fastlane',
      ShellFlowTab.fastlaneCommand => 'Lệnh Fastlane',
    };
  }
}

/// The Ctrl+K overlay.
///
/// Opens on the most-recently-used commands so the frequent case costs one
/// keystroke and no typing; typing narrows across every action in the app,
/// including the ones otherwise buried two tabs deep.
class _CommandPalette extends StatefulWidget {
  const _CommandPalette();

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  static const double _rowHeight = 52;

  final _queryController = TextEditingController();
  final _scrollController = ScrollController();

  /// Escape has to be caught on the query field's own focus node: the text
  /// field turns Escape into a `DismissIntent` and registers its own action for
  /// it, so a shortcut on any ancestor never sees the key.
  late final FocusNode _queryFocus = FocusNode(
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent ||
          event.logicalKey != LogicalKeyboardKey.escape) {
        return KeyEventResult.ignored;
      }
      _shell.closePalette();
      return KeyEventResult.handled;
    },
  );

  String _query = '';
  int _highlighted = 0;

  HomeController get _home => Get.find<HomeController>();
  AppShellController get _shell => Get.find<AppShellController>();

  @override
  void initState() {
    super.initState();
    // The scaffold holds an autofocused node so Ctrl+K works before the user
    // has clicked anything; the query field has to take focus back explicitly
    // once the palette is on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _queryFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    _queryFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<_PaletteCommand> _visibleCommands() {
    final all = _buildPaletteCommands(controller: _home, shell: _shell);

    if (_query.trim().isEmpty) {
      final byId = {for (final command in all) command.id: command};
      // Recents first, then everything else in registration order. Ids that no
      // longer resolve (a lane from a closed project) are simply skipped.
      final recent = _shell.recentCommandIds
          .map((id) => byId[id])
          .whereType<_PaletteCommand>()
          .toList();
      final recentIds = recent.map((command) => command.id).toSet();
      return [
        ...recent,
        ...all.where((command) => !recentIds.contains(command.id)),
      ];
    }

    final matches = <_PaletteMatch>[];
    for (final command in all) {
      final score = _scorePaletteMatch(command.haystack, _query.trim());
      if (score == null) continue;
      matches.add(_PaletteMatch(command: command, score: score));
    }
    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches.map((match) => match.command).toList();
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      _highlighted = 0;
    });
  }

  void _moveHighlight(int delta, int count) {
    if (count == 0) return;
    setState(() {
      _highlighted = (_highlighted + delta) % count;
      if (_highlighted < 0) _highlighted += count;
    });
    _scrollHighlightIntoView();
  }

  void _scrollHighlightIntoView() {
    if (!_scrollController.hasClients) return;
    final target = _highlighted * _rowHeight;
    final position = _scrollController.position;
    final viewportTop = position.pixels;
    final viewportBottom = viewportTop + position.viewportDimension;
    if (target < viewportTop) {
      _scrollController.jumpTo(target);
    } else if (target + _rowHeight > viewportBottom) {
      _scrollController.jumpTo(
        (target + _rowHeight - position.viewportDimension).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    }
  }

  Future<void> _runCommand(_PaletteCommand command) async {
    if (!command.enabled) return;
    _shell.closePalette();
    unawaited(_shell.markCommandUsed(command.id));
    // The palette is already gone; hand the still-mounted scaffold context to
    // commands that open a dialog of their own.
    await command.run(context);
  }

  @override
  Widget build(BuildContext context) {
    final commands = _visibleCommands();
    final highlighted = commands.isEmpty
        ? -1
        : _highlighted.clamp(0, commands.length - 1);

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _shell.closePalette,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
            ),
          ),
          Align(
            alignment: const Alignment(0, -0.55),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    _shell.closePalette(),
                const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                    _moveHighlight(1, commands.length),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                    _moveHighlight(-1, commands.length),
                const SingleActivator(LogicalKeyboardKey.enter): () {
                  if (highlighted < 0) return;
                  unawaited(_runCommand(commands[highlighted]));
                },
                const SingleActivator(LogicalKeyboardKey.numpadEnter): () {
                  if (highlighted < 0) return;
                  unawaited(_runCommand(commands[highlighted]));
                },
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Material(
                  key: const Key('command-palette'),
                  color: Colors.transparent,
                  child: _Panel(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          key: const Key('command-palette-query'),
                          controller: _queryController,
                          focusNode: _queryFocus,
                          autofocus: true,
                          onChanged: _onQueryChanged,
                          style: AppCyberTheme.dataTextStyle(
                            size: 13,
                            color: AppCyberTheme.textPrimary,
                          ),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search_outlined),
                            hintText: 'Gõ tên lệnh, dự án hoặc lane…',
                            border: InputBorder.none,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Divider(
                          height: 1,
                          color: AppCyberTheme.lineBlue.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 6),
                        if (commands.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 26),
                            child: Center(
                              child: Text(
                                'Không có lệnh nào khớp "${_query.trim()}"',
                                style: AppCyberTheme.dataTextStyle(
                                  size: 11.5,
                                  color: AppCyberTheme.textMuted,
                                ),
                              ),
                            ),
                          )
                        else
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 380),
                            child: Scrollbar(
                              controller: _scrollController,
                              child: ListView.builder(
                                controller: _scrollController,
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemExtent: _rowHeight,
                                itemCount: commands.length,
                                itemBuilder: (context, index) {
                                  return _PaletteRow(
                                    command: commands[index],
                                    selected: index == highlighted,
                                    onTap: () =>
                                        unawaited(_runCommand(commands[index])),
                                    onHover: () {
                                      if (_highlighted == index) return;
                                      setState(() => _highlighted = index);
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        const _PaletteFooter(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaletteRow extends StatelessWidget {
  const _PaletteRow({
    required this.command,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final _PaletteCommand command;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final enabled = command.enabled;
    final foreground = !enabled
        ? AppCyberTheme.textMuted.withValues(alpha: 0.55)
        : selected
        ? AppCyberTheme.electricBlue
        : AppCyberTheme.textPrimary;
    final subtitle = enabled
        ? command.subtitle
        : (command.disabledReason.isEmpty
              ? command.subtitle
              : command.disabledReason);

    return InkWell(
      key: Key('command-palette-item-${command.id}'),
      onTap: enabled ? onTap : null,
      onHover: (hovering) {
        if (hovering) onHover();
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: selected
              ? AppCyberTheme.electricBlue.withValues(alpha: 0.13)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(command.icon, size: 17, color: foreground),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    command.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppCyberTheme.dataTextStyle(
                      size: 12,
                      color: foreground,
                      weight: selected ? FontWeight.w800 : FontWeight.w700,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppCyberTheme.dataTextStyle(
                        size: 10.5,
                        color: AppCyberTheme.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              command.group.toUpperCase(),
              style: AppCyberTheme.dataTextStyle(
                size: 9.5,
                color: AppCyberTheme.textMuted.withValues(alpha: 0.8),
                weight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaletteFooter extends StatelessWidget {
  const _PaletteFooter();

  @override
  Widget build(BuildContext context) {
    final style = AppCyberTheme.dataTextStyle(
      size: 10,
      color: AppCyberTheme.textMuted,
    );
    return Row(
      children: [
        Text('↑↓ di chuyển', style: style),
        const SizedBox(width: 14),
        Text('Enter chạy', style: style),
        const SizedBox(width: 14),
        Text('Esc đóng', style: style),
      ],
    );
  }
}

/// The always-visible way in, for the days the shortcut is not yet muscle
/// memory. Reads as a search field because that is what it does.
class _CommandPaletteBar extends StatelessWidget {
  const _CommandPaletteBar({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final shell = Get.find<AppShellController>();
    final border = Border.all(
      color: AppCyberTheme.lineBlue.withValues(alpha: 0.5),
    );

    return Tooltip(
      message: 'Tìm lệnh (Ctrl+K)',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('open-command-palette'),
          borderRadius: BorderRadius.circular(8),
          onTap: shell.openPalette,
          child: Container(
            height: 36,
            width: compact ? 36 : null,
            alignment: compact ? Alignment.center : null,
            padding: compact
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: border,
              color: AppCyberTheme.panelBackgroundStrong.withValues(
                alpha: AppCyberTheme.isCyber ? 0.34 : 0.82,
              ),
            ),
            child: compact
                ? Icon(
                    Icons.search_outlined,
                    size: 18,
                    color: AppCyberTheme.textMuted,
                  )
                : Row(
                    children: [
                      Icon(
                        Icons.search_outlined,
                        size: 17,
                        color: AppCyberTheme.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tìm lệnh, dự án, lane\u2026',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppCyberTheme.dataTextStyle(
                            size: 11.5,
                            color: AppCyberTheme.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Ctrl+K',
                        style: AppCyberTheme.dataTextStyle(
                          size: 10.5,
                          color: AppCyberTheme.textMuted.withValues(alpha: 0.9),
                          weight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
