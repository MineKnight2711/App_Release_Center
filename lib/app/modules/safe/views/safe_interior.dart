import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';

import '../../shared/module_widgets.dart';
import '../controllers/safe_controller.dart';
import '../models/safe_item.dart';
import '../widgets/safe_look.dart';
import '../widgets/safe_metal.dart';
import 'safe_item_detail.dart';
import 'safe_item_editor.dart';
import 'safe_scan_dialog.dart';

/// The inside of the open safe: drawers down the left, deposit boxes in the
/// middle and the opened box on the right.
class SafeInterior extends StatefulWidget {
  const SafeInterior({
    super.key,
    required this.safe,
    required this.searchFocus,
  });

  final SafeController safe;
  final FocusNode searchFocus;

  /// Below this the drawers become a row of chips above the boxes.
  static const railBreakpoint = 760.0;

  /// From this width the opened box sits beside the grid instead of in a
  /// dialog.
  static const detailBreakpoint = 1120.0;

  @override
  State<SafeInterior> createState() => _SafeInteriorState();
}

class _SafeInteriorState extends State<SafeInterior> {
  late final _search = TextEditingController(text: widget.safe.query);
  bool _dropping = false;

  SafeController get _safe => widget.safe;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _add(SafeItemKind kind) async {
    await showSafeItemEditor(context, _safe, _safe.draft(kind), isNew: true);
  }

  Future<void> _importPath(String path) async {
    try {
      final draft = await safeDraftFromFile(_safe, path);
      if (!mounted) return;
      await showSafeItemEditor(context, _safe, draft, isNew: true);
    } on SafeEditorException catch (error) {
      _say(error.message);
    } catch (error) {
      _say('Không đọc được tệp: $error');
    }
  }

  Future<void> _scanFolders() async {
    final result = await showSafeScanDialog(context, _safe);
    if (result == null || !mounted) return;
    final failed = result.failed.isEmpty
        ? ''
        : ' ${result.failed.length} tệp không đọc được nữa.';
    _say(
      'Đã cất ${result.imported} khoá từ ${result.projects} dự án vào két.$failed',
    );
  }

  Future<void> _pickImport() async {
    final file = await file_selector.openFile();
    if (file != null) await _importPath(file.path);
  }

