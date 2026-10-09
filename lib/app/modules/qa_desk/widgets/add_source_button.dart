import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../controllers/qa_workspace_controller.dart';
import '../services/qa_desk_host.dart';
import '../theme/qa_tokens.dart';
import 'qa_widgets.dart';

/// AMC projects that are not QA sources yet: the open one first, then the
/// recent ones, without repeats.
List<String> qaSourceCandidates(
  QaWorkspaceController controller,
  QaDeskHost host, {
  int limit = 8,
}) {
  final candidates = <String>[];
  for (final path in [?host.currentProjectPath, ...host.recentProjectPaths]) {
    if (controller.sources.any((source) => p.equals(source.path, path))) {
      continue;
    }
    if (candidates.any((item) => p.equals(item, path))) continue;
    candidates.add(path);
    if (candidates.length == limit) break;
  }
  return candidates;
}

/// Adds [path] as a source and says how it went.
Future<void> addQaSource(
  BuildContext context,
  QaWorkspaceController controller,
  String path,
) async {
  final error = await controller.addSource(path);
  if (!context.mounted) return;
  if (error != null) {
    showQaMessage(context, error);
    return;
  }
  final source = controller.sources.last;
  showQaMessage(
    context,
    'Đã thêm ${source.name} (${source.suites.length} suite).',
  );
}

Future<void> pickQaSource(
  BuildContext context,
  QaWorkspaceController controller,
) async {
  final path = await getDirectoryPath(confirmButtonText: 'Thêm nguồn');
  if (path == null || !context.mounted) return;
  await addQaSource(context, controller, path);
}

/// "Thêm nguồn": AMC's own projects one click away, any folder after that.
///
/// With nothing to suggest it opens the folder picker straight away.
class QaAddSourceButton extends StatelessWidget {
  const QaAddSourceButton({
    super.key,
    required this.controller,
    required this.host,
    this.prominent = false,
  });

  final QaWorkspaceController controller;
  final QaDeskHost host;

  /// A filled button, for the empty workspace where it is the next step.
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final candidates = qaSourceCandidates(controller, host);
    final enabled = !controller.isRunning;

    Widget button(VoidCallback? onPressed) {
      const icon = Icon(Icons.create_new_folder_outlined, size: 17);
      final label = Text(candidates.isEmpty ? 'Thêm nguồn' : 'Thêm nguồn…');
      return prominent
          ? FilledButton.icon(
              key: const Key('qa-add-source'),
              onPressed: onPressed,
              icon: icon,
              label: label,
            )
          : OutlinedButton.icon(
              key: const Key('qa-add-source'),
              onPressed: onPressed,
              icon: icon,
              label: label,
            );
    }

    if (candidates.isEmpty) {
      return button(enabled ? () => pickQaSource(context, controller) : null);
    }
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    final current = host.currentProjectPath;
    return MenuAnchor(
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Text(
            'DỰ ÁN TRONG AMC',
            style: theme.textTheme.labelSmall?.copyWith(
              color: tokens.muted,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (final path in candidates)
          MenuItemButton(
            key: ValueKey('qa-add-project:$path'),
            leadingIcon: Icon(
              current != null && p.equals(path, current)
                  ? Icons.folder_special_outlined
                  : Icons.history,
              size: 18,
            ),
            onPressed: () => addQaSource(context, controller, path),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    current != null && p.equals(path, current)
                        ? '${p.basename(path)} · đang mở'
                        : p.basename(path),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const Divider(height: 1),
        MenuItemButton(
          key: const Key('qa-add-folder'),
          leadingIcon: const Icon(Icons.folder_open_outlined, size: 18),
          onPressed: () => pickQaSource(context, controller),
          child: const Text('Chọn thư mục khác…'),
        ),
      ],
      builder: (context, menu, _) => button(
        enabled ? () => menu.isOpen ? menu.close() : menu.open() : null,
      ),
    );
  }
}
