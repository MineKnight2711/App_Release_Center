part of '../../home_view.dart';

/// Common frame for a FlowFin tab: a title row with actions, an error strip,
/// and scrollable content.
class _FlowFinTabScaffold extends StatelessWidget {
  const _FlowFinTabScaffold({
    required this.icon,
    required this.title,
    required this.child,
    this.actions = const [],
    this.error = '',
    this.loading = false,
    this.scrollable = true,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final List<Widget> actions;
  final String error;
  final bool loading;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _PanelTitle(icon: icon, title: title),
            const SizedBox(width: 10),
            if (loading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            const Spacer(),
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
          ],
        ),
        if (error.isNotEmpty) ...[
          const SizedBox(height: 10),
          _FlowFinErrorNotice(message: error),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: scrollable ? SingleChildScrollView(child: child) : child,
        ),
      ],
    );
  }
}

/// Money input. Groups thousands as the user types and hands back minor units,
/// or null when what was typed cannot be read as a number — the caller must
/// handle that rather than guess an amount.
class _FlowFinMoneyField extends StatefulWidget {
  const _FlowFinMoneyField({
    required this.controller,
    this.label = 'Số tiền',
    this.fieldKey,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final Key? fieldKey;
  final bool autofocus;

  @override
  State<_FlowFinMoneyField> createState() => _FlowFinMoneyFieldState();
}

class _FlowFinMoneyFieldState extends State<_FlowFinMoneyField> {
  @override
  Widget build(BuildContext context) {
    return TextField(
      key: widget.fieldKey,
      controller: widget.controller,
      autofocus: widget.autofocus,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: FlowFinMoney.symbol,
      ),
      onChanged: (raw) {
        final parsed = FlowFinMoney.parseInput(raw);
        if (parsed == null) return;
        final formatted = FlowFinMoney.grouped(parsed);
        if (formatted == raw) return;
        widget.controller.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      },
    );
  }
}

class _FlowFinDateField extends StatelessWidget {
  const _FlowFinDateField({
    required this.value,
    required this.onChanged,
    this.label = 'Ngày',
    this.fieldKey,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String label;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: fieldKey,
      onPressed: () async {
        final parsed = DateTime.tryParse(value) ?? DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: parsed,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(FlowFinController.isoDate(picked));
      },
      icon: const Icon(Icons.event_outlined, size: 16),
      label: Text('$label: $value'),
    );
  }
}

class _FlowFinDropdown<T> extends StatelessWidget {
  const _FlowFinDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.fieldKey,
    this.width = 200,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final Key? fieldKey;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        key: fieldKey,
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

/// Asks before anything destructive. Deletes in FlowFin are soft on the server
/// but still remove the row from every view, so they get a prompt.
Future<bool> _flowFinConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Xoá',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppCyberTheme.panelBackgroundStrong,
      surfaceTintColor: Colors.transparent,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          key: const Key('flowfin-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Runs a controller action that returns an error message or null, and reports
/// the outcome without stealing focus on success.
Future<bool> _flowFinRun(
  BuildContext context,
  Future<String?> Function() action, {
  String? successMessage,
}) async {
  final error = await action();
  if (!context.mounted) return error == null;

  final messenger = ScaffoldMessenger.maybeOf(context);
  if (error != null) {
    messenger?.showSnackBar(
      SnackBar(content: Text(error), duration: const Duration(seconds: 6)),
    );
    return false;
  }
  if (successMessage != null) {
    messenger?.showSnackBar(
      SnackBar(content: Text(successMessage), duration: const Duration(seconds: 2)),
    );
  }
  return true;
}

class _FlowFinEmpty extends StatelessWidget {
  const _FlowFinEmpty({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: AppCyberTheme.textMuted),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppCyberTheme.dataTextStyle(
                size: 12,
                color: AppCyberTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in a list, with an optional trailing action set.
class _FlowFinRow extends StatelessWidget {
  const _FlowFinRow({
    required this.title,
    this.subtitle = '',
    this.trailing,
    this.leadingColor,
    this.actions = const [],
    this.dimmed = false,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final Color? leadingColor;
  final List<Widget> actions;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppCyberTheme.lineBlue),
      ),
      child: Row(
        children: [
          if (leadingColor != null) ...[
            Container(
              width: 8,
              height: 28,
              decoration: BoxDecoration(
                color: leadingColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: AppCyberTheme.dataTextStyle(
                    size: 12.5,
                    color: dimmed
                        ? AppCyberTheme.textMuted
                        : AppCyberTheme.textPrimary,
                    weight: FontWeight.w700,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: AppCyberTheme.dataTextStyle(
                      size: 11,
                      color: AppCyberTheme.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ...actions.map(
            (action) => Padding(
              padding: const EdgeInsets.only(left: 4),
              child: action,
            ),
          ),
        ],
      ),
    );
  }
}

Color _flowFinParseColor(String raw, Color fallback) {
  final value = raw.trim();
  if (value.length != 7 || !value.startsWith('#')) return fallback;
  final parsed = int.tryParse(value.substring(1), radix: 16);
  if (parsed == null) return fallback;
  return Color(0xFF000000 | parsed);
}
