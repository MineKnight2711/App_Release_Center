import 'package:flutter/material.dart';

import '../../shared/module_widgets.dart';
import '../controllers/qa_workspace_controller.dart';
import '../models/qa_models.dart';
import '../models/scenario_models.dart';
import '../theme/qa_tokens.dart';

/// Asks for the secret values an environment declares, for this session only.
Future<void> showSecretsDialog(
  BuildContext context, {
  required QaWorkspaceController controller,
  required QaSource source,
  required EnvironmentProfile environment,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SecretsDialog(
      controller: controller,
      source: source,
      environment: environment,
    ),
  );
}

class _SecretsDialog extends StatefulWidget {
  const _SecretsDialog({
    required this.controller,
    required this.source,
    required this.environment,
  });

  final QaWorkspaceController controller;
  final QaSource source;
  final EnvironmentProfile environment;

  @override
  State<_SecretsDialog> createState() => _SecretsDialogState();
}

class _SecretsDialogState extends State<_SecretsDialog> {
  late final _fields = {
    for (final key in widget.environment.secretKeys)
      key: TextEditingController(),
  };

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  void _save() {
    widget.controller.updateSessionSecrets(
      widget.source.id,
      widget.environment.id,
      {for (final entry in _fields.entries) entry.key: entry.value.text},
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QaTokens.of(context);
    return AlertDialog(
      title: Text('Secret · ${widget.environment.name}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.source.name,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.muted),
              ),
              const SizedBox(height: 10),
              const NoticeBox(
                text:
                    'Giá trị chỉ nằm trong bộ nhớ của phiên này: không ghi vào '
                    'catalog, log hay lịch sử, và mất khi tắt AMC.',
                icon: Icons.lock_outline,
              ),
              const SizedBox(height: 14),
              for (final entry in _fields.entries) ...[
                TextField(
                  key: Key('qa-secret-${entry.key}'),
                  controller: entry.value,
                  obscureText: true,
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    labelText: entry.key,
                    helperText:
                        widget.controller.sessionSecretIsSet(
                          widget.source.id,
                          widget.environment.id,
                          entry.key,
                        )
                        ? 'Đã nhập. Để trống để giữ nguyên.'
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          key: const Key('qa-secrets-save'),
          onPressed: _save,
          child: const Text('Dùng trong phiên này'),
        ),
      ],
    );
  }
}
