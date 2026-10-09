import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/quick_add_parser.dart';
import '../theme/studio_tokens.dart';

class PaletteEntry {
  const PaletteEntry({
    required this.icon,
    required this.title,
    required this.run,
    this.subtitle = '',
    this.shortcut,
    this.ticket = false,
  });
  final IconData icon;
  final String title, subtitle;
  final String? shortcut;

  /// Tickets are listed after commands and only once the user types.
  final bool ticket;
  final VoidCallback run;
}

/// Ctrl+K: one box for board commands and jumping to a ticket. Matching
/// ignores Vietnamese diacritics, so "qua han" finds "Quá hạn".
Future<void> showStudioPalette(
  BuildContext context,
  List<PaletteEntry> entries,
) async {
  final chosen = await showDialog<PaletteEntry>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => _Palette(entries: entries),
  );
  chosen?.run();
}

class _Palette extends StatefulWidget {
  const _Palette({required this.entries});
  final List<PaletteEntry> entries;
  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  final input = TextEditingController();
  final scroll = ScrollController();
  int selected = 0;

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  List<PaletteEntry> get _matches {
    final q = foldVietnamese(input.text.trim());
    if (q.isEmpty) return widget.entries.where((e) => !e.ticket).toList();
    final words = q.split(RegExp(r'\s+'));
    return widget.entries
        .where((e) {
          final hay = foldVietnamese('${e.title} ${e.subtitle}');
          return words.every(hay.contains);
        })
        .take(50)
        .toList();
  }

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() => selected = (selected + delta) % count);
    const row = 48.0;
    if (scroll.hasClients) {
      final target = selected * row;
      if (target < scroll.offset ||
          target + row > scroll.offset + scroll.position.viewportDimension) {
        scroll.jumpTo(
          (target - 2 * row).clamp(0, scroll.position.maxScrollExtent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = StudioTokens.of(context);
    final matches = _matches;
    if (selected >= matches.length) selected = 0;
    return Align(
      alignment: const Alignment(0, -0.55),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 460),
        child: Material(
          color: theme.colorScheme.surfaceContainerHigh,
          elevation: 12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(StudioTokens.panelRadius),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  _move(1, matches.length),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  _move(-1, matches.length),
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('palette-input'),
                  controller: input,
                  autofocus: true,
                  onChanged: (_) => setState(() => selected = 0),
                  onSubmitted: (_) {
                    if (matches.isNotEmpty) {
                      Navigator.pop(context, matches[selected]);
                    }
                  },
                  decoration: const InputDecoration(
                    hintText: 'Gõ lệnh hoặc mã / tên ticket…',
                    prefixIcon: Icon(Icons.search),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                Divider(height: 1, color: tokens.line),
                Flexible(
                  child: matches.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Không tìm thấy lệnh hay ticket phù hợp.',
                            style: theme.textTheme.bodySmall,
                          ),
                        )
                      : ListView.builder(
                          controller: scroll,
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: matches.length,
                          itemExtent: 48,
                          itemBuilder: (context, n) {
                            final e = matches[n];
                            final active = n == selected;
                            return InkWell(
                              onTap: () => Navigator.pop(context, e),
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: active
                                      ? theme.colorScheme.primary.withValues(
                                          alpha: 0.14,
                                        )
                                      : null,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      e.icon,
                                      size: 18,
                                      color: active
                                          ? theme.colorScheme.primary
                                          : tokens.muted,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            e.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (e.subtitle.isNotEmpty)
                                            Text(
                                              e.subtitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall,
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (e.shortcut != null) KeyCap(e.shortcut!),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Divider(height: 1, color: tokens.line),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const KeyCap('↑↓'),
                      const SizedBox(width: 6),
                      Text('chọn', style: theme.textTheme.bodySmall),
                      const SizedBox(width: 14),
                      const KeyCap('Enter'),
                      const SizedBox(width: 6),
                      Text('chạy', style: theme.textTheme.bodySmall),
                      const SizedBox(width: 14),
                      const KeyCap('Esc'),
                      const SizedBox(width: 6),
                      Text('đóng', style: theme.textTheme.bodySmall),
                    ],
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

class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
      ),
    );
  }
}

const studioShortcuts = [
  ('Ctrl+K', 'Bảng lệnh và tìm ticket'),
  ('/', 'Tìm trên board'),
  ('N', 'Tạo task mới'),
  ('Shift+N', 'Tạo nhiều task cùng lúc'),
  ('?', 'Xem phím tắt'),
  ('Tab / mũi tên', 'Di chuyển giữa các card'),
  ('Enter', 'Mở card đang chọn'),
  ('D', 'Đặt hạn cho card đang chọn'),
  ('M', 'Chuyển card sang dự án khác'),
  ('1 – 6', 'Chuyển card sang cột tương ứng'),
  ('Ctrl+S', 'Lưu ngay trong panel chi tiết'),
  ('Ctrl+Enter', 'Thêm ghi chú / tạo và mở chi tiết'),
  ('Esc', 'Đóng panel, popover hoặc bỏ tìm'),
];

Future<void> showShortcutHelp(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Phím tắt'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (keys, text) in studioShortcuts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 130,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: KeyCap(keys),
                    ),
                  ),
                  Expanded(child: Text(text)),
                ],
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Đóng'),
      ),
    ],
  ),
);
