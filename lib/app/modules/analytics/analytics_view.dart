import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'analytics_transport.dart';
import 'feature_analytics_service.dart';

Future<void> showFeatureAnalytics(BuildContext context) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            AnalyticsView(service: Get.find<FeatureAnalyticsService>()),
      ),
    );

class AnalyticsView extends StatefulWidget {
  const AnalyticsView({super.key, required this.service});
  final FeatureAnalyticsService service;
  @override
  State<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<AnalyticsView> {
  int _days = 30, _request = 0;
  String? _team, _platform, _error;
  bool _busy = false, _ascending = false;
  Map<String, Object?>? _data;
  late final Worker _identityWorker;

  @override
  void initState() {
    super.initState();
    if (!widget.service.globalAdmin.value && widget.service.teams.isNotEmpty) {
      _team = widget.service.teams.first['id'] as String;
    }
    _identityWorker = ever(widget.service.auth.profile, (_) {
      _request++;
      if (mounted) {
        setState(() {
          _data = null;
          _busy = false;
          _error =
              'Tài khoản hoặc quyền truy cập đã thay đổi. Hãy mở lại thống kê.';
        });
      }
    });
    _load();
  }

  @override
  void dispose() {
    _identityWorker.dispose();
    _request++;
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
      _data = null;
    });
    final query = Uri(
      queryParameters: {
        'days': '$_days',
        'team': ?_team,
        'platform': ?_platform,
      },
    ).query;
    try {
      final data = await widget.service.transport.request('features?$query');
      if (mounted && request == _request) setState(() => _data = data);
    } catch (error) {
      if (mounted && request == _request) {
        setState(
          () => _error = error is AnalyticsHttpException && error.status == 403
              ? 'Bạn không có quyền xem phạm vi thống kê này.'
              : 'Chưa tải được thống kê. Kiểm tra kết nối và backend analytics, rồi thử lại.',
        );
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  String _ratio(int value, int total) =>
      total == 0 ? '—' : '${(100 * value / total).toStringAsFixed(1)}%';
  int _number(Map row, String key) => (row[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = ((_data?['features'] as List?) ?? [])
        .map((e) => Map<String, Object?>.from(e as Map))
        .toList();
    rows.sort((a, b) {
      final coverage = (b['tracked'] == true ? 1 : 0).compareTo(
        a['tracked'] == true ? 1 : 0,
      );
      if (coverage != 0) return coverage;
      return _ascending
          ? _number(a, 'uses').compareTo(_number(b, 'uses'))
          : _number(b, 'uses').compareTo(_number(a, 'uses'));
    });
    final measured = rows.where((r) => r['tracked'] == true).length;
    final uses = rows.fold<int>(0, (n, r) => n + _number(r, 'uses'));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thống kê sử dụng'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Tính năng nào đang mang lại giá trị?',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Pilot · Chỉ đo tài khoản đã bật chia sẻ thống kê. Ngày thống kê theo UTC.',
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<int>(
                segments: [
                  for (final days in [7, 30, 90])
                    ButtonSegment(value: days, label: Text('$days ngày')),
                ],
                selected: {_days},
                onSelectionChanged: _busy
                    ? null
                    : (v) {
                        _days = v.single;
                        _load();
                      },
              ),
              DropdownButton<String>(
                value: _team == null && widget.service.globalAdmin.value
                    ? 'all'
                    : widget.service.teams.any((team) => team['id'] == _team)
                    ? _team
                    : null,
                hint: const Text('Chọn phạm vi'),
                items: [
                  if (widget.service.globalAdmin.value)
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('Toàn AMC'),
                    ),
                  for (final team in widget.service.teams)
                    DropdownMenuItem(
                      value: team['id'] as String,
                      child: Text(team['name'] as String),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (v) {
                        _team = v == 'all' ? null : v;
                        _load();
                      },
              ),
              DropdownButton<String>(
                value: _platform ?? 'all',
                items: [
                  for (final entry in {
                    'all': 'Mọi nền tảng',
                    'windows': 'Windows',
                    'macos': 'macOS',
                    'linux': 'Linux',
                  }.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (v) {
                        _platform = v == 'all' ? null : v;
                        _load();
                      },
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ),
          if (_data != null) ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Metric(
                  'Người dùng quan sát được',
                  '${_data!['active_users']}',
                ),
                _Metric(
                  'Tính năng đã gắn tracking',
                  '$measured / ${rows.length}',
                ),
                _Metric('Lượt thao tác', '$uses'),
              ],
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('${_data!['coverage']}'),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _ascending = !_ascending),
                icon: Icon(
                  _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                ),
                label: Text(
                  _ascending
                      ? 'Lượt dùng: ít → nhiều'
                      : 'Lượt dùng: nhiều → ít',
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Tính năng')),
                  DataColumn(label: Text('Độ phủ')),
                  DataColumn(label: Text('Người dùng / đủ điều kiện')),
                  DataColumn(label: Text('Tỷ lệ dùng')),
                  DataColumn(label: Text('Lượt mở')),
                  DataColumn(label: Text('Lượt dùng')),
                  DataColumn(label: Text('Thành công')),
                  DataColumn(label: Text('Lỗi')),
                  DataColumn(label: Text('Chưa có kết quả')),
                  DataColumn(label: Text('Quay lại')),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(
                      cells: [
                        DataCell(Text('${row['name']}')),
                        DataCell(
                          Text(
                            row['tracked'] != true
                                ? 'Chưa gắn tracking'
                                : _number(row, 'eligible_users') == 0
                                ? 'Chưa đủ dữ liệu'
                                : 'Đã đo',
                          ),
                        ),
                        DataCell(
                          Text(
                            row['tracked'] != true
                                ? '—'
                                : '${row['users']} / ${row['eligible_users']}',
                          ),
                        ),
                        DataCell(
                          Text(
                            _ratio(
                              _number(row, 'users'),
                              _number(row, 'eligible_users'),
                            ),
                          ),
                        ),
                        for (final field in [
                          'opens',
                          'uses',
                          'completed',
                          'failed',
                          'unresolved',
                        ])
                          DataCell(
                            Text(
                              row['tracked'] == true
                                  ? '${_number(row, field)}'
                                  : '—',
                            ),
                          ),
                        DataCell(
                          Text(
                            _ratio(
                              _number(row, 'returning_users'),
                              _number(row, 'users'),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Quay lại = thao tác trong ít nhất 2 ngày khác nhau. Chưa có kết quả gồm tác vụ đang chạy hoặc thiếu sự kiện kết thúc; không được coi là lỗi.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Kiểm tra AAB phát hiện vấn đề vẫn tính là công cụ chạy thành công. Chưa nên quyết định ngừng tính năng từ dữ liệu pilot.',
            ),
            const SizedBox(height: 12),
            Text(
              'Nhận dữ liệu gần nhất: ${_data!['last_received_at'] ?? 'Chưa có dữ liệu'}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 240,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
      ),
    ),
  );
}
