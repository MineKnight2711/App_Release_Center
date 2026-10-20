import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/amc_api_client.dart';
import '../../shared/module_widgets.dart';
import '../controllers/safe_controller.dart';
import '../models/safe_item.dart';
import '../services/safe_password_tools.dart';
import '../services/safe_share_crypto.dart';
import '../services/safe_share_service.dart';
import '../widgets/safe_look.dart';
import 'safe_dialogs.dart';

const _mono = TextStyle(
  fontFamily: 'JetBrains Mono',
  fontFamilyFallback: ['Menlo', 'Consolas', 'Courier New'],
  fontSize: 13,
  height: 1.4,
);

/// Letters and digits only: typed on a phone without hunting for symbols,
/// and still about 90 bits at this length.
const _sharePasswordRecipe = PasswordRecipe(length: 16, symbols: false);

String _errorText(Object error) => switch (error) {
  AmcApiException(:final message) => message,
  SafeShareException(:final message) => message,
  _ => '$error',
};

String _clock(DateTime value) => formatSafeTimestamp(value);

/// "sau 5 giờ", "đã hết hạn": how far a link's expiry is.
String _until(DateTime value, DateTime now) {
  final left = value.difference(now);
  if (left.isNegative) return 'đã hết hạn';
  if (left.inMinutes < 60) {
    return 'hết hạn sau ${left.inMinutes < 1 ? 1 : left.inMinutes} phút';
  }
  if (left.inHours < 48) return 'hết hạn sau ${left.inHours} giờ';
  return 'hết hạn sau ${left.inDays} ngày';
}

/// Why no link can be made from here, or null when one can.
String? safeShareBlockedReason(SafeShareService? service, bool? signedIn) {
  if (service == null) {
    return 'Bản build này chưa nối server AMC nên chưa tạo được link.';
  }
  if (signedIn == false) {
    return 'Đăng nhập tài khoản AMC để tạo link: link được giữ trên server '
        'của AMC và chỉ tài khoản tạo ra mới thu hồi được.';
  }
  return null;
}

/// Puts a link, its password or its message on the clipboard, which the safe
/// wipes again after its usual delay.
Future<void> copySafeShareValue(
  BuildContext context,
  SafeController safe,
  String value,
  String what,
) async {
  await safe.copySecret(value);
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          'Đã sao chép $what · tự xoá khỏi clipboard sau '
          '${safe.settings.clipboardSeconds} giây.',
        ),
      ),
    );
}

/// The choices for a link being made, shared by the item and kit dialogs.
/// The password lives only as long as the draft.
class SafeShareDraft extends ChangeNotifier {
  Duration expiry = const SafeShareOptions().expiresIn;
  int? maxViews = const SafeShareOptions().maxViews;
  bool usePassword = true;
  bool showPassword = true;
  bool includeNotes = false;
  final password = TextEditingController(
    text: generatePassword(_sharePasswordRecipe),
  );
  final message = TextEditingController();

  void update(VoidCallback change) {
    change();
    notifyListeners();
  }

  void regenerate() => update(() {
    password.text = generatePassword(_sharePasswordRecipe);
    showPassword = true;
  });

  /// Why the link cannot be made as chosen, or null.
  String? validate() =>
      usePassword ? validateSafeSharePassword(password.text) : null;

  SafeShareOptions get options => SafeShareOptions(
    expiresIn: expiry,
    maxViews: maxViews,
    password: usePassword ? password.text : '',
    includeNotes: includeNotes,
    message: message.text,
  );

  @override
  void dispose() {
    password.dispose();
    message.dispose();
    super.dispose();
  }
}

/// Lifetime, views, password, message and notes of a link being made.
class SafeShareOptionsFields extends StatelessWidget {
  const SafeShareOptionsFields({
    super.key,
    required this.draft,
    required this.enabled,
    this.notesAvailable = false,
    this.notesLabel = 'Gửi kèm ghi chú của mục',
  });

  final SafeShareDraft draft;
  final bool enabled;

