import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/module_widgets.dart';
import '../controllers/qa_workspace_controller.dart';
import '../models/automation_models.dart';
import '../models/qa_models.dart';
import '../services/account_vault.dart';
import '../services/maestro_manager.dart';
import '../services/vault_cipher.dart';
import '../theme/qa_tokens.dart';
import '../widgets/qa_widgets.dart';

/// The demo accounts QA Desk logs in with, and the tool that does it.
Future<void> showVaultSheet(
  BuildContext context,
  QaWorkspaceController controller,
) {
  return showQaSideSheet<void>(
    context,
    key: const Key('qa-vault-sheet'),
    title: 'Tài khoản demo',
    subtitle: 'Tài khoản QA Desk dùng để tự đăng nhập và thao tác',
    width: 600,
    builder: (_) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _VaultBody(controller: controller),
    ),
  );
}

/// Every app the sources declare, with the source that declares it.
List<({QaSource source, QaApp app})> declaredApps(
  QaWorkspaceController controller,
) => [
  for (final source in controller.sources)
    for (final app in source.apps) (source: source, app: app),
];

class _VaultBody extends StatelessWidget {
  const _VaultBody({required this.controller});

  final QaWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final runner = controller.automation;
    if (runner == null) {
      return const QaEmptyState(
        icon: Icons.lock_outline,
        title: 'Chưa dùng được',
        message: 'QA Desk chưa nối kho tài khoản và Maestro.',
      );
    }
    final vault = runner.vault;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MaestroCard(controller: controller),
        const SizedBox(height: 18),
        SectionLabel(
          vault.mode == VaultMode.team
              ? 'Kho của team · ${vault.label}'
              : 'Kho trên máy này',
          action: vault.state == VaultState.ready
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (vault is TeamAccountVault)
                      IconButton(
                        tooltip: 'Tải lại',
                        onPressed: vault.refresh,
                        icon: const Icon(Icons.refresh, size: 18),
                      ),
                    if (vault.mode == VaultMode.team)
                      TextButton.icon(
                        onPressed: vault.lock,
                        icon: const Icon(Icons.lock_outline, size: 16),
                        label: const Text('Khoá trên máy này'),
                      ),
                  ],
                )
              : null,
        ),
        const SizedBox(height: 8),
        switch (vault.state) {
          VaultState.loading => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          VaultState.failed => _Failed(vault: vault),
          VaultState.needsSetup => _Setup(vault: vault),
          VaultState.locked => _Unlock(vault: vault),
          VaultState.ready => _Accounts(controller: controller, vault: vault),
        },
      ],
    );
  }
}

class _MaestroCard extends StatefulWidget {
  const _MaestroCard({required this.controller});

  final QaWorkspaceController controller;

  @override
  State<_MaestroCard> createState() => _MaestroCardState();
}

class _MaestroCardState extends State<_MaestroCard> {
  double? _progress;
  String? _step;
  String? _error;

  Future<void> _install() async {
    final runner = widget.controller.automation!;
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      await runner.maestro.install(
        onProgress: (received, total) =>
            setState(() => _progress = received / total),
        onStep: (step) => setState(() => _step = step),
      );
      await widget.controller.refreshAutomationStatus();
    } on MaestroException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() {
          _progress = null;
          _step = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    final status = widget.controller.automation?.status;
    final ready = status?.ready ?? false;
    final installing = _progress != null;
    return ModuleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                ready ? Icons.check_circle : Icons.smart_toy_outlined,
                color: ready ? tokens.palette.success : tokens.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Maestro ${MaestroManager.version}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      ready
                          ? 'Sẵn sàng · Java ${status!.javaVersion}'
                          : status?.problem ?? 'Đang kiểm tra…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ready ? tokens.muted : tokens.palette.warning,
                      ),
                    ),
                  ],
                ),
              ),
              if (status != null && !status.installed)
                FilledButton.icon(
                  key: const Key('qa-install-maestro'),
                  onPressed: installing ? null : _install,
                  icon: const Icon(Icons.download, size: 17),
                  label: const Text('Tải Maestro (≈300 MB)'),
                )
              else
                IconButton(
                  tooltip: 'Kiểm tra lại',
                  onPressed: widget.controller.refreshAutomationStatus,
                  icon: const Icon(Icons.refresh, size: 18),
                ),
            ],
          ),
          if (installing) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: _step == 'Đang giải nén Maestro' ? null : _progress,
            ),
            const SizedBox(height: 4),
            Text(
              '${_step ?? 'Đang tải'} · '
              '${((_progress ?? 0) * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.bodySmall?.copyWith(color: tokens.muted),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            NoticeBox(text: _error!, tone: NoticeTone.danger),
          ],
          if (status != null && status.installed && !status.javaOk) ...[
            const SizedBox(height: 10),
            const NoticeBox(
              text:
                  'Cài Java 17 trở lên (hoặc Android Studio, có sẵn Java), '
                  'rồi bấm kiểm tra lại.',
              tone: NoticeTone.warning,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Maestro là công cụ điều khiển app trên máy ảo, điện thoại và '
            'trình duyệt. Tải từ GitHub, kiểm SHA-256 trước khi giải nén, '
            'không sửa PATH.',
            style: theme.textTheme.bodySmall?.copyWith(color: tokens.muted),
          ),
        ],
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.vault});

  final AccountVault vault;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      NoticeBox(
        text: vault.error ?? 'Không mở được kho.',
        tone: NoticeTone.danger,
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: vault.load,
          icon: const Icon(Icons.refresh, size: 17),
          label: const Text('Thử lại'),
        ),
      ),
    ],
  );
}

