import 'package:flutter/material.dart';
import '../controllers/plan_editor_controller.dart';

/// Chip input for labels, with suggestions from the project's other tickets.
/// Every change goes straight through the editor's autosave.
class LabelEditor extends StatefulWidget {
  const LabelEditor({
    super.key,
    required this.editor,
    required this.suggestions,
  });
  final PlanEditorController editor;
  final List<String> suggestions;
  @override
  State<LabelEditor> createState() => _LabelEditorState();
}

class _LabelEditorState extends State<LabelEditor> {
  final input = TextEditingController();

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void _add(String value) {
    final label = value.trim().replaceFirst(RegExp(r'^#'), '');
    if (label.isEmpty) return;
    if (!widget.editor.item.labels.contains(label)) {
      widget.editor.change((i) => i.labels = [...i.labels, label]);
    }
    input.clear();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.editor, input]),
    builder: (context, _) {
      final theme = Theme.of(context);
      final labels = widget.editor.item.labels;
      final q = input.text.trim().toLowerCase();
      final suggestions = widget.suggestions
          .where((s) => !labels.contains(s) && s.toLowerCase().contains(q))
          .take(12)
          .toList();
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nhãn', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            if (labels.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final l in labels)
                    InputChip(
                      label: Text(l),
                      visualDensity: VisualDensity.compact,
                      deleteButtonTooltipMessage: 'Bỏ nhãn $l',
                      onDeleted: () => widget.editor.change(
                        (i) => i.labels = [...i.labels]..remove(l),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 10),
            TextField(
              controller: input,
              autofocus: true,
              onSubmitted: _add,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Thêm nhãn rồi Enter',
                prefixIcon: Icon(Icons.tag, size: 18),
              ),
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Đã dùng trong dự án', style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in suggestions)
                    ActionChip(
                      label: Text(s),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _add(s),
                    ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );
}