  /// Shows the notes checkbox, for items that have notes.
  final bool notesAvailable;
  final String notesLabel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Hạn dùng'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in SafeShareOptions.expiryChoices)
                ChoiceChip(
                  key: Key('safe-share-expiry-${choice.inHours}'),
                  label: Text(formatShareDuration(choice)),
                  selected: draft.expiry == choice,
                  onSelected: enabled
                      ? (_) => draft.update(() => draft.expiry = choice)
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 16),
          const SectionLabel('Số lượt xem'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in SafeShareOptions.viewChoices)
                ChoiceChip(
                  key: Key('safe-share-views-${choice ?? 'any'}'),
                  label: Text(
                    choice == 1 ? '1 lần (tự huỷ)' : formatShareViews(choice),
                  ),
                  selected: draft.maxViews == choice,
                  onSelected: enabled
                      ? (_) => draft.update(() => draft.maxViews = choice)
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            key: const Key('safe-share-use-password'),
            contentPadding: EdgeInsets.zero,
            value: draft.usePassword,
            onChanged: enabled
                ? (value) => draft.update(() => draft.usePassword = value)
                : null,
            title: const Text('Yêu cầu mật khẩu'),
            subtitle: Text(
              draft.usePassword
                  ? 'Lộ link vẫn chưa lộ khoá. Sai 10 lần là link tự huỷ.'
                  : 'Ai có link là mở được. Chỉ nên dùng khi gửi thẳng cho '
                        'một người qua kênh riêng.',
            ),
          ),
          if (draft.usePassword) ...[
            const SizedBox(height: 4),
            TextField(
              key: const Key('safe-share-password'),
              controller: draft.password,
              obscureText: !draft.showPassword,
              autocorrect: false,
              enableSuggestions: false,
              enabled: enabled,
              style: _mono,
              onChanged: (_) => draft.update(() {}),
              decoration: InputDecoration(
                labelText: 'Mật khẩu của link',
                helperText:
                    'Chữ không dấu, số, ký hiệu ASCII; ít nhất '
                    '$safeShareMinPasswordLength ký tự. AMC không lưu lại.',
                prefixIcon: const Icon(Icons.key_rounded),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: draft.showPassword ? 'Ẩn' : 'Hiện',
                      onPressed: () => draft.update(
                        () => draft.showPassword = !draft.showPassword,
                      ),
                      icon: Icon(
                        draft.showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                    IconButton(
                      key: const Key('safe-share-generate'),
                      tooltip: 'Tạo mật khẩu mới',
                      onPressed: enabled ? draft.regenerate : null,
                      icon: const Icon(Icons.casino_outlined),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            PasswordStrengthBar(strength: ratePassword(draft.password.text)),
          ],
          const SizedBox(height: 16),
          TextField(
            key: const Key('safe-share-message'),
            controller: draft.message,
            enabled: enabled,
            maxLength: 500,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Lời nhắn cho người nhận (tuỳ chọn)',
              helperText: 'Được mã hoá cùng nội dung.',
              prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
            ),
          ),
          if (notesAvailable)
            CheckboxListTile(
              key: const Key('safe-share-notes'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: draft.includeNotes,
              onChanged: enabled
                  ? (value) =>
                        draft.update(() => draft.includeNotes = value ?? false)
                  : null,
              title: Text(notesLabel),
              subtitle: const Text(
                'Mặc định không gửi: ghi chú trong két thường chỉ để bạn đọc.',
              ),
            ),
        ],
      ),
    );
  }
}

/// A link just made: shown once, with its password and the message to send.
class SafeShareResultView extends StatelessWidget {
  const SafeShareResultView({
    super.key,
    required this.result,
    required this.title,
    required this.onCopy,
    required this.onDone,
  });

  final SafeShareCreated result;

  /// What the link carries, for the message to send with it.
  final String title;
  final void Function(String value, String what) onCopy;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final share = result.share;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 48,
            color: Color(0xFF3DBE7A),
          ),
          const SizedBox(height: 8),
          Text(
            'Đã tạo link chia sẻ',
            key: const Key('safe-share-done'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusChip(
                icon: Icons.schedule_rounded,
                label: 'Hết hạn ${_clock(share.expiresAt)}',
              ),
              StatusChip(
                icon: Icons.visibility_outlined,
                label: share.maxViews == null
                    ? 'Không giới hạn lượt xem'
                    : share.maxViews == 1
                    ? 'Xem 1 lần rồi tự huỷ'
                    : '${share.maxViews} lượt xem',
              ),
              StatusChip(
                icon: share.passwordProtected
                    ? Icons.lock_outline_rounded
                    : Icons.lock_open_rounded,
                label: share.passwordProtected
                    ? 'Có mật khẩu'
                    : 'Không mật khẩu',
                color: share.passwordProtected ? null : theme.colorScheme.error,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _CopyBox(
            key: const Key('safe-share-link'),
            label: 'Link',
            value: result.link,
            onCopy: () => onCopy(result.link, 'link'),
          ),
          if (result.password.isNotEmpty) ...[
            const SizedBox(height: 10),
            _CopyBox(
              key: const Key('safe-share-password-result'),
              label: 'Mật khẩu',
              value: result.password,
              onCopy: () => onCopy(result.password, 'mật khẩu link'),
            ),
          ],
          const SizedBox(height: 14),
          NoticeBox(
            text: result.password.isEmpty
                ? 'AMC không giữ khoá của link: đóng cửa sổ này là không xem '
                      'lại được link, chỉ thu hồi được.'
                : 'Gửi link và mật khẩu qua hai kênh khác nhau (ví dụ link qua '
                      'Slack, mật khẩu qua Zalo). AMC không giữ khoá của link: '
                      'đóng cửa sổ này là không xem lại được, chỉ thu hồi được.',
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                key: const Key('safe-share-copy-message'),
                onPressed: () => onCopy(
                  safeShareMessage(title, result),
                  'lời nhắn kèm link',
                ),
                icon: const Icon(Icons.message_outlined, size: 18),
                label: const Text('Sao chép lời nhắn kèm link'),
              ),
              FilledButton(onPressed: onDone, child: const Text('Xong')),
            ],
          ),
        ],
      ),
    );
  }
}