class _Setup extends StatefulWidget {
  const _Setup({required this.vault});

  final AccountVault vault;

  @override
  State<_Setup> createState() => _SetupState();
}

class _SetupState extends State<_Setup> {
  final _passphrase = TextEditingController();
  final _again = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _passphrase.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_passphrase.text != _again.text) {
      setState(() => _error = 'Hai lần nhập passphrase không khớp.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.vault.create(_passphrase.text);
    } on VaultException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.vault.canEdit) {
      return const NoticeBox(
        text:
            'Team chưa có kho tài khoản demo. Nhờ Admin của team tạo kho '
            'trong QA Desk.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const NoticeBox(
          text:
              'Tài khoản được mã hoá trên máy bằng passphrase của team; '
              'server chỉ giữ bản mã. Mỗi thành viên nhập passphrase một '
              'lần trên máy của mình. Mất passphrase là phải tạo lại kho: hãy '
              'lưu nó trong password manager của team.',
          icon: Icons.lock_outline,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('qa-vault-passphrase'),
          controller: _passphrase,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Passphrase của kho',
            helperText: 'Ít nhất 12 ký tự.',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('qa-vault-passphrase-again'),
          controller: _again,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Nhập lại passphrase'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          NoticeBox(text: _error!, tone: NoticeTone.danger),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const Key('qa-vault-create'),
            onPressed: _busy ? null : _create,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_moderator_outlined, size: 17),
            label: const Text('Tạo kho cho team'),
          ),
        ),
      ],
    );
  }
}

class _Unlock extends StatefulWidget {
  const _Unlock({required this.vault});

  final AccountVault vault;

  @override
  State<_Unlock> createState() => _UnlockState();
}

class _UnlockState extends State<_Unlock> {
  final _passphrase = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.vault.unlock(_passphrase.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const NoticeBox(
        text:
            'Kho của team đang khoá trên máy này. Nhập passphrase một lần; '
            'máy nhớ khoá trong Windows secure storage.',
        icon: Icons.lock_outline,
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('qa-vault-unlock-passphrase'),
        controller: _passphrase,
        obscureText: true,
        onSubmitted: (_) => _unlock(),
        decoration: const InputDecoration(labelText: 'Passphrase của kho'),
      ),
      if (_error != null) ...[
        const SizedBox(height: 10),
        NoticeBox(text: _error!, tone: NoticeTone.danger),
      ],
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          key: const Key('qa-vault-unlock'),
          onPressed: _busy ? null : _unlock,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_open, size: 17),
          label: const Text('Mở khoá'),
        ),
      ),
    ],
  );
}

class _Accounts extends StatelessWidget {
  const _Accounts({required this.controller, required this.vault});

