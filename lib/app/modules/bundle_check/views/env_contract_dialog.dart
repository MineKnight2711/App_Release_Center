import 'package:app_management_center/app/modules/shared/module_widgets.dart';
import 'package:flutter/material.dart';

import '../controllers/bundle_check_controller.dart';
import '../models/bundle_check_models.dart';

/// Shows what the checker derived from the project and lets the user add to
/// it. Saving re-checks the current file with the new contract.
Future<void> showEnvContractDialog(
  BuildContext context,
  BundleCheckController controller,
) async {
  final report = controller.report;
  if (report == null) return;
  final current = await controller.overrideForCurrent();
  if (!context.mounted) return;
  final result = await showDialog<EnvContractOverride>(
    context: context,
    builder: (_) => _EnvContractDialog(
      packageName: report.packageName,
      derived: controller.run?.report.id == report.id
          ? controller.run!.contract
          : null,
      initial: current,
    ),
  );
  if (result != null) await controller.saveOverride(result);
}

class _EnvContractDialog extends StatefulWidget {
  const _EnvContractDialog({
    required this.packageName,
    required this.derived,
    required this.initial,
  });

  final String packageName;
  final EnvContract? derived;
  final EnvContractOverride initial;

  @override
  State<_EnvContractDialog> createState() => _EnvContractDialogState();
}

class _EnvContractDialogState extends State<_EnvContractDialog> {
  late final _extraKeys = TextEditingController(
    text: widget.initial.extraRequiredKeys.join('\n'),
  );
  late final _ignoredKeys = TextEditingController(
    text: widget.initial.ignoredKeys.join('\n'),
  );
  late final _firebase = TextEditingController(
    text: widget.initial.expectedFirebaseProjectId ?? '',
  );
  late final _required = TextEditingController(
    text: widget.initial.requiredStrings.join('\n'),
  );
  late final _forbidden = TextEditingController(
    text: widget.initial.forbiddenStrings.join('\n'),
  );
  late String? _pinned = widget.initial.pinnedSignerSha256;

  @override
  void dispose() {
    for (final controller in [
      _extraKeys,
      _ignoredKeys,
      _firebase,
      _required,
      _forbidden,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  static List<String> _lines(TextEditingController controller) {
    return {
      for (final part in controller.text.split(RegExp(r'[\n,]')))
        if (part.trim().isNotEmpty) part.trim(),
    }.toList();
  }

  EnvContractOverride _build() {
    return EnvContractOverride(
      extraRequiredKeys: _lines(_extraKeys),
      ignoredKeys: _lines(_ignoredKeys),
      expectedFirebaseProjectId: _firebase.text.trim().isEmpty
          ? null
          : _firebase.text.trim(),
      requiredStrings: _lines(_required),
      forbiddenStrings: _lines(_forbidden),
      pinnedSignerSha256: _pinned,
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String helper, {
    bool multiline = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        minLines: multiline ? 2 : 1,
        maxLines: multiline ? 5 : 1,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final derived = widget.derived;
    return AlertDialog(
      title: Text('Contract env · ${widget.packageName}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (derived == null)
                const NoticeBox(
                  text:
                      'Báo cáo này mở từ lịch sử nên không có phần tự suy ra '
                      'từ project. Bấm Kiểm lại để xem.',
                )
              else if (!derived.projectLinked)
                const NoticeBox(
                  text:
                      'Chưa gắn project: chỉ có phần chỉnh tay dưới đây. Gắn '
                      'project để tự suy ra key code đọc và Firebase project.',
                )
              else
                NoticeBox(
                  text: [
                    'Tự suy ra từ project:',
                    ...derived.sources.map((line) => '• $line'),
                    if (derived.requiredKeys.isNotEmpty)
                      '• Bắt buộc: ${derived.requiredKeys.join(', ')}',
                    if (derived.expectedFirebaseProjectId != null)
                      '• Firebase mong đợi: ${derived.expectedFirebaseProjectId}',
                  ].join('\n'),
                ),
              const SizedBox(height: 16),
              _field(
                _extraKeys,
                'Key bắt buộc thêm',
                'Mỗi dòng một key. Thiếu, rỗng hoặc còn giá trị mẫu → lỗi.',
              ),
              _field(
                _ignoredKeys,
                'Key bỏ qua',
                'Key tự suy ra nhưng thực ra không cần.',
              ),
              _field(
                _firebase,
                'Firebase project mong đợi',
                'Ghi đè project suy ra từ google-services.json, vd myapp-prod.',
                multiline: false,
              ),
              _field(
                _required,
                'Chuỗi phải có trong code Dart',
                'Vd host API production. Tìm trong libapp.so — kiểm được giá '
                    'trị --dart-define và firebase_options.',
              ),
              _field(
                _forbidden,
                'Chuỗi cấm',
                'Vd host staging. Thấy trong .env hoặc libapp.so → lỗi.',
              ),
              Row(
                children: [
                  Icon(
                    Icons.push_pin_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _pinned == null
                          ? 'Chưa ghim chữ ký nào.'
                          : 'Chữ ký đã ghim: ${_pinned!.substring(0, 23)}…',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  if (_pinned != null)
                    TextButton(
                      onPressed: () => setState(() => _pinned = null),
                      child: const Text('Bỏ ghim'),
                    ),
                ],
              ),
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
          key: const Key('bundle-check-contract-save'),
          onPressed: () => Navigator.pop(context, _build()),
          child: const Text('Lưu và kiểm lại'),
        ),
      ],
    );
  }
}