/// The bottom bar of a dialog that makes a link: what happens, and [child]
/// to do it.
class SafeShareFooter extends StatelessWidget {
  const SafeShareFooter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Mã hoá ngay trên máy này; server chỉ giữ bản mã.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          child,
        ],
      ),
    );
  }
}

/// Opens the dialog that makes a share link for [item].
Future<SafeShareCreated?> showSafeShareDialog(
  BuildContext context,
  SafeController safe,
  SafeItem item, {
  SafeShareService? service,
  bool? signedIn,
}) {
  return showDialog<SafeShareCreated>(
    context: context,
    barrierDismissible: false,
    builder: (context) => SafeShareDialog(
      safe: safe,
      item: item,
      service: service ?? SafeShareService.resolve(),
      signedIn: signedIn ?? SafeShareService.signedIn,
    ),
  );
}

/// Opens the list of every link made from this account. [onShareKit] opens
/// the dialog that shares a project's whole kit.
Future<void> showSafeSharesDialog(
  BuildContext context,
  SafeController safe, {
  SafeShareService? service,
  VoidCallback? onShareKit,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => SafeSharesDialog(
      safe: safe,
      service: service ?? SafeShareService.resolve(),
      onShareKit: onShareKit,
    ),
  );
}

class SafeShareDialog extends StatefulWidget {
  const SafeShareDialog({
    super.key,
    required this.safe,
    required this.item,
    required this.service,
    this.signedIn,
  });

  final SafeController safe;
  final SafeItem item;

  /// Null when this build has no AMC server to keep links on.
  final SafeShareService? service;

  /// False when no AMC account is signed in; null when unknown.
  final bool? signedIn;

  @override
  State<SafeShareDialog> createState() => _SafeShareDialogState();
}

class _SafeShareDialogState extends State<SafeShareDialog> {
  final _draft = SafeShareDraft();
  bool _busy = false;
  String _error = '';
  SafeShareCreated? _result;

  List<SafeShareLink>? _links;
  String _linksError = '';

  SafeController get _safe => widget.safe;
  SafeItem get _item => widget.item;

  bool get _canCreate =>
      safeShareBlockedReason(widget.service, widget.signedIn) == null && !_busy;

  @override
  void initState() {
    super.initState();
    _safe.addListener(_closeIfLocked);
    _draft.addListener(_clearError);
    unawaited(_loadLinks());
  }

  @override
  void dispose() {
    _safe.removeListener(_closeIfLocked);
    _draft.dispose();
    super.dispose();
  }

  void _closeIfLocked() {
    if (!_safe.isOpen && mounted) Navigator.of(context).maybePop();
  }

  void _clearError() {
    if (_error.isNotEmpty) setState(() => _error = '');
  }

  Future<void> _loadLinks() async {
    final service = widget.service;
    if (service == null || widget.signedIn == false) return;
    try {
      final links = await service.list();
      if (!mounted) return;
      setState(() {
        _links = links
            .where((link) => link.itemId == _item.id && link.isActive)
            .toList();
        _linksError = '';
      });
    } catch (error) {
      if (mounted) setState(() => _linksError = _errorText(error));
    }
  }

  Future<void> _revoke(SafeShareLink link) async {
    final confirmed = await confirmRevokeShare(context);
    if (!confirmed) return;
    try {
      await widget.service!.revoke(link.id);
      if (!mounted) return;
      setState(() => _links?.removeWhere((each) => each.id == link.id));
    } catch (error) {
      if (mounted) setState(() => _linksError = _errorText(error));
    }
  }

