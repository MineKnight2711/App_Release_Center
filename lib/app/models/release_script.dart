import 'package:path/path.dart' as p;

enum ReleaseScriptKind {
  release,
  versionCode,
  versionName,
  commit,
  merge,
  deploy,
  imageValidation,
  shell,
  dartTool,
}

class ReleaseScript {
  const ReleaseScript({required this.path, required this.kind});

  final String path;
  final ReleaseScriptKind kind;

  String get fileName => p.basename(path);
  String get extension => p.extension(path).toLowerCase();
  bool get isShellScript => extension == '.sh';
  bool get isDartTool => extension == '.dart';

  String get label {
    return switch (kind) {
      ReleaseScriptKind.release => 'Luồng release',
      ReleaseScriptKind.versionCode => 'Version code',
      ReleaseScriptKind.versionName => 'Version name',
      ReleaseScriptKind.commit => 'Commit',
      ReleaseScriptKind.merge => 'Merge PR',
      ReleaseScriptKind.deploy => 'Deploy',
      ReleaseScriptKind.imageValidation => 'Ảnh Play',
      ReleaseScriptKind.shell => _humanize(fileName),
      ReleaseScriptKind.dartTool => _humanize(fileName),
    };
  }

  String get description {
    return switch (kind) {
      ReleaseScriptKind.release => 'Chạy version, commit, merge rồi deploy.',
      ReleaseScriptKind.versionCode => 'Cập nhật build number của Android.',
      ReleaseScriptKind.versionName => 'Cập nhật version name của bản release.',
      ReleaseScriptKind.commit =>
        'Commit rồi push các thay đổi của bản release.',
      ReleaseScriptKind.merge => 'Tạo pull request lên dev rồi chờ.',
      ReleaseScriptKind.deploy => 'Chạy các tuỳ chọn deploy của dự án này.',
      ReleaseScriptKind.imageValidation => 'Kiểm tra bộ ảnh cho Google Play.',
      ReleaseScriptKind.shell => 'Chạy shell script này.',
      ReleaseScriptKind.dartTool => 'Chạy Dart tool này.',
    };
  }

  static String _humanize(String fileName) {
    final name = p.basenameWithoutExtension(fileName);
    return name
        .split(RegExp(r'[_-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}