  final QaWorkspaceController controller;
  final AccountVault vault;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    final apps = declaredApps(controller);
    final accounts = vault.accounts;
    String appName(String id) {
      for (final item in apps) {
        if (item.app.id == id) return item.app.name;
      }
      return id;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (apps.isEmpty)
          const NoticeBox(
            text:
                'Chưa nguồn nào khai app trong .fiza-qa/project.yaml (mục '
                'apps:). Khai app trước để tài khoản biết đăng nhập vào đâu.',
            tone: NoticeTone.warning,
          ),
        if (accounts.isEmpty && apps.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Chưa có tài khoản nào.',
              style: theme.textTheme.bodySmall?.copyWith(color: tokens.muted),
            ),
          ),
        for (final account in accounts) ...[
          _AccountRow(
            controller: controller,
            vault: vault,
            account: account,
            appName: appName(account.app),
          ),
          const SizedBox(height: 8),
        ],
        if (vault.canEdit && apps.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('qa-add-account'),
                onPressed: () =>
                    showAccountEditor(context, controller: controller),
                icon: const Icon(Icons.person_add_alt, size: 17),
                label: const Text('Thêm tài khoản'),
              ),
              if (vault case final TeamAccountVault team)
                TextButton.icon(
                  key: const Key('qa-import-local-accounts'),
                  onPressed: () => _importLocal(context, team),
                  icon: const Icon(Icons.drive_file_move_outline, size: 17),
                  label: const Text('Chép từ kho trên máy này'),
                ),
            ],
          ),
        ],
        if (!vault.canEdit)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Chỉ Admin của team thêm, sửa hoặc xem mật khẩu tài khoản.',
              style: theme.textTheme.bodySmall?.copyWith(color: tokens.muted),
            ),
          ),
        const SizedBox(height: 14),
        Text(
          'Chỉ dùng tài khoản test riêng, quyền tối thiểu, không bao giờ là '
          'tài khoản cá nhân. Ai chạy được automation thì máy đó giải mã được '
          'mật khẩu để nhập vào app.',
          style: theme.textTheme.bodySmall?.copyWith(color: tokens.muted),
        ),
      ],
    );
  }
}

/// Copies the accounts kept on this machine, from before the team vault,
/// into the team's.
Future<void> _importLocal(BuildContext context, TeamAccountVault team) async {
  final local = LocalAccountVault(store: const SecureSecretStore());
  await local.load();
  if (!context.mounted) return;
  final accounts = local.accounts;
  if (accounts.isEmpty) {
    showQaMessage(context, 'Kho trên máy này không có tài khoản nào.');
    return;
  }
  final confirmed = await confirmQa(
    context,
    title: 'Chép ${accounts.length} tài khoản vào kho của team?',
    message:
        'Cả team sẽ dùng được các tài khoản này. Tài khoản cùng mã sẽ bị ghi '
        'đè; kho trên máy này giữ nguyên.',
    confirmLabel: 'Chép',
  );
  if (!confirmed) return;
  try {
    final count = await team.importAccounts(accounts);
    if (context.mounted) showQaMessage(context, 'Đã chép $count tài khoản.');
  } on Object catch (error) {
    if (context.mounted) showQaMessage(context, 'Không chép được: $error');
  }
}

class _AccountRow extends StatefulWidget {
  const _AccountRow({
    required this.controller,
    required this.vault,
    required this.account,
    required this.appName,
  });

  final QaWorkspaceController controller;
  final AccountVault vault;
  final DemoAccount account;
  final String appName;

  @override
  State<_AccountRow> createState() => _AccountRowState();
}

class _AccountRowState extends State<_AccountRow> {
  bool _checking = false;
  String? _checkMessage;
  bool? _checkOk;

  Future<void> _check() async {
    final account = widget.account;
    QaSource? source;
    for (final item in declaredApps(widget.controller)) {
      if (item.app.id == account.app) source = item.source;
    }
    if (source == null) {
      setState(() {
        _checkOk = false;
        _checkMessage = 'Không nguồn nào khai app "${account.app}".';
      });
      return;
    }
    setState(() {
      _checking = true;
      _checkMessage = null;
    });
    final result = await widget.controller.checkAccountLogin(
      source.id,
      account.app,
      account,
    );
    if (!mounted) return;
    setState(() {
      _checking = false;
      _checkOk = result.ok;
      _checkMessage = result.message;
    });
  }