  Future<void> _create() async {
    final problem = _draft.validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final created = await widget.service!.create(_item, _draft.options);
      _safe.touch();
      if (mounted) setState(() => _result = created);
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 860),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeShareDialogHeader(
              icon: Icons.link_rounded,
              title: 'Chia sẻ qua link',
              subtitle:
                  'Link mã hoá đầu-cuối cho "${_item.title}". Người nhận chỉ '
                  'cần trình duyệt.',
              onClose: _busy ? null : () => Navigator.of(context).pop(_result),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Flexible(
              child: result == null
                  ? _form()
                  : SafeShareResultView(
                      result: result,
                      title: _item.title,
                      onCopy: (value, what) =>
                          copySafeShareValue(context, _safe, value, what),
                      onDone: () => Navigator.of(context).pop(result),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form() {
    final blocked = safeShareBlockedReason(widget.service, widget.signedIn);
    final links = _links ?? const <SafeShareLink>[];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (blocked != null) ...[
                  NoticeBox(text: blocked, tone: NoticeTone.warning),
                  const SizedBox(height: 14),
                ],
                SafeShareOptionsFields(
                  draft: _draft,
                  enabled: !_busy,
                  notesAvailable: _item.notes.isNotEmpty,
                ),
                if (_linksError.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  NoticeBox(text: _linksError, tone: NoticeTone.warning),
                ],
                if (links.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SectionLabel('Link đang mở của mục này (${links.length})'),
                  const SizedBox(height: 6),
                  for (final link in links)
                    SafeShareLinkTile(
                      link: link,
                      item: _item,
                      showTitle: false,
                      onRevoke: () => _revoke(link),
                    ),
                ],
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  NoticeBox(
                    key: const Key('safe-share-error'),
                    text: _error,
                    tone: NoticeTone.danger,
                  ),
                ],
              ],
            ),
          ),
        ),
        SafeShareFooter(
          child: FilledButton.icon(
            key: const Key('safe-share-submit'),
            onPressed: _canCreate ? _create : null,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_link_rounded, size: 18),
            label: Text(_busy ? 'Đang mã hoá…' : 'Tạo link'),
          ),
        ),
      ],
    );
  }
}

/// Every link this account made from the safe, to see who opened what and
/// to revoke.
class SafeSharesDialog extends StatefulWidget {
  const SafeSharesDialog({
    super.key,
    required this.safe,
    required this.service,
    this.onShareKit,
  });

  final SafeController safe;
  final SafeShareService? service;

  /// Opens the dialog that shares a project's whole kit, after this one
  /// closes.
  final VoidCallback? onShareKit;

  @override
  State<SafeSharesDialog> createState() => _SafeSharesDialogState();
}

class _SafeSharesDialogState extends State<SafeSharesDialog> {
  List<SafeShareLink>? _links;
  String _error = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final service = widget.service;
    if (service == null) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final links = await service.list();
      if (mounted) setState(() => _links = links);
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revoke(SafeShareLink link) async {
    if (link.isActive && !await confirmRevokeShare(context)) return;
    try {
      await widget.service!.revoke(link.id);
      if (mounted) {
        setState(() => _links?.removeWhere((each) => each.id == link.id));
      }
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    }
  }

  Future<void> _clearClosed() async {
    final closed = (_links ?? const <SafeShareLink>[])
        .where((link) => !link.isActive)
        .toList();
    for (final link in closed) {
      try {
        await widget.service!.revoke(link.id);
        if (mounted) {
          setState(() => _links?.removeWhere((each) => each.id == link.id));
        }
      } catch (error) {
        if (mounted) setState(() => _error = _errorText(error));
        return;
      }
    }
  }

