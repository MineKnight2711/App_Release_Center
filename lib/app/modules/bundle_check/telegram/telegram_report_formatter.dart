import '../models/bundle_check_models.dart';
import 'telegram_intake_store.dart';

String _icon(CheckStatus status) => switch (status) {
  CheckStatus.pass => '✅',
  CheckStatus.info => 'ℹ️',
  CheckStatus.warn => '⚠️',
  CheckStatus.fail => '❌',
  CheckStatus.skip => '➖',
};

String _clip(String text, int limit) =>
    text.length <= limit ? text : '${text.substring(0, limit - 1)}…';

String _size(int? bytes) => bytes == null ? '' : ' (${formatBytes(bytes)})';

/// The list the bot shows for `/aab`: newest first, one button per file.
String formatAabList(List<IndexedAab> items) {
  if (items.isEmpty) {
    return 'Chưa thấy file .aab nào trong nhóm này.\n\n'
        'Bot chỉ thấy file gửi sau khi nó vào nhóm, và chỉ khi privacy mode '
        'đã tắt (BotFather → /setprivacy → Disable) hoặc bot là admin. File '
        'cũ hơn: reply /check vào tin nhắn có file đó.';
  }
  return 'Chọn file .aab để tải về và kiểm tra:';
}

String aabButtonLabel(IndexedAab item) {
  final day = item.date.day.toString().padLeft(2, '0');
  final month = item.date.month.toString().padLeft(2, '0');
  return _clip('${item.fileName}${_size(item.fileSize)} · $day/$month', 60);
}

/// The sentence said before fetching, then which file.
String formatDownloading(String sentence, IndexedAab item) {
  return '$sentence\n📦 ${item.fileName}${_size(item.fileSize)}';
}

/// The result, written for a chat: verdict first, then only what needs
/// attention. Never carries env values or log text beyond one error line —
/// the full report stays in AMC.
String formatCheckResult(BundleCheckReport report, {String deviceNote = ''}) {
  final overall = report.overall;
  final verdict = switch (overall) {
    CheckStatus.fail => '❌ Có lỗi',
    CheckStatus.warn => '⚠️ Qua, kèm cảnh báo',
    _ => '✅ Đạt',
  };
  final lines = <String>[
    '$verdict — ${report.fileName}',
    '📱 ${report.packageName} · ${report.versionLabel} · targetSdk '
        '${report.targetSdk ?? '?'}',
    if (report.signer != null)
      '🔏 ${report.signer!.isAndroidDebug ? 'Ký bằng DEBUG key' : 'Ký bởi ${report.signer!.commonName}'}',
    if (report.projectName != null) '📁 So với project ${report.projectName}',
    '',
  ];

  for (final group in CheckGroup.values) {
    final results = report.inGroup(group).toList();
    if (results.isEmpty) continue;
    final fail = results.where((r) => r.status == CheckStatus.fail).length;
    final warn = results.where((r) => r.status == CheckStatus.warn).length;
    final pass = results.where((r) => r.status == CheckStatus.pass).length;
    lines.add('${group.label}: $fail lỗi · $warn cảnh báo · $pass đạt');
  }

  final attention = [
    ...report.results.where((r) => r.status == CheckStatus.fail),
    ...report.results.where((r) => r.status == CheckStatus.warn),
  ].where((r) => r.id != 'E00').toList();
  if (attention.isNotEmpty) {
    lines.add('');
    for (final result in attention.take(10)) {
      lines.add(
        '${_icon(result.status)} ${result.id} ${result.title}: '
        '${_clip(result.detail, 220)}',
      );
      // One log line tells what crashed; anything more belongs in AMC.
      if (result.id == 'R05' && result.items.isNotEmpty) {
        lines.add('   ${_clip(result.items.first, 200)}');
      }
    }
    if (attention.length > 10) {
      lines.add('…và ${attention.length - 10} mục khác.');
    }
  }

  final run = report.deviceRun;
  if (run != null) {
    lines
      ..add('')
      ..add(
        '🚀 Chạy trên ${run.deviceLabel}'
        '${run.coldStartMs == null ? '' : ', cold start ${run.coldStartMs}ms'}.',
      );
  } else if (deviceNote.isNotEmpty) {
    lines
      ..add('')
      ..add('🚀 $deviceNote');
  }
  lines
    ..add('')
    ..add('Báo cáo đầy đủ: AMC → Kiểm tra AAB.');
  return lines.join('\n');
}
