import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../../theme/cyber_theme.dart';
import '../models/plan_reminder.dart';
import '../services/plan_studio_runtime.dart';

class ReminderPopupApp extends StatefulWidget {
  const ReminderPopupApp({super.key});
  @override
  State<ReminderPopupApp> createState() => _ReminderPopupAppState();
}

class _ReminderPopupAppState extends State<ReminderPopupApp> {
  Map<String, dynamic>? data;
  String? error;
  bool busy = false, topmost = true;
  int index = 0;
  static const channel = PlanStudioRuntime.channel;
  final reason = TextEditingController();
  @override
  void initState() {
    super.initState();
    channel.setMethodCallHandler((call) async {
      if (call.method == 'snapshot') _snapshot(call.arguments);
      if (call.method == 'dismiss') await _act('ack');
    });
    unawaited(_ready());
  }

  Future<void> _ready() async {
    try {
      _snapshot(await channel.invokeMethod<dynamic>('ready'));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  List<Map<String, dynamic>> get cards => (data?['cards'] as List? ?? [])
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
  void _snapshot(dynamic value) {
    if (!mounted || value == null) return;
    final oldId = cards.isEmpty ? null : cards[index]['itemId'];
    setState(() {
      data = Map<String, dynamic>.from(value as Map);
      index = cards.indexWhere((c) => c['itemId'] == oldId);
      if (index < 0) index = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ids = cards
          .expand((c) => c['reminders'] as List)
          .map((r) => (r as Map)['id'] as String)
          .toList();
      unawaited(channel.invokeMethod<void>('rendered', ids));
    });
  }

  Future<void> _act(String action, {int? minutes}) async {
    if (busy || cards.isEmpty) return;
    if (action == 'blocked' && reason.text.trim().isEmpty) {
      setState(() => error = 'Nhập lý do bị chặn ở ô bên dưới.');
      return;
    }
    final card = cards[index];
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await channel.invokeMethod<void>('action', {
        ...card,
        'action': action,
        'commandId': const Uuid().v4(),
        'minutes': minutes,
        'reason': reason.text.trim(),
        'preview': data?['preview'] == true,
      });
      reason.clear();
    } catch (e) {
      if (mounted) {
        setState(() => error = e is PlatformException ? e.message : '$e');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    channel.setMethodCallHandler(null);
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final choice =
        AppThemeChoice.values
            .where((t) => t.name == data?['theme'])
            .firstOrNull ??
        AppThemeChoice.console;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppCyberTheme.themeData(choice),
      home: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () => _act('ack'),
        },
        child: Focus(autofocus: true, child: Builder(builder: _body)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (cards.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final c = cards[index];
    final scheme = Theme.of(context).colorScheme;
    final due = DateTime.tryParse(c['dueAt'] as String? ?? '');
    final scheduled = DateTime.parse(c['scheduledAt'] as String);
    final overdue = due != null && due.isBefore(DateTime.now());
    final late = DateTime.now().difference(scheduled).inMinutes;
    final preview = data?['preview'] == true;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          preview
              ? 'Thử popup · không thay đổi dữ liệu'
              : overdue
              ? 'Đã quá hạn'
              : 'Đến giờ theo dõi tiến độ',
        ),
        actions: [
          IconButton(
            tooltip: 'Ghim trên cùng',
            isSelected: topmost,
            onPressed: () async {
              await channel.invokeMethod<void>('topmost', !topmost);
              setState(() => topmost = !topmost);
            },
            icon: const Icon(Icons.push_pin_outlined),
            selectedIcon: const Icon(Icons.push_pin),
          ),
          IconButton(
            tooltip: 'Đã xem',
            onPressed: busy ? null : () => _act('ack'),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Chip(label: Text('${c['project']} · ${c['code']}')),
                    Chip(label: Text('${c['priority']} · ${c['status']}')),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  c['title'] as String,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Hẹn ${studioDate(scheduled)}${late > 0 ? ' · Trễ $late phút' : ''}',
                  style: TextStyle(
                    color: overdue ? scheme.error : scheme.onSurfaceVariant,
                  ),
                ),
                if ((c['repeatLabel'] as String? ?? '').isNotEmpty)
                  Text('${c['repeatLabel']} · Đã xem để chuyển kỳ tiếp theo'),
                if (due != null)
                  Text(
                    'Hạn hoàn thành: ${c['dueLabel'] as String? ?? studioDate(due)}',
                  ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              c['progressLabel'] as String,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (c['progress'] != null)
                            Text(
                              '${((c['progress'] as num) * 100).round()}%',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                        ],
                      ),
                      if (c['progress'] != null) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: (c['progress'] as num).toDouble(),
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ],
                      if ((c['blocked'] as int? ?? 0) > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            '${c['blocked']} task đang bị chặn',
                            style: TextStyle(color: scheme.error),
                          ),
                        ),
                      for (final next in c['next'] as List? ?? [])
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text('• $next'),
                        ),
                    ],
                  ),
                ),
                if ((c['blockedReason'] as String? ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('Bị chặn: ${c['blockedReason']}'),
                  ),
                if ((c['note'] as String? ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Ghi chú: ${c['note']}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (!preview)
                  ExpansionTile(
                    title: const Text('Ghi nhận bị chặn'),
                    tilePadding: EdgeInsets.zero,
                    children: [
                      TextField(
                        controller: reason,
                        decoration: const InputDecoration(
                          labelText: 'Lý do và bước gỡ chặn',
                        ),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => _act('blocked'),
                        child: const Text('Chuyển sang Bị chặn'),
                      ),
                    ],
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(error!, style: TextStyle(color: scheme.error)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (cards.length > 1) ...[
                  IconButton(
                    onPressed: busy
                        ? null
                        : () => setState(
                            () => index =
                                (index - 1 + cards.length) % cards.length,
                          ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('${index + 1}/${cards.length}'),
                  IconButton(
                    onPressed: busy
                        ? null
                        : () => setState(
                            () => index = (index + 1) % cards.length,
                          ),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
                FilledButton.icon(
                  onPressed: busy ? null : () => _act('open'),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(preview ? 'Đóng bản thử' : 'Mở chi tiết'),
                ),
                if (!preview) ...[
                  if (c['statusName'] != 'inProgress')
                    OutlinedButton(
                      onPressed: busy ? null : () => _act('start'),
                      child: const Text('Bắt đầu làm'),
                    ),
                  OutlinedButton(
                    onPressed: busy ? null : () => _act('done'),
                    child: const Text('Hoàn tất'),
                  ),
                  PopupMenuButton<int>(
                    enabled: !busy,
                    tooltip: 'Nhắc lại',
                    onSelected: (m) => _act('snooze', minutes: m),
                    itemBuilder: (_) => [
                      for (final m in [10, 30, 60])
                        PopupMenuItem(value: m, child: Text('Sau $m phút')),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Nhắc lại ▾'),
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => _act('ack'),
                    child: const Text('Đã xem'),
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