  SafeItem? _itemFor(String id) {
    for (final item in widget.safe.items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final links = _links ?? const <SafeShareLink>[];
    final active = links.where((link) => link.isActive).toList();
    final closed = links.where((link) => !link.isActive).toList();

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 820),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeShareDialogHeader(
              icon: Icons.link_rounded,
              title: 'Link chia sẻ',
              subtitle:
                  'Các link đã tạo từ két bằng tài khoản AMC này. Thu hồi để '
                  'link ngừng hoạt động ngay với mọi người.',
              onClose: () => Navigator.of(context).pop(),
              action: IconButton(
                key: const Key('safe-shares-refresh'),
                tooltip: 'Tải lại',
                onPressed: _loading || widget.service == null ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                children: [
                  if (widget.onShareKit case final shareKit?) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        key: const Key('safe-shares-share-kit'),
                        onPressed: () {
                          Navigator.of(context).pop();
                          shareKit();
                        },
                        icon: const Icon(Icons.folder_zip_outlined, size: 18),
                        label: const Text('Chia sẻ bộ keys của một dự án…'),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (widget.service == null)
                    const NoticeBox(
                      text:
                          'Bản build này chưa nối server AMC nên chưa có link '
                          'chia sẻ.',
                      tone: NoticeTone.warning,
                    ),
                  if (_error.isNotEmpty) ...[
                    NoticeBox(text: _error, tone: NoticeTone.danger),
                    const SizedBox(height: 12),
                  ],
                  if (_loading && _links == null)
                    const Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_links != null && links.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Column(
                        children: [
                          Icon(
                            Icons.link_off_rounded,
                            size: 40,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Chưa có link nào. Mở một mục trong két rồi bấm '
                            'nút chia sẻ, hoặc chia sẻ cả bộ keys của một dự '
                            'án.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (active.isNotEmpty) ...[
                    SectionLabel('Đang mở (${active.length})'),
                    const SizedBox(height: 6),
                    for (final link in active)
                      SafeShareLinkTile(
                        link: link,
                        item: _itemFor(link.itemId),
                        onRevoke: () => _revoke(link),
                      ),
                  ],
                  if (closed.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    SectionLabel(
                      'Đã đóng (${closed.length})',
                      action: TextButton(
                        onPressed: _clearClosed,
                        child: const Text('Xoá hết khỏi danh sách'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final link in closed)
                      SafeShareLinkTile(
                        link: link,
                        item: _itemFor(link.itemId),
                        onRevoke: () => _revoke(link),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> confirmRevokeShare(BuildContext context) => confirmSafeAction(
  context,
  title: 'Thu hồi link?',
  message:
      'Link ngừng hoạt động ngay với mọi người đang giữ nó. Không hoàn tác '
      'được; muốn chia sẻ lại thì tạo link mới.',
  confirmLabel: 'Thu hồi',
  danger: true,
  icon: Icons.link_off_rounded,
);

/// One link in a list: what it carries, how much of it is left, and a way
/// to end it.
class SafeShareLinkTile extends StatelessWidget {
  const SafeShareLinkTile({
    super.key,
    required this.link,
    required this.item,
    required this.onRevoke,
    this.showTitle = true,
    this.now,
  });

  final SafeShareLink link;

  /// Null when the item has since left the safe.
  final SafeItem? item;
  final VoidCallback onRevoke;
  final bool showTitle;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = now ?? DateTime.now();
    final kind = item?.kind;
    final bundle = link.bundleProject;
    final title = bundle != null
        ? bundle.isEmpty
              ? 'Bộ keys'
              : 'Bộ keys $bundle'
        : item?.title ?? '(Mục đã xoá khỏi két)';
    final views = link.maxViews == null
        ? '${link.views} lượt đã xem'
        : '${link.views}/${link.maxViews} lượt';
    final details = [
      views,
      if (link.isActive) _until(link.expiresAt, current),
      if (link.passwordProtected) 'có mật khẩu' else 'không mật khẩu',
      if (link.lastViewedAt != null)
        'mở lần cuối ${_clock(link.lastViewedAt!)}',
      if (link.failedAttempts > 0) '${link.failedAttempts} lần sai',
    ].join(' · ');
    final statusColor = switch (link.status) {
      SafeShareStatus.active => const Color(0xFF3DBE7A),
      SafeShareStatus.locked => theme.colorScheme.error,
      _ => theme.colorScheme.outline,
    };

    return Container(
      key: Key('safe-share-link-${link.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            bundle != null
                ? Icons.folder_zip_outlined
                : kind?.icon ?? Icons.link_rounded,
            size: 20,
            color: bundle != null
                ? theme.colorScheme.primary
                : kind?.tint ?? theme.colorScheme.outline,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  showTitle ? title : 'Tạo lúc ${_clock(link.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  details,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusChip(label: link.status.label, color: statusColor),
          IconButton(
            key: Key('safe-share-revoke-${link.id}'),
            tooltip: link.isActive ? 'Thu hồi link' : 'Xoá khỏi danh sách',
            onPressed: onRevoke,
            icon: Icon(
              link.isActive ? Icons.link_off_rounded : Icons.close_rounded,
              color: link.isActive ? theme.colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon, title and close button atop a share dialog.
class SafeShareDialogHeader extends StatelessWidget {
  const SafeShareDialogHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onClose;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary.withValues(alpha: 0.14),
            ),
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ?action,
          IconButton(
            tooltip: 'Đóng',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

/// A value to hand on, selectable, with its copy button.
class _CopyBox extends StatelessWidget {
  const _CopyBox({
    super.key,
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(child: SelectableText(value, style: _mono)),
              FilledButton.tonalIcon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Sao chép'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
