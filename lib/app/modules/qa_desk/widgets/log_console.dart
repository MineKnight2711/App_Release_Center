import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/qa_tokens.dart';
import 'qa_widgets.dart';

/// A terminal-style view of one suite's output.
///
/// Newest line at the bottom and stuck there while the run streams, unless
/// the user scrolls up to read. Filtering keeps only matching lines, which is
/// how a failure is found in three thousand lines of `flutter test`.
class QaLogConsole extends StatefulWidget {
  const QaLogConsole({
    super.key,
    required this.title,
    required this.lines,
    this.liveUpdates,
    this.expandable = true,
    this.emptyMessage = 'Chưa có log.',
  });

  final String title;

  /// Read on every build; a running suite keeps appending to the same list.
  final List<String> lines;

  /// Rebuilds the enlarged view while the run streams.
  final Listenable? liveUpdates;
  final bool expandable;
  final String emptyMessage;

  @override
  State<QaLogConsole> createState() => _QaLogConsoleState();
}

class _QaLogConsoleState extends State<QaLogConsole> {
  final _scroll = ScrollController();
  final _query = TextEditingController();
  bool _searching = false;
  bool _atBottom = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // The list is reversed: offset 0 is the newest line.
      final atBottom = !_scroll.hasClients || _scroll.offset <= 24;
      if (atBottom != _atBottom) setState(() => _atBottom = atBottom);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _query.dispose();
    super.dispose();
  }

  List<String> get _visible {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return widget.lines;
    return widget.lines
        .where((line) => line.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _copy(List<String> lines) async {
    try {
      await Clipboard.setData(ClipboardData(text: lines.join('\n')));
      if (mounted) showQaMessage(context, 'Đã copy ${lines.length} dòng log.');
    } on Object {
      if (mounted) {
        showQaMessage(context, 'Không copy được. Hãy chọn và copy trực tiếp.');
      }
    }
  }

  void _expand() {
    final updates = widget.liveUpdates;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 1200,
          height: double.infinity,
          child: updates == null
              ? QaLogConsole(
                  title: widget.title,
                  lines: widget.lines,
                  expandable: false,
                  emptyMessage: widget.emptyMessage,
                )
              : ListenableBuilder(
                  listenable: updates,
                  builder: (context, _) => QaLogConsole(
                    title: widget.title,
                    lines: widget.lines,
                    expandable: false,
                    emptyMessage: widget.emptyMessage,
                  ),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QaTokens.of(context);
    final visible = _visible;
    final filtering = _query.text.trim().isNotEmpty;
    final iconStyle = IconButton.styleFrom(
      foregroundColor: tokens.consoleMuted,
      minimumSize: const Size(30, 30),
      fixedSize: const Size(30, 30),
      padding: EdgeInsets.zero,
      side: BorderSide.none,
      backgroundColor: Colors.transparent,
    );

    return Container(
      decoration: BoxDecoration(
        color: tokens.consoleBackground,
        borderRadius: BorderRadius.circular(QaTokens.radius),
        border: Border.all(color: tokens.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 15, color: tokens.consoleMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.mono(
                      size: 11.5,
                      color: tokens.consoleText,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_searching)
                  SizedBox(
                    width: 190,
                    height: 30,
                    child: TextField(
                      key: const Key('qa-log-search'),
                      controller: _query,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      style: tokens.mono(size: 11.5, color: tokens.consoleText),
                      cursorColor: tokens.consoleText,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Lọc dòng log…',
                        hintStyle: tokens.mono(
                          size: 11.5,
                          color: tokens.consoleMuted,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        filled: true,
                        fillColor: tokens.consoleText.withValues(alpha: 0.08),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                if (filtering)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      '${visible.length} dòng',
                      style: tokens.mono(size: 11, color: tokens.consoleMuted),
                    ),
                  ),
                IconButton(
                  tooltip: _searching ? 'Bỏ lọc' : 'Lọc log',
                  style: iconStyle,
                  onPressed: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) _query.clear();
                  }),
                  icon: Icon(
                    _searching ? Icons.search_off : Icons.search,
                    size: 17,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy log',
                  style: iconStyle,
                  onPressed: visible.isEmpty ? null : () => _copy(visible),
                  icon: const Icon(Icons.copy_all_outlined, size: 17),
                ),
                if (widget.expandable)
                  IconButton(
                    tooltip: 'Phóng to',
                    style: iconStyle,
                    onPressed: _expand,
                    icon: const Icon(Icons.open_in_full, size: 16),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.consoleMuted.withValues(alpha: 0.2)),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      filtering ? 'Không có dòng khớp.' : widget.emptyMessage,
                      style: tokens.mono(
                        size: 11.5,
                        color: tokens.consoleMuted,
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      SelectionArea(
                        child: ListView.builder(
                          controller: _scroll,
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final line = visible[visible.length - 1 - index];
                            return Text(
                              line,
                              style: tokens
                                  .mono(
                                    size: 11.5,
                                    color: tokens.consoleLine(line),
                                  )
                                  .copyWith(height: 1.45),
                            );
                          },
                        ),
                      ),
                      if (!_atBottom)
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: IconButton.filledTonal(
                            tooltip: 'Xuống dòng mới nhất',
                            onPressed: () => _scroll.animateTo(
                              0,
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                            ),
                            icon: const Icon(Icons.arrow_downward, size: 18),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