  Future<void> _reveal() async {
    await widget.vault.recordReveal(widget.account.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Mật khẩu · ${widget.account.role}'),
        content: SelectableText(
          widget.account.password,
          style: QaTokens.of(context).mono(size: 14),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: widget.account.password),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Copy và đóng'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await confirmQa(
      context,
      title: 'Xoá tài khoản?',
      message:
          'Xoá "${widget.account.role}" (${widget.account.maskedUsername}) '
          'khỏi kho. Kịch bản dùng vai trò này sẽ không chạy được tới khi có '
          'tài khoản khác.',
      confirmLabel: 'Xoá',
    );
    if (confirmed) await widget.vault.delete(widget.account.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    final palette = tokens.palette;
    final account = widget.account;
    final lease = widget.vault.leases[account.id];
    final held = lease != null && !lease.expiredAt(DateTime.now());
    final production = widget.controller.isProductionEnvironment(
      account.environment,
    );
    final failed = account.status == AccountStatus.loginFailed;

    return Container(
      key: Key('qa-account-${account.id}'),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: tokens.well,
        borderRadius: BorderRadius.circular(QaTokens.radius),
        border: Border.all(color: failed ? palette.dangerBorder : tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_circle_outlined,
                color: failed ? palette.danger : tokens.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.role,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${widget.appName} · ${account.maskedUsername}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.muted,
                      ),
                    ),
                  ],
                ),
              ),
              QaTag(
                label: account.environment,
                color: production ? palette.danger : palette.info,
              ),
              const SizedBox(width: 6),
              QaTag(
                label:
                    account.effectiveAccess(production) ==
                        AccountAccess.readOnly
                    ? 'chỉ đọc'
                    : 'đọc/ghi',
              ),
              PopupMenuButton<String>(
                tooltip: 'Thao tác tài khoản',
                icon: const Icon(Icons.more_vert, size: 18),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      showAccountEditor(
                        context,
                        controller: widget.controller,
                        existing: account,
                      );
                    case 'reveal':
                      _reveal();
                    case 'delete':
                      _delete();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    enabled: widget.vault.canEdit,
                    child: const Text('Sửa'),
                  ),
                  PopupMenuItem(
                    value: 'reveal',
                    enabled: widget.vault.canEdit,
                    child: const Text('Xem mật khẩu'),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    enabled: widget.vault.canEdit,
                    child: const Text('Xoá'),
                  ),
                ],
              ),
            ],
          ),
          if (failed) ...[
            const SizedBox(height: 6),
            Text(
              'Đăng nhập lỗi${account.statusAt == null ? '' : ' lúc ${shortDateTime(account.statusAt!)}'}'
              '${account.statusMessage.isEmpty ? '' : ': ${account.statusMessage}'}',
              style: theme.textTheme.bodySmall?.copyWith(color: palette.danger),
            ),
          ],
          if (held) ...[
            const SizedBox(height: 6),
            Text(
              'Đang được ${lease.holderName} dùng tới '
              '${shortDateTime(lease.expiresAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.warning,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              OutlinedButton.icon(
                key: Key('qa-check-login-${account.id}'),
                onPressed: _checking ? null : _check,
                icon: _checking
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login, size: 16),
                label: Text(_checking ? 'Đang thử…' : 'Thử đăng nhập'),
              ),
              const SizedBox(width: 10),
              if (_checkMessage != null)
                Expanded(
                  child: Text(
                    _checkMessage!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _checkOk == true
                          ? palette.success
                          : palette.danger,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Adds or edits a demo account.
Future<void> showAccountEditor(
  BuildContext context, {
  required QaWorkspaceController controller,
  DemoAccount? existing,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AccountEditor(controller: controller, existing: existing),
  );
}

class _AccountEditor extends StatefulWidget {
  const _AccountEditor({required this.controller, this.existing});

  final QaWorkspaceController controller;
  final DemoAccount? existing;

  @override
  State<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<_AccountEditor> {
  late final _apps = declaredApps(widget.controller);
  late String? _app =
      widget.existing?.app ?? (_apps.isEmpty ? null : _apps.first.app.id);
  late String? _environment = widget.existing?.environment;
  late final _role = TextEditingController(text: widget.existing?.role);
  late final _username = TextEditingController(text: widget.existing?.username);
  late final _password = TextEditingController(text: widget.existing?.password);
  late final _extra = TextEditingController(
    text: widget.existing?.extra.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('\n'),
  );
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late AccountAccess _access =
      widget.existing?.access ?? AccountAccess.readWrite;
  bool _showPassword = false;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final field in [_role, _username, _password, _extra, _notes]) {
      field.dispose();
    }
    super.dispose();
  }

  QaApp? get _selectedApp {
    for (final item in _apps) {
      if (item.app.id == _app) return item.app;
    }
    return null;
  }

  Future<void> _save() async {
    final app = _selectedApp;
    final environment = _environment ?? app?.environments.firstOrNull?.name;
    if (app == null || environment == null) {
      setState(() => _error = 'Chọn app và môi trường.');
      return;
    }
    if (_role.text.trim().isEmpty ||
        _username.text.trim().isEmpty ||
        _password.text.isEmpty) {
      setState(() => _error = 'Cần vai trò, tên đăng nhập và mật khẩu.');
      return;
    }
    final extra = <String, String>{};
    for (final line in _extra.text.split(RegExp(r'\r?\n'))) {
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      extra[line.substring(0, separator).trim()] = line
          .substring(separator + 1)
          .trim();
    }
    final production = app.environment(environment)?.isProduction ?? false;
    final account = DemoAccount(
      id: widget.existing?.id ?? 'acc-${DateTime.now().microsecondsSinceEpoch}',
      app: app.id,
      environment: environment,
      role: _role.text.trim(),
      username: _username.text.trim(),
      password: _password.text,
      extra: extra,
      access: production ? AccountAccess.readOnly : _access,
      notes: _notes.text.trim(),
      status: widget.existing?.status ?? AccountStatus.ok,
      statusMessage: widget.existing?.statusMessage ?? '',
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.automation!.vault.save(account);
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      setState(() {
        _saving = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = _selectedApp;
    final environments = app?.environments ?? const <QaAppEnvironment>[];
    final environment = environments.any((item) => item.name == _environment)
        ? _environment
        : environments.firstOrNull?.name;
    final production =
        app?.environment(environment ?? '')?.isProduction ?? false;
    final roles = widget.controller.automation!.vault.rolesFor(
      _app ?? '',
      environment ?? '',
    );

    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Thêm tài khoản demo' : 'Sửa tài khoản demo',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: const Key('qa-account-app'),
                initialValue: _app,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'App'),
                items: [
                  for (final item in _apps)
                    DropdownMenuItem(
                      value: item.app.id,
                      child: Text('${item.app.name} · ${item.source.name}'),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _app = value;
                  _environment = null;
                }),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('qa-account-env-$_app'),
                initialValue: environment,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Môi trường'),
                items: [
                  for (final item in environments)
                    DropdownMenuItem(
                      value: item.name,
                      child: Text(
                        item.isProduction
                            ? '${item.name} · production'
                            : item.name,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _environment = value),
              ),
              const SizedBox(height: 10),
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _role.text),
                optionsBuilder: (value) => roles.where(
                  (role) =>
                      role.toLowerCase().contains(value.text.toLowerCase()),
                ),
                onSelected: (value) => _role.text = value,
                fieldViewBuilder: (context, controller, focus, submit) {
                  controller.addListener(() => _role.text = controller.text);
                  return TextField(
                    key: const Key('qa-account-role'),
                    controller: controller,
                    focusNode: focus,
                    decoration: const InputDecoration(
                      labelText: 'Vai trò',
                      helperText:
                          'Nhãn do team đặt: Chủ shop, Nhân viên… Kịch bản '
                          'chọn tài khoản theo vai trò.',
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('qa-account-username'),
                controller: _username,
                decoration: const InputDecoration(
                  labelText: 'Tên đăng nhập',
                  helperText: r'Trong flow: ${MAESTRO_QA_USERNAME}',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('qa-account-password'),
                controller: _password,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: 'Mật khẩu',
                  helperText: r'Trong flow: ${MAESTRO_QA_PASSWORD}',
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? 'Ẩn' : 'Hiện',
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _extra,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Trường thêm (tuỳ chọn)',
                  helperText:
                      r'KEY=giá trị mỗi dòng, như SHOP=001; trong flow: ${MAESTRO_QA_SHOP}',
                ),
              ),
              const SizedBox(height: 10),
              if (production)
                const NoticeBox(
                  text:
                      'Tài khoản production luôn là chỉ đọc: kịch bản ghi dữ '
                      'liệu không chạy với nó. Phía backend cũng nên cấp tài '
                      'khoản không có quyền ghi.',
                  tone: NoticeTone.warning,
                )
              else
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Chỉ đọc'),
                  subtitle: const Text(
                    'Bật nếu tài khoản không có quyền tạo hoặc sửa dữ liệu.',
                  ),
                  value: _access == AccountAccess.readOnly,
                  onChanged: (value) => setState(
                    () => _access = value
                        ? AccountAccess.readOnly
                        : AccountAccess.readWrite,
                  ),
                ),
              const SizedBox(height: 6),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Ghi chú'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                NoticeBox(text: _error!, tone: NoticeTone.danger),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          key: const Key('qa-account-save'),
          onPressed: _saving ? null : _save,
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}
