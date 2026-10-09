import 'package:flutter/material.dart';

import '../controllers/mail_cleaner_controller.dart';
import '../models/mail_item.dart';
import '../../shared/module_widgets.dart';
import 'mail_cleaner_connect_pane.dart';
import 'mail_cleaner_workspace_pane.dart';

/// Opens the mail cleaner as a full page over the shell.
Future<void> showMailCleaner(BuildContext context) => Navigator.of(
  context,
).push<void>(MaterialPageRoute(builder: (_) => const MailCleanerView()));

/// The page that owns one mail-cleaning session.
///
/// The IMAP connection lives exactly as long as this page: leaving it logs out,
/// so no socket and no password outlive the screen the user closed.
class MailCleanerView extends StatefulWidget {
  const MailCleanerView({super.key, this.controller});

  /// Injected by the tests; left null the page builds its own.
  final MailCleanerController? controller;

  @override
  State<MailCleanerView> createState() => _MailCleanerViewState();
}

class _MailCleanerViewState extends State<MailCleanerView> {
  late final MailCleanerController _controller =
      widget.controller ?? MailCleanerController();
  late final bool _ownsController = widget.controller == null;
  bool _showLog = false;

  @override
  void initState() {
    super.initState();
    _controller.loadSettings();
  }

  @override
  void dispose() {
    // Only a controller this page created is its to tear down; an injected one
    // belongs to whoever passed it in.
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  bool get _connected =>
      _controller.stage != MailCleanerStage.disconnected &&
      _controller.stage != MailCleanerStage.connecting;

  Future<bool> _confirmLeaveWhileBusy() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.hourglass_top_outlined),
        title: const Text('Đang có thao tác chạy'),
        content: const Text(
          'Đóng màn hình này sẽ ngắt kết nối giữa lúc đang làm việc với hộp '
          'thư. Thư đã gắn cờ vẫn còn cờ, chưa bị xoá.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ở lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Đóng và ngắt'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final busy =
            _controller.stage == MailCleanerStage.scanning ||
            _controller.stage == MailCleanerStage.deleting;

        return PopScope(
          canPop: !busy,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop || !mounted) return;
            final navigator = Navigator.of(context);
            if (await _confirmLeaveWhileBusy() && mounted) navigator.pop();
          },
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Dọn hộp thư'),
              actions: [
                if (_connected) ...[
                  if (_controller.flaggedCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: StatusChip(
                        label:
                            '${formatCount(_controller.flaggedCount)} thư gắn cờ',
                        icon: Icons.flag_outlined,
                        color: Theme.of(context).colorScheme.error,
                        tooltip:
                            'Có thư đang gắn cờ \\Deleted nhưng chưa xoá.\n'
                            'Bấm "Gỡ cờ" ở thanh dưới nếu muốn huỷ.',
                      ),
                    ),
                  TextButton.icon(
                    onPressed: () => setState(() => _showLog = !_showLog),
                    icon: Icon(
                      _showLog
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.terminal_rounded,
                      size: 18,
                    ),
                    label: const Text('Nhật ký'),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _controller.disconnect(),
                    icon: const Icon(Icons.logout, size: 16),
                    label: const Text('Ngắt'),
                  ),
                ],
                const SizedBox(width: 12),
              ],
            ),
            body: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _connected
                  ? MailCleanerWorkspacePane(
                      key: const ValueKey('workspace'),
                      controller: _controller,
                      showLog: _showLog,
                    )
                  : MailCleanerConnectPane(
                      key: const ValueKey('connect'),
                      controller: _controller,
                    ),
            ),
          ),
        );
      },
    );
  }
}