  Future<void> _openBox(SafeItem item, {required bool inline}) async {
    _safe.select(item.id);
    if (inline) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
          child: ListenableBuilder(
            listenable: _safe,
            builder: (context, _) {
              final current = _safe.selected;
              if (current == null || !_safe.isOpen) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).maybePop();
                  }
                });
                return const SizedBox.shrink();
              }
              return SafeItemDetail(
                safe: _safe,
                item: current,
                onClose: () => Navigator.of(dialogContext).pop(),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final steel = SafeSteel.of(context);
    return ListenableBuilder(
      listenable: _safe,
      builder: (context, _) {
        final decoration = BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: steel.interior,
          ),
        );
        // Shut: an empty steel box, so nothing decrypted lingers on screen
        // while the door swings closed.
        if (!_safe.isOpen) return DecoratedBox(decoration: decoration);

        return DropTarget(
          onDragEntered: (_) => setState(() => _dropping = true),
          onDragExited: (_) => setState(() => _dropping = false),
          onDragDone: (details) {
            setState(() => _dropping = false);
            final path = details.files.firstOrNull?.path;
            if (path != null) unawaited(_importPath(path));
          },
          child: DecoratedBox(
            decoration: decoration,
            child: Stack(
              children: [
                // Inner walls: darker towards the edges, like a box seen from
                // its open side.
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          radius: 1.2,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(
                              alpha: steel.dark ? 0.35 : 0.12,
                            ),
                          ],
                          stops: const [0.6, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                LayoutBuilder(
                  builder: (context, constraints) =>
                      _layout(constraints.maxWidth),
                ),
                if (_dropping) const Positioned.fill(child: _DropOverlay()),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _layout(double width) {
    final withRail = width >= SafeInterior.railBreakpoint;
    final inlineDetail = width >= SafeInterior.detailBreakpoint;
    final selected = _safe.selected;
    final items = _safe.visibleItems;

    return Padding(
      padding: EdgeInsets.all(width < 600 ? 12 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Toolbar(
            search: _search,
            searchFocus: widget.searchFocus,
            compact: width < 600,
            onSearch: _safe.setQuery,
            onAdd: _add,
            onImport: _pickImport,
            onScan: _scanFolders,
          ),
          if (_safe.error.isNotEmpty) ...[
            const SizedBox(height: 10),
            NoticeBox(text: _safe.error, tone: NoticeTone.danger),
          ],
          const SizedBox(height: 14),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (withRail) ...[
                  SizedBox(width: 214, child: _DrawerRail(safe: _safe)),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!withRail) ...[
                        _DrawerChips(safe: _safe),
                        const SizedBox(height: 10),
                      ],
                      Expanded(
                        child: _safe.items.isEmpty
                            ? _EmptySafe(
                                onAdd: _add,
                                onImport: _pickImport,
                                onScan: _scanFolders,
                              )
                            : items.isEmpty
                            ? const _NothingMatches()
                            : _BoxGrid(
                                items: items,
                                selectedId: inlineDetail ? selected?.id : null,
                                onOpen: (item) =>
                                    _openBox(item, inline: inlineDetail),
                                onCopy: (item) async {
                                  final value = item.kind.quickCopy(item);
                                  if (value == null) return;
                                  await _safe.copySecret(value);
                                  _say(
                                    '${item.kind.quickCopyLabel}: "${item.title}" · tự xoá sau '
                                    '${_safe.settings.clipboardSeconds} giây.',
                                  );
                                },
                                onFavorite: (item) =>
                                    _safe.toggleFavorite(item.id),
                              ),
                      ),
                    ],
                  ),
                ),
                if (inlineDetail) ...[
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 430,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: selected == null
                          ? const _ClosedBoxHint()
                          : SafeItemDetail(
                              key: ValueKey(selected.id),
                              safe: _safe,
                              item: selected,
                              onClose: () => _safe.select(null),
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.search,
    required this.searchFocus,
    required this.compact,
    required this.onSearch,
    required this.onAdd,
    required this.onImport,
    required this.onScan,
  });

  final TextEditingController search;
  final FocusNode searchFocus;
  final bool compact;
  final ValueChanged<String> onSearch;
  final ValueChanged<SafeItemKind> onAdd;
  final VoidCallback onImport;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: TextField(
              key: const Key('safe-search'),
              controller: search,
              focusNode: searchFocus,
              onChanged: onSearch,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                hintText: 'Tìm theo tên, tài khoản, tên biến env…',
                suffixIcon: ListenableBuilder(
                  listenable: search,
                  builder: (context, _) => search.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          tooltip: 'Xoá tìm kiếm',
                          onPressed: () {
                            search.clear();
                            onSearch('');
                          },
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        if (compact)
          IconButton(
            key: const Key('safe-scan'),
            tooltip: 'Dò khoá trong thư mục project',
            onPressed: onScan,
            icon: const Icon(Icons.radar_rounded),
          )
        else ...[
          OutlinedButton.icon(
            key: const Key('safe-scan'),
            onPressed: onScan,
            icon: const Icon(Icons.radar_rounded, size: 18),
            label: const Text('Dò thư mục…'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: const Text('Cất tệp…'),
          ),
          const SizedBox(width: 8),
        ],
        PopupMenuButton<SafeItemKind>(
          key: const Key('safe-add'),
          tooltip: 'Cất thêm vào két',
          position: PopupMenuPosition.under,
          onSelected: onAdd,
          itemBuilder: (context) => [
            for (final kind in SafeItemKind.values)
              PopupMenuItem(
                value: kind,
                child: Row(
                  children: [
                    Icon(kind.icon, color: kind.tint, size: 20),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(kind.label, style: theme.textTheme.titleSmall),
                        Text(
                          kind.description,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
          child: IgnorePointer(
            child: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(compact ? 'Thêm' : 'Cất vào két'),
            ),
          ),
        ),
      ],
    );
  }
}

typedef _Compartment = (
  SafeFilter filter,
  String label,
  IconData icon,
  Color? tint,
);

List<_Compartment> get _compartments => [
  (const SafeFilterAll(), 'Tất cả', Icons.all_inbox_rounded, null),
  (
    const SafeFilterFavorites(),
    'Đã ghim',
    Icons.star_rounded,
    const Color(0xFFE0A526),
  ),
  for (final kind in SafeItemKind.values)
    (SafeFilterKind(kind), kind.label, kind.icon, kind.tint),
];

/// The drawers: one per compartment. The open one slides out a little.
class _DrawerRail extends StatelessWidget {
  const _DrawerRail({required this.safe});

  final SafeController safe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'NGĂN KÉO',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.4,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final (filter, label, icon, tint) in _compartments)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _DrawerFront(
              label: label,
              icon: icon,
              tint: tint,
              count: safe.countFor(filter),
              selected: safe.filter == filter,
              onTap: () => safe.setFilter(filter),
            ),
          ),
        if (safe.projects.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 10, bottom: 8),
            child: Text(
              'DỰ ÁN',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final project in safe.projects)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _DrawerFront(
                key: Key('safe-project-$project'),
                label: project,
                icon: Icons.folder_special_outlined,
                tint: null,
                count: safe.countFor(SafeFilterProject(project)),
                selected: safe.filter == SafeFilterProject(project),
                onTap: () => safe.setFilter(SafeFilterProject(project)),
              ),
            ),
        ],
      ],
    );
  }
}

class _DrawerFront extends StatefulWidget {
  const _DrawerFront({
    super.key,
    required this.label,
    required this.icon,
    required this.tint,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color? tint;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_DrawerFront> createState() => _DrawerFrontState();
}

class _DrawerFrontState extends State<_DrawerFront> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steel = SafeSteel.of(context);
    final accent = widget.tint ?? theme.colorScheme.primary;
    final pulled = widget.selected ? 10.0 : (_hover ? 4.0 : 0.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(pulled, 0, 0),
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: steel.boxFace,
            ),
            border: Border.all(
              color: widget.selected
                  ? accent.withValues(alpha: 0.7)
                  : steel.boxEdge,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: widget.selected ? 0.4 : 0.18,
                ),
                blurRadius: widget.selected ? 12 : 4,
                offset: Offset(pulled / 2, widget.selected ? 5 : 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          padding: const EdgeInsets.only(right: 10),
          child: Row(
            children: [
              // The open drawer's coloured edge.
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: widget.selected ? 4 : 0,
                color: accent,
              ),
              SizedBox(width: widget.selected ? 6 : 10),
              Icon(widget.icon, size: 18, color: accent),
              const SizedBox(width: 10),
              // The card slot holding the drawer's label.
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: steel.dark
                        ? const Color(0xFF1F242A)
                        : const Color(0xFFFFFCF2),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: steel.boxEdge),
                  ),
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: widget.selected
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 26,
                child: Text(
                  '${widget.count}',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Pull handle.
              Container(
                width: 6,
                height: 26,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: LinearGradient(
                    colors: [steel.highlight, steel.shadow],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerChips extends StatelessWidget {
  const _DrawerChips({required this.safe});

  final SafeController safe;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final (filter, label, icon, tint) in [
            ..._compartments,
            for (final project in safe.projects)
              (
                SafeFilterProject(project),
                project,
                Icons.folder_special_outlined,
                null,
              ),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(icon, size: 16, color: tint),
                label: Text('$label ${safe.countFor(filter)}'),
                selected: safe.filter == filter,
                onSelected: (_) => safe.setFilter(filter),
              ),
            ),
        ],
      ),
    );
  }
}

class _BoxGrid extends StatelessWidget {
  const _BoxGrid({
    required this.items,
    required this.selectedId,
    required this.onOpen,
    required this.onCopy,
    required this.onFavorite,
  });

  final List<SafeItem> items;
  final String? selectedId;
  final ValueChanged<SafeItem> onOpen;
  final ValueChanged<SafeItem> onCopy;
  final ValueChanged<SafeItem> onFavorite;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 12, right: 4),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisExtent: 112,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _DepositBox(
          key: ValueKey(item.id),
          item: item,
          selected: item.id == selectedId,
          onOpen: () => onOpen(item),
          onCopy: item.kind.quickCopy(item) == null ? null : () => onCopy(item),
          onFavorite: () => onFavorite(item),
        );
      },
    );
  }
}

/// One deposit box: a steel face with a label plate, a keyhole and the
/// quick actions.
class _DepositBox extends StatefulWidget {
  const _DepositBox({
    super.key,
    required this.item,
    required this.selected,
    required this.onOpen,
    required this.onCopy,
    required this.onFavorite,
  });

  final SafeItem item;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback? onCopy;
  final VoidCallback onFavorite;

  @override
  State<_DepositBox> createState() => _DepositBoxState();
}

class _DepositBoxState extends State<_DepositBox> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steel = SafeSteel.of(context);
    final item = widget.item;
    final tint = item.kind.tint;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: steel.boxFace,
          ),
          border: Border.all(
            color: widget.selected ? tint : steel.boxEdge,
            width: widget.selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.selected
                  ? tint.withValues(alpha: 0.35)
                  : Colors.black.withValues(alpha: _hover ? 0.32 : 0.18),
              blurRadius: widget.selected || _hover ? 14 : 5,
              offset: Offset(0, _hover ? 6 : 3),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: widget.onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 6, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tint.withValues(alpha: 0.15),
                          border: Border.all(
                            color: tint.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Icon(item.kind.icon, size: 18, color: tint),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.summary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontFamily: 'JetBrains Mono',
                                fontFamilyFallback: const ['Menlo', 'Consolas'],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: item.favorite ? 'Bỏ ghim' : 'Ghim lên đầu',
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onFavorite,
                        icon: Icon(
                          item.favorite
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 18,
                          color: item.favorite
                              ? const Color(0xFFE0A526)
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      KeyholeIcon(
                        size: 16,
                        color: steel.dark ? steel.highlight : steel.shadow,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.project.isEmpty
                              ? formatSafeDate(item.updatedAt)
                              : '${item.project} · ${formatSafeDate(item.updatedAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (widget.onCopy != null)
                        IconButton(
                          tooltip: item.kind.quickCopyLabel,
                          visualDensity: VisualDensity.compact,
                          onPressed: widget.onCopy,
                          icon: const Icon(Icons.copy_rounded, size: 17),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptySafe extends StatelessWidget {
  const _EmptySafe({
    required this.onAdd,
    required this.onImport,
    required this.onScan,
  });

  final ValueChanged<SafeItemKind> onAdd;
  final VoidCallback onImport;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 56,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text('Két đang trống', style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Cất mật khẩu, API key, file .env, JSON service account hay '
                'keystore vào đây. Kéo thả tệp vào cũng được.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final kind in SafeItemKind.values)
                    OutlinedButton.icon(
                      onPressed: () => onAdd(kind),
                      icon: Icon(kind.icon, size: 18, color: kind.tint),
                      label: Text(kind.label),
                    ),
                  FilledButton.tonalIcon(
                    onPressed: onImport,
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: const Text('Cất từ tệp…'),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                key: const Key('safe-empty-scan'),
                onPressed: onScan,
                icon: const Icon(Icons.radar_rounded),
                label: const Text('Dò khoá trong thư mục project…'),
              ),
              const SizedBox(height: 6),
              Text(
                'Quét mọi thư mục con, gom khoá theo từng dự án.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NothingMatches extends StatelessWidget {
  const _NothingMatches();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text('Không có hộp nào khớp', style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _ClosedBoxHint extends StatelessWidget {
  const _ClosedBoxHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steel = SafeSteel.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: steel.boxEdge.withValues(alpha: 0.6),
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyholeIcon(size: 44, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'Chọn một hộp để mở',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Mọi giá trị đều ẩn cho đến khi bạn bấm hiện.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.primary, width: 2),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.move_to_inbox_rounded,
              size: 52,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 10),
            Text('Thả để cất vào két', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '.env → Env · .json → JSON key · tệp khác → Tệp',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
